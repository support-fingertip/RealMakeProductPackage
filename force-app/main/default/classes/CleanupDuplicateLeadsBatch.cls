/**
 * Safety-net batch job that deletes Lead__c records where Duplicate_Of__c is
 * populated. These are duplicate leads that should have been deleted by the
 * leadDuplicateRedirector LWC but were missed (e.g. user closed browser,
 * LWC not on page, API-created leads).
 *
 * Schedule hourly:
 *   System.schedule('Cleanup Duplicate Leads', '0 0 * * * ?', new CleanupDuplicateLeadsBatch());
 */
public class CleanupDuplicateLeadsBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Lead__c
            WHERE Duplicate_Of__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Lead__c> scope) {
        delete scope;
    }

    public void finish(Database.BatchableContext bc) {
        // No post-processing needed
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(this, 200);
    }
}