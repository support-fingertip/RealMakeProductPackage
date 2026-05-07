/**
 * @description Scheduled batch job to unblock expired units.
 * Runs daily at 6 AM. Rule: UNIT_R04
 */
global class UnitBlockExpiryBatch implements Database.Batchable<sObject>, Schedulable {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Unit_Number__c, Blocked_By_Lead__c, Block_Expiry__c,
                   Blocked_By_Lead__r.Owner__c
            FROM Unit__c
            WHERE Status__c = 'Blocked'
            AND Block_Expiry__c <= TODAY
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Unit__c> scope) {
        for (Unit__c u : scope) {
            u.Status__c = 'Available';
            u.Blocked_By_Lead__c = null;
            u.Block_Expiry__c = null;
        }
        update scope;
    }

    global void finish(Database.BatchableContext bc) {
        // Could send summary notification to admin
    }

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new UnitBlockExpiryBatch(), 200);
    }
}