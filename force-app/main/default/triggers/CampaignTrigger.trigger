/**
 * CAMPAIGN TRIGGER
 *
 * Handles:
 * 1. BEFORE UPDATE: Validate status transitions
 *
 * Valid Status Lifecycle:
 *   Planned → Started
 *   Started → Hold / Completed / Cancelled
 *   Hold    → Started (resume)
 *
 * Invalid transitions (blocked):
 *   Planned → Completed (must go through Started)
 *   Planned → Hold (must go through Started)
 *   Completed → any (terminal state)
 *   Cancelled → any (terminal state)
 */
trigger CampaignTrigger on Campaign__c (before update) {

    if (Trigger.isBefore && Trigger.isUpdate) {
        CampaignTriggerHandler.validateStatusTransitions(Trigger.new, Trigger.oldMap);
    }
}