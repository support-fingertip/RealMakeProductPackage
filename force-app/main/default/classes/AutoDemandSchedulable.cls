/**
 * @description Schedulable Apex job that runs daily to automatically raise demands
 *              for Payment Schedules where Auto_Demand_Date__c matches today.
 *              Launches AutoDemandBatch to process all eligible schedules.
 *
 *              Schedule examples:
 *              - Daily at 2 AM:  System.schedule('Daily Auto Demand', '0 0 2 * * ?', new AutoDemandSchedulable());
 *              - Daily at 7 AM:  System.schedule('Daily Auto Demand', '0 0 7 * * ?', new AutoDemandSchedulable());
 *
 * @author System
 * @date 2026-03-31
 */
public with sharing class AutoDemandSchedulable implements Schedulable {

    private static final Integer DEFAULT_BATCH_SIZE = 50;

    public void execute(SchedulableContext sc) {
        try {
            Database.executeBatch(new AutoDemandBatch(), DEFAULT_BATCH_SIZE);
        } catch (Exception e) {
            System.debug('AutoDemandSchedulable error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
}