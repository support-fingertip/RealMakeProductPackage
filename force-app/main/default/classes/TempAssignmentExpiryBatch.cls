/**
 * @description Scheduled batch to remove expired temporary lead assignments.
 * Runs daily at 6 AM. Clears temp owner fields, removes manual sharing
 * (Lead + Site Visit), and logs to Reassignment_History__c.
 */
global class TempAssignmentExpiryBatch implements Database.Batchable<sObject>, Schedulable {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Temp_Owner__c, Temp_Expiry__c, Temp_Start__c, Owner__c
            FROM Lead__c
            WHERE Temp_Owner__c != null
            AND Temp_Expiry__c <= TODAY
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Lead__c> scope) {
        Map<Id, Id> leadToTempOwner = new Map<Id, Id>();
        Set<Id> scopeLeadIds = new Set<Id>();

        for (Lead__c l : scope) {
            scopeLeadIds.add(l.Id);
            leadToTempOwner.put(l.Id, l.Temp_Owner__c);

            l.Temp_Owner__c = null;
            l.Temp_Start__c = null;
            l.Temp_Expiry__c = null;
        }

        update scope;

        // Remove manual sharing for expired temp owners (Lead + Site Visit)
        if (!leadToTempOwner.isEmpty()) {
            try {
                SharingUtility.removeLeadShares(leadToTempOwner);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Lead sharing removal skipped: ' + e.getMessage());
            }
            try {
                SharingUtility.removeSiteVisitSharesForLeads(leadToTempOwner);
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Site Visit sharing removal skipped: ' + e.getMessage());
            }
        }

        // Update existing Active Temporary history records in place
        List<Reassignment_History__c> historiesToUpdate = new List<Reassignment_History__c>();
        for (Reassignment_History__c rh : [
            SELECT Id, Lead__c
            FROM Reassignment_History__c
            WHERE Lead__c IN :scopeLeadIds
            AND Reassignment_Type__c = 'Temporary' AND Status__c = 'Active'
        ]) {
            rh.Status__c = 'Expired';
            rh.Ownership_End_Date__c = System.now();
            rh.Exit_Status__c = 'Expired';
            historiesToUpdate.add(rh);
        }
        if (!historiesToUpdate.isEmpty()) {
            update historiesToUpdate;
        }
    }

    global void finish(Database.BatchableContext bc) {}

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new TempAssignmentExpiryBatch(), 200);
    }
}