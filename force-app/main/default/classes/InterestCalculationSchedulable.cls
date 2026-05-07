/**
 * @description Schedulable Apex job that runs daily to calculate interest on
 *              overdue Payment Schedules. Launches InterestCalculationBatch
 *              to process all active Bookings with overdue amounts.
 *
 *              Interest rate is sourced from Project__c.Interest_Rate__c (annual %).
 *              Formula: Interest = Principal x (Rate / 365) x Days Overdue
 *
 *              Schedule examples:
 *              - Daily at 1 AM:  System.schedule('Daily Interest Calculation', '0 0 1 * * ?', new InterestCalculationSchedulable());
 *              - Daily at 6 AM:  System.schedule('Daily Interest Calculation', '0 0 6 * * ?', new InterestCalculationSchedulable());
 *
 * @author System
 * @date 2026-03-30
 */
public with sharing class InterestCalculationSchedulable implements Schedulable {

    private static final Integer DEFAULT_BATCH_SIZE = 50;

    public void execute(SchedulableContext sc) {
        try {
            Database.executeBatch(new InterestCalculationBatch(), DEFAULT_BATCH_SIZE);
        } catch (Exception e) {
            System.debug('InterestCalculationSchedulable error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
}