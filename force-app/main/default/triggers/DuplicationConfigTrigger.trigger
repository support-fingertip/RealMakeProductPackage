/**
 * Trigger on Duplication_Configuration__c
 *
 * Ensures only one Duplication Configuration per Primary Object API Name
 * can be active at a time. When a config is activated, all other active
 * configs for the same Primary Object are automatically deactivated.
 */
trigger DuplicationConfigTrigger on Duplication_Configuration__c (before insert, before update) {

    if (Trigger.isBefore && Trigger.isInsert) {
        DuplicationConfigTriggerHandler.handleBeforeInsert(Trigger.new);
    }

    if (Trigger.isBefore && Trigger.isUpdate) {
        DuplicationConfigTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}