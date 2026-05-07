/**
 * @description Site Visit trigger — delegates to SiteVisitTriggerHandler.
 * Handles Push to Sales automation on SV creation and completion.
 * Also recalculates Campaign Site Visit counts.
 */
trigger SiteVisitTrigger on Site_Visit__c (after insert, after update, after delete) {

    if (Trigger.isAfter && Trigger.isInsert) {
        SiteVisitTriggerHandler.onAfterInsert(Trigger.new);

        // Recalculate Campaign Site Visit counts
        Set<Id> leadIds = new Set<Id>();
        for (Site_Visit__c sv : Trigger.new) {
            if (sv.Lead__c != null) leadIds.add(sv.Lead__c);
        }
        if (!leadIds.isEmpty()) {
            CampaignService.recalculateCampaignCountsForLeads(leadIds);
        }
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        SiteVisitTriggerHandler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }

    if (Trigger.isAfter && Trigger.isDelete) {
        Set<Id> leadIds = new Set<Id>();
        for (Site_Visit__c sv : Trigger.old) {
            if (sv.Lead__c != null) leadIds.add(sv.Lead__c);
        }
        if (!leadIds.isEmpty()) {
            CampaignService.recalculateCampaignCountsForLeads(leadIds);
        }
    }
}