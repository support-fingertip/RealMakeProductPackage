/**
 * Trigger handler for Duplication_Configuration__c.
 *
 * Enforces that only ONE Duplication Configuration per Primary Object API Name
 * can be active at a time. When a record is activated (Active__c = true),
 * all other active configurations for the same Primary Object are deactivated.
 *
 * On insert: if the new record is active, deactivate existing active configs.
 * On update: if Active__c changed to true, deactivate existing active configs.
 */
public with sharing class DuplicationConfigTriggerHandler {

    /**
     * Handles before insert: adds error if another active config already exists
     * for the same Primary Object. The saveConfiguration method is responsible
     * for deactivating previous configs before inserting.
     */
    public static void handleBeforeInsert(List<Duplication_Configuration__c> newRecords) {
        deactivateExistingConfigs(newRecords, null);
    }

    /**
     * Handles before update: when a record is being activated, block if another
     * active config already exists for the same Primary Object.
     */
    public static void handleBeforeUpdate(
        List<Duplication_Configuration__c> newRecords,
        Map<Id, Duplication_Configuration__c> oldMap
    ) {
        // Only process records where Active__c changed to true
        List<Duplication_Configuration__c> newlyActivated = new List<Duplication_Configuration__c>();
        for (Duplication_Configuration__c rec : newRecords) {
            Duplication_Configuration__c oldRec = oldMap.get(rec.Id);
            if (rec.Active__c == true && oldRec.Active__c == false) {
                newlyActivated.add(rec);
            }
        }

        if (!newlyActivated.isEmpty()) {
            blockIfActiveExists(newlyActivated);
        }
    }

    /**
     * Blocks activation if another active config already exists for the same
     * Primary Object. Adds an error to the record being activated.
     */
    private static void blockIfActiveExists(List<Duplication_Configuration__c> records) {
        Set<String> primaryObjects = new Set<String>();
        Set<Id> currentRecordIds = new Set<Id>();
        for (Duplication_Configuration__c rec : records) {
            if (rec.Active__c == true && String.isNotBlank(rec.Primary_Object_API_Name__c)) {
                primaryObjects.add(rec.Primary_Object_API_Name__c);
            }
            if (rec.Id != null) {
                currentRecordIds.add(rec.Id);
            }
        }

        if (primaryObjects.isEmpty()) {
            return;
        }

        List<Duplication_Configuration__c> existingActive = [
            SELECT Id, Primary_Object_API_Name__c
            FROM Duplication_Configuration__c
            WHERE Primary_Object_API_Name__c IN :primaryObjects
            AND Active__c = true
            AND Id NOT IN :currentRecordIds
        ];

        Set<String> objectsWithActiveConfig = new Set<String>();
        for (Duplication_Configuration__c existing : existingActive) {
            objectsWithActiveConfig.add(existing.Primary_Object_API_Name__c);
        }

        for (Duplication_Configuration__c rec : records) {
            if (rec.Active__c == true && objectsWithActiveConfig.contains(rec.Primary_Object_API_Name__c)) {
                rec.addError('An active Duplication Configuration already exists for '
                    + rec.Primary_Object_API_Name__c
                    + '. Please deactivate the existing configuration before activating this one.');
            }
        }
    }

    /**
     * For each record being activated, find and deactivate all other active
     * configurations that share the same Primary_Object_API_Name__c.
     */
    private static void deactivateExistingConfigs(
        List<Duplication_Configuration__c> activatingRecords,
        Map<Id, Duplication_Configuration__c> oldMap
    ) {
        // Collect Primary Object API Names for records being set to active
        Set<String> primaryObjects = new Set<String>();
        for (Duplication_Configuration__c rec : activatingRecords) {
            if (rec.Active__c == true && String.isNotBlank(rec.Primary_Object_API_Name__c)) {
                primaryObjects.add(rec.Primary_Object_API_Name__c);
            }
        }

        if (primaryObjects.isEmpty()) {
            return;
        }

        // Collect IDs of records being inserted/updated so we exclude them
        Set<Id> currentRecordIds = new Set<Id>();
        for (Duplication_Configuration__c rec : activatingRecords) {
            if (rec.Id != null) {
                currentRecordIds.add(rec.Id);
            }
        }

        // Query existing active configs for those Primary Objects
        List<Duplication_Configuration__c> existingActiveConfigs = [
            SELECT Id, Primary_Object_API_Name__c, Active__c
            FROM Duplication_Configuration__c
            WHERE Primary_Object_API_Name__c IN :primaryObjects
            AND Active__c = true
            AND Id NOT IN :currentRecordIds
        ];

        if (existingActiveConfigs.isEmpty()) {
            return;
        }

        // Deactivate them
        for (Duplication_Configuration__c existing : existingActiveConfigs) {
            existing.Active__c = false;
        }

        update existingActiveConfigs;
    }
}