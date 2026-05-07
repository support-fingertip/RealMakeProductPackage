/**
 * @description Service to auto-create Demands from approved Debit Notes.
 *              When a debit note is approved and Auto_Create_Demand__c is true,
 *              this service creates a Demand__c record linked to the debit note's
 *              payment schedule and booking, and links the demand back to the debit note.
 * @author System
 * @date 2026-03-30
 */
public with sharing class DebitNoteApplicationService {

    /**
     * @description Flow input wrapper for invocable method
     */
    public class FlowInput {
        @InvocableVariable(required=true label='Debit Note Id')
        public Id debitNoteId;
    }

    /**
     * @description Flow output wrapper
     */
    public class FlowOutput {
        @InvocableVariable(label='Created Demand Id')
        public Id demandId;

        @InvocableVariable(label='Demand Created')
        public Boolean demandCreated;
    }

    /**
     * @description Invocable entry point callable from Flows
     */
    @InvocableMethod(label='Create Demand from Debit Note' description='Auto-creates a demand when a debit note is approved with Auto Create Demand enabled' category='Financial')
    public static List<FlowOutput> createDemandsFromFlow(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();
        List<Id> debitNoteIds = new List<Id>();

        for (FlowInput input : inputs) {
            if (input.debitNoteId != null) {
                debitNoteIds.add(input.debitNoteId);
            }
        }

        Map<Id, FlowOutput> resultMap = createDemandsFromDebitNotes(debitNoteIds);

        for (FlowInput input : inputs) {
            if (resultMap.containsKey(input.debitNoteId)) {
                outputs.add(resultMap.get(input.debitNoteId));
            } else {
                FlowOutput out = new FlowOutput();
                out.demandCreated = false;
                outputs.add(out);
            }
        }

        return outputs;
    }

    /**
     * @description Core logic: for each approved debit note with Auto_Create_Demand__c = true,
     *              create a Demand record and link it back to the debit note.
     * @param debitNoteIds List of debit note IDs
     * @return Map of debit note ID to FlowOutput with results
     */
    private static Map<Id, FlowOutput> createDemandsFromDebitNotes(List<Id> debitNoteIds) {
        Map<Id, FlowOutput> resultMap = new Map<Id, FlowOutput>();

        if (debitNoteIds == null || debitNoteIds.isEmpty()) {
            return resultMap;
        }

        // Query debit notes that are approved with auto-create demand enabled
        List<Debit_Note__c> debitNotes = [
            SELECT Id, Booking__c, Debit_Amount__c, Debit_Date__c,
                   Payment_Schedule__c, Debit_Against__c, Debit_Type__c,
                   Description__c, Auto_Create_Demand__c, Demands__c,
                   Payment_Due_Date__c
            FROM Debit_Note__c
            WHERE Id IN :debitNoteIds
            AND Auto_Create_Demand__c = true
            AND Demands__c = null
        ];

        if (debitNotes.isEmpty()) {
            return resultMap;
        }

        List<Demands__c> demandsToInsert = new List<Demands__c>();
        Map<Integer, Debit_Note__c> indexToDebitNote = new Map<Integer, Debit_Note__c>();
        Integer idx = 0;

        for (Debit_Note__c dn : debitNotes) {
            Demands__c demand = new Demands__c();
            demand.Booking__c = dn.Booking__c;
            demand.Demand_Amount__c = dn.Debit_Amount__c;
            demand.Pending_Amount__c = dn.Debit_Amount__c;
            demand.Demand_Date__c = dn.Debit_Date__c != null ? dn.Debit_Date__c : Date.today();
            demand.Due_Date__c = dn.Payment_Due_Date__c != null ? dn.Payment_Due_Date__c : Date.today().addDays(30);
            demand.Demand_Type__c = PostSalesConstants.DEMAND_TYPE_DEBIT_NOTE;
            demand.Status__c = PostSalesConstants.DEMAND_STATUS_RAISED;
            demand.Reminder_Date__c = demand.Demand_Date__c;
            demand.Notes__c = 'Auto-created from Debit Note: ' + dn.Id;

            // Link to payment schedule if available (Next Demand / Last Demand resolved)
            if (dn.Payment_Schedule__c != null) {
                demand.Payment_Schedule__c = dn.Payment_Schedule__c;
            }

            demandsToInsert.add(demand);
            indexToDebitNote.put(idx, dn);
            idx++;
        }

        if (!demandsToInsert.isEmpty()) {
            insert demandsToInsert;

            // Link demands back to debit notes
            List<Debit_Note__c> debitNotesToUpdate = new List<Debit_Note__c>();
            List<Id> createdDemandIds = new List<Id>();

            for (Integer i = 0; i < demandsToInsert.size(); i++) {
                Demands__c demand = demandsToInsert[i];
                Debit_Note__c dn = indexToDebitNote.get(i);

                Debit_Note__c dnUpdate = new Debit_Note__c();
                dnUpdate.Id = dn.Id;
                dnUpdate.Demands__c = demand.Id;
                debitNotesToUpdate.add(dnUpdate);

                createdDemandIds.add(demand.Id);

                FlowOutput output = new FlowOutput();
                output.demandId = demand.Id;
                output.demandCreated = true;
                resultMap.put(dn.Id, output);
            }

            update debitNotesToUpdate;

            // Auto-send demand emails if configured in Post Sales Admin
            sendDemandEmails(createdDemandIds);
        }

        return resultMap;
    }

    /**
     * @description Sends demand emails with document template attachment for individually created demands.
     *              Reads email template and document template from Post_Sales_Configuration__c (type = 'Demand').
     *              Only sends if Auto_Send_Email__c is enabled or an email template is configured.
     * @param demandIds List of demand IDs to send emails for
     */
    private static void sendDemandEmails(List<Id> demandIds) {
        if (demandIds == null || demandIds.isEmpty()) return;

        try {
            // Load Demand config from Post Sales Admin
            List<Post_Sales_Configuration__c> configs = [
                SELECT Email_Template__c, Document_Template__c, Auto_Send_Email__c
                FROM Post_Sales_Configuration__c
                WHERE Configuration_Type__c = 'Demand'
                AND Is_Active__c = true
                LIMIT 1
            ];

            if (configs.isEmpty()) return;

            Post_Sales_Configuration__c config = configs[0];

            // Only send if auto-send is enabled or email template is configured
            if (config.Auto_Send_Email__c != true && config.Email_Template__c == null) return;

            // Query demands with booking email
            List<Demands__c> demands = [
                SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.Name,
                       Booking__r.OwnerId, Booking__r.First_Applicant_Name__c,
                       Demand_Amount__c, Pending_Amount__c, Due_Date__c
                FROM Demands__c
                WHERE Id IN :demandIds
                AND Booking__r.Email__c != null
            ];

            if (demands.isEmpty()) return;

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            List<Demands__c> demandsToUpdate = new List<Demands__c>();

            for (Demands__c demand : demands) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ demand.Booking__r.Email__c });
                email.setSaveAsActivity(true);

                List<Messaging.EmailFileAttachment> fileAttachments = new List<Messaging.EmailFileAttachment>();

                if (config.Email_Template__c != null) {
                    // Use email template from Post Sales Admin
                    EmailSenderController.PreparedEmailData prepared =
                        EmailSenderController.prepareEmailFromTemplate(config.Email_Template__c, demand.Id);

                    email.setSubject(prepared.subject);
                    email.setHtmlBody(prepared.body);

                    // Include attachments from email template config
                    if (prepared.attachments != null) {
                        for (EmailPdfGenerator.AttachmentInfo att : prepared.attachments) {
                            if (att.isSelected == true && att.type == 'VFPage' && String.isNotBlank(att.VFPageName)) {
                                Map<String, String> extraParams = new Map<String, String>();
                                if (String.isNotBlank(att.documentTemplateId)) {
                                    extraParams.put('templateId', att.documentTemplateId);
                                }
                                Messaging.EmailFileAttachment pdfAtt = EmailPdfGenerator.generatePdfAttachment(
                                    att.VFPageName, demand.Id, att.fileName, att.VFParamName, extraParams
                                );
                                if (pdfAtt != null) fileAttachments.add(pdfAtt);
                            } else if (att.isSelected == true && att.type == 'StaticDocument' && String.isNotBlank(att.documentId)) {
                                Messaging.EmailFileAttachment staticAtt = EmailPdfGenerator.getStaticDocumentAttachment(att.documentId);
                                if (staticAtt != null) fileAttachments.add(staticAtt);
                            }
                        }
                    }
                } else {
                    // Fallback simple email
                    email.setSubject('Payment Demand - ' + demand.Booking__r.Name + ' - ' + demand.Name);
                    String body = '<p>Dear ' + (demand.Booking__r.First_Applicant_Name__c != null ? demand.Booking__r.First_Applicant_Name__c : 'Customer') + ',</p>';
                    body += '<p>A payment demand has been raised for Booking <strong>' + demand.Booking__r.Name + '</strong>.</p>';
                    body += '<p>Demand Amount: ' + PostSalesConstants.formatCurrency(demand.Demand_Amount__c) + '</p>';
                    if (demand.Due_Date__c != null) {
                        body += '<p>Due Date: ' + demand.Due_Date__c.format() + '</p>';
                    }
                    body += '<p>Please contact us for any queries.</p>';
                    email.setHtmlBody(body);
                }

                // Fallback: attach Document Template PDF from Post Sales Admin if no template attachments
                if (fileAttachments.isEmpty() && config.Document_Template__c != null) {
                    Map<String, String> extraParams = new Map<String, String>();
                    extraParams.put('templateId', config.Document_Template__c);
                    Messaging.EmailFileAttachment pdfAtt = EmailPdfGenerator.generatePdfAttachment(
                        'DynamicDocumentPDF', demand.Id,
                        'Demand_' + demand.Name + '.pdf', 'id', extraParams
                    );
                    if (pdfAtt != null) fileAttachments.add(pdfAtt);
                }

                if (!fileAttachments.isEmpty()) {
                    email.setFileAttachments(fileAttachments);
                }

                emails.add(email);

                // Track email sent
                Demands__c dUpdate = new Demands__c();
                dUpdate.Id = demand.Id;
                dUpdate.Email_Sent__c = true;
                dUpdate.Email_Sent_Date__c = Date.today();
                dUpdate.Email_Sent_To__c = demand.Booking__r.Email__c;
                dUpdate.Status__c = PostSalesConstants.DEMAND_STATUS_EMAILED;
                demandsToUpdate.add(dUpdate);
            }

            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails, false);
            }
            if (!demandsToUpdate.isEmpty()) {
                update demandsToUpdate;
            }

        } catch (Exception e) {
            System.debug('DebitNoteApplicationService.sendDemandEmails error: ' + e.getMessage());
        }
    }
}