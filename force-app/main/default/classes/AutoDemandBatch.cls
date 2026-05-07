/**
 * @description Batchable Apex that automatically raises demands for Payment Schedules
 *              where Auto_Demand_Date__c equals today. Follows the same demand creation
 *              process as BulkDemandController.createBulkDemands():
 *              1. Creates Demands__c records with amounts from Payment Schedule
 *              2. Updates Payment_Schedule__c (Demand_Raised__c = true, Demand_Date__c = today)
 *              3. Populates reminder dates via DemandReminderService
 *              4. Auto-applies credit notes via CreditNoteApplicationService
 *
 *              Grace period is resolved from:
 *              1. Post_Sales_Config_Master__c.Grace_Period_Days__c (global config)
 *              2. PostSalesConstants.DEFAULT_GRACE_PERIOD_DAYS (fallback = 15)
 *
 * @author System
 * @date 2026-03-31
 */
public with sharing class AutoDemandBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Date demandDate;
    private Integer totalDemandsCreated = 0;
    private Integer totalSchedulesProcessed = 0;
    private List<String> errors = new List<String>();

    /**
     * @description Constructor using today's date
     */
    public AutoDemandBatch() {
        this.demandDate = Date.today();
    }

    /**
     * @description Constructor with explicit date (useful for testing)
     * @param demandDate The date to check Auto_Demand_Date__c against
     */
    public AutoDemandBatch(Date demandDate) {
        this.demandDate = demandDate != null ? demandDate : Date.today();
    }

    /**
     * @description Queries Payment Schedules where Auto_Demand_Date__c matches today,
     *              demand has not been raised yet, and there is a pending amount.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Booking__c, Booking__r.Project__c, Booking__r.Name,
                   Pending_Amount__c, Payment_Schedule_Amount_Pending__c,
                   GST_Amount_Pending__c, TDS_Amount_Pending__c,
                   Interest_Pending__c, Milestone_Name__c, Sequence__c
            FROM Payment_Schedule__c
            WHERE Auto_Demand_Date__c = :demandDate
            AND Demand_Raised__c = false
            AND Pending_Amount__c > 0
            AND Status__c NOT IN :PostSalesConstants.SCHEDULE_CLOSED_STATUSES
            AND Booking__r.Is_Cancelled__c = false
        ]);
    }

    /**
     * @description Processes each batch of Payment Schedules by creating demands
     *              following the same process as BulkDemandController.
     */
    public void execute(Database.BatchableContext bc, List<Payment_Schedule__c> scope) {
        if (scope.isEmpty()) return;

        Savepoint sp = Database.setSavepoint();

        try {
            // Resolve grace period from config hierarchy
            Integer graceDays = resolveGracePeriod();
            Date dueDate = demandDate.addDays(graceDays);

            // Group schedules by booking for demand creation
            Map<Id, List<Payment_Schedule__c>> schedulesByBooking = new Map<Id, List<Payment_Schedule__c>>();
            for (Payment_Schedule__c ps : scope) {
                if (!schedulesByBooking.containsKey(ps.Booking__c)) {
                    schedulesByBooking.put(ps.Booking__c, new List<Payment_Schedule__c>());
                }
                schedulesByBooking.get(ps.Booking__c).add(ps);
            }

            // Create one demand per booking (aggregating all due schedules)
            List<Demands__c> demandsToInsert = new List<Demands__c>();
            Map<Integer, Id> indexToBookingId = new Map<Integer, Id>();
            Map<Id, List<Id>> bookingToScheduleIds = new Map<Id, List<Id>>();
            Integer idx = 0;

            for (Id bookingId : schedulesByBooking.keySet()) {
                List<Payment_Schedule__c> schedules = schedulesByBooking.get(bookingId);

                Decimal totalAmount = 0;
                Decimal baseAmount = 0;
                Decimal gstAmount = 0;
                Decimal tdsAmount = 0;
                Decimal interestAmount = 0;
                List<Id> scheduleIds = new List<Id>();

                for (Payment_Schedule__c ps : schedules) {
                    totalAmount += ps.Pending_Amount__c != null ? ps.Pending_Amount__c : 0;
                    baseAmount += ps.Payment_Schedule_Amount_Pending__c != null ? ps.Payment_Schedule_Amount_Pending__c : 0;
                    gstAmount += ps.GST_Amount_Pending__c != null ? ps.GST_Amount_Pending__c : 0;
                    tdsAmount += ps.TDS_Amount_Pending__c != null ? ps.TDS_Amount_Pending__c : 0;
                    interestAmount += ps.Interest_Pending__c != null ? ps.Interest_Pending__c : 0;
                    scheduleIds.add(ps.Id);
                }

                Demands__c demand = new Demands__c();
                demand.Booking__c = bookingId;
                demand.Demand_Amount__c = totalAmount;
                demand.Base_Amount__c = baseAmount;
                demand.GST_Amount__c = gstAmount;
                demand.TDS_Amount__c = tdsAmount;
                demand.Interest_Amount__c = interestAmount;
                demand.Status__c = PostSalesConstants.DEMAND_STATUS_RAISED;
                demand.Demand_Type__c = PostSalesConstants.DEMAND_TYPE_AUTO;
                demand.Demand_Date__c = demandDate;
                demand.Due_Date__c = dueDate;
                demand.Grace_Period_Days__c = graceDays;
                demand.Reminder_Date__c = demandDate;

                demandsToInsert.add(demand);
                indexToBookingId.put(idx, bookingId);
                bookingToScheduleIds.put(bookingId, scheduleIds);
                idx++;
            }

            // Insert demands
            Database.SaveResult[] insertResults = Database.insert(demandsToInsert, false);

            // Process results and update payment schedules
            List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();
            List<Id> successfulDemandIds = new List<Id>();
            List<Demands__c> successfulDemands = new List<Demands__c>();

            for (Integer i = 0; i < insertResults.size(); i++) {
                Id bookingId = indexToBookingId.get(i);

                if (insertResults[i].isSuccess()) {
                    totalDemandsCreated++;
                    successfulDemandIds.add(insertResults[i].getId());
                    successfulDemands.add(demandsToInsert[i]);

                    // Mark payment schedules as demand raised
                    List<Id> scheduleIds = bookingToScheduleIds.get(bookingId);
                    if (scheduleIds != null) {
                        for (Id schedId : scheduleIds) {
                            Payment_Schedule__c ps = new Payment_Schedule__c();
                            ps.Id = schedId;
                            ps.Demand_Raised__c = true;
                            ps.Demand_Date__c = demandDate;
                            schedulesToUpdate.add(ps);
                            totalSchedulesProcessed++;
                        }
                    }
                } else {
                    errors.add('Booking ' + bookingId + ': ' + insertResults[i].getErrors()[0].getMessage());
                }
            }

            // Update payment schedules
            if (!schedulesToUpdate.isEmpty()) {
                Database.update(schedulesToUpdate, false);
            }

            // Populate reminder dates on successfully created demands
            if (!successfulDemands.isEmpty()) {
                DemandReminderService.populateReminderDates(successfulDemands);
                update successfulDemands;
            }

            // Auto-apply credit notes
            if (!successfulDemandIds.isEmpty()) {
                CreditNoteApplicationService.applyCredits(successfulDemandIds);
            }

        } catch (Exception e) {
            Database.rollback(sp);
            errors.add('Batch execute error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    /**
     * @description Logs the batch execution summary.
     */
    public void finish(Database.BatchableContext bc) {
        String summary = 'AutoDemandBatch completed.\n' +
            'Demand Date: ' + String.valueOf(demandDate) + '\n' +
            'Demands Created: ' + totalDemandsCreated + '\n' +
            'Schedules Processed: ' + totalSchedulesProcessed;

        if (!errors.isEmpty()) {
            summary += '\nErrors (' + errors.size() + '):\n' + String.join(errors, '\n');
        }

        System.debug(summary);
    }

    // ==================== PRIVATE HELPERS ====================

    private Integer resolveGracePeriod() {
        List<Post_Sales_Config_Master__c> masterConfigs = [
            SELECT Grace_Period_Days__c
            FROM Post_Sales_Config_Master__c
            WHERE Is_Active__c = true
            LIMIT 1
        ];
        if (!masterConfigs.isEmpty() && masterConfigs[0].Grace_Period_Days__c != null) {
            return Integer.valueOf(masterConfigs[0].Grace_Period_Days__c);
        }
        return PostSalesConstants.DEFAULT_GRACE_PERIOD_DAYS;
    }

    // ==================== RESULT GETTERS (for testing) ====================

    public Integer getTotalDemandsCreated() { return totalDemandsCreated; }
    public Integer getTotalSchedulesProcessed() { return totalSchedulesProcessed; }
    public List<String> getErrors() { return errors; }
}