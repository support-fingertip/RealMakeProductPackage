/**
 * @description Generic Invocable Apex class for sending emails from Flow.
 * Works with any object type. Takes a list of record IDs and an email template name.
 * Resolves merge fields, recipients, and attachments from the Email_Template_Config__c.
 */
public with sharing class EmailSenderInvocable {

    public class EmailRequest {
        @InvocableVariable(label='Record IDs' description='Comma-separated record IDs or a single ID' required=true)
        public String recordIds;

        @InvocableVariable(label='Template Name' description='Name of the Email_Template_Config__c template' required=true)
        public String templateName;

        @InvocableVariable(label='Additional To Addresses' description='Comma-separated additional TO email addresses')
        public String additionalToAddresses;

        @InvocableVariable(label='Additional CC Addresses' description='Comma-separated additional CC email addresses')
        public String additionalCcAddresses;

        @InvocableVariable(label='Subject Override' description='Override the template subject (merge fields supported)')
        public String subjectOverride;

        @InvocableVariable(label='Body Override' description='Override the template body HTML (merge fields supported)')
        public String bodyOverride;

        @InvocableVariable(label='Skip Attachments' description='Set to true to skip generating attachments')
        public Boolean skipAttachments;
    }

    public class EmailResponse {
        @InvocableVariable(label='Success' description='Whether all emails were sent successfully')
        public Boolean success;

        @InvocableVariable(label='Message' description='Result message with details')
        public String message;

        @InvocableVariable(label='Sent Count' description='Number of emails successfully sent')
        public Integer sentCount;

        @InvocableVariable(label='Failed Count' description='Number of emails that failed')
        public Integer failedCount;

        @InvocableVariable(label='Error Details' description='Detailed error information if any')
        public String errorDetails;
    }

    @InvocableMethod(
        label='Send Email from Template'
        description='Sends emails using an Email_Template_Config__c template for one or more records. Works with any object.'
        category='Email'
    )
    public static List<EmailResponse> sendEmails(List<EmailRequest> requests) {
        List<EmailResponse> responses = new List<EmailResponse>();

        for (EmailRequest request : requests) {
            responses.add(processRequest(request));
        }

        return responses;
    }

    private static EmailResponse processRequest(EmailRequest request) {
        EmailResponse response = new EmailResponse();
        response.sentCount = 0;
        response.failedCount = 0;

        try {
            // Validate inputs
            if (String.isBlank(request.recordIds)) {
                throw new EmailSenderException('Record IDs are required');
            }
            if (String.isBlank(request.templateName)) {
                throw new EmailSenderException('Template Name is required');
            }

            // Find template by name
            List<Email_Template_Config__c> templates = [
                SELECT Id, Name, Template_Name__c, Object_API_Name__c, Subject__c,
                       Email_Body__c, From_Address__c, Reply_To__c,
                       Recipients_Config__c, Attachments_Config__c,
                       Allow_Additional_Recipients__c, Allow_File_Upload__c,
                       Is_Active__c
                FROM Email_Template_Config__c
                WHERE (Template_Name__c = :request.templateName OR Name = :request.templateName)
                  AND Is_Active__c = true
                LIMIT 1
            ];

            if (templates.isEmpty()) {
                throw new EmailSenderException('No active email template found with name: ' + request.templateName);
            }

            Email_Template_Config__c template = templates[0];
            String objectApiName = template.Object_API_Name__c;

            // Parse record IDs
            List<Id> recordIds = parseRecordIds(request.recordIds);
            if (recordIds.isEmpty()) {
                throw new EmailSenderException('No valid record IDs provided');
            }

            // Parse additional addresses
            List<String> additionalTo = parseEmails(request.additionalToAddresses);
            List<String> additionalCc = parseEmails(request.additionalCcAddresses);

            // Build and send emails for each record
            List<Messaging.SingleEmailMessage> emailMessages = new List<Messaging.SingleEmailMessage>();
            List<String> errors = new List<String>();

            for (Id recordId : recordIds) {
                try {
                    // If objectApiName is blank, derive from record ID
                    String objApi = String.isNotBlank(objectApiName)
                        ? objectApiName
                        : recordId.getSObjectType().getDescribe().getName();

                    Messaging.SingleEmailMessage email = buildEmail(
                        template, recordId, objApi,
                        additionalTo, additionalCc,
                        request.subjectOverride, request.bodyOverride,
                        request.skipAttachments == true
                    );

                    if (email != null) {
                        emailMessages.add(email);
                    }
                } catch (Exception e) {
                    errors.add('Record ' + recordId + ': ' + e.getMessage());
                }
            }

            // Send all emails
            if (!emailMessages.isEmpty()) {
                Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(emailMessages, false);

                for (Integer i = 0; i < sendResults.size(); i++) {
                    if (sendResults[i].isSuccess()) {
                        response.sentCount++;
                    } else {
                        response.failedCount++;
                        for (Messaging.SendEmailError err : sendResults[i].getErrors()) {
                            errors.add(err.getMessage());
                        }
                    }
                }
            }

            response.success = errors.isEmpty();
            if (errors.isEmpty()) {
                response.message = 'Successfully sent ' + response.sentCount + ' email(s)';
            } else {
                response.message = 'Sent ' + response.sentCount + ', Failed ' + response.failedCount;
                response.errorDetails = String.join(errors, '; ');
            }

        } catch (EmailSenderException e) {
            response.success = false;
            response.message = e.getMessage();
            response.errorDetails = e.getMessage();
        } catch (Exception e) {
            response.success = false;
            response.message = 'Unexpected error: ' + e.getMessage();
            response.errorDetails = e.getMessage() + ' at line ' + e.getLineNumber();
        }

        return response;
    }

    private static Messaging.SingleEmailMessage buildEmail(
        Email_Template_Config__c template,
        Id recordId,
        String objectApiName,
        List<String> additionalTo,
        List<String> additionalCc,
        String subjectOverride,
        String bodyOverride,
        Boolean skipAttachments
    ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

        // Resolve recipients from config
        List<String> toAddresses = new List<String>();
        List<String> ccAddresses = new List<String>();
        List<String> bccAddresses = new List<String>();

        if (String.isNotBlank(template.Recipients_Config__c)) {
            resolveRecipients(template.Recipients_Config__c, recordId, objectApiName,
                              toAddresses, ccAddresses, bccAddresses);
        }

        // Add additional recipients
        toAddresses.addAll(additionalTo);
        ccAddresses.addAll(additionalCc);

        // Must have at least one TO address
        if (toAddresses.isEmpty()) {
            throw new AuraHandledException('No TO recipients resolved for record ' + recordId);
        }

        email.setToAddresses(toAddresses);
        if (!ccAddresses.isEmpty()) email.setCcAddresses(ccAddresses);
        if (!bccAddresses.isEmpty()) email.setBccAddresses(bccAddresses);

        // From address
        if (String.isNotBlank(template.From_Address__c)) {
            try {
                email.setOrgWideEmailAddressId(template.From_Address__c);
            } catch (Exception e) {
                // Ignore - will send from running user
            }
        }

        // Reply-To
        if (String.isNotBlank(template.Reply_To__c)) {
            email.setReplyTo(template.Reply_To__c);
        }

        // Subject
        String subject = String.isNotBlank(subjectOverride)
            ? subjectOverride
            : template.Subject__c;
        if (String.isNotBlank(subject)) {
            subject = EmailMergeFieldResolver.resolveMergeFields(subject, recordId, objectApiName);
        }
        email.setSubject(subject);

        // Body
        String body = String.isNotBlank(bodyOverride)
            ? bodyOverride
            : template.Email_Body__c;
        if (String.isNotBlank(body)) {
            body = EmailMergeFieldResolver.resolveMergeFields(body, recordId, objectApiName);
        }
        email.setHtmlBody(body);

        // Activity tracking
        if (PostSalesConstants.isWhatIdSupported(objectApiName)) {
            email.setWhatId(recordId);
        }
        email.setSaveAsActivity(true);

        // Attachments
        if (!skipAttachments && String.isNotBlank(template.Attachments_Config__c)) {
            List<Messaging.EmailFileAttachment> attachments = generateAttachments(
                template.Attachments_Config__c, recordId, objectApiName
            );
            if (!attachments.isEmpty()) {
                email.setFileAttachments(attachments);
            }
        }

        return email;
    }

    private static void resolveRecipients(
        String recipientsConfigJson,
        Id recordId,
        String objectApiName,
        List<String> toAddresses,
        List<String> ccAddresses,
        List<String> bccAddresses
    ) {
        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(recipientsConfigJson);

            resolveRecipientList(config, 'to', recordId, objectApiName, toAddresses);
            resolveRecipientList(config, 'cc', recordId, objectApiName, ccAddresses);
            resolveRecipientList(config, 'bcc', recordId, objectApiName, bccAddresses);

        } catch (Exception e) {
            System.debug('Error resolving recipients: ' + e.getMessage());
        }
    }

    private static void resolveRecipientList(
        Map<String, Object> config,
        String type,
        Id recordId,
        String objectApiName,
        List<String> addresses
    ) {
        List<Object> recipientList = (List<Object>) config.get(type);
        if (recipientList == null) return;

        for (Object rec : recipientList) {
            Map<String, Object> recMap = (Map<String, Object>) rec;
            String sourceType = (String) recMap.get('sourceType');
            String fieldApiName = (String) recMap.get('fieldApiName');
            String staticEmail = (String) recMap.get('staticEmail');

            String email = EmailMergeFieldResolver.resolveRecipientEmail(
                sourceType, fieldApiName, staticEmail, recordId, objectApiName
            );

            if (String.isNotBlank(email) && isValidEmail(email)) {
                addresses.add(email);
            }
        }
    }

    private static List<Messaging.EmailFileAttachment> generateAttachments(
        String attachmentsConfigJson,
        Id recordId,
        String objectApiName
    ) {
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();

        try {
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(attachmentsConfigJson);
            List<Object> attList = (List<Object>) config.get('attachments');
            if (attList == null) return attachments;

            for (Object attObj : attList) {
                Map<String, Object> attMap = (Map<String, Object>) attObj;
                String attType = (String) attMap.get('type');
                Boolean isDefault = attMap.get('isDefaultChecked') == true;
                Boolean isRequired = attMap.get('isRequired') == true;

                // Only generate default/required attachments for flow
                if (!isDefault && !isRequired) continue;

                try {
                    if (attType == PostSalesConstants.ATTACHMENT_TYPE_VF_PAGE) {
                        String vfPageName = (String) attMap.get('vfPageName');
                        String docTemplateId = (String) attMap.get('documentTemplateId');
                        String fileNamePattern = (String) attMap.get('fileNamePattern');
                        String attName = (String) attMap.get('name');

                        String fileName = String.isNotBlank(fileNamePattern)
                            ? EmailMergeFieldResolver.resolveMergeFields(fileNamePattern, recordId, objectApiName)
                            : (String.isNotBlank(attName) ? attName + '.pdf' : 'Document.pdf');

                        Map<String, String> extraParams = new Map<String, String>();
                        if (String.isNotBlank(docTemplateId)) {
                            extraParams.put('templateId', docTemplateId);
                        }

                        Messaging.EmailFileAttachment fileAtt = EmailPdfGenerator.generatePdfAttachment(
                            vfPageName, recordId, fileName, 'id', extraParams
                        );
                        if (fileAtt != null) {
                            attachments.add(fileAtt);
                        }
                    } else if (attType == PostSalesConstants.ATTACHMENT_TYPE_STATIC_DOC) {
                        String docId = (String) attMap.get('documentId');
                        if (String.isNotBlank(docId)) {
                            Messaging.EmailFileAttachment fileAtt = EmailPdfGenerator.getStaticDocumentAttachment(docId);
                            if (fileAtt != null) {
                                attachments.add(fileAtt);
                            }
                        }
                    }
                } catch (Exception e) {
                    System.debug('Error generating attachment: ' + e.getMessage());
                }
            }
        } catch (Exception e) {
            System.debug('Error processing attachments config: ' + e.getMessage());
        }

        return attachments;
    }

    // ============ UTILITY METHODS ============

    private static List<Id> parseRecordIds(String recordIdsStr) {
        List<Id> ids = new List<Id>();
        if (String.isBlank(recordIdsStr)) return ids;

        for (String idStr : recordIdsStr.split('[,;\\s]+')) {
            String trimmed = idStr.trim();
            if (String.isNotBlank(trimmed)) {
                try {
                    ids.add(Id.valueOf(trimmed));
                } catch (Exception e) {
                    System.debug('Invalid ID: ' + trimmed);
                }
            }
        }
        return ids;
    }

    private static List<String> parseEmails(String emailsStr) {
        List<String> emails = new List<String>();
        if (String.isBlank(emailsStr)) return emails;

        for (String email : emailsStr.split('[,;]+')) {
            String trimmed = email.trim();
            if (String.isNotBlank(trimmed) && isValidEmail(trimmed)) {
                emails.add(trimmed);
            }
        }
        return emails;
    }

    private static Boolean isValidEmail(String email) {
        if (String.isBlank(email)) return false;
        String emailRegex = '^[a-zA-Z0-9._|\\\\%#~`=?&/$^*!}{+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,4}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        Matcher matcher = emailPattern.matcher(email);
        return matcher.matches();
    }

    public class EmailSenderException extends Exception {}
}