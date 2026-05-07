/**
 * @description Trigger for General_Setup__c.
 * Delegates to GeneralSetupTriggerHandler.
 */
trigger GeneralSetupTrigger on General_Setup__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            GeneralSetupTriggerHandler.handleBeforeInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            GeneralSetupTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}