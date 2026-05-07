/**
 * @description Handler for Followup__c trigger.
 *              Stamps Cancelled_Date__c when a followup is cancelled.
 */
public with sharing class FollowupTriggerHandler {

    public static void handleBeforeUpdate(List<Followup__c> newRecords, Map<Id, Followup__c> oldMap) {
        for (Followup__c fu : newRecords) {
            Followup__c oldFu = oldMap.get(fu.Id);

            // Stamp cancellation date when status changes to Cancelled
            if (fu.Status__c == 'Cancelled' && oldFu.Status__c != 'Cancelled') {
                fu.Cancelled_Date__c = System.now();
            }
        }
    }
}