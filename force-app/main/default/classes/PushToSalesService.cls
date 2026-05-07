/**
 * @description Service for pushing Leads from Pre-Sales to Sales.
 *
 * Core actions (always executed):
 *   1. RecordType  → Pre_Sales to Sales
 *   2. Pre_Sale_User__c → previous Owner (pre-sales owner)
 *   3. Transferred_On__c → System.now()
 *   4. Lead_Status__c → 'Site Visit Scheduled' (on SV Scheduled push) or
 *                        'Site Visit Completed' (on SV Completed push)
 *   5. Owner assignment → Sales user via RoundRobin
 *   6. Manual sharing → Lead & SV shared with Pre Sale User
 *
 * Field-mapping actions (driven by General_Setup__c → Field_Mapping__c):
 *   For each active mapping, copy sourceField value into targetField on the Lead.
 *   Unmapped fields remain untouched.
 *
 * Entry points:
 *   • pushManual(leadId)           — manual push (only if status is SV Scheduled/Completed)
 *   • pushOnSVScheduled(svIds)     — automation: triggered on Site Visit creation
 *   • pushOnSVCompleted(svIds)     — automation: triggered on Site Visit completion
 */
public with sharing class PushToSalesService {

    private static final String PUSH_TYPE_MANUAL = 'Manual';
    private static final String PUSH_TYPE_SV_CREATION = 'Automation /On Site-Visit Creation';
    private static final String PUSH_TYPE_SV_COMPLETION = 'Automation /On Site-Visit Completion';

    // ═══════════════════════════════════════════════════════════════════
    //  PUBLIC: Manual Push
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Manual push to sales — only allowed when Lead_Status__c
     *              is 'Site Visit Scheduled' or 'Site Visit Completed'.
     */
    public static void pushManual(Id leadId) {
        Lead__c lead = queryLead(leadId);

        // Gate: manual push only on SV Scheduled / SV Completed
        Set<String> allowedStatuses = new Set<String>{ 'Site Visit Scheduled', 'Site Visit Completed' };
        if (!allowedStatuses.contains(lead.Lead_Status__c)) {
            throw new PushToSalesException(
                'Manual push is only allowed when Lead Status is Site Visit Scheduled or Site Visit Completed. Current status: ' + lead.Lead_Status__c
            );
        }

        General_Setup__c config = getActiveConfig(PUSH_TYPE_MANUAL);
        if (config == null) {
            throw new PushToSalesException('No active General Setup found for Manual push type.');
        }

        // Determine status based on current lead status
        String newStatus = lead.Lead_Status__c; // keeps current SV Scheduled or SV Completed

        List<Site_Visit__c> siteVisits = [
            SELECT Id FROM Site_Visit__c
            WHERE Lead__c = :leadId AND Status__c = 'Scheduled'
        ];

        executePush(lead, config, newStatus, siteVisits);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PUBLIC: Automation — On Site Visit Creation (Scheduled)
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Called from SiteVisitTriggerHandler on SV insert.
     *              Pushes lead to Sales immediately on SV creation.
     *              SV & Lead assigned to Sales via RoundRobin.
     *              SV & Lead shared with Pre Sale User.
     */
    public static void pushOnSVScheduled(List<Site_Visit__c> newSiteVisits) {
        General_Setup__c config = getActiveConfig(PUSH_TYPE_SV_CREATION);
        if (config == null) return; // no active config for this type

        Set<Id> leadIds = new Set<Id>();
        Map<Id, List<Site_Visit__c>> leadToSVs = new Map<Id, List<Site_Visit__c>>();

        for (Site_Visit__c sv : newSiteVisits) {
            if (sv.Lead__c != null) {
                leadIds.add(sv.Lead__c);
                if (!leadToSVs.containsKey(sv.Lead__c)) {
                    leadToSVs.put(sv.Lead__c, new List<Site_Visit__c>());
                }
                leadToSVs.get(sv.Lead__c).add(sv);
            }
        }

        if (leadIds.isEmpty()) return;

        Map<Id, Lead__c> leads = new Map<Id, Lead__c>(queryLeads(leadIds));

        for (Id leadId : leads.keySet()) {
            Lead__c lead = leads.get(leadId);
            // Only push if still in Pre_Sales record type
            if (!isPreSalesRecordType(lead.RecordTypeId)) continue;

            List<Site_Visit__c> svs = leadToSVs.get(leadId);
            executePush(lead, config, 'Site Visit Scheduled', svs);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PUBLIC: Automation — On Site Visit Completion
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Called from SiteVisitTriggerHandler when SV is marked Completed.
     *              Transfers Lead & SV ownership to Sales via RoundRobin.
     *              Shares Lead & SV with Pre Sale User.
     */
    public static void pushOnSVCompleted(List<Site_Visit__c> completedSiteVisits) {
        General_Setup__c config = getActiveConfig(PUSH_TYPE_SV_COMPLETION);
        if (config == null) return;

        Set<Id> leadIds = new Set<Id>();
        Map<Id, List<Site_Visit__c>> leadToSVs = new Map<Id, List<Site_Visit__c>>();

        for (Site_Visit__c sv : completedSiteVisits) {
            if (sv.Lead__c != null) {
                leadIds.add(sv.Lead__c);
                if (!leadToSVs.containsKey(sv.Lead__c)) {
                    leadToSVs.put(sv.Lead__c, new List<Site_Visit__c>());
                }
                leadToSVs.get(sv.Lead__c).add(sv);
            }
        }

        if (leadIds.isEmpty()) return;

        Map<Id, Lead__c> leads = new Map<Id, Lead__c>(queryLeads(leadIds));

        for (Id leadId : leads.keySet()) {
            Lead__c lead = leads.get(leadId);
            if (!isPreSalesRecordType(lead.RecordTypeId)) continue;

            List<Site_Visit__c> svs = leadToSVs.get(leadId);
            executePush(lead, config, 'Site Visit Completed', svs);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PRIVATE: Core Push Execution
    // ═══════════════════════════════════════════════════════════════════

    // Core push fields that must never be overwritten by field mappings
    private static final Set<String> PROTECTED_FIELDS = new Set<String>{
        'recordtypeid', 'ownerid', 'pre_sale_user__c', 'transferred_on__c', 'lead_status__c'
    };

    private static void executePush(Lead__c lead, General_Setup__c config, String newStatus, List<Site_Visit__c> siteVisits) {
        Id preSaleUserId = lead.OwnerId;

        // 1. Query field mappings to discover which Lead fields are needed
        List<Field_Mapping__c> mappings = [
            SELECT Primary_Object_Field_value__c, Related_object_field__c,
                   Mapping_Type__c, Active__c
            FROM Field_Mapping__c
            WHERE General_Setup__c = :config.Id
            AND Active__c = true
            ORDER BY Sequence__c ASC
        ];

        // 2. Build dynamic SOQL: base fields + mapped source fields + round-robin filter fields
        Set<String> fieldSet = new Set<String>{
            'id', 'ownerid', 'project__c', 'lead_status__c', 'recordtypeid'
        };
        Map<String, Schema.SObjectField> leadFieldMap = Schema.SObjectType.Lead__c.fields.getMap();
        for (Field_Mapping__c fm : mappings) {
            if (fm.Mapping_Type__c == 'field' && String.isNotBlank(fm.Primary_Object_Field_value__c)) {
                String srcField = fm.Primary_Object_Field_value__c.trim().toLowerCase();
                if (leadFieldMap.containsKey(srcField)) {
                    fieldSet.add(srcField);
                }
            }
        }

        // Include fields used by Round Robin filters so RoundRobinService
        // can read them dynamically via sObject.get()
        for (Round_Robin_Filter__c rrf : [
            SELECT Field_API_Name__c FROM Round_Robin_Filter__c
            WHERE Round_Robin__r.Is_Active__c = true
            AND Field_API_Name__c != null
        ]) {
            String filterField = rrf.Field_API_Name__c.trim().toLowerCase();
            if (leadFieldMap.containsKey(filterField)) {
                fieldSet.add(filterField);
            }
        }

        Id leadId = lead.Id;
        String soql = 'SELECT ' + String.join(new List<String>(fieldSet), ', ')
                     + ' FROM Lead__c WHERE Id = :leadId LIMIT 1';
        List<SObject> queryResult = Database.query(soql);
        if (queryResult.isEmpty()) {
            throw new PushToSalesException('Lead not found during push: ' + leadId);
        }
        lead = (Lead__c) queryResult[0];

        // 3. Apply field mappings FIRST (from General Setup) so they operate
        //    on the original pre-sales field values before core push changes
        applyFieldMappings(lead, mappings);

        // Get Sales record type Id
        Id salesRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName().get('Sales').getRecordTypeId();

        // Get sales executive via round-robin (pass full lead for better filter matching)
        Id salesExecId = RoundRobinService.getNextUser(lead, 'Sales');

        // Guard: if no sales user found via round robin — block with clear error
        if (salesExecId == null) {
            String projectField = (String) lead.get('Project__c');
            if (String.isBlank(projectField)) {
                throw new PushToSalesException(
                    'Push to Sales failed: This lead has no Project assigned. ' +
                    'Please assign a Project to the lead before scheduling a site visit.'
                );
            } else {
                throw new PushToSalesException(
                    'Push to Sales failed: No active Sales Round Robin is configured for this project. ' +
                    'Please contact your admin to set up a Round Robin with active Sales members for this project.'
                );
            }
        }

        // 4. Core field updates — applied AFTER mappings so they always take precedence.
        //    This ensures Pre_Sale_User__c and OwnerId are never overwritten by mappings.
        lead.RecordTypeId = salesRTId;
        lead.Pre_Sale_User__c = preSaleUserId;
        lead.Transferred_On__c = System.now();
        lead.Transferred_By__c = UserInfo.getUserId();
        lead.Lead_Status__c = newStatus;
        lead.OwnerId = salesExecId;

        // 5. Save lead
        update lead;

        // 6. Reassign pending followups to sales executive
        List<Followup__c> fus = [SELECT Id FROM Followup__c WHERE Lead__c = :lead.Id AND Status__c = 'Pending'];
        for (Followup__c fu : fus) {
            fu.Assigned_To__c = salesExecId;
        }
        if (!fus.isEmpty()) update fus;

        // 7. Reassign site visits to sales executive
        List<Site_Visit__c> allSVs = [
            SELECT Id FROM Site_Visit__c
            WHERE Lead__c = :lead.Id
            AND Status__c IN ('Scheduled', 'Completed')
        ];
        for (Site_Visit__c sv : allSVs) {
            sv.Assigned_To__c = salesExecId;
        }
        if (!allSVs.isEmpty()) update allSVs;

        // 8. Share Lead & SV records with Pre Sale User
        SharingUtility.shareLeadWithUser(lead.Id, preSaleUserId);
        List<Id> svIds = new List<Id>();
        for (Site_Visit__c sv : allSVs) {
            svIds.add(sv.Id);
        }
        if (!svIds.isEmpty()) {
            SharingUtility.shareSiteVisitsWithUser(svIds, preSaleUserId);
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PRIVATE: Apply Field Mappings
    // ═══════════════════════════════════════════════════════════════════

    private static void applyFieldMappings(Lead__c lead, List<Field_Mapping__c> mappings) {
        for (Field_Mapping__c fm : mappings) {
            if (fm.Mapping_Type__c == 'field'
                && String.isNotBlank(fm.Primary_Object_Field_value__c)
                && String.isNotBlank(fm.Related_object_field__c)) {

                // Skip core push fields — these are managed by executePush and
                // must never be overwritten by field mappings
                String targetLower = fm.Related_object_field__c.trim().toLowerCase();
                if (PROTECTED_FIELDS.contains(targetLower)) {
                    continue;
                }

                // Copy value from source field to target field on the same Lead
                Object val = lead.get(fm.Primary_Object_Field_value__c);
                lead.put(fm.Related_object_field__c, val);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PRIVATE: Helpers
    // ═══════════════════════════════════════════════════════════════════

    private static Lead__c queryLead(Id leadId) {
        List<Lead__c> leads = [
            SELECT Id, OwnerId, Project__c, Lead_Status__c, RecordTypeId
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];
        if (leads.isEmpty()) {
            throw new PushToSalesException('Lead not found: ' + leadId);
        }
        return leads[0];
    }

    private static List<Lead__c> queryLeads(Set<Id> leadIds) {
        return [
            SELECT Id, OwnerId, Project__c, Lead_Status__c, RecordTypeId
            FROM Lead__c
            WHERE Id IN :leadIds
        ];
    }

    private static General_Setup__c getActiveConfig(String pushType) {
        List<General_Setup__c> configs = [
            SELECT Id, Push_To_Sales_Type__c
            FROM General_Setup__c
            WHERE Push_To_Sales_Type__c = :pushType
            AND Is_Active__c = true
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    private static Boolean isPreSalesRecordType(Id recordTypeId) {
        return recordTypeId == Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
            .get('Pre_Sales').getRecordTypeId();
    }

    public class PushToSalesException extends Exception {}
}