/**
 * @description Queueable job to send discount approval notifications (bell + task + email)
 *              AFTER the originating transaction commits. This ensures bell notifications
 *              are not silently dropped when the target record has DML in the same transaction.
 */
public with sharing class DiscountNotificationQueueable implements Queueable {

    private Id costSheetId;
    private String costSheetName;
    private Set<Id> recipientIds;
    private String comments;
    private String bellTitle;
    private String bellBody;

    public DiscountNotificationQueueable(
        Id costSheetId, String costSheetName, Set<Id> recipientIds,
        String comments, String bellTitle, String bellBody
    ) {
        this.costSheetId = costSheetId;
        this.costSheetName = costSheetName;
        this.recipientIds = recipientIds;
        this.comments = comments;
        this.bellTitle = bellTitle;
        this.bellBody = bellBody;
    }

    public void execute(QueueableContext context) {
        // Bell notification is sent directly in DiscountApprovalEngine (synchronous, reliable)
        // Queueable handles only tasks and emails (post-commit)
        createTasks();
        sendEmailToApprovers();
    }

    private void createTasks() {
        List<Task> tasks = new List<Task>();
        for (Id approverId : recipientIds) {
            tasks.add(new Task(
                Subject = 'Discount Approval Required: ' + costSheetName,
                Description = 'Cost Sheet ' + costSheetName + ' has been submitted for discount approval.'
                             + '\n\nComments: ' + (String.isNotBlank(comments) ? comments : 'None')
                             + '\n\nPlease navigate to the Cost Sheet record to review and approve/reject.',
                OwnerId = approverId,
                WhatId = costSheetId,
                Priority = 'High',
                Status = 'Not Started',
                ActivityDate = Date.today().addDays(2)
            ));
        }
        if (!tasks.isEmpty()) {
            try { insert tasks; } catch (Exception e) {
                System.debug('DiscountNotificationQueueable task error: ' + e.getMessage());
            }
        }
    }

    private void sendEmailToApprovers() {
        try {
            List<User> approvers = [
                SELECT Id, Email, Name FROM User
                WHERE Id IN :recipientIds AND Email != null
            ];
            if (approvers.isEmpty()) return;

            String submitterName = '';
            // Extract submitter name from bell body if available
            if (bellBody != null && bellBody.contains(' submitted ')) {
                submitterName = bellBody.substringBefore(' submitted ');
            }

            List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
            for (User approver : approvers) {
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setToAddresses(new List<String>{ approver.Email });
                email.setSubject('Discount Approval Required: ' + costSheetName);
                email.setPlainTextBody(
                    'Dear ' + approver.Name + ',\n\n'
                    + (String.isNotBlank(submitterName) ? submitterName : 'A user')
                    + ' has submitted Cost Sheet ' + costSheetName
                    + ' for discount approval.\n\n'
                    + 'Comments: ' + (String.isNotBlank(comments) ? comments : 'None') + '\n\n'
                    + 'Please log in to Salesforce and navigate to the Cost Sheet record to approve or reject.\n\n'
                    + 'Regards,\nDiscount Approval System'
                );
                email.setSaveAsActivity(false);
                emails.add(email);
            }
            if (!emails.isEmpty()) {
                Messaging.sendEmail(emails);
            }
        } catch (Exception e) {
            System.debug('DiscountNotificationQueueable email error: ' + e.getMessage());
        }
    }
}