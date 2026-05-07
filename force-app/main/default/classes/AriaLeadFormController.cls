/**
 * @description Backend for the guided lead-capture form (and the smaller
 * site-visit / follow-up forms) inside the Aria chat.
 *
 * Goals:
 *   - Sales execs should never have to TYPE a state, project, BHK or budget —
 *     all of those are dropdowns sourced from real org data so there's no
 *     possibility of a typo.
 *   - Lead creation reuses the existing LeadDeduplicationService — same dedup,
 *     credit, round-robin behaviour as walk-in / CP / API entry points.
 *   - Site visit + follow-up creation reuses the existing services and trigger
 *     handlers respectively.
 */
public with sharing class AriaLeadFormController {

    // ════════════════════════════════════════════════════════════
    // OPTIONS for the cascading dropdowns
    // ════════════════════════════════════════════════════════════

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getStates() {
        Set<String> stateSet = new Set<String>();
        for (Project__c p : [
            SELECT State__c FROM Project__c
            WHERE Is_Active__c = true
              AND Project_Status__c IN ('Pre-Launch', 'Launched', 'Ongoing')
              AND State__c != null
        ]) {
            stateSet.add(p.State__c);
        }

        List<String> states = new List<String>(stateSet);
        states.sort();

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (String s : states) {
            out.add(new Map<String, Object>{ 'label' => s, 'value' => s });
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getProjectsByState(String state) {
        if (String.isBlank(state)) {
            return new List<Map<String, Object>>();
        }

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Project__c p : [
            SELECT Id, Name, Project_Code__c, City__c, Allowed_BHK_Types__c, Property_Types__c
            FROM Project__c
            WHERE Is_Active__c = true
              AND Project_Status__c IN ('Pre-Launch', 'Launched', 'Ongoing')
              AND State__c = :state
            ORDER BY Name
        ]) {
            out.add(new Map<String, Object>{
                'label'             => p.Name + (String.isNotBlank(p.City__c) ? ' (' + p.City__c + ')' : ''),
                'value'             => p.Id,
                'project_code'      => p.Project_Code__c,
                'allowed_bhk'       => p.Allowed_BHK_Types__c,
                'property_types'    => p.Property_Types__c
            });
        }
        return out;
    }

    /**
     * @description Returns BHK options for a project. Falls back to the
     *              Lead__c.BHK_Type__c picklist if the project has no
     *              Allowed_BHK_Types__c configured.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getBhkOptionsForProject(Id projectId) {
        List<String> values = new List<String>();
        if (projectId != null) {
            for (Project__c p : [
                SELECT Allowed_BHK_Types__c FROM Project__c WHERE Id = :projectId LIMIT 1
            ]) {
                if (String.isNotBlank(p.Allowed_BHK_Types__c)) {
                    for (String v : p.Allowed_BHK_Types__c.split(';')) {
                        if (String.isNotBlank(v)) values.add(v.trim());
                    }
                }
            }
        }
        if (values.isEmpty()) {
            // Fallback: full picklist from Lead__c.BHK_Type__c
            for (Map<String, Object> opt : getPicklistValues('Lead__c', 'BHK_Type__c')) {
                values.add((String) opt.get('value'));
            }
        }

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (String v : values) {
            out.add(new Map<String, Object>{ 'label' => v, 'value' => v });
        }
        return out;
    }

    /**
     * @description One-shot fetch: returns all the static dropdowns the form
     *              needs (budget, purpose, timeline, lead source) so the LWC
     *              only has to make one Apex call on mount.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getStaticOptions() {
        return new Map<String, Object>{
            'budgets'      => getPicklistValues('Lead__c', 'Budget_Range__c'),
            'purposes'     => getPicklistValues('Lead__c', 'Purchase_Purpose__c'),
            'timelines'    => getPicklistValues('Lead__c', 'Purchase_Timeline__c'),
            'visit_modes'  => getPicklistValues('Site_Visit__c', 'Mode_Of_Visit__c')
        };
    }

    // ════════════════════════════════════════════════════════════
    // SUBMIT — Lead
    // ════════════════════════════════════════════════════════════

    /**
     * @description Submit the captured form. Delegates to the existing dedup
     *              service so the lead routes through the same matrix as a
     *              CP / walk-in / API submission.
     *
     * @param payloadJson JSON map with: first_name, last_name, mobile, email,
     *                    project_code (required), bhk_preference, budget_range,
     *                    purchase_purpose, purchase_timeline, preferred_language
     */
    @AuraEnabled
    public static Map<String, Object> submitLead(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Form data is required.');
        }
        Map<String, Object> raw;
        try {
            raw = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid form payload: ' + e.getMessage());
        }

        Map<String, String> args = new Map<String, String>();
        for (String k : raw.keySet()) {
            Object v = raw.get(k);
            args.put(k, v == null ? null : String.valueOf(v));
        }
        try {
            return AriaActionService.createLead(toObjectMap(args));
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ════════════════════════════════════════════════════════════
    // SUBMIT — Site Visit (mini-form, used on Lead record pages)
    // ════════════════════════════════════════════════════════════

    @AuraEnabled
    public static Map<String, Object> submitSiteVisit(
        Id leadId, Id projectId, String scheduledIso, String mode
    ) {
        if (leadId == null) {
            throw new AuraHandledException('Lead Id is required.');
        }
        try {
            return AriaActionService.scheduleSiteVisit(new Map<String, Object>{
                'lead_id'      => leadId,
                'project_id'   => projectId,
                'scheduled_at' => scheduledIso,
                'mode'         => mode
            });
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ════════════════════════════════════════════════════════════
    // SUBMIT — Follow-up (mini-form)
    // ════════════════════════════════════════════════════════════

    @AuraEnabled
    public static Map<String, Object> submitFollowup(
        Id leadId, String dueIso, String subject, String notes
    ) {
        if (leadId == null) {
            throw new AuraHandledException('Lead Id is required.');
        }
        try {
            return AriaActionService.scheduleFollowup(new Map<String, Object>{
                'lead_id'  => leadId,
                'due_date' => dueIso,
                'subject'  => subject,
                'notes'    => notes
            });
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    // ════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════

    @TestVisible
    private static List<Map<String, Object>> getPicklistValues(String objectName, String fieldName) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        Schema.SObjectType sobjType = NamespaceUtil.describeObject(objectName);
        if (sobjType == null) return out;
        Schema.SObjectField sfField = NamespaceUtil.describeField(sobjType, fieldName);
        if (sfField == null) return out;
        Schema.DescribeFieldResult dfr = sfField.getDescribe();
        for (Schema.PicklistEntry e : dfr.getPicklistValues()) {
            if (e.isActive()) {
                out.add(new Map<String, Object>{ 'label' => e.getLabel(), 'value' => e.getValue() });
            }
        }
        return out;
    }

    private static Map<String, Object> toObjectMap(Map<String, String> source) {
        Map<String, Object> out = new Map<String, Object>();
        for (String k : source.keySet()) {
            out.put(k, source.get(k));
        }
        return out;
    }
}