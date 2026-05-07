/**
 * @description Schedulable Apex job that runs daily (configurable, default 10 AM)
 *              to send escalation emails for overdue snags.
 *
 *              Escalation logic:
 *              - Snags past Expected_Completion_Date__c that are not Completed/Closed
 *              - Email sent to Project Head (from Project__c.Project_Head__c)
 *              - CC to Booking Owner
 *              - Uses Post_Sales_Configuration__c 'Snag Escalation' for email template
 *
 *              Schedule: System.schedule('Snag Escalation Daily', '0 0 10 * * ?', new SnagEscalationSchedulable());
 * @author System
 * @date 2026-03-29
 */
public with sharing class SnagEscalationSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        try {
            processOverdueSnags();
        } catch (Exception e) {
            System.debug('SnagEscalationSchedulable error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    /**
     * @description Finds all overdue snags and sends escalation emails to Project Head
     *              with CC to Booking Owner.
     */
    public static void processOverdueSnags() {
        Date today = Date.today();

        // Load Snag Escalation email config
        Post_Sales_Configuration__c config = loadConfig('Snag Escalation');

        // Query overdue snags with related booking, project, and project head
        List<Snag__c> overdueSnags = [
            SELECT Id, Name, Description__c, Category__c, Priority__c,
                   Expected_Completion_Date__c, Actual_Completion_Date__c,
                   Status__c, Location__c, Specific_Location__c,
                   Assigned_To__c, Assigned_To__r.Name, Assigned_To__r.Email,
                   Booking__c, Booking__r.Name, Booking__r.OwnerId,
                   Booking__r.First_Applicant_Name__c, Booking__r.Email__c,
                   Booking__r.Unit__r.Name,
                   Booking__r.Project__c, Booking__r.Project__r.Name,
                   Booking__r.Project__r.Project_Head__c,
                   Booking__r.Project__r.Project_Head__r.Email,
                   Inspection__c, Inspection__r.Name
            FROM Snag__c
            WHERE Expected_Completion_Date__c < :today
            AND Status__c NOT IN ('Completed', 'Closed', 'Cancelled', 'Verified')
            AND Booking__r.Project__r.Project_Head__c != null
            LIMIT 500
        ];

        if (overdueSnags.isEmpty()) return;

        // Group snags by project for consolidated emails
        Map<Id, List<Snag__c>> snagsByProject = new Map<Id, List<Snag__c>>();
        for (Snag__c snag : overdueSnags) {
            Id projectId = snag.Booking__r.Project__c;
            if (!snagsByProject.containsKey(projectId)) {
                snagsByProject.put(projectId, new List<Snag__c>());
            }
            snagsByProject.get(projectId).add(snag);
        }

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Id projectId : snagsByProject.keySet()) {
            List<Snag__c> projectSnags = snagsByProject.get(projectId);
            Snag__c sampleSnag = projectSnags[0];

            // Build consolidated escalation email
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

            // To: Project Head
            String projectHeadEmail = sampleSnag.Booking__r.Project__r.Project_Head__r.Email;
            if (String.isBlank(projectHeadEmail)) continue;
            email.setToAddresses(new List<String>{ projectHeadEmail });

            // CC: All unique booking owners
            Set<String> ccEmails = new Set<String>();
            for (Snag__c s : projectSnags) {
                if (s.Booking__r.OwnerId != null) {
                    String ownerEmail = getUserEmail(s.Booking__r.OwnerId);
                    if (String.isNotBlank(ownerEmail)) ccEmails.add(ownerEmail);
                }
            }
            if (!ccEmails.isEmpty()) {
                email.setCcAddresses(new List<String>(ccEmails));
            }

            email.setSubject('Escalation: ' + projectSnags.size() + ' Overdue Snag(s) - ' +
                sampleSnag.Booking__r.Project__r.Name);

            // Build HTML body with snag table
            String body = '<p>Dear Project Head,</p>';
            body += '<p>The following <strong>' + projectSnags.size() + '</strong> snag(s) in project <strong>' +
                sampleSnag.Booking__r.Project__r.Name + '</strong> are overdue:</p>';

            body += '<table border="1" cellpadding="5" cellspacing="0" style="border-collapse:collapse;">';
            body += '<tr style="background-color:#f2f2f2;">';
            body += '<th>Snag</th><th>Booking</th><th>Unit</th><th>Category</th>';
            body += '<th>Priority</th><th>Expected Date</th><th>Days Overdue</th><th>Assigned To</th>';
            body += '</tr>';

            for (Snag__c s : projectSnags) {
                Integer daysOverdue = s.Expected_Completion_Date__c.daysBetween(today);
                body += '<tr>';
                body += '<td>' + s.Name + '</td>';
                body += '<td>' + (s.Booking__r.Name != null ? s.Booking__r.Name : '') + '</td>';
                body += '<td>' + (s.Booking__r.Unit__r != null ? s.Booking__r.Unit__r.Name : '') + '</td>';
                body += '<td>' + (s.Category__c != null ? s.Category__c : '') + '</td>';
                body += '<td>' + (s.Priority__c != null ? s.Priority__c : '') + '</td>';
                body += '<td>' + s.Expected_Completion_Date__c.format() + '</td>';
                body += '<td style="color:red;font-weight:bold;">' + daysOverdue + '</td>';
                body += '<td>' + (s.Assigned_To__r != null ? s.Assigned_To__r.Name : '') + '</td>';
                body += '</tr>';
            }
            body += '</table>';
            body += '<p>Please take immediate action to resolve these snags.</p>';

            email.setHtmlBody(body);
            email.setSaveAsActivity(false);
            emails.add(email);
        }

        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails, false);
            } catch (Exception e) {
                System.debug('Error sending snag escalation emails: ' + e.getMessage());
            }
        }

        System.debug('Snag Escalation: Sent ' + emails.size() + ' escalation emails for ' +
            overdueSnags.size() + ' overdue snags');
    }

    private static Post_Sales_Configuration__c loadConfig(String configType) {
        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Email_Template__c, Auto_Send_Email__c
            FROM Post_Sales_Configuration__c
            WHERE Configuration_Type__c = :configType
            AND Is_Active__c = true
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    private static String getUserEmail(Id userId) {
        try {
            List<User> users = [SELECT Email FROM User WHERE Id = :userId LIMIT 1];
            return users.isEmpty() ? null : users[0].Email;
        } catch (Exception e) {
            return null;
        }
    }
}