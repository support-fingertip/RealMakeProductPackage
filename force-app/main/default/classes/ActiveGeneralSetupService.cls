/**
 * @description Thin service around the single-active General_Setup__c record.
 *              The trigger handler guarantees at most one active record, so
 *              callers can rely on a single lookup. Cross-project site visits
 *              are only permitted when the active setup's Lead_Duplication_Type__c
 *              is 'Mobile Only'; any other value (or no active setup) means
 *              a lead is uniquely scoped to its project and must not be shared.
 */
public with sharing class ActiveGeneralSetupService {

    private static Boolean cached = false;
    private static General_Setup__c cachedSetup;

    public static General_Setup__c getActiveSetup() {
        if (cached) return cachedSetup;
        List<General_Setup__c> rows = [
            SELECT Id, Is_Active__c, Lead_Duplication_Type__c, Push_To_Sales_Type__c
            FROM General_Setup__c
            WHERE Is_Active__c = true
            LIMIT 1
        ];
        cachedSetup = rows.isEmpty() ? null : rows[0];
        cached = true;
        return cachedSetup;
    }

    public static Boolean isCrossProjectSiteVisitAllowed() {
        General_Setup__c setup = getActiveSetup();
        return setup != null && setup.Lead_Duplication_Type__c == 'Mobile Only';
    }

    @TestVisible
    private static void clearCache() {
        cached = false;
        cachedSetup = null;
    }
}