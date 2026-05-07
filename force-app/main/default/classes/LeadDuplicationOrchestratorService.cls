/**
 * @description Config-driven orchestrator for lead duplication rules.
 * Reads the active Duplication_Configuration__c for Lead__c and determines
 * the rule type by parsing Primary_Expression__c:
 *   - Contains Project__c → MOBILE_PROJECT rule
 *   - Only mobile fields  → MOBILE_ONLY rule
 *
 * Used by UI controllers to check for duplicates BEFORE DML enters the trigger chain.
 */
public with sharing class LeadDuplicationOrchestratorService {

    public static final String RULE_MOBILE_ONLY = 'MOBILE_ONLY';
    public static final String RULE_MOBILE_PROJECT = 'MOBILE_PROJECT';

    /**
     * @description Determine the active duplication rule type.
     * @return 'MOBILE_ONLY' or 'MOBILE_PROJECT', or null if no config found
     */
    public static String getActiveRuleType() {
        Duplication_Configuration__c config = getActiveConfig();
        if (config == null) return null;
        return parseRuleType(config.Primary_Expression__c);
    }

    /**
     * @description Check for duplicate leads based on the active duplication configuration.
     * @param primaryMobile   Primary mobile number to check
     * @param secondaryMobile Secondary mobile number to check (optional)
     * @param projectId       Project context for the check
     * @return DuplicationResult with action recommendation
     */
    public static DuplicationResult checkDuplicate(
        String primaryMobile, String secondaryMobile, Id projectId
    ) {
        DuplicationResult result = new DuplicationResult();

        Duplication_Configuration__c config = getActiveConfig();
        if (config == null) {
            result.action = 'NEW';
            result.message = 'No duplication configuration found. Proceed as new lead.';
            return result;
        }

        result.ruleType = parseRuleType(config.Primary_Expression__c);

        if (String.isBlank(primaryMobile)) {
            result.action = 'NEW';
            result.message = 'No mobile number provided.';
            return result;
        }

        // Build cross-mobile matching query (matches Primary ↔ Secondary in both directions)
        String query = 'SELECT Id, Lead_Status__c, Is_Active__c, Project__c, '
            + 'Owner__c, First_Name__c, Last_Name__c, Name '
            + 'FROM Lead__c WHERE (';

        List<String> mobileClauses = new List<String>();
        mobileClauses.add('Primary_Mobile__c = :primaryMobile');
        mobileClauses.add('Secondary_Mobile__c = :primaryMobile');
        if (String.isNotBlank(secondaryMobile)) {
            mobileClauses.add('Primary_Mobile__c = :secondaryMobile');
            mobileClauses.add('Secondary_Mobile__c = :secondaryMobile');
        }
        query += String.join(mobileClauses, ' OR ') + ')';

        // For MOBILE_PROJECT rule, also match on project
        if (result.ruleType == RULE_MOBILE_PROJECT) {
            query += ' AND Project__c = :projectId';
        }

        query += ' LIMIT 1';

        List<Lead__c> matches = Database.query(query);

        if (matches.isEmpty()) {
            result.action = 'NO_DUPLICATE';
            result.message = 'No duplicate found.';
            return result;
        }

        Lead__c existing = matches[0];
        result.existingLeadId = existing.Id;
        result.existingLeadStatus = existing.Lead_Status__c;
        result.isActive = existing.Is_Active__c;

        // Resolve project name
        if (existing.Project__c != null) {
            List<Project__c> projects = [SELECT Name FROM Project__c WHERE Id = :existing.Project__c LIMIT 1];
            result.projectName = projects.isEmpty() ? '' : projects[0].Name;
        }

        if (result.ruleType == RULE_MOBILE_ONLY) {
            // Mobile-only: check if same or different project
            if (existing.Project__c == projectId) {
                // Same project duplicate
                if (existing.Is_Active__c) {
                    result.action = 'REENGAGE';
                    result.message = 'Active lead found on the same project. Lead will be re-engaged.';
                } else {
                    result.action = 'REOPEN';
                    result.message = 'Inactive lead found on the same project. Lead can be re-opened.';
                }
            } else {
                // Different project → cross-project site visit
                result.action = 'CROSS_PROJECT_SV';
                result.message = 'Lead exists on project "' + result.projectName
                    + '". A cross-project site visit can be scheduled.';
            }
        } else {
            // Mobile+Project: match is always same project (query filtered by project)
            if (existing.Is_Active__c) {
                result.action = 'REENGAGE';
                result.message = 'Active duplicate found on this project. Lead will be re-engaged.';
            } else {
                result.action = 'REOPEN';
                result.message = 'Inactive duplicate found on this project. Lead can be re-opened.';
            }
        }

        return result;
    }

    // ════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ════════════════════════════════════════════════════════════

    private static Duplication_Configuration__c getActiveConfig() {
        List<Duplication_Configuration__c> configs = [
            SELECT Id, Primary_Object_API_Name__c, Primary_Expression__c,
                   Related_Object_API_Name__c, Related_Expression__c
            FROM Duplication_Configuration__c
            WHERE Primary_Object_API_Name__c = 'Lead__c'
            AND Active__c = true
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    @TestVisible
    private static String parseRuleType(String expression) {
        if (String.isBlank(expression)) return RULE_MOBILE_ONLY;
        // If expression references Project__c, it's a mobile+project rule
        if (expression.containsIgnoreCase('Project__c')) {
            return RULE_MOBILE_PROJECT;
        }
        return RULE_MOBILE_ONLY;
    }

    // ════════════════════════════════════════════════════════════
    // RESULT DTO
    // ════════════════════════════════════════════════════════════

    public class DuplicationResult {
        @AuraEnabled public String ruleType;
        @AuraEnabled public String action;       // CROSS_PROJECT_SV, REOPEN, REENGAGE, NO_DUPLICATE, NEW
        @AuraEnabled public Id existingLeadId;
        @AuraEnabled public String existingLeadStatus;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String projectName;
        @AuraEnabled public String message;
    }
}