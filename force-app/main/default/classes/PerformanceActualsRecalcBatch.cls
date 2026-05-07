/**
 * @description Scheduled + Batchable Apex job for recalculating performance actuals.
 *              Queries active user-level Performance Targets, recalculates live actuals,
 *              creates daily snapshot records, and chains into PerformanceNotificationBatch.
 *
 *              Schedule: System.schedule('Performance Actuals Recalc', '0 0 2 * * ?', new PerformanceActualsRecalcBatch());
 */
public with sharing class PerformanceActualsRecalcBatch implements Database.Batchable<SObject>, Schedulable {

    // ── Schedulable entry point ──────────────────────────────────

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PerformanceActualsRecalcBatch(), 200);
    }

    // ── Batchable methods ────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, Metric__c, Target_Value__c, Actual_Value__c,
                   Last_Calculated__c, Period_Start__c, Period_End__c,
                   Assignee__c, Parent_Target__c, Is_Active__c, Target_Level__c,
                   Project__c, Team_Role__c
            FROM Performance_Target__c
            WHERE Is_Active__c = true
            AND Target_Level__c = 'User'
            AND Period_End__c >= TODAY
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Performance_Target__c> scope) {
        // 1. Calculate live actuals via service
        Map<Id, Decimal> liveActuals = PerformanceTargetService.calculateLiveActuals(scope);

        // 2. Collect target IDs and query existing snapshots for today to avoid duplicates
        Set<Id> targetIds = new Set<Id>();
        for (Performance_Target__c target : scope) {
            targetIds.add(target.Id);
        }

        Set<Id> targetsWithSnapshotToday = new Set<Id>();
        for (Performance_Snapshot__c existing : [
            SELECT Performance_Target__c
            FROM Performance_Snapshot__c
            WHERE Performance_Target__c IN :targetIds
            AND Snapshot_Date__c = TODAY
        ]) {
            targetsWithSnapshotToday.add(existing.Performance_Target__c);
        }

        // 3. Update targets and build snapshot records
        List<Performance_Target__c> targetsToUpdate = new List<Performance_Target__c>();
        List<Performance_Snapshot__c> snapshots = new List<Performance_Snapshot__c>();

        for (Performance_Target__c target : scope) {
            Decimal actualValue = liveActuals.containsKey(target.Id) ? liveActuals.get(target.Id) : 0;

            // Update actual value and last calculated timestamp
            targetsToUpdate.add(new Performance_Target__c(
                Id = target.Id,
                Actual_Value__c = actualValue,
                Last_Calculated__c = Datetime.now()
            ));

            // Create snapshot if one doesn't already exist for today
            if (!targetsWithSnapshotToday.contains(target.Id)) {
                Decimal achievementPct = 0;
                if (target.Target_Value__c != null && target.Target_Value__c != 0) {
                    achievementPct = actualValue / target.Target_Value__c;
                }

                Integer periodDayNumber = target.Period_Start__c.daysBetween(Date.today()) + 1;

                snapshots.add(new Performance_Snapshot__c(
                    Performance_Target__c = target.Id,
                    Snapshot_Date__c = Date.today(),
                    Actual_Value__c = actualValue,
                    Achievement_Pct__c = achievementPct,
                    Period_Day_Number__c = periodDayNumber
                ));
            }
        }

        if (!targetsToUpdate.isEmpty()) {
            update targetsToUpdate;
        }
        if (!snapshots.isEmpty()) {
            insert snapshots;
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Rollup parent targets
        Set<Id> parentIds = new Set<Id>();
        for (Performance_Target__c t : [
            SELECT Parent_Target__c FROM Performance_Target__c
            WHERE Parent_Target__c != null AND Is_Active__c = true
        ]) {
            parentIds.add(t.Parent_Target__c);
        }
        if (!parentIds.isEmpty()) {
            PerformanceTargetService.rollupParentTargets(parentIds);
        }

        // Chain notification batch
        Database.executeBatch(new PerformanceNotificationBatch(), 200);
    }
}