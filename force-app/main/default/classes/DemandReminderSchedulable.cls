/**
 * @description Schedulable Apex job that runs daily to process demand reminders
 *              and automatic unit unblocking. Reads project-level configuration
 *              to determine reminder timings and actions.
 *
 *              Schedule examples:
 *              - Daily at 8 AM:  System.schedule('Demand Reminders Daily', '0 0 8 * * ?', new DemandReminderSchedulable());
 *              - Every hour:     System.schedule('Demand Reminders Hourly', '0 0 * * * ?', new DemandReminderSchedulable());
 * @author System
 * @date 2026-03-29
 */
public with sharing class DemandReminderSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        try {
            DemandReminderService.ProcessingResult result = DemandReminderService.processDueReminders();
            System.debug(result.toLogString());
        } catch (Exception e) {
            System.debug('DemandReminderSchedulable error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
}