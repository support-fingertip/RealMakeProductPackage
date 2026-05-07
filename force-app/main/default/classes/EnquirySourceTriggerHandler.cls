/**
 * @description Handler for Enquiry Source trigger operations.
 * Manages Campaign inheritance from parent Lead.
 */
public with sharing class EnquirySourceTriggerHandler {

    /**
     * @description Inherit Campaign from parent Lead when creating Enquiry Source.
     * If the Enquiry Source already has a Campaign set, keep it.
     * If not, copy the Campaign from the parent Lead.
     * This ensures Campaign consistency between Lead and Enquiry Source.
     */
    public static void inheritCampaignFromLead(List<Enquiry_Source__c> newRecords) {
        // Collect Lead IDs where Campaign is not already set on the Enquiry Source
        Set<Id> leadIds = new Set<Id>();
        for (Enquiry_Source__c es : newRecords) {
            if (es.Campaign__c == null && es.Lead__c != null) {
                leadIds.add(es.Lead__c);
            }
        }

        if (leadIds.isEmpty()) {
            return;
        }

        // Query parent Leads for their Campaign
        Map<Id, Lead__c> leadMap = new Map<Id, Lead__c>([
            SELECT Id, Campaign__c
            FROM Lead__c
            WHERE Id IN :leadIds
            AND Campaign__c != null
        ]);

        // Set Campaign on Enquiry Source from parent Lead
        for (Enquiry_Source__c es : newRecords) {
            if (es.Campaign__c == null && es.Lead__c != null) {
                Lead__c parentLead = leadMap.get(es.Lead__c);
                if (parentLead != null) {
                    es.Campaign__c = parentLead.Campaign__c;
                }
            }
        }
    }
}