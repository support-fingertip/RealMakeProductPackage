/**
 * @description Trigger handler that logs ownership changes on Lead__c
 * to Reassignment_History__c. Fires on after update when OwnerId changes.
 */
public with sharing class LeadOwnerChangeHandler {

    /**
     * @description Create Reassignment_History__c records for leads whose OwnerId changed.
     * Called from LeadTrigger (after update context).
     */
    public static void logOwnerChanges(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        List<Reassignment_History__c> histories = new List<Reassignment_History__c>();

        for (Lead__c newLead : newLeads) {
            Lead__c oldLead = oldMap.get(newLead.Id);
            if (oldLead == null) continue;

            // Detect OwnerId change
            if (newLead.OwnerId != oldLead.OwnerId) {
                Reassignment_History__c rh = new Reassignment_History__c();
                rh.Lead__c = newLead.Id;
                rh.Old_Owner__c = oldLead.OwnerId;
                rh.New_Owner__c = newLead.OwnerId;
                rh.Assigned_By__c = UserInfo.getUserId();
                rh.Reassigned_Date__c = System.now();
                rh.Reassignment_Type__c = 'Permanent';
                rh.Status__c = 'Active';
                histories.add(rh);
            }
        }

        if (!histories.isEmpty()) {
            insert histories;
        }
    }

    // =========================================================================
    // Terminal statuses that close out ownership tracking
    // =========================================================================
    private static final Set<String> TERMINAL_STATUSES = new Set<String>{
        'Booked', 'Unqualified', 'Closed Lost'
    };

    /**
     * @description Create initial Reassignment_History__c records when leads are first created.
     * Called from LeadTrigger (after insert context).
     */
    public static void logInitialAssignment(List<Lead__c> newLeads) {
        List<Reassignment_History__c> histories = new List<Reassignment_History__c>();

        for (Lead__c newLead : newLeads) {
            Reassignment_History__c rh = new Reassignment_History__c();
            rh.Lead__c = newLead.Id;
            rh.New_Owner__c = newLead.OwnerId;
            rh.Assigned_By__c = UserInfo.getUserId();
            rh.Reassigned_Date__c = System.now();
            rh.Ownership_Start_Date__c = System.now();
            rh.Reassignment_Type__c = 'Initial Assignment';
            rh.Status__c = 'Active';
            rh.Entry_Status__c = newLead.Lead_Status__c;
            histories.add(rh);
        }

        if (!histories.isEmpty()) {
            insert histories;
        }
    }

    /**
     * @description Enhanced owner change handler that closes previous active history
     * and creates new history with full ownership tracking fields.
     * Replaces the trigger call to logOwnerChanges (which remains untouched).
     * Called from LeadTrigger (after update context).
     */
    public static void handleOwnerChanges(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        Set<Id> changedLeadIds = new Set<Id>();

        for (Lead__c newLead : newLeads) {
            Lead__c oldLead = oldMap.get(newLead.Id);
            if (oldLead != null && newLead.OwnerId != oldLead.OwnerId) {
                changedLeadIds.add(newLead.Id);
            }
        }

        if (changedLeadIds.isEmpty()) {
            return;
        }

        // Build map of lead ID → old Lead_Status__c for exit status
        Map<Id, String> leadToOldStatus = new Map<Id, String>();
        for (Id leadId : changedLeadIds) {
            Lead__c oldLead = oldMap.get(leadId);
            if (oldLead != null) {
                leadToOldStatus.put(leadId, oldLead.Lead_Status__c);
            }
        }

        // Close previous active histories
        Map<Id, Id> leadToPreviousHistoryId = new Map<Id, Id>();
        List<Reassignment_History__c> toClose = new List<Reassignment_History__c>();

        for (Reassignment_History__c rh : [
            SELECT Id, Lead__c
            FROM Reassignment_History__c
            WHERE Lead__c IN :changedLeadIds AND Status__c = 'Active'
        ]) {
            rh.Ownership_End_Date__c = System.now();
            rh.Status__c = 'Completed';
            rh.Exit_Status__c = leadToOldStatus.get(rh.Lead__c);
            toClose.add(rh);
            leadToPreviousHistoryId.put(rh.Lead__c, rh.Id);
        }

        if (!toClose.isEmpty()) {
            update toClose;
        }

        // Create new history records with full tracking fields
        List<Reassignment_History__c> histories = new List<Reassignment_History__c>();

        for (Lead__c newLead : newLeads) {
            Lead__c oldLead = oldMap.get(newLead.Id);
            if (oldLead == null || newLead.OwnerId == oldLead.OwnerId) {
                continue;
            }

            Reassignment_History__c rh = new Reassignment_History__c();
            rh.Lead__c = newLead.Id;
            rh.Old_Owner__c = oldLead.OwnerId;
            rh.New_Owner__c = newLead.OwnerId;
            rh.Assigned_By__c = UserInfo.getUserId();
            rh.Reassigned_Date__c = System.now();
            rh.Ownership_Start_Date__c = System.now();
            rh.Reassignment_Type__c = 'Permanent';
            rh.Entry_Status__c = newLead.Lead_Status__c;

            if (leadToPreviousHistoryId.containsKey(newLead.Id)) {
                rh.Previous_History__c = leadToPreviousHistoryId.get(newLead.Id);
            }

            // If the lead also reached a terminal status in the same update,
            // mark this record as completed immediately (0-duration ownership)
            if (TERMINAL_STATUSES.contains(newLead.Lead_Status__c)
                && newLead.Lead_Status__c != oldLead.Lead_Status__c) {
                rh.Status__c = 'Completed';
                rh.Ownership_End_Date__c = System.now();
                rh.Exit_Status__c = newLead.Lead_Status__c;
            } else {
                rh.Status__c = 'Active';
            }

            histories.add(rh);
        }

        if (!histories.isEmpty()) {
            insert histories;
        }
    }

    /**
     * @description Share leads with their Pre_Sale_User__c when ownership changes.
     * Ensures the pre-sale user retains Read access to the lead after reassignment.
     * Called from LeadTrigger (after update context).
     */
    public static void shareWithPreSaleUsers(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        Set<Id> changedLeadIds = new Set<Id>();

        for (Lead__c newLead : newLeads) {
            Lead__c oldLead = oldMap.get(newLead.Id);
            if (oldLead != null && newLead.OwnerId != oldLead.OwnerId) {
                changedLeadIds.add(newLead.Id);
            }
        }

        if (changedLeadIds.isEmpty()) return;

        // Query Pre_Sale_User__c (not available in trigger context without explicit query)
        Map<Id, Id> leadToPreSaleUser = new Map<Id, Id>();
        for (Lead__c l : [SELECT Id, Pre_Sale_User__c FROM Lead__c
                          WHERE Id IN :changedLeadIds AND Pre_Sale_User__c != null]) {
            leadToPreSaleUser.put(l.Id, l.Pre_Sale_User__c);
        }
        if (leadToPreSaleUser.isEmpty()) return;

        // Group leads by Pre_Sale_User for bulk sharing
        Map<Id, List<Id>> userToLeadIds = new Map<Id, List<Id>>();
        for (Lead__c nl : newLeads) {
            if (!leadToPreSaleUser.containsKey(nl.Id)) continue;
            Id preSaleUserId = leadToPreSaleUser.get(nl.Id);
            // Skip if new owner IS the pre-sale user (already has access)
            if (nl.OwnerId == preSaleUserId) continue;

            if (!userToLeadIds.containsKey(preSaleUserId)) {
                userToLeadIds.put(preSaleUserId, new List<Id>());
            }
            userToLeadIds.get(preSaleUserId).add(nl.Id);
        }

        // Bulk share
        for (Id userId : userToLeadIds.keySet()) {
            SharingUtility.shareLeadsWithUser(userToLeadIds.get(userId), userId, 'Read');
        }
    }

    /**
     * @description Log terminal status changes (Booked, Unqualified, Closed Lost).
     * Updates the existing active ownership history record with exit details
     * instead of creating a separate Status Change record.
     * Skips leads where OwnerId also changed (handled by handleOwnerChanges).
     * Called from LeadTrigger (after update context).
     */
    public static void logTerminalStatusChange(List<Lead__c> newLeads, Map<Id, Lead__c> oldMap) {
        Set<Id> terminalLeadIds = new Set<Id>();

        for (Lead__c newLead : newLeads) {
            Lead__c oldLead = oldMap.get(newLead.Id);
            if (oldLead == null) continue;

            // Only process if status changed to terminal AND owner did NOT change
            if (TERMINAL_STATUSES.contains(newLead.Lead_Status__c)
                && newLead.Lead_Status__c != oldLead.Lead_Status__c
                && newLead.OwnerId == oldLead.OwnerId) {
                terminalLeadIds.add(newLead.Id);
            }
        }

        if (terminalLeadIds.isEmpty()) {
            return;
        }

        // Build a map of lead Id to terminal status for setting Exit_Status__c
        Map<Id, String> leadToTerminalStatus = new Map<Id, String>();
        for (Lead__c newLead : newLeads) {
            if (terminalLeadIds.contains(newLead.Id)) {
                leadToTerminalStatus.put(newLead.Id, newLead.Lead_Status__c);
            }
        }

        // Update existing active records with exit details
        List<Reassignment_History__c> toUpdate = new List<Reassignment_History__c>();

        for (Reassignment_History__c rh : [
            SELECT Id, Lead__c
            FROM Reassignment_History__c
            WHERE Lead__c IN :terminalLeadIds AND Status__c = 'Active'
        ]) {
            rh.Ownership_End_Date__c = System.now();
            rh.Status__c = 'Completed';
            rh.Exit_Status__c = leadToTerminalStatus.get(rh.Lead__c);
            toUpdate.add(rh);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

}