/**
 * @description Lead deduplication and creation service.
 * Handles dedup logic per M4 spec: mobile + project matching.
 * Rules: LEAD_SRC_01-06, dedup matrix
 *
 * CP-specific dedup scenarios (from CP module doc):
 *   S1: Same mobile, source NOT CP, same project, Active → "Lead already exists, you will not get the credit"
 *   S2: Same mobile, different project → new lead with credit
 *   S3: Same mobile, source is ANOTHER CP, same project, Active → credit (enquiry source)
 *   S4: Same mobile, same project, but Lost/Unqualified/Booked → re-open with CP, credit
 *   S5: Same mobile, SAME CP, same project, Active → "Lead already exists with your name"
 *
 * All field mappings via IntegrationFieldMappingEngine:
 *   - 'LEAD_CREATION' config for lead field mapping + defaults
 *   - 'ENQUIRY_SOURCE_CREATION' config for enquiry source field mapping
 *
 * All business parameters from CP_Module_Config__c via CPModuleConfigService.
 */
public with sharing class LeadDeduplicationService {

    public class LeadResult {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String action; // CREATED, REENGAGED, REOPENED, DUPLICATE, DUPLICATE_SAME_CP, DUPLICATE_NO_CREDIT
        @AuraEnabled public String message;
    }

    /**
     * @description Process incoming lead with deduplication.
     *              Handles both CP and non-CP leads with scenario-specific logic.
     */
    public static LeadResult processIncomingLead(Map<String, String> leadData) {
        String primaryMobile = leadData.get('primary_mobile');
        String secondaryMobile = leadData.get('secondary_mobile');
        String projectCode = leadData.get('project_code');
        String source = leadData.get('source');
        String subSource = leadData.get('sub_source');
        String campaignIdText = leadData.get('campaign_id');
        String cpId = leadData.get('cp_id');
        Boolean isCPLead = String.isNotBlank(cpId);

        // Resolve Campaign by auto-number Name (e.g., CMP-00042) — not Salesforce record ID.
        Id campaignId = CampaignService.resolveCampaignId(campaignIdText);

        // Find project by code
        List<Project__c> projects = [SELECT Id FROM Project__c WHERE Project_Code__c = :projectCode LIMIT 1];
        if (projects.isEmpty()) {
            LeadResult r = new LeadResult();
            r.action = 'ERROR';
            r.message = 'Invalid project code: ' + projectCode;
            return r;
        }
        Id projectId = projects[0].Id;

        // ── Dedup: search by mobile + SAME project ──────────────────
        List<Lead__c> sameProjectLeads = [
            SELECT Id, Primary_Mobile__c, Secondary_Mobile__c, Project__c,
                   Lead_Status__c, Owner__c, Lead_Type__c,
                   Is_Active__c, Lead_Source__c, Channel_Partner__c
            FROM Lead__c
            WHERE Project__c = :projectId
            AND (Primary_Mobile__c = :primaryMobile
                 OR Secondary_Mobile__c = :primaryMobile
                 OR Primary_Mobile__c = :secondaryMobile
                 OR Secondary_Mobile__c = :secondaryMobile)
            LIMIT 1
        ];

        // Load config once for this transaction
        CP_Module_Config__c cfg = CPModuleConfigService.getConfig();
        Set<String> inactiveStatuses = CPModuleConfigService.getLeadInactiveStatuses();

        LeadResult result = new LeadResult();

        if (!sameProjectLeads.isEmpty()) {
            Lead__c existing = sameProjectLeads[0];
            Boolean isActive = !inactiveStatuses.contains(existing.Lead_Status__c);

            if (isCPLead) {
                return handleCPDuplication(existing, isActive, cpId, source, subSource, campaignId, projectId, leadData, cfg);
            } else {
                return handleNonCPDuplication(existing, isActive, source, subSource, campaignId, projectId, leadData, cfg);
            }

        } else {
            // ── No match on same project: check different project ──
            List<Lead__c> diffProjectLeads = [
                SELECT Id FROM Lead__c
                WHERE (Primary_Mobile__c = :primaryMobile
                       OR Secondary_Mobile__c = :primaryMobile
                       OR Primary_Mobile__c = :secondaryMobile
                       OR Secondary_Mobile__c = :secondaryMobile)
                AND Project__c != :projectId
                LIMIT 1
            ];

            // S2: Different project (or no existing lead at all) → Create new lead
            return createNewLead(leadData, projectId, source, subSource, campaignId, cpId, isCPLead, cfg);
        }
    }

    // ════════════════════════════════════════════════════════════
    // CP LEAD DUPLICATION SCENARIOS
    // ════════════════════════════════════════════════════════════

    private static LeadResult handleCPDuplication(
        Lead__c existing, Boolean isActive, String cpId,
        String source, String subSource, Id campaignId,
        Id projectId, Map<String, String> leadData,
        CP_Module_Config__c cfg
    ) {
        LeadResult result = new LeadResult();
        String existingSource = existing.Lead_Source__c;
        String existingCpId = existing.Channel_Partner__c;
        String cpSourceName = cfg.CP_Source_Name__c;
        Integer creditDays = cfg.Credit_Expiry_Days__c.intValue();
        String creditMessage = 'Lead registered successfully, you will have credit for '
            + creditDays + ' days (if the lead is not marked as Lost; after '
            + creditDays + ' days, you will not get the credit even if it is not marked as Lost), and you should bring the customer to the site.';

        if (isActive) {
            // ── S5: Same CP, same project, Active ────────────────
            if (existingSource == cpSourceName && existingCpId == cpId) {
                createEnquirySource(existing.Id, cfg.Lead_Reengaged_Type__c, source, subSource, campaignId, cpId, leadData, cfg);
                existing.Lead_Type__c = cfg.Lead_Reengaged_Type__c;
                existing.Last_Reengaged_Source__c = source;
                existing.Last_Reengaged_Sub__c = subSource;
                existing.Last_Reengaged_Date__c = Date.today();
                update existing;
                result.leadId = existing.Id;
                result.action = 'DUPLICATE_SAME_CP';
                result.message = 'Lead already exists with your name.';
                return result;
            }

            // ── S1: Source NOT CP, same project, Active ──────────
            if (existingSource != cpSourceName) {
                createEnquirySource(existing.Id, cfg.Lead_Reengaged_Type__c, source, subSource, campaignId, cpId, leadData, cfg);
                existing.Lead_Type__c = cfg.Lead_Reengaged_Type__c;
                existing.Last_Reengaged_Source__c = source;
                existing.Last_Reengaged_Sub__c = subSource;
                existing.Last_Reengaged_Date__c = Date.today();
                update existing;
                result.leadId = existing.Id;
                result.action = 'DUPLICATE_NO_CREDIT';
                result.message = 'Lead already exists, you will not get the credit.';
                return result;
            }

            // ── S3: Source is ANOTHER CP, same project, Active ───
            if (existingSource == cpSourceName && existingCpId != cpId) {
                createEnquirySource(existing.Id, cfg.Lead_Reengaged_Type__c, source, subSource, campaignId, cpId, leadData, cfg);
                existing.Lead_Type__c = cfg.Lead_Reengaged_Type__c;
                existing.Last_Reengaged_CP__c = cpId;
                existing.Last_Reengaged_Source__c = source;
                existing.Last_Reengaged_Sub__c = subSource;
                existing.Last_Reengaged_Date__c = Date.today();
                if (campaignId != null) {
                    existing.Last_Reengaged_Campaign__c = campaignId;
                }
                update existing;
                result.leadId = existing.Id;
                result.action = 'REENGAGED';
                result.message = creditMessage;
                return result;
            }

        } else {
            // ── S4: Inactive (Lost/Unqualified/Booked) → Re-open ──
            createEnquirySource(existing.Id, cfg.Lead_Reopened_Type__c, source, subSource, campaignId, cpId, leadData, cfg);
            existing.Lead_Type__c = cfg.Lead_Reopened_Type__c;
            existing.Lead_Status__c = cfg.Lead_Default_Status__c;
            existing.Last_Reopened_Date__c = Date.today();
            existing.Channel_Partner__c = cpId;
            existing.Lead_Source__c = cpSourceName;
            existing.Lead_Sub_Source__c = subSource;
            existing.Last_Reengaged_CP__c = cpId;
            existing.Owner__c = RoundRobinService.getNextUser(projectId, cfg.Assignment_Type__c);
            update existing;
            result.leadId = existing.Id;
            result.action = 'REOPENED';
            result.message = creditMessage;
            return result;
        }

        // Fallback (shouldn't reach here)
        result.leadId = existing.Id;
        result.action = 'REENGAGED';
        result.message = 'Lead registered.';
        return result;
    }

    // ════════════════════════════════════════════════════════════
    // NON-CP LEAD DUPLICATION
    // ════════════════════════════════════════════════════════════

    private static LeadResult handleNonCPDuplication(
        Lead__c existing, Boolean isActive,
        String source, String subSource, Id campaignId,
        Id projectId, Map<String, String> leadData,
        CP_Module_Config__c cfg
    ) {
        LeadResult result = new LeadResult();

        if (isActive) {
            createEnquirySource(existing.Id, cfg.Lead_Reengaged_Type__c, source, subSource, campaignId, null, leadData, cfg);
            existing.Lead_Type__c = cfg.Lead_Reengaged_Type__c;
            existing.Last_Reengaged_Source__c = source;
            existing.Last_Reengaged_Sub__c = subSource;
            existing.Last_Reengaged_Date__c = Date.today();
            if (campaignId != null) {
                existing.Last_Reengaged_Campaign__c = campaignId;
            }
            update existing;
            result.leadId = existing.Id;
            result.action = 'REENGAGED';
            result.message = 'Lead re-engaged. Current owner notified.';
        } else {
            createEnquirySource(existing.Id, cfg.Lead_Reopened_Type__c, source, subSource, campaignId, null, leadData, cfg);
            LeadReopenService.reopenLead(existing.Id, source, subSource);
            result.leadId = existing.Id;
            result.action = 'REOPENED';
            result.message = 'Lead re-opened and assigned to new executive.';
        }

        return result;
    }

    // ════════════════════════════════════════════════════════════
    // NEW LEAD CREATION
    // ════════════════════════════════════════════════════════════

    /**
     * @description Create a brand new lead (no match on same project).
     *              Uses IntegrationFieldMappingEngine (LEAD_CREATION) for field mapping + defaults.
     */
    private static LeadResult createNewLead(
        Map<String, String> leadData, Id projectId,
        String source, String subSource, Id campaignId,
        String cpId, Boolean isCPLead,
        CP_Module_Config__c cfg
    ) {
        LeadResult result = new LeadResult();

        // Map payload using engine — field rules + defaults from LEAD_CREATION config
        Map<String, Object> payload = new Map<String, Object>();
        for (String key : leadData.keySet()) {
            payload.put(key, leadData.get(key));
        }
        Lead__c newLead = (Lead__c) IntegrationFieldMappingEngine.mapPayload('LEAD_CREATION', payload);

        // System-managed fields (business logic decisions)
        newLead.Project__c = projectId;
        newLead.Lead_Source__c = source;
        newLead.Lead_Sub_Source__c = subSource;

        if (campaignId != null) {
            newLead.Campaign__c = campaignId;
        }
        if (isCPLead) {
            newLead.Channel_Partner__c = cpId;
            newLead.Lead_Source__c = cfg.CP_Source_Name__c;
        }

        // Round-robin assignment (assignment type from config)
        newLead.Owner__c = RoundRobinService.getNextUser(projectId, cfg.Assignment_Type__c);

        // Skip DuplicateConversionEngine in LeadTrigger - this service creates
        // its own Enquiry Source below (prevents double creation).
        try {
            DuplicateConversionEngine.skipProcessing = true;
            insert newLead;
        } finally {
            DuplicateConversionEngine.skipProcessing = false;
        }

        // Create enquiry source (with CP credit if applicable). Tracking
        // side-effect — swallow errors so a misconfigured enquiry source
        // mapping doesn't roll back the successful lead insert.
        try {
            createEnquirySource(newLead.Id, 'New', source, subSource, campaignId, cpId, leadData, cfg);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Enquiry source creation failed for lead '
                + newLead.Id + ': ' + e.getMessage());
        }

        result.leadId = newLead.Id;
        result.action = 'CREATED';
        if (isCPLead) {
            Integer creditDays = cfg.Credit_Expiry_Days__c.intValue();
            result.message = 'Lead registered successfully, you will have credit for '
                + creditDays + ' days (if the lead is not marked as Lost; after '
                + creditDays + ' days, you will not get the credit even if it is not marked as Lost), and you should bring the customer to the site.';
        } else {
            result.message = 'Lead created successfully.';
        }

        return result;
    }

    // ════════════════════════════════════════════════════════════
    // ENQUIRY SOURCE CREATION
    // ════════════════════════════════════════════════════════════

    /**
     * @description Create Enquiry_Source__c record to track every submission.
     *              Uses IntegrationFieldMappingEngine (ENQUIRY_SOURCE_CREATION) for field mapping.
     *              Credit days and statuses from CP_Module_Config__c.
     */
    private static void createEnquirySource(
        Id leadId, String enquiryType, String source, String subSource,
        Id campaignId, String cpId, Map<String, String> leadData,
        CP_Module_Config__c cfg
    ) {
        // Map payload using engine
        Map<String, Object> payload = new Map<String, Object>();
        for (String key : leadData.keySet()) {
            payload.put(key, leadData.get(key));
        }
        payload.put('enquiry_type', enquiryType);
        payload.put('source', source);
        payload.put('sub_source', subSource);
        Enquiry_Source__c es = (Enquiry_Source__c) IntegrationFieldMappingEngine.mapPayload('ENQUIRY_SOURCE_CREATION', payload);

        // System-managed fields
        es.Lead__c = leadId;
        es.Enquiry_Date__c = DateTime.now();

        if (campaignId != null) {
            es.Campaign__c = campaignId;
        }
        if (String.isNotBlank(cpId)) {
            try {
                es.Channel_Partner__c = cpId;
                es.CP_Credit_Expiry__c = Date.today().addDays(CPModuleConfigService.getCreditExpiryDays());
                es.Credit_Status__c = cfg.Credit_Active_Status__c;
            } catch (Exception e) { /* invalid ID format */ }
        }

        insert es;
    }
}