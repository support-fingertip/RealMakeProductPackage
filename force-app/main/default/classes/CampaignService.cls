/**
 * @description Service class for Campaign operations.
 * Handles Campaign lookup by auto-number Name (e.g., CMP-00042),
 * error logging for failed matches, and rollup statistics.
 */
public with sharing class CampaignService {

    /**
     * @description Resolve Campaign record ID from the auto-number Name field.
     * External systems pass the Campaign ID text (e.g., "CMP-00042"), not the Salesforce record ID.
     * @param campaignIdText The auto-number Campaign ID text (e.g., CMP-00042)
     * @return The Salesforce record Id, or null if not found
     */
    public static Id resolveCampaignId(String campaignIdText) {
        if (String.isBlank(campaignIdText)) {
            return null;
        }

        // If it looks like a Salesforce ID already, return as-is
        if (campaignIdText instanceof Id) {
            return (Id) campaignIdText;
        }

        List<Campaign__c> campaigns = [
            SELECT Id FROM Campaign__c
            WHERE Name = :campaignIdText
            OR Campaign_Name__c = :campaignIdText
            LIMIT 1
        ];

        if (!campaigns.isEmpty()) {
            return campaigns[0].Id;
        }

        // Log error but do not block lead creation
        logCampaignError(campaignIdText, 'Campaign not found with ID: ' + campaignIdText);
        return null;
    }

    /**
     * @description Bulk resolve Campaign IDs from auto-number Names.
     * @param campaignIdTexts Set of auto-number Campaign ID texts
     * @return Map of Campaign ID text to Salesforce record Id
     */
    public static Map<String, Id> resolveCampaignIds(Set<String> campaignIdTexts) {
        Map<String, Id> result = new Map<String, Id>();
        if (campaignIdTexts == null || campaignIdTexts.isEmpty()) {
            return result;
        }

        Set<String> textsToQuery = new Set<String>();
        for (String text : campaignIdTexts) {
            if (String.isNotBlank(text)) {
                if (text instanceof Id) {
                    result.put(text, (Id) text);
                } else {
                    textsToQuery.add(text);
                }
            }
        }

        if (!textsToQuery.isEmpty()) {
            for (Campaign__c c : [
                SELECT Id, Name, Campaign_Name__c FROM Campaign__c
                WHERE Name IN :textsToQuery
                OR Campaign_Name__c IN :textsToQuery
            ]) {
                result.put(c.Name, c.Id);
                if (String.isNotBlank(c.Campaign_Name__c)) {
                    result.put(c.Campaign_Name__c, c.Id);
                }
            }

            // Log errors for unmatched campaigns
            for (String text : textsToQuery) {
                if (!result.containsKey(text)) {
                    logCampaignError(text, 'Campaign not found with ID: ' + text);
                }
            }
        }

        return result;
    }

    /**
     * @description Resolve Campaign_Id_Text__c to Campaign__c for new Leads.
     * Called from LeadTrigger (before insert). Only resolves when Campaign__c
     * is not already set.
     * Bulk-safe: one query regardless of how many Leads are in the batch.
     */
    public static void resolveCampaignForLeads(List<Lead__c> leads) {
        Set<String> campaignTexts = new Set<String>();
        for (Lead__c ld : leads) {
            if (String.isNotBlank(ld.Campaign_Id_Text__c) && ld.Campaign__c == null) {
                campaignTexts.add(ld.Campaign_Id_Text__c);
            }
        }

        if (campaignTexts.isEmpty()) {
            return;
        }

        Map<String, Id> resolvedMap = resolveCampaignIds(campaignTexts);

        for (Lead__c ld : leads) {
            if (String.isNotBlank(ld.Campaign_Id_Text__c) && ld.Campaign__c == null) {
                Id resolvedId = resolvedMap.get(ld.Campaign_Id_Text__c);
                if (resolvedId != null) {
                    ld.Campaign__c = resolvedId;
                }
            }
        }
    }

    /**
     * @description Resolve Campaign_Id_Text__c to Campaign__c on Lead updates.
     * Called from LeadTrigger (before update). Only processes Leads where
     * Campaign_Id_Text__c actually changed — overwrites Campaign__c
     * with the newly resolved Campaign.
     */
    public static void resolveCampaignForLeadUpdates(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        Set<String> campaignTexts = new Set<String>();
        List<Lead__c> leadsToResolve = new List<Lead__c>();

        for (Lead__c ld : newLeads) {
            Lead__c oldLd = oldMap.get(ld.Id);
            // Only process if Campaign_Id_Text__c actually changed
            if (String.isNotBlank(ld.Campaign_Id_Text__c)
                && ld.Campaign_Id_Text__c != oldLd.Campaign_Id_Text__c) {
                campaignTexts.add(ld.Campaign_Id_Text__c);
                leadsToResolve.add(ld);
            }
        }

        if (campaignTexts.isEmpty()) {
            return;
        }

        Map<String, Id> resolvedMap = resolveCampaignIds(campaignTexts);

        for (Lead__c ld : leadsToResolve) {
            Id resolvedId = resolvedMap.get(ld.Campaign_Id_Text__c);
            if (resolvedId != null) {
                ld.Campaign__c = resolvedId;
            }
        }
    }

    /**
     * @description Log a Campaign matching error to the error log object.
     * Non-blocking: errors are logged but do not prevent lead creation.
     */
    private static void logCampaignError(String campaignIdText, String errorMessage) {
        try {
            Field_Mapping_Error_Log__c errorLog = new Field_Mapping_Error_Log__c();
            errorLog.Error_Message__c = errorMessage;
            errorLog.Operation_Type__c = 'Campaign Matching';
            errorLog.Source_Record_Id__c = campaignIdText;
            errorLog.Error_Timestamp__c = DateTime.now();
            insert errorLog;
        } catch (Exception e) {
            System.debug('Failed to log campaign error: ' + e.getMessage());
        }
    }

    /**
     * @description Recalculate Total_Leads__c for the given Campaign IDs.
     * Called from Lead trigger when Campaign changes.
     */
    public static void recalculateTotalLeads(Set<Id> campaignIds) {
        if (campaignIds == null || campaignIds.isEmpty()) {
            return;
        }

        // Remove nulls
        campaignIds.remove(null);
        if (campaignIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> countMap = new Map<Id, Integer>();
        for (Id cId : campaignIds) {
            countMap.put(cId, 0);
        }

        for (AggregateResult ar : [
            SELECT Campaign__c campId, COUNT(Id) cnt
            FROM Lead__c
            WHERE Campaign__c IN :campaignIds
            GROUP BY Campaign__c
        ]) {
            Id campId = (Id) ar.get('campId');
            Integer cnt = (Integer) ar.get('cnt');
            countMap.put(campId, cnt);
        }

        List<Campaign__c> toUpdate = new List<Campaign__c>();
        for (Id cId : countMap.keySet()) {
            toUpdate.add(new Campaign__c(
                Id = cId,
                Total_Leads__c = countMap.get(cId)
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * @description Recalculate Total_Enquiry_Sources__c for the given Campaign IDs.
     * Called from Enquiry Source trigger when Campaign changes.
     */
    public static void recalculateTotalEnquirySources(Set<Id> campaignIds) {
        if (campaignIds == null || campaignIds.isEmpty()) {
            return;
        }

        campaignIds.remove(null);
        if (campaignIds.isEmpty()) {
            return;
        }

        Map<Id, Integer> countMap = new Map<Id, Integer>();
        for (Id cId : campaignIds) {
            countMap.put(cId, 0);
        }

        for (AggregateResult ar : [
            SELECT Campaign__c campId, COUNT(Id) cnt
            FROM Enquiry_Source__c
            WHERE Campaign__c IN :campaignIds
            GROUP BY Campaign__c
        ]) {
            Id campId = (Id) ar.get('campId');
            Integer cnt = (Integer) ar.get('cnt');
            countMap.put(campId, cnt);
        }

        List<Campaign__c> toUpdate = new List<Campaign__c>();
        for (Id cId : countMap.keySet()) {
            toUpdate.add(new Campaign__c(
                Id = cId,
                Total_Enquiry_Sources__c = countMap.get(cId)
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * @description Recalculate Site_Visits__c, Qualified_Leads__c, and Bookings__c
     * for the given Campaign IDs. Runs a single update with all three counts.
     * Called from Lead, Site Visit, and Booking triggers.
     */
    public static void recalculateCampaignCounts(Set<Id> campaignIds) {
        if (campaignIds == null || campaignIds.isEmpty()) return;
        campaignIds.remove(null);
        if (campaignIds.isEmpty()) return;

        // Initialize counts
        Map<Id, Integer> siteVisitCounts = new Map<Id, Integer>();
        Map<Id, Integer> qualifiedCounts = new Map<Id, Integer>();
        Map<Id, Integer> bookingCounts = new Map<Id, Integer>();
        for (Id cId : campaignIds) {
            siteVisitCounts.put(cId, 0);
            qualifiedCounts.put(cId, 0);
            bookingCounts.put(cId, 0);
        }

        // Count Site Visits (via Lead → Campaign)
        for (AggregateResult ar : [
            SELECT Lead__r.Campaign__c campId, COUNT(Id) cnt
            FROM Site_Visit__c
            WHERE Lead__r.Campaign__c IN :campaignIds
            GROUP BY Lead__r.Campaign__c
        ]) {
            Id campId = (Id) ar.get('campId');
            siteVisitCounts.put(campId, (Integer) ar.get('cnt'));
        }

        // Count Qualified Leads (status NOT Unqualified or Closed Lost)
        for (AggregateResult ar : [
            SELECT Campaign__c campId, COUNT(Id) cnt
            FROM Lead__c
            WHERE Campaign__c IN :campaignIds
            AND Lead_Status__c NOT IN ('Unqualified', 'Closed Lost')
            GROUP BY Campaign__c
        ]) {
            Id campId = (Id) ar.get('campId');
            qualifiedCounts.put(campId, (Integer) ar.get('cnt'));
        }

        // Count Bookings (non-cancelled, via Lead → Campaign)
        for (AggregateResult ar : [
            SELECT Lead__r.Campaign__c campId, COUNT(Id) cnt
            FROM Booking__c
            WHERE Lead__r.Campaign__c IN :campaignIds
            AND Is_Cancelled__c = false
            GROUP BY Lead__r.Campaign__c
        ]) {
            Id campId = (Id) ar.get('campId');
            bookingCounts.put(campId, (Integer) ar.get('cnt'));
        }

        // Update campaigns with all three counts
        List<Campaign__c> toUpdate = new List<Campaign__c>();
        for (Id cId : campaignIds) {
            toUpdate.add(new Campaign__c(
                Id = cId,
                Site_Visits__c = siteVisitCounts.get(cId),
                Qualified_Leads__c = qualifiedCounts.get(cId),
                Bookings__c = bookingCounts.get(cId)
            ));
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * @description Helper to extract Campaign IDs from Leads for rollup.
     */
    public static Set<Id> getCampaignIdsFromLeads(List<Lead__c> leads) {
        Set<Id> campaignIds = new Set<Id>();
        for (Lead__c ld : leads) {
            if (ld.Campaign__c != null) {
                campaignIds.add(ld.Campaign__c);
            }
        }
        return campaignIds;
    }

    /**
     * @description Recalculate Campaign counts from Lead IDs.
     * Used by Site Visit and Booking triggers which only know the Lead ID,
     * not the Campaign ID. Queries the Lead to find the Campaign, then recalculates.
     */
    public static void recalculateCampaignCountsForLeads(Set<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) return;
        Set<Id> campaignIds = new Set<Id>();
        for (Lead__c ld : [SELECT Campaign__c FROM Lead__c WHERE Id IN :leadIds AND Campaign__c != null]) {
            campaignIds.add(ld.Campaign__c);
        }
        if (!campaignIds.isEmpty()) {
            recalculateCampaignCounts(campaignIds);
        }
    }
}