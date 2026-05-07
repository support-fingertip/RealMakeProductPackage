/**
 * @description Unified service for reopening inactive leads.
 * Consolidates reopen logic previously scattered across DuplicateConversionEngine,
 * LeadDeduplicationService, and PreSalesService into a single source of truth.
 *
 * Callers:
 *   - DuplicateConversionEngine.applyReengageReopenLogic() (trigger path)
 *   - LeadDeduplicationService.handleNonCPDuplication()     (API path)
 *   - PreSalesService.processGREWalkin()                    (GRE walk-in)
 *   - LeadReopenController                                  (manual quick action)
 */
public with sharing class LeadReopenService {

    /**
     * @description Reopen an inactive lead using standard config-driven defaults.
     * @param leadId      The inactive lead to reopen
     * @param source      Primary source for the new Enquiry_Source__c
     * @param subSource   Primary sub-source for the new Enquiry_Source__c
     * @return ReopenResult with updated lead info
     */
    public static ReopenResult reopenLead(Id leadId, String source, String subSource) {
        return reopenLead(leadId, source, subSource, null, null);
    }

    /**
     * @description Reopen an inactive lead with optional owner and status overrides.
     * Used by GRE walk-in flow where salesExecId pre-assigns ownership
     * and status is set to 'Site Visit Scheduled' instead of config default.
     *
     * @param leadId          The inactive lead to reopen
     * @param source          Primary source for the new Enquiry_Source__c
     * @param subSource       Primary sub-source for the new Enquiry_Source__c
     * @param overrideOwnerId If provided, skip RR and assign to this user
     * @param overrideStatus  If provided, use this status instead of config default
     * @return ReopenResult with updated lead info
     */
    public static ReopenResult reopenLead(
        Id leadId, String source, String subSource,
        Id overrideOwnerId, String overrideStatus
    ) {
system.debug('==========================================');
        if (leadId == null) {
            throw new LeadReopenException('Lead ID is required.');
        }

        Lead__c lead = [
            SELECT Id, Lead_Status__c, Lead_Type__c,Secondary_Mobile__c,Primary_Mobile__c, Is_Active__c, Project__c,
                   Owner__c, First_Name__c, Last_Name__c
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        // Validate lead is inactive
        if (lead.Is_Active__c == true) {
            throw new LeadReopenException('Lead is already active. Only inactive leads can be reopened.');
        }

        // Load config
        CP_Module_Config__c cfg = CPModuleConfigService.getConfig();

        String newType = cfg.Lead_Reopened_Type__c != null ? cfg.Lead_Reopened_Type__c : 'Re-opened';
        String newStatus = (overrideStatus != null) ? overrideStatus
            : (cfg.Lead_Default_Status__c != null ? cfg.Lead_Default_Status__c : 'New Enquiry');
        String assignmentType = cfg.Assignment_Type__c;
        system.debug('newType' + newType);
             system.debug('newStatus' + newStatus);

        // Determine new owner
        Id newOwnerId;
        if (overrideOwnerId != null) {
            newOwnerId = overrideOwnerId;
        } else if (String.isNotBlank(assignmentType)) {
            try {
                newOwnerId = RoundRobinService.getNextUser(lead.Project__c, assignmentType);
            } catch (Exception rrEx) {
                System.debug(LoggingLevel.WARN, 'Round Robin assignment failed during reopen, keeping current owner: ' + rrEx.getMessage());
            }
        }

        // Update lead
        lead.Lead_Type__c = newType;
        lead.Lead_Status__c = newStatus;
        lead.Last_Reopened_Date__c = Date.today();
        if (newOwnerId != null) {
            lead.Owner__c = newOwnerId;
        }
        update lead;

        // Create Enquiry Source
        Enquiry_Source__c es = new Enquiry_Source__c();
        es.Lead__c = leadId;
        es.Enquiry_Date__c = DateTime.now();
        es.Enquiry_Type__c = 'Re-opened';
        //es.Primary_Email__c = lead.Primary_Mobile__c;
        es.Secondary_Mobile__c = lead.Secondary_Mobile__c;
		 es.Primary_Mobile__c = lead.Primary_Mobile__c;
         es.Project__c = lead.Project__c;
        if (String.isNotBlank(source)) {
            es.Source__c = source;
        }
        if (String.isNotBlank(subSource)) {
            es.Sub_Source__c = subSource;
        }
        insert es;

        // Build result
        ReopenResult result = new ReopenResult();
        result.leadId = leadId;
        result.newStatus = newStatus;
        result.newOwnerId = (newOwnerId != null) ? newOwnerId : lead.Owner__c;
        result.message = 'Lead re-opened successfully. Status: ' + newStatus;
        return result;
    }

    // ════════════════════════════════════════════════════════════
    // RESULT DTO
    // ════════════════════════════════════════════════════════════

    public class ReopenResult {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String newStatus;
        @AuraEnabled public Id newOwnerId;
        @AuraEnabled public String message;
    }

    public class LeadReopenException extends Exception {}
}