/**
 * @description DEPRECATED — Auto-escalation for discount approvals has been removed.
 *              This class is retained as a no-op stub so that any existing scheduled
 *              jobs referencing it will not fail. Remove the scheduled job from Setup
 *              and then delete this class.
 */
public with sharing class DiscountApprovalEscalationBatch implements Database.Batchable<SObject>, Schedulable {

    public void execute(SchedulableContext sc) {
        // No-op: auto-escalation removed
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id FROM Cost_Sheet__c WHERE Id = null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Cost_Sheet__c> scope) {
        // No-op: auto-escalation removed
    }

    public void finish(Database.BatchableContext bc) {
        // No-op: auto-escalation removed
    }
}