/**
 * @description Trigger for Master_Payment_Schedule__c.
 * Validates that total Percentage__c per Project does not exceed 100%.
 * Delegates to MasterPaymentScheduleTriggerHandler.
 */
trigger MasterPaymentScheduleTrigger on Master_Payment_Schedule__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            MasterPaymentScheduleTriggerHandler.validateTotalPercentage(Trigger.new, null);
        }
        if (Trigger.isUpdate) {
            MasterPaymentScheduleTriggerHandler.validateTotalPercentage(Trigger.new, Trigger.oldMap);
        }
    }
}