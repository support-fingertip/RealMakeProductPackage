/**
 * @description Scheduled batch to flag expired CP credits.
 * Credit period and status values are configurable via CP_Module_Config__c.
 * Runs daily at midnight.
 *
 * Logic:
 *   - Queries Enquiry_Source__c records where CP credit has expired
 *   - Updates Credit_Status__c to the configured expired status
 *   - Removes Channel_Partner__c from the lead if the expired credit was the only active one
 *
 * Schedule: System.schedule('CP Credit Expiry Daily', '0 0 0 * * ?', new CPCreditExpiryBatch());
 */
global class CPCreditExpiryBatch implements Database.Batchable<sObject>, Schedulable {

    private String activeStatus;
    private String expiredStatus;

    global CPCreditExpiryBatch() {
        CP_Module_Config__c cfg = CPModuleConfigService.getConfig();
        this.activeStatus = cfg.Credit_Active_Status__c;
        this.expiredStatus = cfg.Credit_Expired_Status__c;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, CP_Credit_Expiry__c, Channel_Partner__c, Lead__c, Credit_Status__c '
            + 'FROM Enquiry_Source__c '
            + 'WHERE Channel_Partner__c != null '
            + 'AND CP_Credit_Expiry__c <= TODAY '
            + 'AND CP_Credit_Expiry__c != null '
            + 'AND (Credit_Status__c = null OR Credit_Status__c = :activeStatus)'
        );
    }

    global void execute(Database.BatchableContext bc, List<Enquiry_Source__c> scope) {
        // 1. Mark all expired credits
        for (Enquiry_Source__c es : scope) {
            es.Credit_Status__c = this.expiredStatus;
        }
        update scope;

        // 2. Collect lead IDs to check if they still have active CP credits
        Set<Id> affectedLeadIds = new Set<Id>();
        for (Enquiry_Source__c es : scope) {
            if (es.Lead__c != null) {
                affectedLeadIds.add(es.Lead__c);
            }
        }

        if (affectedLeadIds.isEmpty()) {
            return;
        }

        // 3. For each affected lead, check if any active CP credit remains
        Map<Id, Boolean> leadHasActiveCredit = new Map<Id, Boolean>();
        for (Id leadId : affectedLeadIds) {
            leadHasActiveCredit.put(leadId, false);
        }

        String creditActiveStatus = this.activeStatus;
        List<Enquiry_Source__c> remainingCredits = Database.query(
            'SELECT Lead__c FROM Enquiry_Source__c '
            + 'WHERE Lead__c IN :affectedLeadIds '
            + 'AND Channel_Partner__c != null '
            + 'AND Credit_Status__c = :creditActiveStatus '
            + 'AND CP_Credit_Expiry__c > TODAY'
        );
        for (Enquiry_Source__c es : remainingCredits) {
            leadHasActiveCredit.put(es.Lead__c, true);
        }

        // 4. Remove CP from leads with no remaining active credits
        List<Lead__c> leadsToUpdate = new List<Lead__c>();
        for (Id leadId : leadHasActiveCredit.keySet()) {
            if (!leadHasActiveCredit.get(leadId)) {
                leadsToUpdate.add(new Lead__c(
                    Id = leadId,
                    Channel_Partner__c = null
                ));
            }
        }
        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }

    global void finish(Database.BatchableContext bc) {}

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new CPCreditExpiryBatch(), 200);
    }
}