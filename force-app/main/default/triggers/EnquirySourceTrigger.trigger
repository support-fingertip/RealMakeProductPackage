/**
 * ENQUIRY SOURCE TRIGGER
 *
 * Handles:
 * 1. BEFORE INSERT: Inherit Campaign from parent Lead (if not already set)
 * 2. AFTER INSERT/UPDATE/DELETE/UNDELETE: Recalculate Campaign rollup statistics
 */
trigger EnquirySourceTrigger on Enquiry_Source__c (before insert, after insert, after update, after delete, after undelete) {

    // ============================================================================
    // BEFORE INSERT: Inherit Campaign from parent Lead
    // ============================================================================
    if (Trigger.isBefore && Trigger.isInsert) {
        EnquirySourceTriggerHandler.inheritCampaignFromLead(Trigger.new);
    }

    // ============================================================================
    // AFTER INSERT/UPDATE/DELETE/UNDELETE: Recalculate Campaign statistics
    // ============================================================================
    if (Trigger.isAfter) {
        Set<Id> campaignIds = new Set<Id>();

        if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
            for (Enquiry_Source__c es : Trigger.new) {
                if (es.Campaign__c != null) {
                    campaignIds.add(es.Campaign__c);
                }
            }
        }

        if (Trigger.isUpdate || Trigger.isDelete) {
            for (Enquiry_Source__c es : Trigger.old) {
                if (es.Campaign__c != null) {
                    campaignIds.add(es.Campaign__c);
                }
            }
        }

        if (!campaignIds.isEmpty()) {
            CampaignService.recalculateTotalEnquirySources(campaignIds);
        }
    }
}