/**
 * @description Trigger handler for Master_Payment_Schedule__c.
 * Validates that the total Percentage__c across all records
 * for a single Project does not exceed 100%.
 * @author System
 * @date 2026-04-10
 */
public with sharing class MasterPaymentScheduleTriggerHandler {

    /**
     * @description Validates that the sum of Percentage__c for all Master Payment Schedule
     *              records under the same Project does not exceed 100%.
     * @param newRecords List of new/updated Master_Payment_Schedule__c records
     * @param oldMap Map of old records (null on insert)
     */
    public static void validateTotalPercentage(
        List<Master_Payment_Schedule__c> newRecords,
        Map<Id, Master_Payment_Schedule__c> oldMap
    ) {
        Set<Id> projectIds = new Set<Id>();
        Set<Id> triggerRecordIds = new Set<Id>();

        for (Master_Payment_Schedule__c rec : newRecords) {
            projectIds.add(rec.Project__c);
            if (rec.Id != null) {
                triggerRecordIds.add(rec.Id);
            }
        }

        // Query existing sum of Percentage__c per Project, excluding records in current trigger
        Map<Id, Decimal> existingSumByProject = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Project__c, SUM(Percentage__c) totalPct
            FROM Master_Payment_Schedule__c
            WHERE Project__c IN :projectIds
            AND Id NOT IN :triggerRecordIds
            GROUP BY Project__c
        ]) {
            existingSumByProject.put((Id) ar.get('Project__c'), (Decimal) ar.get('totalPct'));
        }

        // Sum trigger records' percentages per Project
        Map<Id, Decimal> triggerSumByProject = new Map<Id, Decimal>();
        for (Master_Payment_Schedule__c rec : newRecords) {
            Decimal current = triggerSumByProject.containsKey(rec.Project__c)
                ? triggerSumByProject.get(rec.Project__c)
                : 0;
            triggerSumByProject.put(rec.Project__c, current + (rec.Percentage__c != null ? rec.Percentage__c : 0));
        }

        // Validate total per Project
        for (Master_Payment_Schedule__c rec : newRecords) {
            Id projectId = rec.Project__c;
            Decimal existingSum = existingSumByProject.containsKey(projectId)
                ? existingSumByProject.get(projectId)
                : 0;
            Decimal triggerSum = triggerSumByProject.get(projectId);
            Decimal totalSum = existingSum + triggerSum;

            if (totalSum > 100) {
                rec.Percentage__c.addError(
                    'Total percentage for this Project cannot exceed 100%. Current total would be ' +
                    totalSum.setScale(0) + '%.'
                );
            }
        }
    }
}