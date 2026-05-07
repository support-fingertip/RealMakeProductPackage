/**
 * @description Configuration service for the Channel Partner module.
 *              Reads CP_Module_Config__c (single-record) and caches it per transaction.
 *              All business parameters (source names, statuses, credit days, etc.)
 *              come from this config — zero hardcoded values in service classes.
 */
public with sharing class CPModuleConfigService {

    private static CP_Module_Config__c cachedConfig;

    /**
     * @description Returns the active CP Module Configuration.
     *              Cached for the duration of the transaction (single SOQL on first call).
     */
    public static CP_Module_Config__c getConfig() {
        if (cachedConfig != null) {
            return cachedConfig;
        }

        List<CP_Module_Config__c> configs = [
            SELECT Id, CP_Source_Name__c, CP_Approval_Process__c,
                   CP_Active_Statuses__c, Lead_Inactive_Statuses__c,
                   Lead_Reopened_Type__c, Lead_Reengaged_Type__c,
                   Lead_Default_Status__c, Credit_Expiry_Days__c,
                   Credit_Active_Status__c, Credit_Expired_Status__c,
                   Assignment_Type__c
            FROM CP_Module_Config__c
            WHERE Is_Active__c = true
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new CPModuleConfigException(
                'No active CP Module Configuration found. '
                + 'Please create a CP_Module_Config__c record and mark it as Active.'
            );
        }

        cachedConfig = configs[0];
        return cachedConfig;
    }

    // ════════════════════════════════════════════════════════════
    // CONVENIENCE GETTERS
    // ════════════════════════════════════════════════════════════

    public static String getCPSourceName() {
        return getConfig().CP_Source_Name__c;
    }

    public static Set<String> getCPActiveStatuses() {
        return parseJsonStringSet(getConfig().CP_Active_Statuses__c);
    }

    public static Set<String> getLeadInactiveStatuses() {
        return parseJsonStringSet(getConfig().Lead_Inactive_Statuses__c);
    }

    public static Integer getCreditExpiryDays() {
        Decimal d = getConfig().Credit_Expiry_Days__c;
        return (d != null) ? d.intValue() : 90;
    }

    // ════════════════════════════════════════════════════════════
    // JSON PARSING HELPERS
    // ════════════════════════════════════════════════════════════

    private static Set<String> parseJsonStringSet(String jsonStr) {
        Set<String> result = new Set<String>();
        if (String.isBlank(jsonStr)) return result;
        try {
            List<Object> items = (List<Object>) JSON.deserializeUntyped(jsonStr);
            for (Object item : items) {
                result.add(String.valueOf(item));
            }
        } catch (Exception e) {
            // Fallback: treat as comma-separated
            for (String item : jsonStr.split(',')) {
                String trimmed = item.trim().removeStart('"').removeEnd('"');
                if (String.isNotBlank(trimmed)) {
                    result.add(trimmed);
                }
            }
        }
        return result;
    }

    @TestVisible
    private static void clearCache() {
        cachedConfig = null;
    }

    public class CPModuleConfigException extends Exception {}
}