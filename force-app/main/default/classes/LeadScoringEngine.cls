/**
 * ════════════════════════════════════════════════════════════════════════════
 * LeadScoringEngine
 * ════════════════════════════════════════════════════════════════════════════
 * Dynamic Lead Scoring Engine — fully metadata-driven via Lead_Score_Rule__c
 * and Lead_Score_Tier__c. Zero hardcoded field names, values, or point values.
 *
 * Architecture (4-step pipeline):
 *   1. QUERY RULES  — Load all active Lead_Score_Rule__c records         (1 SOQL)
 *   2. COUNT RELATED — Bulk-query related object counts for Count rules  (1 SOQL per related obj)
 *   3. EVALUATE      — Compare each rule against each lead (in-memory)   (0 SOQL)
 *   4. RESOLVE TIER  — Map total score to tier via Lead_Score_Tier__c    (1 SOQL)
 *
 * Entry point:
 *   LeadScoringEngine.calculateScores(leads)  — called from before insert/update
 *
 * Governor cost: 2-3 SOQL, 0 DML (runs in before trigger, mutates Lead directly)
 * ════════════════════════════════════════════════════════════════════════════
 */
public with sharing class LeadScoringEngine {

    /**
     * Main entry point. Evaluates all active scoring rules against the given
     * leads and sets Lead_Score__c, Lead_Score_Tier__c, and Last_Score_Date__c.
     *
     * Designed for before insert / before update trigger context — mutates
     * the Lead records directly (no DML needed).
     *
     * @param leads  List of Lead__c records (will be mutated)
     */
    public static void calculateScores(List<Lead__c> leads) {
        if (leads == null || leads.isEmpty()) return;

        // Step 1: Query all active scoring rules (1 SOQL)
        List<Lead_Score_Rule__c> rules = [
            SELECT Id, Rule_Type__c, Field_API_Name__c, Operator__c,
                   Field_Value__c, Points__c, Category__c,
                   Related_Object__c, Lookup_Field__c, Count_Threshold__c
            FROM Lead_Score_Rule__c
            WHERE Is_Active__c = true
            ORDER BY Sequence__c ASC
        ];

        if (rules.isEmpty()) return;

        // Separate rules by type
        List<Lead_Score_Rule__c> fieldRules = new List<Lead_Score_Rule__c>();
        List<Lead_Score_Rule__c> countRules = new List<Lead_Score_Rule__c>();

        for (Lead_Score_Rule__c r : rules) {
            if (r.Rule_Type__c == 'Count') {
                countRules.add(r);
            } else {
                fieldRules.add(r);
            }
        }

        // Step 2: Bulk-query related object counts for Count rules
        // Key: Related_Object__c + '|' + Lookup_Field__c → Map<Lead Id, Integer count>
        Map<String, Map<Id, Integer>> countsByObject = new Map<String, Map<Id, Integer>>();

        if (!countRules.isEmpty()) {
            // Collect Lead Ids (only for update — insert won't have Ids yet)
            Set<Id> leadIds = new Set<Id>();
            for (Lead__c ld : leads) {
                if (ld.Id != null) {
                    leadIds.add(ld.Id);
                }
            }

            if (!leadIds.isEmpty()) {
                countsByObject = queryRelatedCounts(countRules, leadIds);
            }
        }

        // Step 3: Evaluate each lead against all rules (in-memory, 0 SOQL)
        for (Lead__c ld : leads) {
            Decimal totalScore = 0;

            // Evaluate field-based rules
            for (Lead_Score_Rule__c r : fieldRules) {
                if (evaluateFieldRule(ld, r)) {
                    totalScore += r.Points__c;
                }
            }

            // Evaluate count-based rules (only for existing leads with Ids)
            if (ld.Id != null) {
                for (Lead_Score_Rule__c r : countRules) {
                    String objKey = r.Related_Object__c + '|' + r.Lookup_Field__c;
                    Map<Id, Integer> countsMap = countsByObject.get(objKey);
                    Integer cnt = (countsMap != null && countsMap.containsKey(ld.Id))
                        ? countsMap.get(ld.Id) : 0;

                    if (evaluateCountRule(cnt, r)) {
                        totalScore += r.Points__c;
                    }
                }
            }

            ld.Lead_Score__c = totalScore;
            ld.Last_Score_Date__c = DateTime.now();
        }

        // Step 4: Resolve tier for each lead (1 SOQL)
        List<Lead_Score_Tier__c> tiers = [
            SELECT Name, Min_Score__c, Max_Score__c
            FROM Lead_Score_Tier__c
            ORDER BY Min_Score__c ASC
        ];

        for (Lead__c ld : leads) {
            ld.Lead_Score_Tier__c = resolveTier(ld.Lead_Score__c, tiers);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    //  PRIVATE: Field Rule Evaluation
    // ════════════════════════════════════════════════════════════════════

    /**
     * Evaluates a single field-based rule against a lead.
     * Uses sObject.get() for fully dynamic field access.
     */
    @TestVisible
    private static Boolean evaluateFieldRule(Lead__c ld, Lead_Score_Rule__c rule) {
        if (String.isBlank(rule.Field_API_Name__c)) return false;

        Object rawVal;
        try {
            rawVal = ld.get(rule.Field_API_Name__c);
        } catch (Exception e) {
            return false; // Invalid field name — skip
        }

        String strVal = (rawVal != null) ? String.valueOf(rawVal) : null;
        String ruleVal = rule.Field_Value__c;
        String op = rule.Operator__c;

        if (op == 'equals') {
            return strVal != null && strVal == ruleVal;
        } else if (op == 'not_equals') {
            return strVal == null || strVal != ruleVal;
        } else if (op == 'contains') {
            return strVal != null && ruleVal != null && strVal.containsIgnoreCase(ruleVal);
        } else if (op == 'greater_than' || op == 'less_than'
                || op == 'greater_or_equal' || op == 'less_or_equal') {
            return evaluateNumericComparison(strVal, ruleVal, op);
        }

        return false;
    }

    /**
     * Attempts numeric comparison. Falls back to string comparison if
     * values are not parseable as decimals.
     */
    private static Boolean evaluateNumericComparison(
        String actualStr, String ruleStr, String op
    ) {
        if (actualStr == null || ruleStr == null) return false;

        try {
            Decimal actual = Decimal.valueOf(actualStr);
            Decimal target = Decimal.valueOf(ruleStr);

            if (op == 'greater_than') return actual > target;
            if (op == 'less_than') return actual < target;
            if (op == 'greater_or_equal') return actual >= target;
            if (op == 'less_or_equal') return actual <= target;
        } catch (Exception e) {
            // Not numeric — compare as strings
            Integer cmp = actualStr.compareTo(ruleStr);
            if (op == 'greater_than') return cmp > 0;
            if (op == 'less_than') return cmp < 0;
            if (op == 'greater_or_equal') return cmp >= 0;
            if (op == 'less_or_equal') return cmp <= 0;
        }

        return false;
    }

    // ════════════════════════════════════════════════════════════════════
    //  PRIVATE: Count Rule Evaluation
    // ════════════════════════════════════════════════════════════════════

    /**
     * Evaluates whether the actual count meets the rule's threshold
     * using the rule's operator.
     */
    @TestVisible
    private static Boolean evaluateCountRule(Integer actualCount, Lead_Score_Rule__c rule) {
        Decimal threshold = (rule.Count_Threshold__c != null) ? rule.Count_Threshold__c : 1;
        String op = rule.Operator__c;

        if (op == 'equals') return actualCount == threshold;
        if (op == 'not_equals') return actualCount != threshold;
        if (op == 'greater_than') return actualCount > threshold;
        if (op == 'less_than') return actualCount < threshold;
        if (op == 'greater_or_equal') return actualCount >= threshold;
        if (op == 'less_or_equal') return actualCount <= threshold;

        // Default for count: >= threshold
        return actualCount >= threshold;
    }

    // ════════════════════════════════════════════════════════════════════
    //  PRIVATE: Bulk Related Object Count Query
    // ════════════════════════════════════════════════════════════════════

    /**
     * Queries counts of related records for all count-based rules in bulk.
     * Groups by Related_Object__c + Lookup_Field__c so each unique
     * combination only needs one SOQL query.
     *
     * @return Map keyed by "ObjectName|LookupField" → Map<LeadId, count>
     */
    private static Map<String, Map<Id, Integer>> queryRelatedCounts(
        List<Lead_Score_Rule__c> countRules, Set<Id> leadIds
    ) {
        Map<String, Map<Id, Integer>> result = new Map<String, Map<Id, Integer>>();

        // Deduplicate: group rules by object+lookup to avoid redundant queries
        Set<String> queriedKeys = new Set<String>();

        for (Lead_Score_Rule__c r : countRules) {
            if (String.isBlank(r.Related_Object__c) || String.isBlank(r.Lookup_Field__c)) continue;

            String objKey = r.Related_Object__c + '|' + r.Lookup_Field__c;
            if (queriedKeys.contains(objKey)) continue;
            queriedKeys.add(objKey);

            Map<Id, Integer> countsMap = new Map<Id, Integer>();

            try {
                String soql = 'SELECT ' + String.escapeSingleQuotes(r.Lookup_Field__c) + ', COUNT(Id) cnt '
                    + 'FROM ' + String.escapeSingleQuotes(r.Related_Object__c) + ' '
                    + 'WHERE ' + String.escapeSingleQuotes(r.Lookup_Field__c) + ' IN :leadIds '
                    + 'GROUP BY ' + String.escapeSingleQuotes(r.Lookup_Field__c);

                List<AggregateResult> aggResults = Database.query(soql);

                for (AggregateResult ar : aggResults) {
                    Id leadId = (Id) ar.get(r.Lookup_Field__c);
                    Integer cnt = (Integer) ar.get('cnt');
                    countsMap.put(leadId, cnt);
                }
            } catch (Exception e) {
                // Invalid object/field — skip silently
            }

            result.put(objKey, countsMap);
        }

        return result;
    }

    // ════════════════════════════════════════════════════════════════════
    //  PRIVATE: Tier Resolution
    // ════════════════════════════════════════════════════════════════════

    /**
     * Resolves a numeric score to a tier name by checking which
     * Lead_Score_Tier__c range contains the score.
     *
     * @return Tier Name (e.g. "Hot", "Warm"), or null if no tier matches
     */
    @TestVisible
    private static String resolveTier(Decimal score, List<Lead_Score_Tier__c> tiers) {
        if (score == null || tiers == null) return null;

        for (Lead_Score_Tier__c t : tiers) {
            if (score >= t.Min_Score__c && score <= t.Max_Score__c) {
                return t.Name;
            }
        }

        return null;
    }
}