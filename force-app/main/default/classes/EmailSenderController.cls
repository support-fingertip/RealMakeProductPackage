/**
 * @description COMPLETE EmailSenderController with Related Object Attachment Support
 * This is a FULL file - replace or merge with your existing EmailSenderController
 * @author Your Name
 * @date 2024
 */
public with sharing class EmailSenderController {
    
    // ============ WRAPPER CLASSES ============
    
    public class EmailDataWrapper {
        @AuraEnabled public String templateId { get; set; }
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public List<String> toAddresses { get; set; }
        @AuraEnabled public List<String> ccAddresses { get; set; }
        @AuraEnabled public List<String> bccAddresses { get; set; }
        @AuraEnabled public String fromAddressId { get; set; }
        @AuraEnabled public String replyTo { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String body { get; set; }
        @AuraEnabled public List<AttachmentData> attachments { get; set; }
        @AuraEnabled public List<String> uploadedFileIds { get; set; }
    }
    
    /**
     * ENHANCED AttachmentData with Related Object fields
     */
    public class AttachmentData {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String fileName { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String vfPageName { get; set; }
        @AuraEnabled public String vfPageParam { get; set; }
        @AuraEnabled public String documentId { get; set; }
        @AuraEnabled public String documentTemplateId { get; set; }
        @AuraEnabled public Boolean isSelected { get; set; }

        // NEW FIELDS FOR RELATED OBJECTS
        @AuraEnabled public String recordSourceType { get; set; }
        @AuraEnabled public String selectedRelationship { get; set; }
        @AuraEnabled public String relationshipType { get; set; }
        @AuraEnabled public String relationshipName { get; set; }
        @AuraEnabled public String relatedObjectApi { get; set; }
        @AuraEnabled public String childRecordType { get; set; }
        @AuraEnabled public String filterConditionsJson { get; set; }
        @AuraEnabled public String orderByField { get; set; }
        @AuraEnabled public String orderByDirection { get; set; }
        @AuraEnabled public Integer singleChildLimit { get; set; }
        @AuraEnabled public Integer maxChildRecords { get; set; }
        @AuraEnabled public String fileNamePattern { get; set; }
    }
    
    public class RecipientData {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String sourceType { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Boolean isRequired { get; set; }
        @AuraEnabled public Boolean isEditable { get; set; }
        @AuraEnabled public Boolean isValid { get; set; }
    }
    
    public class PreparedEmailData {
        @AuraEnabled public List<RecipientData> toRecipients { get; set; }
        @AuraEnabled public List<RecipientData> ccRecipients { get; set; }
        @AuraEnabled public List<RecipientData> bccRecipients { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String body { get; set; }
        @AuraEnabled public String fromAddressId { get; set; }
        @AuraEnabled public String fromAddressLabel { get; set; }
        @AuraEnabled public String replyTo { get; set; }
        @AuraEnabled public List<EmailPdfGenerator.AttachmentInfo> attachments { get; set; }
        @AuraEnabled public Boolean allowAdditionalRecipients { get; set; }
        @AuraEnabled public Boolean allowFileUpload { get; set; }
    }
    
    public class EmailResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String activityId { get; set; }
    }
    
    // ============ GET OBJECT API NAME FROM RECORD ID ============
    
    @AuraEnabled(cacheable=true)
    public static String getObjectApiName(Id recordId) {
        if (recordId == null) {
            return null;
        }
        return recordId.getSObjectType().getDescribe().getName();
    }
    
    // ============ PREPARE EMAIL DATA ============
    
    @AuraEnabled
    public static PreparedEmailData prepareEmailFromTemplate(String templateId, String recordId) {
        try {
            if (String.isBlank(templateId) || String.isBlank(recordId)) {
                throw new AuraHandledException('Template ID and Record ID are required');
            }
            
            EmailTemplateConfigController.TemplateWrapper template = 
                EmailTemplateConfigController.getTemplateById(templateId);
            
            if (template == null) {
                throw new AuraHandledException('Template not found');
            }
            
            String objectApiName = template.objectApiName;
            
            PreparedEmailData preparedData = new PreparedEmailData();
            
            preparedData.toRecipients = resolveRecipients(template.recipientsConfig, 'to', recordId, objectApiName);
            preparedData.ccRecipients = resolveRecipients(template.recipientsConfig, 'cc', recordId, objectApiName);
            preparedData.bccRecipients = resolveRecipients(template.recipientsConfig, 'bcc', recordId, objectApiName);
            
            preparedData.subject = EmailMergeFieldResolver.resolveMergeFields(
                template.subject, recordId, objectApiName
            );
            preparedData.body = EmailMergeFieldResolver.resolveMergeFields(
                template.emailBody, recordId, objectApiName
            );
            
            preparedData.fromAddressId = template.fromAddress;
            if (String.isNotBlank(template.fromAddress)) {
                preparedData.fromAddressLabel = getFromAddressLabel(template.fromAddress);
            }
            
            preparedData.replyTo = template.replyTo;
            
            preparedData.attachments = EmailPdfGenerator.getAttachmentInfoList(
                template.attachmentsConfig, recordId, objectApiName
            );
            
            preparedData.allowAdditionalRecipients = template.allowAdditionalRecipients;
            preparedData.allowFileUpload = template.allowFileUpload;
            
            return preparedData;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error preparing email: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static PreparedEmailData prepareBlankEmail(String recordId, String objectApiName) {
        try {
            PreparedEmailData preparedData = new PreparedEmailData();
            
            preparedData.toRecipients = new List<RecipientData>();
            preparedData.ccRecipients = new List<RecipientData>();
            preparedData.bccRecipients = new List<RecipientData>();
            preparedData.subject = '';
            preparedData.body = '';
            preparedData.attachments = new List<EmailPdfGenerator.AttachmentInfo>();
            preparedData.allowAdditionalRecipients = true;
            preparedData.allowFileUpload = true;
            
            return preparedData;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error preparing blank email: ' + e.getMessage());
        }
    }
    
    // ============ RESOLVE RECIPIENTS ============
    
    private static List<RecipientData> resolveRecipients(
        String recipientsConfigJson, 
        String recipientType, 
        Id recordId, 
        String objectApiName
    ) {
        List<RecipientData> recipients = new List<RecipientData>();
        
        try {
            if (String.isBlank(recipientsConfigJson)) {
                return recipients;
            }
            
            Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(recipientsConfigJson);
            List<Object> recipientList = (List<Object>) config.get(recipientType);
            
            if (recipientList == null) {
                return recipients;
            }
            
            for (Object rec : recipientList) {
                Map<String, Object> recMap = (Map<String, Object>) rec;
                
                RecipientData data = new RecipientData();
                data.id = (String) recMap.get('id');
                data.type = recipientType.toUpperCase();
                data.sourceType = (String) recMap.get('sourceType');
                data.label = (String) recMap.get('label');
                data.isRequired = recMap.get('isRequired') == true;
                data.isEditable = recMap.get('isEditable') == true;
                
                String sourceType = data.sourceType;
                String fieldApiName = (String) recMap.get('fieldApiName');
                String staticEmail = (String) recMap.get('staticEmail');
                
                data.email = EmailMergeFieldResolver.resolveRecipientEmail(
                    sourceType, fieldApiName, staticEmail, recordId, objectApiName
                );
                
                data.isValid = String.isNotBlank(data.email) && isValidEmail(data.email);
                
                recipients.add(data);
            }
            
        } catch (Exception e) {
            System.debug('Error resolving recipients: ' + e.getMessage());
        }
        
        return recipients;
    }
    
    private static String getFromAddressLabel(String fromAddressId) {
        try {
            if (String.isBlank(fromAddressId)) {
                return null;
            }
            
            List<OrgWideEmailAddress> oweas = [
                SELECT DisplayName, Address
                FROM OrgWideEmailAddress
                WHERE Id = :fromAddressId
                LIMIT 1
            ];
            
            if (!oweas.isEmpty()) {
                return oweas[0].DisplayName + ' <' + oweas[0].Address + '>';
            }
            
        } catch (Exception e) {
            System.debug('Error getting from address: ' + e.getMessage());
        }
        
        return null;
    }
    
    // ============ SEND EMAIL ============
    
    @AuraEnabled
    public static EmailResult sendEmail(String emailDataJson) {
        EmailResult result = new EmailResult();
        
        try {
            if (String.isBlank(emailDataJson)) {
                throw new AuraHandledException('Email data is required');
            }
            
            EmailDataWrapper emailData = (EmailDataWrapper) JSON.deserialize(
                emailDataJson, EmailDataWrapper.class
            );
            
            validateEmailData(emailData);
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            
            if (emailData.toAddresses != null && !emailData.toAddresses.isEmpty()) {
                email.setToAddresses(emailData.toAddresses);
            }
            if (emailData.ccAddresses != null && !emailData.ccAddresses.isEmpty()) {
                email.setCcAddresses(emailData.ccAddresses);
            }
            if (emailData.bccAddresses != null && !emailData.bccAddresses.isEmpty()) {
                email.setBccAddresses(emailData.bccAddresses);
            }
            
            if (String.isNotBlank(emailData.fromAddressId)) {
                email.setOrgWideEmailAddressId(emailData.fromAddressId);
            }
            
            if (String.isNotBlank(emailData.replyTo)) {
                email.setReplyTo(emailData.replyTo);
            }
            
            email.setSubject(emailData.subject);
            email.setHtmlBody(emailData.body);
            
            if (String.isNotBlank(emailData.recordId)) {
                String objectApiName = emailData.objectApiName;
                if (isWhatIdSupported(objectApiName)) {
                    email.setWhatId(emailData.recordId);
                }
            }
            
            email.setSaveAsActivity(true);
            
            // ENHANCED: Generate attachments with related object support
            List<Messaging.EmailFileAttachment> attachments = generateAttachments(emailData);
            if (!attachments.isEmpty()) {
                email.setFileAttachments(attachments);
            }
            
            Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(
                new Messaging.SingleEmailMessage[] { email }
            );
            
            if (sendResults[0].isSuccess()) {
                result.success = true;
                result.message = 'Email sent successfully';
            } else {
                result.success = false;
                Messaging.SendEmailError[] errors = sendResults[0].getErrors();
                result.message = errors[0].getMessage();
            }
            
        } catch (AuraHandledException e) {
            result.success = false;
            result.message = e.getMessage();
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error sending email: ' + e.getMessage();
        }
        
        return result;
    }
    
    private static void validateEmailData(EmailDataWrapper emailData) {
        if (emailData.toAddresses == null || emailData.toAddresses.isEmpty()) {
            throw new AuraHandledException('At least one recipient is required');
        }
        
        if (String.isBlank(emailData.subject)) {
            throw new AuraHandledException('Subject is required');
        }
        
        if (String.isBlank(emailData.body)) {
            throw new AuraHandledException('Email body is required');
        }
        
        for (String email : emailData.toAddresses) {
            if (!isValidEmail(email)) {
                throw new AuraHandledException('Invalid email address: ' + email);
            }
        }
    }
    
    private static Boolean isValidEmail(String email) {
        if (String.isBlank(email)) {
            return false;
        }
        String emailRegex = '^[a-zA-Z0-9._|\\\\%#~`=?&/$^*!}{+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,4}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        Matcher matcher = emailPattern.matcher(email);
        return matcher.matches();
    }
    
    private static Boolean isWhatIdSupported(String objectApiName) {
        return PostSalesConstants.isWhatIdSupported(objectApiName);
    }
    
    // ============ ENHANCED: GENERATE ATTACHMENTS WITH RELATED OBJECT SUPPORT ============
    
    /**
     * @description Generate email attachments with related object support
     */
    private static List<Messaging.EmailFileAttachment> generateAttachments(EmailDataWrapper emailData) {
        List<Messaging.EmailFileAttachment> attachments = new List<Messaging.EmailFileAttachment>();
        
        try {
            // Process template attachments
            if (emailData.attachments != null && !emailData.attachments.isEmpty()) {
                for (AttachmentData att : emailData.attachments) {
                    if (att == null || att.isSelected == null || !att.isSelected) {
                        continue;
                    }
                    
                    if (att.type == PostSalesConstants.ATTACHMENT_TYPE_VF_PAGE) {
                        // Get record IDs based on configuration
                        List<Id> recordIds = resolveRecordIds(att, emailData.recordId, emailData.objectApiName);

                        // Build extra params (e.g., templateId for DynamicDocumentPDF)
                        Map<String, String> extraParams = new Map<String, String>();
                        if (String.isNotBlank(att.documentTemplateId)) {
                            extraParams.put('templateId', att.documentTemplateId);
                        }

                        // Generate PDF for each record ID
                        for (Id recordId : recordIds) {
                            String fileName = resolveFileName(att.fileNamePattern, att.name, recordId);

                            Messaging.EmailFileAttachment fileAtt = EmailPdfGenerator.generatePdfAttachment(
                                att.vfPageName,
                                recordId,
                                fileName,
                                'id',
                                extraParams
                            );

                            if (fileAtt != null) {
                                attachments.add(fileAtt);
                            }
                        }
                        
                    } else if (att.type == PostSalesConstants.ATTACHMENT_TYPE_STATIC_DOC) {
                        Messaging.EmailFileAttachment fileAtt = EmailPdfGenerator.getStaticDocumentAttachment(att.documentId);
                        if (fileAtt != null) {
                            attachments.add(fileAtt);
                        }
                    }
                }
            }
            
            // Process uploaded files
            if (emailData.uploadedFileIds != null && !emailData.uploadedFileIds.isEmpty()) {
                List<ContentVersion> files = [
                    SELECT Title, FileExtension, VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :emailData.uploadedFileIds
                    AND IsLatest = true
                ];
                
                for (ContentVersion cv : files) {
                    Messaging.EmailFileAttachment fileAtt = new Messaging.EmailFileAttachment();
                    fileAtt.setFileName(cv.Title + '.' + cv.FileExtension);
                    fileAtt.setBody(cv.VersionData);
                    attachments.add(fileAtt);
                }
            }
            
        } catch (Exception e) {
            System.debug('Error generating attachments: ' + e.getMessage());
        }
        
        return attachments;
    }
    
    // ============ NEW: RESOLVE RECORD IDS ============
    
    /**
     * @description Determine which record IDs to use based on attachment configuration
     */
    private static List<Id> resolveRecordIds(AttachmentData att, Id mainRecordId, String objectApiName) {
        List<Id> recordIds = new List<Id>();
        
        try {
            String recordSourceType = String.isNotBlank(att.recordSourceType) ? att.recordSourceType : PostSalesConstants.SOURCE_TYPE_DIRECT;
            
            if (recordSourceType == PostSalesConstants.SOURCE_TYPE_DIRECT) {
                recordIds.add(mainRecordId);
                
            } else if (recordSourceType == PostSalesConstants.SOURCE_TYPE_RELATED) {
                
                if (att.relationshipType == PostSalesConstants.RELATIONSHIP_TYPE_PARENT) {
                    Id parentId = queryParentRecord(mainRecordId, att.relationshipName, objectApiName);
                    if (parentId != null) {
                        recordIds.add(parentId);
                    }
                    
                } else if (att.relationshipType == PostSalesConstants.RELATIONSHIP_TYPE_CHILD) {
                    
                    if (att.childRecordType == PostSalesConstants.CHILD_RECORD_TYPE_ALL) {
                        recordIds = queryAllChildRecords(mainRecordId, att);
                    } else {
                        recordIds = querySingleChildRecord(mainRecordId, att);
                    }
                }
            }
            
        } catch (Exception e) {
            System.debug('Error resolving record IDs: ' + e.getMessage());
        }
        
        return recordIds;
    }
    
    // ============ NEW: QUERY PARENT RECORD ============
    
    /**
     * @description Query parent record through lookup field
     */
    private static Id queryParentRecord(Id mainRecordId, String relationshipName, String objectApiName) {
        try {
            String query = 'SELECT ' + String.escapeSingleQuotes(relationshipName) + 
                           ' FROM ' + String.escapeSingleQuotes(objectApiName) + 
                           ' WHERE Id = :mainRecordId LIMIT 1';
            
            List<SObject> results = Database.query(query);
            
            if (!results.isEmpty() && results[0].get(relationshipName) != null) {
                return (Id) results[0].get(relationshipName);
            }
            
        } catch (Exception e) {
            System.debug('Error querying parent record: ' + e.getMessage());
        }
        
        return null;
    }
    
    // ============ NEW: QUERY ALL CHILD RECORDS ============
    
    /**
     * @description Query all child records
     */
    private static List<Id> queryAllChildRecords(Id mainRecordId, AttachmentData att) {
        List<Id> ids = new List<Id>();
        
        try {
            Integer maxRecords = att.maxChildRecords != null ? att.maxChildRecords : PostSalesConstants.DEFAULT_MAX_CHILD_RECORDS;
            
            String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(att.relatedObjectApi) +
                           ' WHERE ' + String.escapeSingleQuotes(att.relationshipName) + ' = :mainRecordId' +
                           ' LIMIT ' + maxRecords;
            
            List<SObject> children = Database.query(query);
            
            for (SObject child : children) {
                ids.add(child.Id);
            }
            
        } catch (Exception e) {
            System.debug('Error querying all child records: ' + e.getMessage());
        }
        
        return ids;
    }
    
    // ============ NEW: QUERY SINGLE CHILD RECORD ============
    
    /**
     * @description Query single child record with filter, ORDER BY, and LIMIT
     */
    private static List<Id> querySingleChildRecord(Id mainRecordId, AttachmentData att) {
        List<Id> ids = new List<Id>();
        
        try {
            String whereClause = String.escapeSingleQuotes(att.relationshipName) + ' = :mainRecordId';
            
            if (String.isNotBlank(att.filterConditionsJson)) {
                String additionalFilter = buildFilterFromConditions(att.filterConditionsJson);
                if (String.isNotBlank(additionalFilter)) {
                    whereClause += ' AND ' + additionalFilter;
                }
            }
            
            String query = 'SELECT Id FROM ' + String.escapeSingleQuotes(att.relatedObjectApi) +
                           ' WHERE ' + whereClause;
            
            if (String.isNotBlank(att.orderByField)) {
                String direction = String.isNotBlank(att.orderByDirection) ? att.orderByDirection : PostSalesConstants.DEFAULT_ORDER_DIRECTION;
                query += ' ORDER BY ' + String.escapeSingleQuotes(att.orderByField) + ' ' + direction;
            }
            
            Integer limitNum = att.singleChildLimit != null ? att.singleChildLimit : PostSalesConstants.DEFAULT_SINGLE_CHILD_LIMIT;
            query += ' LIMIT ' + limitNum;
            
            System.debug('Single Child Query: ' + query);
            
            List<SObject> children = Database.query(query);
            
            for (SObject child : children) {
                ids.add(child.Id);
            }
            
        } catch (Exception e) {
            System.debug('Error querying single child record: ' + e.getMessage());
        }
        
        return ids;
    }
    
    // ============ NEW: BUILD FILTER FROM CONDITIONS ============
    
    /**
     * @description Build SOQL WHERE clause from filter conditions JSON
     */
    private static String buildFilterFromConditions(String filterConditionsJson) {
        List<String> clauses = new List<String>();
        
        try {
            List<Object> conditions = (List<Object>) JSON.deserializeUntyped(filterConditionsJson);
            
            for (Object condObj : conditions) {
                Map<String, Object> cond = (Map<String, Object>) condObj;
                String field = (String) cond.get('field');
                String operator = (String) cond.get('operator');
                String value = (String) cond.get('value');
                
                if (String.isNotBlank(field) && String.isNotBlank(value)) {
                    field = String.escapeSingleQuotes(field);
                    
                    if (!isNumeric(value) && !value.startsWith('\'')) {
                        value = String.escapeSingleQuotes(value);
                        
                        if (operator == 'LIKE') {
                            value = '\'%' + value + '%\'';
                        } else if (operator == 'STARTS_WITH') {
                            value = '\'' + value + '%\'';
                            operator = 'LIKE';
                        } else {
                            value = '\'' + value + '\'';
                        }
                    }
                    
                    clauses.add(field + ' ' + operator + ' ' + value);
                }
            }
            
        } catch (Exception e) {
            System.debug('Error building filter: ' + e.getMessage());
        }
        
        return String.join(clauses, ' AND ');
    }
    
    // ============ NEW: HELPER METHODS ============
    
    private static Boolean isNumeric(String value) {
        try {
            Decimal.valueOf(value);
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    private static String resolveFileName(String fileNamePattern, String defaultName, Id recordId) {
        try {
            if (String.isNotBlank(fileNamePattern)) {
                String objectApiName = recordId.getSObjectType().getDescribe().getName();
                return EmailMergeFieldResolver.resolveMergeFields(fileNamePattern, recordId, objectApiName);
            }
        } catch (Exception e) {
            System.debug('Error resolving file name: ' + e.getMessage());
        }
        
        return String.isNotBlank(defaultName) ? defaultName : PostSalesConstants.DEFAULT_ATTACHMENT_FILENAME;
    }
    
    // ============ GET RELATED FILES ============
    
    @AuraEnabled
    public static List<Map<String, Object>> getRelatedFiles(String recordId) {
        List<Map<String, Object>> files = new List<Map<String, Object>>();
        
        try {
            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId, ContentDocument.Title, 
                       ContentDocument.FileExtension, ContentDocument.ContentSize
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :recordId
                ORDER BY ContentDocument.Title
            ];
            
            for (ContentDocumentLink link : links) {
                Map<String, Object> fileInfo = new Map<String, Object>();
                fileInfo.put('id', link.ContentDocumentId);
                fileInfo.put('name', link.ContentDocument.Title);
                fileInfo.put('extension', link.ContentDocument.FileExtension);
                fileInfo.put('size', link.ContentDocument.ContentSize);
                fileInfo.put('fileName', link.ContentDocument.Title + '.' + link.ContentDocument.FileExtension);
                files.add(fileInfo);
            }
            
        } catch (Exception e) {
            System.debug('Error getting related files: ' + e.getMessage());
        }
        
        return files;
    }

    // ============ EMAIL HISTORY ============

    public class TemplateWithMatchStatus {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public Boolean isDefault { get; set; }
        @AuraEnabled public String actionBinding { get; set; }
        @AuraEnabled public String matchingCriteria { get; set; }
        @AuraEnabled public Boolean criteriaMatched { get; set; }
        @AuraEnabled public String matchSummary { get; set; }
        @AuraEnabled public Boolean alreadySent { get; set; }
        @AuraEnabled public String sentDate { get; set; }
    }

    @AuraEnabled
    public static List<TemplateWithMatchStatus> getTemplatesWithMatchStatus(String recordId, String objectApiName) {
        List<TemplateWithMatchStatus> results = new List<TemplateWithMatchStatus>();

        if (String.isBlank(objectApiName) && String.isNotBlank(recordId)) {
            objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
        }

        if (String.isBlank(objectApiName)) return results;

        List<Email_Template_Config__c> templates = [
            SELECT Id, Template_Name__c, Description__c, Subject__c,
                   Is_Default__c, Action_Binding__c, Matching_Criteria__c
            FROM Email_Template_Config__c
            WHERE Object_API_Name__c = :objectApiName
            AND Is_Active__c = true
            ORDER BY Is_Default__c DESC, Template_Name__c ASC
        ];

        // Check which templates have already been sent for this record
        // by looking at email activity (Task with email subtype or EmailMessage)
        Set<String> sentSubjects = new Set<String>();
        if (String.isNotBlank(recordId)) {
            try {
                for (EmailMessage em : [
                    SELECT Subject FROM EmailMessage
                    WHERE RelatedToId = :recordId
                    ORDER BY MessageDate DESC LIMIT 100
                ]) {
                    if (em.Subject != null) sentSubjects.add(em.Subject.toLowerCase());
                }
            } catch (Exception e) { /* EmailMessage may not be available */ }

            try {
                for (Task t : [
                    SELECT Subject FROM Task
                    WHERE WhatId = :recordId AND TaskSubtype = 'Email'
                    ORDER BY ActivityDate DESC LIMIT 100
                ]) {
                    if (t.Subject != null) sentSubjects.add(t.Subject.toLowerCase());
                }
            } catch (Exception e) { /* skip */ }
        }

        for (Email_Template_Config__c tmpl : templates) {
            TemplateWithMatchStatus item = new TemplateWithMatchStatus();
            item.id = tmpl.Id;
            item.name = tmpl.Template_Name__c;
            item.description = tmpl.Description__c;
            item.subject = tmpl.Subject__c;
            item.isDefault = tmpl.Is_Default__c;
            item.actionBinding = tmpl.Action_Binding__c;
            item.matchingCriteria = tmpl.Matching_Criteria__c;

            // Evaluate matching criteria
            if (String.isBlank(tmpl.Matching_Criteria__c)) {
                item.criteriaMatched = true;
                item.matchSummary = 'Applies to all records';
            } else {
                try {
                    item.criteriaMatched = ConfigMatchingService.evaluateCriteria(
                        tmpl.Matching_Criteria__c, Id.valueOf(recordId), objectApiName
                    );
                    item.matchSummary = item.criteriaMatched ? 'Criteria matched' : 'Criteria not met';
                } catch (Exception e) {
                    item.criteriaMatched = false;
                    item.matchSummary = 'Error evaluating criteria';
                }
            }

            // Check if already sent by matching subject pattern
            item.alreadySent = false;
            if (String.isNotBlank(tmpl.Subject__c) && !sentSubjects.isEmpty()) {
                String templateSubjectLower = tmpl.Subject__c.toLowerCase()
                    .replaceAll('\\{[^}]+\\}', ''); // strip merge fields for matching
                for (String sentSubj : sentSubjects) {
                    if (sentSubj.containsIgnoreCase(templateSubjectLower.trim()) ||
                        templateSubjectLower.trim().length() > 3 && sentSubj.contains(templateSubjectLower.trim())) {
                        item.alreadySent = true;
                        break;
                    }
                }
            }

            results.add(item);
        }

        return results;
    }

    public class EmailHistoryItem {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String toAddress { get; set; }
        @AuraEnabled public DateTime sentDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String senderName { get; set; }
        @AuraEnabled public Boolean hasAttachment { get; set; }
        @AuraEnabled public String messageId { get; set; }
    }

    @AuraEnabled
    public static List<EmailHistoryItem> getEmailHistory(String recordId) {
        List<EmailHistoryItem> history = new List<EmailHistoryItem>();
        if (String.isBlank(recordId)) return history;

        // Query EmailMessage records linked to the record
        try {
            List<EmailMessage> emails = [
                SELECT Id, Subject, ToAddress, MessageDate, Status,
                       CreatedBy.Name, HasAttachment, RelatedToId
                FROM EmailMessage
                WHERE RelatedToId = :recordId
                ORDER BY MessageDate DESC
                LIMIT 50
            ];

            for (EmailMessage em : emails) {
                EmailHistoryItem item = new EmailHistoryItem();
                item.id = em.Id;
                item.subject = em.Subject;
                item.toAddress = em.ToAddress;
                item.sentDate = em.MessageDate;
                item.status = em.Status == '3' ? 'Sent' : (em.Status == '0' ? 'New' : em.Status);
                item.senderName = em.CreatedBy.Name;
                item.hasAttachment = em.HasAttachment;
                item.messageId = em.Id;
                history.add(item);
            }
        } catch (Exception e) {
            // EmailMessage may not be available - fall back to Task records
            System.debug('EmailMessage query failed, trying Tasks: ' + e.getMessage());
        }

        // Also query Task records with email subtype
        try {
            List<Task> emailTasks = [
                SELECT Id, Subject, Description, ActivityDate, Status,
                       Owner.Name, WhatId
                FROM Task
                WHERE WhatId = :recordId
                AND TaskSubtype = 'Email'
                ORDER BY ActivityDate DESC
                LIMIT 50
            ];

            Set<String> existingSubjects = new Set<String>();
            for (EmailHistoryItem h : history) {
                if (h.subject != null) existingSubjects.add(h.subject);
            }

            for (Task t : emailTasks) {
                // Skip if already captured via EmailMessage
                if (existingSubjects.contains(t.Subject)) continue;

                EmailHistoryItem item = new EmailHistoryItem();
                item.id = t.Id;
                item.subject = t.Subject;
                item.sentDate = t.ActivityDate != null ? DateTime.newInstance(t.ActivityDate, Time.newInstance(0, 0, 0, 0)) : null;
                item.status = 'Sent';
                item.senderName = t.Owner.Name;
                item.hasAttachment = false;
                history.add(item);
            }
        } catch (Exception e) {
            System.debug('Task email query failed: ' + e.getMessage());
        }

        // Sort by date descending
        history.sort();
        return history;
    }
}