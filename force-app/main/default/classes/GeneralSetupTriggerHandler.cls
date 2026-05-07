/**
 * @description Handler for General_Setup__c trigger.
 *              Ensures only one General_Setup__c record is active at a time.
 *              When a record is activated, all other active records are deactivated.
 */
public with sharing class GeneralSetupTriggerHandler {

    /**
     * @description Before insert — if a new record is active, deactivate all others.
     */
    public static void handleBeforeInsert(List<General_Setup__c> newRecords) {
        enforceOneActive(newRecords, null);
    }

    /**
     * @description Before update — if a record is being activated, deactivate all others.
     */
    public static void handleBeforeUpdate(List<General_Setup__c> newRecords, Map<Id, General_Setup__c> oldMap) {
        enforceOneActive(newRecords, oldMap);
    }

    private static void enforceOneActive(List<General_Setup__c> newRecords, Map<Id, General_Setup__c> oldMap) {
        // Collect records being activated in this transaction
        List<General_Setup__c> activating = new List<General_Setup__c>();
        for (General_Setup__c gs : newRecords) {
            Boolean isBeingActivated = gs.Is_Active__c;
            if (oldMap != null) {
                isBeingActivated = gs.Is_Active__c && !oldMap.get(gs.Id).Is_Active__c;
            }
            if (isBeingActivated) {
                activating.add(gs);
            }
        }

        if (activating.isEmpty()) return;

        // Only one record can be activated at a time
        if (activating.size() > 1) {
            for (Integer i = 1; i < activating.size(); i++) {
                activating[i].addError('Only one General Setup configuration can be active at a time.');
            }
        }

        // Collect IDs of records being activated (to exclude from deactivation query)
        Set<Id> activatingIds = new Set<Id>();
        for (General_Setup__c gs : activating) {
            if (gs.Id != null) activatingIds.add(gs.Id);
        }

        // Deactivate all other currently active records
        List<General_Setup__c> toDeactivate = [
            SELECT Id, Is_Active__c
            FROM General_Setup__c
            WHERE Is_Active__c = true
            AND Id NOT IN :activatingIds
        ];

        for (General_Setup__c gs : toDeactivate) {
            gs.Is_Active__c = false;
        }
        if (!toDeactivate.isEmpty()) {
            update toDeactivate;
        }
    }
}