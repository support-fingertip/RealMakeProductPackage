/**
 * @description Core service for processing demand reminders and automatic unit unblocking.
 *              All reminder configuration is project-level: each Project defines days for
 *              1st Reminder, 2nd Reminder, Termination Mail, and Unit Unblocking with
 *              enable/disable toggles for each.
 *
 *              Reminder dates are set on Demand records at creation time based on the
 *              Project config. This service is called by DemandReminderSchedulable daily
 *              to process due reminders.
 *
 *              Uses Post_Sales_Configuration__c to look up the correct email template
 *              for each reminder type (Demand Reminder 1, Demand Reminder 2, Termination Mail,
 *              Unit Unblocking).
 * @author System
 * @date 2026-03-29
 */
public with sharing class DemandReminderService {

    // ==================== PUBLIC METHODS ====================

    /**
     * @description Populates reminder dates on a Demand record based on Project configuration.
     *              Should be called when a Demand is created or when demand date changes.
     * @param demands List of Demands with Booking__c populated
     */
    public static void populateReminderDates(List<Demands__c> demands) {
        if (demands == null || demands.isEmpty()) return;

        // Collect project IDs via bookings
        Set<Id> bookingIds = new Set<Id>();
        for (Demands__c d : demands) {
            if (d.Booking__c != null) bookingIds.add(d.Booking__c);
        }

        if (bookingIds.isEmpty()) return;

        Map<Id, Id> bookingToProject = new Map<Id, Id>();
        for (Booking__c b : [SELECT Id, Project__c FROM Booking__c WHERE Id IN :bookingIds]) {
            bookingToProject.put(b.Id, b.Project__c);
        }

        Set<Id> projectIds = new Set<Id>(bookingToProject.values());
        Map<Id, Project__c> projectMap = new Map<Id, Project__c>([
            SELECT Id, Enable_Reminder_1__c, Reminder_1_Days__c,
                   Enable_Reminder_2__c, Reminder_2_Days__c,
                   Enable_Reminder_3__c, Reminder_3_Days__c,
                   Enable_Reminder_4__c, Reminder_4_Days__c,
                   Enable_Termination_Mail__c, Termination_Mail_Days__c,
                   Enable_Auto_Unit_Unblocking__c, Unit_Unblocking_Days__c
            FROM Project__c
            WHERE Id IN :projectIds
        ]);

        for (Demands__c d : demands) {
            Id projectId = bookingToProject.get(d.Booking__c);
            if (projectId == null) continue;

            Project__c project = projectMap.get(projectId);
            if (project == null) continue;

            Date demandDate = d.Demand_Date__c != null ? d.Demand_Date__c : Date.today();

            // Store project reference
            d.Project__c = projectId;

            // 1st Reminder
            if (project.Enable_Reminder_1__c && project.Reminder_1_Days__c != null && project.Reminder_1_Days__c > 0) {
                d.Reminder_1_Date__c = demandDate.addDays(Integer.valueOf(project.Reminder_1_Days__c));
            }

            // 2nd Reminder
            if (project.Enable_Reminder_2__c && project.Reminder_2_Days__c != null && project.Reminder_2_Days__c > 0) {
                d.Reminder_2_Date__c = demandDate.addDays(Integer.valueOf(project.Reminder_2_Days__c));
            }

            // 3rd Reminder
            if (project.Enable_Reminder_3__c && project.Reminder_3_Days__c != null && project.Reminder_3_Days__c > 0) {
                d.Reminder_3_Date__c = demandDate.addDays(Integer.valueOf(project.Reminder_3_Days__c));
            }

            // 4th Reminder
            if (project.Enable_Reminder_4__c && project.Reminder_4_Days__c != null && project.Reminder_4_Days__c > 0) {
                d.Reminder_4_Date__c = demandDate.addDays(Integer.valueOf(project.Reminder_4_Days__c));
            }

            // Termination Mail
            if (project.Enable_Termination_Mail__c && project.Termination_Mail_Days__c != null && project.Termination_Mail_Days__c > 0) {
                d.Termination_Mail_Date__c = demandDate.addDays(Integer.valueOf(project.Termination_Mail_Days__c));
            }

            // Unit Unblocking
            if (project.Enable_Auto_Unit_Unblocking__c && project.Unit_Unblocking_Days__c != null && project.Unit_Unblocking_Days__c > 0) {
                d.Unit_Unblocking_Date__c = demandDate.addDays(Integer.valueOf(project.Unit_Unblocking_Days__c));
            }
        }
    }

    /**
     * @description Main method called by the scheduled job daily.
     *              Processes all pending reminders that are due today or overdue.
     * @return ProcessingResult with counts of actions taken
     */
    public static ProcessingResult processDueReminders() {
        ProcessingResult result = new ProcessingResult();
        Date today = Date.today();

        // Load email template configs for each reminder type
        Map<String, Post_Sales_Configuration__c> templateConfigs = loadReminderConfigs();

        // Load master config document templates as fallback
        Map<String, Id> masterDocTemplates = loadMasterConfigDocTemplates();

        // Process 1st Reminders
        result.reminder1Count = processReminder1(today, templateConfigs.get('Demand Reminder 1'), masterDocTemplates.get('reminder1'));

        // Process 2nd Reminders
        result.reminder2Count = processReminder2(today, templateConfigs.get('Demand Reminder 2'), masterDocTemplates.get('reminder2'));

        // Process 3rd Reminders
        result.reminder3Count = processReminder3(today, templateConfigs.get('Demand Reminder 3'), masterDocTemplates.get('reminder3'));

        // Process 4th Reminders
        result.reminder4Count = processReminder4(today, templateConfigs.get('Demand Reminder 4'), masterDocTemplates.get('reminder4'));

        // Process Termination Mails
        result.terminationCount = processTerminationMails(today, templateConfigs.get('Termination Mail'));

        // Process Unit Unblocking
        result.unblockingCount = processUnitUnblocking(today, templateConfigs.get('Unit Unblocking'));

        return result;
    }

    // ==================== REMINDER PROCESSING ====================

    private static Integer processReminder1(Date today, Post_Sales_Configuration__c config, Id masterDocTemplateId) {
        List<Demands__c> demands = [
            SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.OwnerId,
                   Booking__r.Name, Booking__r.First_Applicant_Name__c,
                   Demand_Amount__c, Pending_Amount__c, Due_Date__c,
                   Reminder_1_Date__c, Project__c
            FROM Demands__c
            WHERE Reminder_1_Date__c <= :today
            AND Reminder_1_Sent__c = false
            AND Reminders_Disabled__c = false
            AND Status__c NOT IN ('Paid', 'Cancelled')
            AND Pending_Amount__c > 0
            LIMIT 200
        ];

        if (demands.isEmpty()) return 0;

        List<Demands__c> toUpdate = new List<Demands__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Demands__c d : demands) {
            // Send email
            if (String.isNotBlank(d.Booking__r.Email__c)) {
                Messaging.SingleEmailMessage email = buildReminderEmail(d, config, '1st Reminder', masterDocTemplateId);
                if (email != null) emails.add(email);
            }

            d.Reminder_1_Sent__c = true;
            d.Reminder_1_Sent_Date__c = DateTime.now();
            d.Number_of_Reminders__c = (d.Number_of_Reminders__c != null ? d.Number_of_Reminders__c : 0) + 1;
            d.Last_Reminder_Date__c = today;
            d.Status__c = PostSalesConstants.DEMAND_STATUS_REMINDER_SENT;
            toUpdate.add(d);
        }

        sendEmails(emails);
        if (!toUpdate.isEmpty()) update toUpdate;

        // Send bell notifications to booking owners
        sendReminderNotifications(demands, '1st Demand Reminder sent');

        return demands.size();
    }

    private static Integer processReminder2(Date today, Post_Sales_Configuration__c config, Id masterDocTemplateId) {
        List<Demands__c> demands = [
            SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.OwnerId,
                   Booking__r.Name, Booking__r.First_Applicant_Name__c,
                   Demand_Amount__c, Pending_Amount__c, Due_Date__c,
                   Reminder_2_Date__c, Project__c
            FROM Demands__c
            WHERE Reminder_2_Date__c <= :today
            AND Reminder_2_Sent__c = false
            AND Reminders_Disabled__c = false
            AND Status__c NOT IN ('Paid', 'Cancelled')
            AND Pending_Amount__c > 0
            LIMIT 200
        ];

        if (demands.isEmpty()) return 0;

        List<Demands__c> toUpdate = new List<Demands__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Demands__c d : demands) {
            if (String.isNotBlank(d.Booking__r.Email__c)) {
                Messaging.SingleEmailMessage email = buildReminderEmail(d, config, '2nd Reminder', masterDocTemplateId);
                if (email != null) emails.add(email);
            }

            d.Reminder_2_Sent__c = true;
            d.Reminder_2_Sent_Date__c = DateTime.now();
            d.Number_of_Reminders__c = (d.Number_of_Reminders__c != null ? d.Number_of_Reminders__c : 0) + 1;
            d.Last_Reminder_Date__c = today;
            toUpdate.add(d);
        }

        sendEmails(emails);
        if (!toUpdate.isEmpty()) update toUpdate;

        sendReminderNotifications(demands, '2nd Demand Reminder sent');

        return demands.size();
    }

    private static Integer processReminder3(Date today, Post_Sales_Configuration__c config, Id masterDocTemplateId) {
        List<Demands__c> demands = [
            SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.OwnerId,
                   Booking__r.Name, Booking__r.First_Applicant_Name__c,
                   Demand_Amount__c, Pending_Amount__c, Due_Date__c,
                   Reminder_3_Date__c, Project__c
            FROM Demands__c
            WHERE Reminder_3_Date__c <= :today
            AND Reminder_3_Sent__c = false
            AND Reminders_Disabled__c = false
            AND Status__c NOT IN ('Paid', 'Cancelled')
            AND Pending_Amount__c > 0
            LIMIT 200
        ];

        if (demands.isEmpty()) return 0;

        List<Demands__c> toUpdate = new List<Demands__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Demands__c d : demands) {
            if (String.isNotBlank(d.Booking__r.Email__c)) {
                Messaging.SingleEmailMessage email = buildReminderEmail(d, config, '3rd Reminder', masterDocTemplateId);
                if (email != null) emails.add(email);
            }

            d.Reminder_3_Sent__c = true;
            d.Reminder_3_Sent_Date__c = DateTime.now();
            d.Number_of_Reminders__c = (d.Number_of_Reminders__c != null ? d.Number_of_Reminders__c : 0) + 1;
            d.Last_Reminder_Date__c = today;
            toUpdate.add(d);
        }

        sendEmails(emails);
        if (!toUpdate.isEmpty()) update toUpdate;

        sendReminderNotifications(demands, '3rd Demand Reminder sent');

        return demands.size();
    }

    private static Integer processReminder4(Date today, Post_Sales_Configuration__c config, Id masterDocTemplateId) {
        List<Demands__c> demands = [
            SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.OwnerId,
                   Booking__r.Name, Booking__r.First_Applicant_Name__c,
                   Demand_Amount__c, Pending_Amount__c, Due_Date__c,
                   Reminder_4_Date__c, Project__c
            FROM Demands__c
            WHERE Reminder_4_Date__c <= :today
            AND Reminder_4_Sent__c = false
            AND Reminders_Disabled__c = false
            AND Status__c NOT IN ('Paid', 'Cancelled')
            AND Pending_Amount__c > 0
            LIMIT 200
        ];

        if (demands.isEmpty()) return 0;

        List<Demands__c> toUpdate = new List<Demands__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Demands__c d : demands) {
            if (String.isNotBlank(d.Booking__r.Email__c)) {
                Messaging.SingleEmailMessage email = buildReminderEmail(d, config, '4th Reminder', masterDocTemplateId);
                if (email != null) emails.add(email);
            }

            d.Reminder_4_Sent__c = true;
            d.Reminder_4_Sent_Date__c = DateTime.now();
            d.Number_of_Reminders__c = (d.Number_of_Reminders__c != null ? d.Number_of_Reminders__c : 0) + 1;
            d.Last_Reminder_Date__c = today;
            toUpdate.add(d);
        }

        sendEmails(emails);
        if (!toUpdate.isEmpty()) update toUpdate;

        sendReminderNotifications(demands, '4th Demand Reminder sent');

        return demands.size();
    }

    private static Integer processTerminationMails(Date today, Post_Sales_Configuration__c config) {
        Id masterDocTemplateId = null; // Termination uses config-level doc template only
        List<Demands__c> demands = [
            SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.OwnerId,
                   Booking__r.Name, Booking__r.First_Applicant_Name__c,
                   Booking__r.Project__r.Include_Interest_In_Termination__c,
                   Booking__r.Project__r.Interest_Rate__c,
                   Demand_Amount__c, Pending_Amount__c, Interest_Amount__c,
                   Due_Date__c, Termination_Mail_Date__c, Project__c
            FROM Demands__c
            WHERE Termination_Mail_Date__c <= :today
            AND Termination_Mail_Sent__c = false
            AND Reminders_Disabled__c = false
            AND Status__c NOT IN ('Paid', 'Cancelled')
            AND Pending_Amount__c > 0
            LIMIT 200
        ];

        if (demands.isEmpty()) return 0;

        List<Demands__c> toUpdate = new List<Demands__c>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Demands__c d : demands) {
            if (String.isNotBlank(d.Booking__r.Email__c)) {
                Messaging.SingleEmailMessage email = buildReminderEmail(d, config, 'Termination Notice', masterDocTemplateId);
                if (email != null) emails.add(email);
            }

            d.Termination_Mail_Sent__c = true;
            d.Termination_Mail_Sent_Date__c = DateTime.now();
            d.Status__c = PostSalesConstants.DEMAND_STATUS_OVERDUE;
            toUpdate.add(d);
        }

        sendEmails(emails);
        if (!toUpdate.isEmpty()) update toUpdate;

        sendReminderNotifications(demands, 'Termination mail sent - payment overdue');

        return demands.size();
    }

    private static Integer processUnitUnblocking(Date today, Post_Sales_Configuration__c config) {
        Id masterDocTemplateId = null; // Unit unblocking uses config-level doc template only
        List<Demands__c> demands = [
            SELECT Id, Name, Booking__c, Booking__r.Email__c, Booking__r.OwnerId,
                   Booking__r.Name, Booking__r.First_Applicant_Name__c,
                   Booking__r.Unit__c, Booking__r.Status__c,
                   Demand_Amount__c, Pending_Amount__c, Due_Date__c,
                   Unit_Unblocking_Date__c, Project__c
            FROM Demands__c
            WHERE Unit_Unblocking_Date__c <= :today
            AND Unit_Unblocked__c = false
            AND Reminders_Disabled__c = false
            AND Status__c NOT IN ('Paid', 'Cancelled')
            AND Pending_Amount__c > 0
            AND Booking__r.Status__c != :PostSalesConstants.BOOKING_STATUS_CANCELLED
            LIMIT 200
        ];

        if (demands.isEmpty()) return 0;

        List<Demands__c> demandsToUpdate = new List<Demands__c>();
        List<Booking__c> bookingsToUpdate = new List<Booking__c>();
        List<Unit__c> unitsToUpdate = new List<Unit__c>();
        Set<Id> processedBookings = new Set<Id>();
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Demands__c d : demands) {
            // Mark demand as unblocked
            d.Unit_Unblocked__c = true;
            d.Unit_Unblocked_Date__c = DateTime.now();
            d.Cancellation_Initiated__c = true;
            demandsToUpdate.add(d);

            // Cancel booking and release unit (once per booking)
            if (d.Booking__c != null && !processedBookings.contains(d.Booking__c)) {
                processedBookings.add(d.Booking__c);

                bookingsToUpdate.add(new Booking__c(
                    Id = d.Booking__c,
                    Status__c = PostSalesConstants.BOOKING_STATUS_CANCELLED,
                    Cancellation_Date__c = Date.today(),
                    Cancellation_Reason__c = 'Auto-cancelled: Non-payment after demand period'
                ));

                if (d.Booking__r.Unit__c != null) {
                    unitsToUpdate.add(new Unit__c(
                        Id = d.Booking__r.Unit__c,
                        Status__c = PostSalesConstants.UNIT_STATUS_AVAILABLE,
                        Current_Booking__c = null
                    ));
                }

                // Send unblocking notification email
                if (String.isNotBlank(d.Booking__r.Email__c)) {
                    Messaging.SingleEmailMessage email = buildReminderEmail(d, config, 'Unit Unblocking', masterDocTemplateId);
                    if (email != null) emails.add(email);
                }
            }
        }

        sendEmails(emails);
        if (!demandsToUpdate.isEmpty()) update demandsToUpdate;
        if (!bookingsToUpdate.isEmpty()) update bookingsToUpdate;
        if (!unitsToUpdate.isEmpty()) update unitsToUpdate;

        // Bell notifications for unit unblocking
        sendReminderNotifications(demands, 'Unit automatically unblocked due to non-payment');

        return processedBookings.size();
    }

    // ==================== DISABLE REMINDERS ON PAYMENT ====================

    /**
     * @description Disables all pending reminders for demands that have been fully paid.
     *              Should be called after receipt approval or payment processing.
     * @param bookingIds Set of booking IDs to check
     */
    public static void disableRemindersForPaidDemands(Set<Id> bookingIds) {
        if (bookingIds == null || bookingIds.isEmpty()) return;

        List<Demands__c> demands = [
            SELECT Id, Reminders_Disabled__c, Pending_Amount__c
            FROM Demands__c
            WHERE Booking__c IN :bookingIds
            AND Reminders_Disabled__c = false
            AND (Pending_Amount__c = 0 OR Pending_Amount__c = null)
            AND Status__c = 'Paid'
        ];

        if (demands.isEmpty()) return;

        for (Demands__c d : demands) {
            d.Reminders_Disabled__c = true;
        }
        update demands;
    }

    // ==================== EMAIL BUILDING ====================

    private static Messaging.SingleEmailMessage buildReminderEmail(
        Demands__c demand, Post_Sales_Configuration__c config, String reminderType, Id masterDocTemplateId
    ) {
        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ demand.Booking__r.Email__c });

            // CC to booking owner
            if (demand.Booking__r.OwnerId != null) {
                String ownerEmail = getUserEmail(demand.Booking__r.OwnerId);
                if (String.isNotBlank(ownerEmail)) {
                    email.setCcAddresses(new List<String>{ ownerEmail });
                }
            }

            // If a Post Sales Config exists with email template, use it
            if (config != null && config.Email_Template__c != null) {
                EmailSenderController.PreparedEmailData prepared =
                    EmailSenderController.prepareEmailFromTemplate(
                        config.Email_Template__c, demand.Id
                    );

                email.setSubject(prepared.subject);
                email.setHtmlBody(prepared.body);

                // Attach PDFs from email template attachments config
                List<Messaging.EmailFileAttachment> fileAttachments = new List<Messaging.EmailFileAttachment>();

                if (prepared.attachments != null && !prepared.attachments.isEmpty()) {
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

                // If no attachments from email template, use Document Template from config or master config
                Id docTemplateId = config.Document_Template__c != null ? config.Document_Template__c : masterDocTemplateId;
                if (fileAttachments.isEmpty() && docTemplateId != null) {
                    Map<String, String> extraParams = new Map<String, String>();
                    extraParams.put('templateId', docTemplateId);
                    Messaging.EmailFileAttachment pdfAtt = EmailPdfGenerator.generatePdfAttachment(
                        'DynamicDocumentPDF', demand.Id,
                        reminderType.replaceAll(' ', '_') + '_' + demand.Name + '.pdf',
                        'id', extraParams
                    );
                    if (pdfAtt != null) fileAttachments.add(pdfAtt);
                }

                if (!fileAttachments.isEmpty()) {
                    email.setFileAttachments(fileAttachments);
                }
            } else {
                // Fallback: build a simple email with document template attachment if configured
                String subject = reminderType + ' - ' + demand.Booking__r.Name + ' - Demand ' + demand.Name;
                email.setSubject(subject);

                String body = '<p>Dear ' + (demand.Booking__r.First_Applicant_Name__c != null ? demand.Booking__r.First_Applicant_Name__c : 'Customer') + ',</p>';
                body += '<p>This is a <strong>' + reminderType + '</strong> for Booking <strong>' + demand.Booking__r.Name + '</strong>.</p>';
                body += '<p>Demand Amount: ' + PostSalesConstants.formatCurrency(demand.Demand_Amount__c) + '</p>';
                body += '<p>Pending Amount: ' + PostSalesConstants.formatCurrency(demand.Pending_Amount__c) + '</p>';

                if (demand.Due_Date__c != null) {
                    body += '<p>Due Date: ' + demand.Due_Date__c.format() + '</p>';
                }

                if (reminderType == 'Termination Notice' && demand.Interest_Amount__c != null && demand.Interest_Amount__c > 0) {
                    body += '<p>Interest Amount: ' + PostSalesConstants.formatCurrency(demand.Interest_Amount__c) + '</p>';
                }

                if (reminderType == 'Unit Unblocking') {
                    body += '<p><strong>Your booking has been automatically cancelled and the unit has been released due to non-payment.</strong></p>';
                }

                body += '<p>Please contact us for any queries.</p>';
                email.setHtmlBody(body);

                // Attach Document Template PDF even for fallback emails (config or master config)
                Id fallbackDocId = (config != null && config.Document_Template__c != null) ? config.Document_Template__c : masterDocTemplateId;
                if (fallbackDocId != null) {
                    Map<String, String> extraParams = new Map<String, String>();
                    extraParams.put('templateId', fallbackDocId);
                    Messaging.EmailFileAttachment pdfAtt = EmailPdfGenerator.generatePdfAttachment(
                        'DynamicDocumentPDF', demand.Id,
                        reminderType.replaceAll(' ', '_') + '_' + demand.Name + '.pdf',
                        'id', extraParams
                    );
                    if (pdfAtt != null) {
                        email.setFileAttachments(new List<Messaging.EmailFileAttachment>{ pdfAtt });
                    }
                }
            }

            email.setSaveAsActivity(true);
            return email;

        } catch (Exception e) {
            System.debug('Error building reminder email for demand ' + demand.Name + ': ' + e.getMessage());
            return null;
        }
    }

    // ==================== NOTIFICATION HELPERS ====================

    private static void sendReminderNotifications(List<Demands__c> demands, String message) {
        Set<String> targetIds = new Set<String>();
        for (Demands__c d : demands) {
            if (d.Booking__r.OwnerId != null) {
                targetIds.add(d.Booking__r.OwnerId);
            }
        }

        if (targetIds.isEmpty()) return;

        List<CustomNotificationType> notifTypes = [
            SELECT Id FROM CustomNotificationType
            WHERE DeveloperName = 'Demand_Reminder_Notification'
            LIMIT 1
        ];

        if (notifTypes.isEmpty()) return;

        for (Demands__c d : demands) {
            if (d.Booking__r.OwnerId == null) continue;

            try {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle('Demand Reminder - ' + d.Booking__r.Name);
                notification.setBody(message + ': Demand ' + d.Name +
                    ', Pending: ' + PostSalesConstants.formatCurrency(d.Pending_Amount__c));
                notification.setNotificationTypeId(notifTypes[0].Id);
                notification.setTargetId(d.Booking__c);
                notification.send(new Set<String>{ d.Booking__r.OwnerId });
            } catch (Exception e) {
                System.debug('Error sending notification for demand ' + d.Name + ': ' + e.getMessage());
            }
        }
    }

    // ==================== CONFIG HELPERS ====================

    private static Map<String, Post_Sales_Configuration__c> loadReminderConfigs() {
        Map<String, Post_Sales_Configuration__c> configMap = new Map<String, Post_Sales_Configuration__c>();

        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Configuration_Type__c, Email_Template__c,
                   Document_Template__c, Auto_Send_Email__c
            FROM Post_Sales_Configuration__c
            WHERE Configuration_Type__c IN (
                'Demand Reminder 1', 'Demand Reminder 2',
                'Demand Reminder 3', 'Demand Reminder 4',
                'Termination Mail', 'Unit Unblocking'
            )
            AND Is_Active__c = true
        ];

        for (Post_Sales_Configuration__c c : configs) {
            configMap.put(c.Configuration_Type__c, c);
        }

        return configMap;
    }

    /**
     * @description Loads document template IDs from the active Post_Sales_Config_Master__c
     *              for each reminder. These are used as fallback when Post_Sales_Configuration__c
     *              does not have a document template configured.
     * @return Map of reminder key ('reminder1'-'reminder4') to Document_Template__c Id
     */
    private static Map<String, Id> loadMasterConfigDocTemplates() {
        Map<String, Id> docTemplates = new Map<String, Id>();

        List<Post_Sales_Config_Master__c> masters = [
            SELECT Reminder_1_Document__c, Reminder_2_Document__c,
                   Reminder_3_Document__c, Reminder_4_Document__c
            FROM Post_Sales_Config_Master__c
            WHERE Is_Active__c = true
            LIMIT 1
        ];

        if (!masters.isEmpty()) {
            Post_Sales_Config_Master__c m = masters[0];
            if (m.Reminder_1_Document__c != null) docTemplates.put('reminder1', m.Reminder_1_Document__c);
            if (m.Reminder_2_Document__c != null) docTemplates.put('reminder2', m.Reminder_2_Document__c);
            if (m.Reminder_3_Document__c != null) docTemplates.put('reminder3', m.Reminder_3_Document__c);
            if (m.Reminder_4_Document__c != null) docTemplates.put('reminder4', m.Reminder_4_Document__c);
        }

        return docTemplates;
    }

    // ==================== UTILITY ====================

    private static void sendEmails(List<Messaging.SingleEmailMessage> emails) {
        if (emails.isEmpty()) return;
        try {
            Messaging.sendEmail(emails, false);
        } catch (Exception e) {
            System.debug('Error sending reminder emails: ' + e.getMessage());
        }
    }

    private static String getUserEmail(Id userId) {
        try {
            List<User> users = [SELECT Email FROM User WHERE Id = :userId LIMIT 1];
            return users.isEmpty() ? null : users[0].Email;
        } catch (Exception e) {
            return null;
        }
    }

    // ==================== RESULT WRAPPER ====================

    public class ProcessingResult {
        public Integer reminder1Count = 0;
        public Integer reminder2Count = 0;
        public Integer reminder3Count = 0;
        public Integer reminder4Count = 0;
        public Integer terminationCount = 0;
        public Integer unblockingCount = 0;

        public Integer totalProcessed() {
            return reminder1Count + reminder2Count + reminder3Count + reminder4Count + terminationCount + unblockingCount;
        }

        public String toLogString() {
            return 'Demand Reminders Processed - ' +
                '1st Reminders: ' + reminder1Count +
                ', 2nd Reminders: ' + reminder2Count +
                ', 3rd Reminders: ' + reminder3Count +
                ', 4th Reminders: ' + reminder4Count +
                ', Termination Mails: ' + terminationCount +
                ', Unit Unblockings: ' + unblockingCount;
        }
    }
}