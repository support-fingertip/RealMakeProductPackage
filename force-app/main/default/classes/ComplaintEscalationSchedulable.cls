/**
 * @description Schedulable Apex job that runs daily (default 10 AM) to process
 *              complaint escalations using the configurable Escalation Matrix.
 *
 *              Uses ComplaintEscalationService to:
 *              - Match overdue complaints against Complaint_Escalation_Matrix__c rules
 *              - Determine escalation level (1-3) based on days overdue
 *              - Send targeted notifications to configured recipients
 *              - Auto-reassign complaints when configured
 *              - Track escalation level and history on the complaint
 *
 *              Schedule: System.schedule('Complaint Escalation Daily', '0 0 10 * * ?', new ComplaintEscalationSchedulable());
 * @author System
 * @date 2026-03-29
 */
public with sharing class ComplaintEscalationSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        try {
            ComplaintEscalationService.EscalationResult result =
                ComplaintEscalationService.processEscalations();
            System.debug('ComplaintEscalationSchedulable: ' + result.message);
            if (!result.errors.isEmpty()) {
                System.debug('Escalation errors: ' + String.join(result.errors, '; '));
            }
        } catch (Exception e) {
            System.debug('ComplaintEscalationSchedulable error: ' + e.getMessage() +
                '\n' + e.getStackTraceString());
        }
    }
}