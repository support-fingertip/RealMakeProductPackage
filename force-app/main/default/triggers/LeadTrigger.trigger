/**
 * LEAD TRIGGER - Enterprise Duplicate Detection & Conversion (FINAL)
 * 
 * FINAL SCENARIOS:
 * 1. No duplicates → Create Lead + Create Enquiry (keep both)
 * 2. Lead duplicate → Create Lead + Enquiry + Delete NEW Lead (old Lead remains)
 * 3. Enquiry duplicate → Create Lead + Enquiry + Delete NEW Lead (no new Lead)
 * 4. Both duplicates → Create Lead + Enquiry + Delete NEW Lead (old Lead remains)
 */
trigger LeadTrigger on Lead__c (before insert, before update, after insert, after update, after delete, after undelete) {
    
    // ============================================================================
    // BEFORE INSERT/UPDATE: Validate against duplicates
    // Skip when DuplicateConversionEngine is updating Duplicate_Of__c to
    // prevent re-entry into duplicate detection logic.
    // ============================================================================
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        if (!DuplicateConversionEngine.skipProcessing) {
            String objectApiName = Trigger.new[0].getSObjectType().getDescribe().getName();
            GenericDuplicationTriggerHandler.handleBeforeInsertUpdate(Trigger.new, objectApiName);
        }
    }

    // ============================================================================
    // BEFORE INSERT/UPDATE: Resolve Campaign_Id_Text__c → Campaign__c
    // External systems pass Campaign auto-number text (e.g., CMP-00042) in
    // Campaign_Id_Text__c. This resolves it to the actual Campaign lookup.
    // ============================================================================
    if (Trigger.isBefore && Trigger.isInsert) {
        CampaignService.resolveCampaignForLeads(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        CampaignService.resolveCampaignForLeadUpdates(Trigger.new, Trigger.oldMap);
    }

    // ============================================================================
    // BEFORE INSERT/UPDATE: Dynamic Lead Scoring (sets Lead_Score__c + Tier)
    // ============================================================================
    if (Trigger.isBefore && (Trigger.isInsert || Trigger.isUpdate)) {
        LeadScoringEngine.calculateScores(Trigger.new);
    }

    // ============================================================================
    // BEFORE INSERT: Dynamic Round Robin Assignment (Phase 1 - sets OwnerId)
    // ============================================================================
    if (Trigger.isBefore && Trigger.isInsert){
        RoundRobinAssignmentHandler.assignOwners(Trigger.new);
    }
    
    // ============================================================================
    // AFTER INSERT: Create Enquiry and potentially delete the NEW Lead
    // ============================================================================
    if (Trigger.isAfter && Trigger.isInsert) {
        // Skip duplicate/conversion processing when GRE controller handles
        // its own Enquiry Source creation (prevents duplicate Enquiry Sources)
        if (!DuplicateConversionEngine.skipProcessing) {
            String objectApiName = Trigger.new[0].getSObjectType().getDescribe().getName();

            // Process conversion:
            // 1. Creates Enquiry Source from new Lead data
            // 2. Returns IDs of NEW Leads that should be deleted
            List<Id> newLeadsToDelete = DuplicateConversionEngine.processRecordWithConversion(
                Trigger.new,
                objectApiName
            );

            // Duplicate leads are NOT deleted here. The leadDuplicateRedirector
            // LWC on the record page reads Duplicate_Of__c, shows a toast,
            // deletes the record, and navigates to the existing lead.
            // A scheduled CleanupDuplicateLeadsBatch handles edge cases.
        }

        // Round Robin Assignment (Phase 2 - commit rotation tracking)
        RoundRobinAssignmentHandler.commitRotationUpdates();

        // Campaign rollup: recalculate Total_Leads__c + Site Visits/Qualified/Bookings
        Set<Id> campaignIds = new Set<Id>();
        for (Lead__c ld : Trigger.new) {
            if (ld.Campaign__c != null) {
                campaignIds.add(ld.Campaign__c);
            }
        }
        if (!campaignIds.isEmpty()) {
            CampaignService.recalculateTotalLeads(campaignIds);
            CampaignService.recalculateCampaignCounts(campaignIds);
        }

        // Log initial assignment to Reassignment_History__c
        LeadOwnerChangeHandler.logInitialAssignment(Trigger.new);
    }

    // ============================================================================
    // AFTER UPDATE: Log owner changes to Reassignment_History__c (enhanced)
    // ============================================================================
    if (Trigger.isAfter && Trigger.isUpdate) {
        LeadOwnerChangeHandler.handleOwnerChanges(Trigger.new, Trigger.oldMap);

        // Log terminal status changes (Booked / Unqualified / Closed Lost)
        LeadOwnerChangeHandler.logTerminalStatusChange(Trigger.new, Trigger.oldMap);

        // Share leads with Pre_Sale_User when ownership changes (Req 4)
        LeadOwnerChangeHandler.shareWithPreSaleUsers(Trigger.new, Trigger.oldMap);
    }

    // ============================================================================
    // AFTER UPDATE: Similar logic for updates
    // Skip when DuplicateConversionEngine is updating Lead_Type__c / Duplicate_Of__c
    // to prevent re-entry into duplicate detection logic.
    // ============================================================================
    if (Trigger.isAfter && Trigger.isUpdate && !DuplicateConversionEngine.skipProcessing) {
        String objectApiName = Trigger.new[0].getSObjectType().getDescribe().getName();

        // Only process if key fields changed
        List<Lead__c> changedRecords = new List<Lead__c>();
        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Lead__c newLead = Trigger.new[i];
            Lead__c oldLead = Trigger.old[i];

            if (newLead.Primary_Mobile__c != oldLead.Primary_Mobile__c ||
                newLead.Secondary_Mobile__c != oldLead.Secondary_Mobile__c ||
                newLead.Project__c != oldLead.Project__c) {
                changedRecords.add(newLead);
            }
        }

        if (!changedRecords.isEmpty()) {
            List<Id> newLeadsToDelete = DuplicateConversionEngine.processRecordWithConversion(
                changedRecords,
                objectApiName
            );

            // Duplicate leads are deleted by the leadDuplicateRedirector LWC
            // (or the scheduled CleanupDuplicateLeadsBatch as a safety net).
        }

        // Campaign rollup: recalculate when Campaign changes or Lead Status changes
        Set<Id> campaignIds = new Set<Id>();
        for (Integer i = 0; i < Trigger.new.size(); i++) {
            Lead__c newLead = Trigger.new[i];
            Lead__c oldLead = Trigger.old[i];
            if (newLead.Campaign__c != oldLead.Campaign__c) {
                if (newLead.Campaign__c != null) {
                    campaignIds.add(newLead.Campaign__c);
                }
                if (oldLead.Campaign__c != null) {
                    campaignIds.add(oldLead.Campaign__c);
                }
            }
            // Also recalc when Lead Status changes (affects Qualified count)
            if (newLead.Lead_Status__c != oldLead.Lead_Status__c && newLead.Campaign__c != null) {
                campaignIds.add(newLead.Campaign__c);
            }
        }
        if (!campaignIds.isEmpty()) {
            CampaignService.recalculateTotalLeads(campaignIds);
            CampaignService.recalculateCampaignCounts(campaignIds);
        }
    }

    // ============================================================================
    // AFTER DELETE: Recalculate Campaign statistics
    // ============================================================================
    if (Trigger.isAfter && Trigger.isDelete) {
        Set<Id> campaignIds = new Set<Id>();
        for (Lead__c ld : Trigger.old) {
            if (ld.Campaign__c != null) {
                campaignIds.add(ld.Campaign__c);
            }
        }
        if (!campaignIds.isEmpty()) {
            CampaignService.recalculateTotalLeads(campaignIds);
            CampaignService.recalculateCampaignCounts(campaignIds);
        }
    }

    // ============================================================================
    // AFTER UNDELETE: Recalculate Campaign statistics
    // ============================================================================
    if (Trigger.isAfter && Trigger.isUndelete) {
        Set<Id> campaignIds = new Set<Id>();
        for (Lead__c ld : Trigger.new) {
            if (ld.Campaign__c != null) {
                campaignIds.add(ld.Campaign__c);
            }
        }
        if (!campaignIds.isEmpty()) {
            CampaignService.recalculateTotalLeads(campaignIds);
            CampaignService.recalculateCampaignCounts(campaignIds);
        }
    }
}