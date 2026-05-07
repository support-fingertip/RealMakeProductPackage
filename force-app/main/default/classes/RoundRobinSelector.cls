/**
 * ════════════════════════════════════════════════════════════════════════════
 * RoundRobinSelector
 * ════════════════════════════════════════════════════════════════════════════
 * Pure SOQL layer for Round Robin data.
 *
 * Queries ALL active buckets with ALL their child filters and ALL active
 * members.  No business-logic filtering happens here — that is the
 * responsibility of RoundRobinService.
 *
 * Governor cost: 1 SOQL (parent + 2 child subqueries counted as 1).
 * ════════════════════════════════════════════════════════════════════════════
 */
public without sharing class RoundRobinSelector {

    /**
     * Returns every active Round_Robin__c with:
     *   • Round_Robin_Filters__r  – all filter criteria (sorted by Preference_Order__c)
     *   • Round_Robin_Members__r  – all ACTIVE members regardless of Assignment_Type__c
     *                               (sorted by Order__c for deterministic rotation)
     *
     * IMPORTANT: Assignment_Type__c is intentionally NOT filtered in SOQL.
     * The service layer filters members by type in Apex AFTER bucket matching.
     * This prevents the "empty-member skip" bug where a matching bucket was
     * skipped because its SOQL-filtered member list was empty.
     */
    public static List<Round_Robin__c> getActiveBucketsWithChildren() {
        return [
            SELECT Id, Name,
                (SELECT Id, Field_API_Name__c, Field_Value__c, Field_Priority__c
                 FROM Round_Robin_Filters__r
                 ORDER BY Preference_Order__c ASC),
                (SELECT Id, User__c, User__r.Availability__c, User__r.is_working__c,
                        Assignment_Type__c, Order__c, Last_Assigned__c
                 FROM Round_Robin_Members__r
                 WHERE Is_Active__c = true
                 ORDER BY Order__c ASC NULLS LAST)
            FROM Round_Robin__c
            WHERE Is_Active__c = true
        ];
    }
}