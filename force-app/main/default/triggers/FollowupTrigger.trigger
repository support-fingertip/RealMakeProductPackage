/**
 * @description Trigger for Followup__c.
 * Delegates to FollowupTriggerHandler.
 */
trigger FollowupTrigger on Followup__c (before update) {
    if (Trigger.isBefore && Trigger.isUpdate) {
        FollowupTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}