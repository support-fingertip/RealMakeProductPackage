/**
 * @description Batchable Apex that calculates daily interest on overdue Payment Schedules
 *              across all active Bookings. For each Booking with overdue schedules,
 *              it delegates to InterestCalculationService to compute simple interest
 *              using the Project's Interest_Rate__c and create Interest_Line_Item__c records.
 *
 *              Interest = Principal x (Annual Rate / 365) x Days Overdue
 *
 *              The batch queries active Bookings that have at least one overdue
 *              Payment Schedule with a pending amount, and whose Project has a
 *              non-zero interest rate configured.
 *
 * @author System
 * @date 2026-03-30
 */
public with sharing class InterestCalculationBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Date calculationDate;
    private Integer totalBookingsProcessed = 0;
    private Integer totalSchedulesWithInterest = 0;
    private Decimal totalInterestAmount = 0;
    private List<String> errors = new List<String>();

    /**
     * @description Constructor using today's date
     */
    public InterestCalculationBatch() {
        this.calculationDate = Date.today();
    }

    /**
     * @description Constructor with explicit calculation date (useful for testing)
     * @param calcDate The date to calculate interest as of
     */
    public InterestCalculationBatch(Date calcDate) {
        this.calculationDate = calcDate != null ? calcDate : Date.today();
    }

    /**
     * @description Queries all active Bookings that have overdue Payment Schedules
     *              with pending amounts and a Project with a non-zero interest rate.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM Booking__c
            WHERE Is_Cancelled__c = false
            AND Project__r.Interest_Rate__c > 0
            AND Id IN (
                SELECT Booking__c
                FROM Payment_Schedule__c
                WHERE Due_Date__c < :calculationDate
                AND Pending_Amount__c > 0
                AND Status__c NOT IN :PostSalesConstants.SCHEDULE_CLOSED_STATUSES
            )
        ]);
    }

    /**
     * @description Processes each batch of Bookings by calculating interest
     *              on their overdue Payment Schedules.
     */
    public void execute(Database.BatchableContext bc, List<Booking__c> scope) {
        for (Booking__c booking : scope) {
            try {
                InterestCalculationService.FlowOutput result =
                    InterestCalculationService.calculateForBooking(booking.Id, calculationDate);

                totalBookingsProcessed++;
                totalSchedulesWithInterest += result.schedulesWithInterest;
                totalInterestAmount += result.totalInterest;
            } catch (Exception e) {
                errors.add('Booking ' + booking.Id + ': ' + e.getMessage());
            }
        }
    }

    /**
     * @description Logs the batch execution summary.
     */
    public void finish(Database.BatchableContext bc) {
        String summary = 'InterestCalculationBatch completed.\n' +
            'Calculation Date: ' + String.valueOf(calculationDate) + '\n' +
            'Bookings Processed: ' + totalBookingsProcessed + '\n' +
            'Schedules with Interest: ' + totalSchedulesWithInterest + '\n' +
            'Total Interest: ' + PostSalesConstants.formatCurrency(totalInterestAmount);

        if (!errors.isEmpty()) {
            summary += '\nErrors (' + errors.size() + '):\n' + String.join(errors, '\n');
        }

        System.debug(summary);
    }

    // ==================== RESULT GETTERS (for testing) ====================

    public Integer getTotalBookingsProcessed() { return totalBookingsProcessed; }
    public Integer getTotalSchedulesWithInterest() { return totalSchedulesWithInterest; }
    public Decimal getTotalInterestAmount() { return totalInterestAmount; }
    public List<String> getErrors() { return errors; }
}