/**
 * Controller for leadDuplicateRedirector LWC.
 *
 * Uses ALL ROWS so the Duplicate_Of__c value can still be read even after
 * the record has been soft-deleted (recycle bin).
 */
public with sharing class LeadDuplicateController {

    @AuraEnabled
    public static Id getDuplicateOfId(Id recordId) {
        List<Lead__c> leads = [
            SELECT Duplicate_Of__c
            FROM Lead__c
            WHERE Id = :recordId
            ALL ROWS
        ];
        if (!leads.isEmpty()) {
            return leads[0].Duplicate_Of__c;
        }
        return null;
    }

    @AuraEnabled
    public static void deleteDuplicateLead(Id recordId) {
        List<Lead__c> leads = [
            SELECT Id FROM Lead__c
            WHERE Id = :recordId
            AND Duplicate_Of__c != null
        ];
        if (!leads.isEmpty()) {
            delete leads;
        }
    }
}