/**
 * @description Trigger for Project__c.
 * Delegates to ProjectTriggerHandler.
 */
trigger ProjectTrigger on Project__c (before update, before delete) {
    if (Trigger.isBefore) {
        if (Trigger.isDelete) {
            ProjectTriggerHandler.handleBeforeDelete(Trigger.old);
        }
        if (Trigger.isUpdate) {
            ProjectTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}