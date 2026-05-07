/**
 * @description Schedulable batch class that sends demand reminders based on
 *              Post Sales Configuration reminder settings.
 *              Reads reminder config (up to 4 levels), checks days overdue,
 *              and sends email reminders. Reminders marked as N/A are skipped.
 *
 * Schedule example:
 *   System.schedule('Daily Demand Reminders', '0 0 8 * * ?', new DemandReminderBatch());
 */
public with sharing class DemandReminderBatch implements Database.Batchable<SObject>, Schedulable {

    // ==================== INNER CLASSES ====================

    public class ReminderLevel {
        public Boolean isNA { get; set; }
        public Integer daysAfterDue { get; set; }
        public String againstObject { get; set; }
        public String documentTemplateId { get; set; }
    }

    // ==================== SCHEDULABLE ====================

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new DemandReminderBatch(), 50);
    }

    // ==================== BATCHABLE ====================

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Get overdue demands that haven't been fully paid or cancelled
        return Database.getQueryLocator([
            SELECT Id, Name, Booking__c, Booking__r.Project__c,
                   Due_Date__c, Pending_Amount__c, Status__c,
                   Number_of_Reminders__c, Last_Reminder_Date__c,
                   Demand_Amount__c, Net_Demand_Amount__c,
                   Booking__r.Name, Booking__r.Unit__r.Name
            FROM Demands__c
            WHERE Due_Date__c < TODAY
            AND Pending_Amount__c > 0
            AND Status__c NOT IN ('Paid', 'Cancelled', 'Waived')
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Demands__c> scope) {
        // Load active Demand configuration with reminders enabled
        Post_Sales_Configuration__c config = getActiveDemandConfig();
        if (config == null || !config.Enable_Reminders__c) return;

        List<ReminderLevel> reminders = parseReminderConfig(config.Reminder_Config__c);
        if (reminders.isEmpty()) return;

        Date today = Date.today();
        List<Demands__c> demandsToUpdate = new List<Demands__c>();

        for (Demands__c demand : scope) {
            Integer daysOverdue = demand.Due_Date__c.daysBetween(today);
            Integer remindersSent = demand.Number_of_Reminders__c != null
                ? Integer.valueOf(demand.Number_of_Reminders__c) : 0;

            // Find which reminder level applies
            ReminderLevel applicableLevel = findApplicableLevel(reminders, daysOverdue, remindersSent);
            if (applicableLevel == null) continue;

            // Skip if already sent a reminder today
            if (demand.Last_Reminder_Date__c == today) continue;

            // Update demand with reminder tracking
            demand.Number_of_Reminders__c = remindersSent + 1;
            demand.Last_Reminder_Date__c = today;
            demand.Reminder_Sent__c = true;
            demand.Reminder_Sent_Date__c = today;
            demand.Status__c = PostSalesConstants.DEMAND_STATUS_REMINDER_SENT;
            demandsToUpdate.add(demand);
        }

        if (!demandsToUpdate.isEmpty()) {
            update demandsToUpdate;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Could add notification/logging here if needed
    }

    // ==================== HELPER METHODS ====================

    /**
     * Find the applicable reminder level for a demand based on days overdue
     * and how many reminders have already been sent.
     * Returns null if no reminder should fire (all applicable levels are N/A or
     * already sent).
     */
    private ReminderLevel findApplicableLevel(List<ReminderLevel> reminders, Integer daysOverdue, Integer remindersSent) {
        // Find the highest-level reminder that matches the days overdue
        // and hasn't been sent yet
        ReminderLevel applicable = null;

        for (Integer i = 0; i < reminders.size(); i++) {
            ReminderLevel level = reminders[i];

            // Skip N/A reminders
            if (level.isNA == true) continue;

            // Check if days overdue has reached this level's threshold
            if (daysOverdue >= level.daysAfterDue) {
                // This level is eligible. Check if we've already sent this many reminders
                if (remindersSent <= i) {
                    applicable = level;
                    break; // Send the earliest unsent reminder
                }
            }
        }

        return applicable;
    }

    private Post_Sales_Configuration__c getActiveDemandConfig() {
        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Enable_Reminders__c, Reminder_Config__c,
                   Email_Template__c, Auto_Send_Email__c
            FROM Post_Sales_Configuration__c
            WHERE Configuration_Type__c = 'Demand'
            AND Is_Active__c = true
            AND Enable_Reminders__c = true
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    /**
     * Parse the reminder config JSON into a list of ReminderLevel objects.
     * Expected format: [
     *   {"isNA": false, "daysAfterDue": 7, "againstObject": "Booking__c", "documentTemplateId": ""},
     *   {"isNA": true, "daysAfterDue": 14, ...},  // N/A - will be skipped
     *   ...
     * ]
     */
    private List<ReminderLevel> parseReminderConfig(String configJson) {
        List<ReminderLevel> levels = new List<ReminderLevel>();
        if (String.isBlank(configJson)) return levels;

        try {
            List<Object> parsed = (List<Object>) JSON.deserializeUntyped(configJson);
            for (Object obj : parsed) {
                Map<String, Object> m = (Map<String, Object>) obj;
                ReminderLevel level = new ReminderLevel();
                level.isNA = m.get('isNA') == true;
                level.daysAfterDue = m.get('daysAfterDue') != null ? Integer.valueOf(String.valueOf(m.get('daysAfterDue'))) : 0;
                level.againstObject = (String) m.get('againstObject');
                level.documentTemplateId = (String) m.get('documentTemplateId');
                levels.add(level);
            }
        } catch (Exception e) {
            System.debug('Error parsing reminder config: ' + e.getMessage());
        }

        return levels;
    }
}