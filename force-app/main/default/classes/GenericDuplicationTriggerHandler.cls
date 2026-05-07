/**
 * GENERIC HANDLER - Validates before insert/update.
 *
 * Two-layer deduplication:
 *   1. Intra-batch: in-memory check across records within the same DML batch (0 SOQL)
 *   2. DB check: bulk SOQL query against existing committed records (1 SOQL)
 *
 * Intra-batch runs ALWAYS (regardless of Block_On_Duplicate__c) to prevent
 * N identical records slipping through in a single Data Loader / Bulk API batch.
 * DB check only runs when Block_On_Duplicate__c = true.
 *
 * Governor cost: 1 SOQL (config query) + 0 SOQL (intra-batch) + 1 SOQL (DB check) = 2 total.
 */
public with sharing class GenericDuplicationTriggerHandler {

    public static void handleBeforeInsertUpdate(List<SObject> newRecords, String objectApiName) {
        checkAndPreventDuplicates(newRecords, objectApiName);
    }

    private static void checkAndPreventDuplicates(List<SObject> newRecords, String objectApiName) {
        // 1. Get configuration (1 SOQL). Tolerate config records stored with either
        // prefixed or un-prefixed object names.
        Set<String> objectNameCandidates = new Set<String>{
            objectApiName, NamespaceUtil.strip(objectApiName), NamespaceUtil.qualify(objectApiName)
        };
        List<Duplication_Configuration__c> configs = [
            SELECT Id,
                   Primary_Object_API_Name__c,
                   Primary_Expression__c,
                   Related_Object_API_Name__c,
                   Related_Expression__c,
                   Block_On_Duplicate__c
            FROM Duplication_Configuration__c
            WHERE Primary_Object_API_Name__c IN :objectNameCandidates
            AND Active__c = true
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            return;
        }

        Duplication_Configuration__c config = configs[0];
        String expression = config.Primary_Expression__c;

        // 2. Intra-batch duplicate detection — always runs (0 SOQL, pure in-memory)
        //    Prevents N identical records in a single bulk batch from all being inserted.
        //    First occurrence is kept; subsequent duplicates get addError().
        Set<Integer> batchDuplicateIndices =
            DuplicationDetectionHelper.checkForIntraBatchDuplicates(newRecords, expression);

        for (Integer idx : batchDuplicateIndices) {
            newRecords[idx].addError(
                'Duplicate record found within the same batch. '
                + 'Another record in this batch has the same deduplication key. '
                + 'Please remove duplicate entries and retry.'
            );
        }

        // 3. If blocking is disabled, stop here — after-insert handles DB duplicates
        if (!config.Block_On_Duplicate__c) {
            return;
        }

        // 4. DB duplicate check — bulk-safe, single SOQL (1 SOQL)
        //    Only check surviving (non-batch-duplicate) records against committed DB rows.
        List<SObject> survivingRecords = new List<SObject>();
        Map<Integer, Integer> survivingToOriginalIndex = new Map<Integer, Integer>();

        for (Integer i = 0; i < newRecords.size(); i++) {
            if (!batchDuplicateIndices.contains(i)) {
                survivingToOriginalIndex.put(survivingRecords.size(), i);
                survivingRecords.add(newRecords[i]);
            }
        }

        if (survivingRecords.isEmpty()) {
            return;
        }

        Map<Integer, List<String>> dbDuplicateMap =
            DuplicationDetectionHelper.checkForDuplicatesByIndex(
                survivingRecords, objectApiName, expression
            );

        for (Integer survivingIdx : dbDuplicateMap.keySet()) {
            Integer originalIdx = survivingToOriginalIndex.get(survivingIdx);
            List<String> duplicateIds = dbDuplicateMap.get(survivingIdx);
            String errorMessage = 'Duplicate record(s) found! Matching record IDs: '
                + String.join(duplicateIds, ', ')
                + '. Please review before saving.';
            newRecords[originalIdx].addError(errorMessage);
        }
    }
}