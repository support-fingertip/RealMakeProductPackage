public with sharing class LeadStatusUpdateController {

    // ═══════════════════════════════════════════════════════════════
    //  STATIC CACHE — CMT records loaded once per transaction
    // ═══════════════════════════════════════════════════════════════
    private static List<Lead_Status_Action_Config__mdt> cachedConfigs;

    private static List<Lead_Status_Action_Config__mdt> getActiveConfigs() {
        if (cachedConfigs != null) return cachedConfigs;
        cachedConfigs = [
            SELECT DeveloperName, Status_Value__c, Requires_FollowUp__c,
                   Requires_SiteVisit__c, Requires_Lost_Reason__c, Requires_Remarks__c,
                   Disable_FollowUp__c, FollowUp_Mandatory__c, SiteVisit_Mandatory__c,
                   FollowUp_Default_Subject__c, SiteVisit_Default_Status__c,
                   Section_Label__c, Sort_Order__c, Is_Active__c
            FROM Lead_Status_Action_Config__mdt
            WHERE Is_Active__c = true
            ORDER BY Sort_Order__c ASC
        ];
        return cachedConfigs;
    }

    private static Lead_Status_Action_Config__mdt getConfigForStatus(String statusValue) {
        for (Lead_Status_Action_Config__mdt cfg : getActiveConfigs()) {
            if (cfg.Status_Value__c == statusValue) return cfg;
        }
        return null;
    }

    // ═══════════════════════════════════════════════════════════════
    //  INIT DATA — Called when quick action opens
    // ═══════════════════════════════════════════════════════════════
    @AuraEnabled
    public static InitDataWrapper getInitData(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead ID is required.');
        }

        Lead__c lead = [
            SELECT Id, Name, Lead_Status__c, Lost_Reason__c, Remarks__c,
                   RecordTypeId, RecordType.DeveloperName, Project__c
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        List<StatusConfigWrapper> configs = new List<StatusConfigWrapper>();
        for (Lead_Status_Action_Config__mdt cfg : getActiveConfigs()) {
            configs.add(new StatusConfigWrapper(cfg));
        }

        InitDataWrapper result = new InitDataWrapper();
        result.leadId = lead.Id;
        result.leadName = lead.Name;
        result.currentStatus = lead.Lead_Status__c;
        result.lostReason = lead.Lost_Reason__c;
        result.remarks = lead.Remarks__c;
        result.recordTypeId = lead.RecordTypeId;
        result.recordTypeDeveloperName = lead.RecordType.DeveloperName;
        result.leadProjectId = lead.Project__c;
        result.crossProjectAllowed = ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed(); 
        result.statusConfigs = configs;
        return result;
    }

    // ═══════════════════════════════════════════════════════════════
    //  SUBMIT — Atomic update of Lead + optional child records
    // ═══════════════════════════════════════════════════════════════
    @AuraEnabled
    public static SubmitResultWrapper submitLeadStatusUpdate(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Payload is required.');
        }

        SubmitPayload payload = (SubmitPayload) JSON.deserialize(payloadJson, SubmitPayload.class);

        // Re-read config server-side (never trust client)
        Lead_Status_Action_Config__mdt config = getConfigForStatus(payload.newStatus);

        // ── Validate required fields based on config ──
        if (config != null) {
            if (config.Requires_Lost_Reason__c && String.isBlank(payload.lostReason)) {
                throw new AuraHandledException('Lost Reason is required for this status.');
            }
            if (config.Requires_Remarks__c && String.isBlank(payload.remarks)) {
                throw new AuraHandledException('Remarks are required for this status.');
            }

            // Follow-up validations
            if (config.Requires_FollowUp__c && config.FollowUp_Mandatory__c) {
                if (payload.followUp == null) {
                    throw new AuraHandledException('Follow-up details are required for this status.');
                }
                if (String.isBlank(payload.followUp.subject)) {
                    throw new AuraHandledException('Follow-up Subject is required.');
                }
                if (String.isBlank(payload.followUp.notes)) {
                    throw new AuraHandledException('Follow-up Notes are required.');
                }
                if (String.isBlank(payload.followUp.dueDate)) {
                    throw new AuraHandledException('Follow-up Due Date is required.');
                }
                DateTime dueDateTime = parseDateTime(payload.followUp.dueDate);
                if (dueDateTime < DateTime.now().addSeconds(1)) {
                    throw new AuraHandledException('Follow-up Due Date must be in the future.');
                }
            }

            // Site Visit validations
            if (config.Requires_SiteVisit__c && config.SiteVisit_Mandatory__c) {
                if (payload.siteVisit == null) {
                    throw new AuraHandledException('Site Visit details are required for this status.');
                }
                if (String.isBlank(payload.siteVisit.projectId)) {
                    throw new AuraHandledException('Site Visit Project is required.');
                }
                if (String.isBlank(payload.siteVisit.scheduledDate)) {
                    throw new AuraHandledException('Site Visit Scheduled Date is required.');
                }
                DateTime svDateTime = parseDateTime(payload.siteVisit.scheduledDate);
                if (svDateTime <= DateTime.now().addSeconds(1))  {
                    throw new AuraHandledException('Site Visit Scheduled Date must be in the future.');
                }
            }
        }

        // ── Duplicate checks ──
        Boolean createFollowUp = false;
        Boolean createSiteVisit = false;

        if (config != null && config.Requires_FollowUp__c && payload.followUp != null
                && !String.isBlank(payload.followUp.dueDate) && !String.isBlank(payload.followUp.subject)) {
            createFollowUp = true;
        }

        if (config != null && config.Requires_SiteVisit__c && payload.siteVisit != null
                && !String.isBlank(payload.siteVisit.scheduledDate) && !String.isBlank(payload.siteVisit.projectId)) {
            createSiteVisit = true;
        }

        // Also allow optional follow-up when not disabled and user filled in data
        if (config != null && !config.Disable_FollowUp__c && !config.Requires_FollowUp__c
                && payload.followUp != null && !String.isBlank(payload.followUp.dueDate)
                && !String.isBlank(payload.followUp.subject)) {
            createFollowUp = true;
        }

        if (createFollowUp) {
            List<Followup__c> existingFU = [
                SELECT Id FROM Followup__c
                WHERE Lead__c = :payload.leadId
                  AND Assigned_To__c = :UserInfo.getUserId()
                  AND Status__c = 'Pending'
                LIMIT 1
            ];
            if (!existingFU.isEmpty()) {
                throw new AuraHandledException(
                    'You already have a pending follow-up for this lead. Please complete or cancel it before creating a new one.'
                );
            }

            // Validate future date for optional follow-ups too
            DateTime dueDateTime = parseDateTime(payload.followUp.dueDate);
            if (dueDateTime < DateTime.now().addMinutes(-2)) {
                throw new AuraHandledException('Follow-up Due Date must be in the future.');
            }
        }
        
          if (createSiteVisit) {
            // Gate cross-project SV scheduling on the active General Setup
            if (!ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed()) {
                Lead__c leadForGate = [SELECT Id, Project__c FROM Lead__c WHERE Id = :payload.leadId LIMIT 1];
                if (leadForGate.Project__c != payload.siteVisit.projectId) {
                    throw new AuraHandledException(
                        'Cross-project site visits are not allowed by the current General Setup. ' +
                        'Please contact your administrator.'
                    );
                }
            }

            List<Site_Visit__c> existingSV = [
                SELECT Id FROM Site_Visit__c
                WHERE Lead__c = :payload.leadId
                  AND Project__c = :payload.siteVisit.projectId
                  AND Status__c = 'Scheduled'
                LIMIT 1
            ];

       /* if (createSiteVisit) {
            List<Site_Visit__c> existingSV = [
                SELECT Id FROM Site_Visit__c
                WHERE Lead__c = :payload.leadId
                  AND Project__c = :payload.siteVisit.projectId
                  AND Status__c = 'Scheduled'
                LIMIT 1
            ];*/
            if (!existingSV.isEmpty()) {
                throw new AuraHandledException(
                    'A site visit is already scheduled for this lead and project. Please cancel or complete it first.'
                );
            }

            DateTime svDateTime = parseDateTime(payload.siteVisit.scheduledDate);
            if (svDateTime < DateTime.now().addMinutes(-2)) {
                throw new AuraHandledException('Site Visit Scheduled Date must be in the future.');
            }
        }

        // ── Atomic DML ──
        Savepoint sp = Database.setSavepoint();
        try {
            // 1. Update Lead
            Lead__c lead = new Lead__c(Id = payload.leadId);
            lead.Lead_Status__c = payload.newStatus;

            if (config != null && config.Requires_Lost_Reason__c) {
                lead.Lost_Reason__c = payload.lostReason;
            }
            if (config != null && config.Requires_Remarks__c) {
                lead.Remarks__c = payload.remarks;
            }

            update lead;

            SubmitResultWrapper result = new SubmitResultWrapper();
            result.success = true;
            result.leadId = lead.Id;

            // 2. Insert Site Visit (before follow-up, in case follow-up needs to reference it)
            if (createSiteVisit) {
                String defaultSvStatus = (config != null && !String.isBlank(config.SiteVisit_Default_Status__c))
                    ? config.SiteVisit_Default_Status__c
                    : 'Scheduled';

                Site_Visit__c sv = new Site_Visit__c();
                sv.Lead__c = payload.leadId;
                sv.Project__c = payload.siteVisit.projectId;
                sv.Scheduled_Date__c = parseDateTime(payload.siteVisit.scheduledDate);
                sv.Status__c = defaultSvStatus;
                String modeVal = !String.isBlank(payload.siteVisit.visitType)
                    ? payload.siteVisit.visitType : 'On Site';
                sv.Mode_Of_Visit__c = modeVal;
                sv.Source_Type__c = 'Digital (Own)';
                sv.Need_Pick_Up_Assistance__c = payload.siteVisit.needPickUp == true;
                if (!String.isBlank(payload.siteVisit.feedback)) {
                    sv.FeedBack__c = payload.siteVisit.feedback;
                }
                insert sv;
                result.siteVisitId = sv.Id;
            }

            // 3. Insert Follow-up
            if (createFollowUp) {
                Followup__c fu = new Followup__c();
                fu.Lead__c = payload.leadId;
                fu.Subject__c = payload.followUp.subject;
                fu.Due_Date__c = parseDateTime(payload.followUp.dueDate);
                fu.Status__c = 'Pending';
                fu.Assigned_To__c = UserInfo.getUserId();
                if (!String.isBlank(payload.followUp.notes)) {
                    fu.Notes__c = payload.followUp.notes;
                }
                insert fu;
                result.followUpId = fu.Id;
            }

            // 4. Handle "Looking for other Project" flow
            if (payload.newStatus == 'Unqualified'
                && payload.lostReason == 'Looking for other Project'
                && String.isNotBlank(payload.targetProjectId)) {

                // Query existing lead for key fields to copy
                Lead__c existingLead = [
                    SELECT Primary_Mobile__c, Secondary_Mobile__c, First_Name__c,
                           Last_Name__c, Primary_Email__c, Lead_Source__c,
                           Lead_Sub_Source__c
                    FROM Lead__c WHERE Id = :payload.leadId
                ];

                // Create new lead for target project
                // Goes through normal trigger chain: RR assignment, dedup
                Lead__c newLead = new Lead__c();
                newLead.Primary_Mobile__c = existingLead.Primary_Mobile__c;
                newLead.Secondary_Mobile__c = existingLead.Secondary_Mobile__c;
                newLead.First_Name__c = existingLead.First_Name__c;
                newLead.Last_Name__c = existingLead.Last_Name__c;
                newLead.Primary_Email__c = existingLead.Primary_Email__c;
                newLead.Lead_Source__c = existingLead.Lead_Source__c;
                newLead.Lead_Sub_Source__c = existingLead.Lead_Sub_Source__c;
                newLead.Project__c = payload.targetProjectId;
                newLead.Lead_Type__c = 'Fresh';
                newLead.Transferred_By__c = UserInfo.getUserId();
                insert newLead;
                result.newLeadId = newLead.Id;
            }

            // Build success message
            List<String> parts = new List<String>{ 'Lead status updated' };
            if (result.siteVisitId != null) parts.add('Site Visit scheduled');
            if (result.followUpId != null) parts.add('Follow-up created');
            if (result.newLeadId != null) parts.add('New lead created for target project');
            result.message = String.join(parts, ', ') + '.';

            return result;
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        } catch (Exception e) {
            Database.rollback(sp);
            String msg = e.getMessage();
            // Extract clean message from PushToSalesException wrapped in DML/trigger chain
            if (msg != null && msg.contains('PushToSalesException:')) {
                String cleanMsg = msg.substringAfter('PushToSalesException:').substringBefore('Class.').trim();
                throw new AuraHandledException(cleanMsg);
            }
            throw new AuraHandledException('An error occurred: ' + msg);
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  PRIVATE HELPERS
    // ═══════════════════════════════════════════════════════════════

    /**
     * @description Parses datetime strings from LWC. Handles both ISO 8601 format
     *              (e.g., "2026-03-30T10:00:00.000Z") and legacy format ("2026-03-30T15:30").
     *              ISO format is timezone-aware; legacy format is interpreted as GMT.
     */
    private static DateTime parseDateTime(String dtStr) {
        if (String.isBlank(dtStr)) return null;
        if (dtStr.contains('.') || dtStr.endsWith('Z')) {
            return (DateTime) JSON.deserialize('"' + dtStr + '"', DateTime.class);
        }
        return DateTime.valueOf(dtStr.replace('T', ' '));
    }

    // ═══════════════════════════════════════════════════════════════
    //  INNER CLASSES — DTOs
    // ═══════════════════════════════════════════════════════════════

    public class InitDataWrapper {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String currentStatus;
        @AuraEnabled public String lostReason;
        @AuraEnabled public String remarks;
        @AuraEnabled public Id recordTypeId;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public Id leadProjectId;
        @AuraEnabled public Boolean crossProjectAllowed; 
        @AuraEnabled public List<StatusConfigWrapper> statusConfigs;
    }

    public class StatusConfigWrapper {
        @AuraEnabled public String developerName;
        @AuraEnabled public String statusValue;
        @AuraEnabled public Boolean requiresFollowUp;
        @AuraEnabled public Boolean requiresSiteVisit;
        @AuraEnabled public Boolean requiresLostReason;
        @AuraEnabled public Boolean requiresRemarks;
        @AuraEnabled public Boolean disableFollowUp;
        @AuraEnabled public Boolean followUpMandatory;
        @AuraEnabled public Boolean siteVisitMandatory;
        @AuraEnabled public String followUpDefaultSubject;
        @AuraEnabled public String siteVisitDefaultStatus;
        @AuraEnabled public String sectionLabel;
        @AuraEnabled public Decimal sortOrder;

        public StatusConfigWrapper(Lead_Status_Action_Config__mdt cfg) {
            this.developerName = cfg.DeveloperName;
            this.statusValue = cfg.Status_Value__c;
            this.requiresFollowUp = cfg.Requires_FollowUp__c;
            this.requiresSiteVisit = cfg.Requires_SiteVisit__c;
            this.requiresLostReason = cfg.Requires_Lost_Reason__c;
            this.requiresRemarks = cfg.Requires_Remarks__c;
            this.disableFollowUp = cfg.Disable_FollowUp__c;
            this.followUpMandatory = cfg.FollowUp_Mandatory__c;
            this.siteVisitMandatory = cfg.SiteVisit_Mandatory__c;
            this.followUpDefaultSubject = cfg.FollowUp_Default_Subject__c;
            this.siteVisitDefaultStatus = cfg.SiteVisit_Default_Status__c;
            this.sectionLabel = cfg.Section_Label__c;
            this.sortOrder = cfg.Sort_Order__c;
        }
    }

    public class SubmitResultWrapper {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id leadId;
        @AuraEnabled public Id followUpId;
        @AuraEnabled public Id siteVisitId;
        @AuraEnabled public Id newLeadId;
    }

    public class SubmitPayload {
        public Id leadId;
        public String newStatus;
        public String lostReason;
        public String remarks;
        public String targetProjectId;
        public FollowUpPayload followUp;
        public SiteVisitPayload siteVisit;
    }

    public class FollowUpPayload {
        public String dueDate;
        public String subject;
        public String notes;
    }

    public class SiteVisitPayload {
        public String scheduledDate;
        public String projectId;
        public String feedback;
        public String visitType;
        public Boolean needPickUp;
    }
}