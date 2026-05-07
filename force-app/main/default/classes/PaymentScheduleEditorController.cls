/**
 * @description Controller for Payment Schedule Editor LWC.
 *              Supports editing amounts/percentages on payment schedules post-booking creation
 *              when Schedule_Edit_Mode__c = 'Custom' in the Payment Schedule configuration.
 * @author Arun Kumar N
 * @date 2026-04-01
 */
public with sharing class PaymentScheduleEditorController {

    // ─── Inner Wrapper Classes ───────────────────────────────────────────────────

    public class ScheduleWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public String milestoneName;
        @AuraEnabled public Decimal percentage;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Decimal baseAmount;
        @AuraEnabled public Decimal gstAmount;
        @AuraEnabled public Decimal tdsAmount;
        @AuraEnabled public Decimal amountPaid;
        @AuraEnabled public Decimal pendingAmount;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isEditable; // false if already paid/completed
    }

    public class BookingTotals {
        @AuraEnabled public Decimal totalPayableAmount;
        @AuraEnabled public Decimal totalBaseAmount;
        @AuraEnabled public Decimal totalGstAmount;
    }

    public class EditResult {
        @AuraEnabled public List<ScheduleWrapper> schedules;
        @AuraEnabled public BookingTotals totals;
        @AuraEnabled public Boolean editingEnabled;
    }

    // ─── AuraEnabled Methods ─────────────────────────────────────────────────────

    /**
     * @description Retrieves payment schedules for a booking along with booking totals
     *              and whether custom editing is enabled.
     * @param bookingId The Booking__c record Id
     * @return EditResult containing schedules, totals, and editing flag
     */
    @AuraEnabled
    public static EditResult getSchedulesForEditing(Id bookingId) {
        try {
            if (bookingId == null) {
                throw new AuraHandledException('Booking ID is required.');
            }

            EditResult result = new EditResult();
            result.editingEnabled = checkEditingEnabled(bookingId);

            // Query Booking totals
            List<Booking__c> bookings = [
                SELECT Id, Total_Payable_Amount__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];

            if (bookings.isEmpty()) {
                throw new AuraHandledException('Booking record not found.');
            }

            Booking__c booking = bookings[0];

            BookingTotals totals = new BookingTotals();
            totals.totalPayableAmount = booking.Total_Payable_Amount__c != null ? booking.Total_Payable_Amount__c : 0;
            result.totals = totals;

            // Query Payment Schedules
            List<Payment_Schedule__c> schedules = [
                SELECT Id, Name, Sequence__c, Milestone_Name__c, Percentage__c,
                       Amount__c, Payment_Schedule_Amount__c, GST_Amount__c,
                       TDS_Amount__c, Amount_Paid__c, Pending_Amount__c, Status__c
                FROM Payment_Schedule__c
                WHERE Booking__c = :bookingId
                ORDER BY Sequence__c ASC
            ];

            List<ScheduleWrapper> wrappers = new List<ScheduleWrapper>();
            for (Payment_Schedule__c ps : schedules) {
                ScheduleWrapper w = new ScheduleWrapper();
                w.id = ps.Id;
                w.name = ps.Name != null ? ps.Name : '';
                w.sequence = ps.Sequence__c != null ? ps.Sequence__c : 0;
                w.milestoneName = ps.Milestone_Name__c != null ? ps.Milestone_Name__c : '';
                w.percentage = ps.Percentage__c != null ? ps.Percentage__c : 0;
                w.amount = ps.Amount__c != null ? ps.Amount__c : 0;
                w.baseAmount = ps.Payment_Schedule_Amount__c != null ? ps.Payment_Schedule_Amount__c : 0;
                w.gstAmount = ps.GST_Amount__c != null ? ps.GST_Amount__c : 0;
                w.tdsAmount = ps.TDS_Amount__c != null ? ps.TDS_Amount__c : 0;
                w.amountPaid = ps.Amount_Paid__c != null ? ps.Amount_Paid__c : 0;
                w.pendingAmount = ps.Pending_Amount__c != null ? ps.Pending_Amount__c : 0;
                w.status = ps.Status__c != null ? ps.Status__c : '';
                w.isEditable = !PostSalesConstants.SCHEDULE_CLOSED_STATUSES.contains(ps.Status__c);
                wrappers.add(w);
            }

            result.schedules = wrappers;
            return result;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug('Error in getSchedulesForEditing: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading schedules: ' + e.getMessage());
        }
    }

    /**
     * @description Checks whether custom schedule editing is enabled for a booking
     *              by looking at the Post_Sales_Configuration__c with type 'Payment Schedule'.
     * @param bookingId The Booking__c record Id
     * @return true if Schedule_Edit_Mode__c = 'Custom'
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isEditingEnabled(Id bookingId) {
        try {
            if (bookingId == null) {
                throw new AuraHandledException('Booking ID is required.');
            }
            return checkEditingEnabled(bookingId);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug('Error in isEditingEnabled: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error checking edit mode: ' + e.getMessage());
        }
    }

    /**
     * @description Saves edited payment schedules after validating totals.
     *              Validates that percentages sum to 100 and amounts match the booking total.
     * @param bookingId The Booking__c record Id
     * @param schedulesJson JSON array of edited ScheduleWrapper objects
     * @return Updated EditResult with recalculated schedules
     */
    @AuraEnabled
    public static EditResult saveEditedSchedules(Id bookingId, String schedulesJson) {
        try {
            if (bookingId == null) {
                throw new AuraHandledException('Booking ID is required.');
            }
            if (String.isBlank(schedulesJson)) {
                throw new AuraHandledException('No schedule data provided.');
            }

            // Deserialize edited schedules
            List<ScheduleWrapper> editedSchedules = (List<ScheduleWrapper>) JSON.deserialize(
                schedulesJson, List<ScheduleWrapper>.class
            );

            if (editedSchedules == null || editedSchedules.isEmpty()) {
                throw new AuraHandledException('No schedules to save.');
            }

            // Query booking for validation
            List<Booking__c> bookings = [
                SELECT Id, Total_Payable_Amount__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];

            if (bookings.isEmpty()) {
                throw new AuraHandledException('Booking record not found.');
            }

            Decimal bookingTotalPayable = bookings[0].Total_Payable_Amount__c != null
                ? bookings[0].Total_Payable_Amount__c : 0;

            // Validate percentage sum = 100
            Decimal percentageSum = 0;
            Decimal amountSum = 0;
            for (ScheduleWrapper sw : editedSchedules) {
                percentageSum += (sw.percentage != null ? sw.percentage : 0);
                amountSum += (sw.amount != null ? sw.amount : 0);
            }

            if (percentageSum.setScale(2) != Decimal.valueOf(100).setScale(2)) {
                throw new AuraHandledException(
                    'Total percentage must equal 100%. Current total: ' + percentageSum.setScale(2) + '%'
                );
            }

            // Validate amount sum = booking total payable
            if (amountSum.setScale(2) != bookingTotalPayable.setScale(2)) {
                throw new AuraHandledException(
                    'Total amount (' + amountSum.setScale(2) +
                    ') must equal booking total payable amount (' + bookingTotalPayable.setScale(2) + ').'
                );
            }

            // Build map of existing schedules for update
            Set<Id> scheduleIds = new Set<Id>();
            for (ScheduleWrapper sw : editedSchedules) {
                if (sw.id != null) {
                    scheduleIds.add(sw.id);
                }
            }

            Map<Id, Payment_Schedule__c> existingSchedules = new Map<Id, Payment_Schedule__c>([
                SELECT Id, Amount__c, Percentage__c, Payment_Schedule_Amount__c,
                       GST_Amount__c, TDS_Amount__c, Amount_Paid__c, Pending_Amount__c, Status__c
                FROM Payment_Schedule__c
                WHERE Id IN :scheduleIds
                AND Booking__c = :bookingId
            ]);

            // Prepare updates
            List<Payment_Schedule__c> schedulesToUpdate = new List<Payment_Schedule__c>();
            for (ScheduleWrapper sw : editedSchedules) {
                if (sw.id == null || !existingSchedules.containsKey(sw.id)) {
                    continue;
                }

                Payment_Schedule__c existing = existingSchedules.get(sw.id);

                // Skip non-editable (closed) schedules
                if (PostSalesConstants.SCHEDULE_CLOSED_STATUSES.contains(existing.Status__c)) {
                    continue;
                }

                Payment_Schedule__c toUpdate = new Payment_Schedule__c(Id = sw.id);
                toUpdate.Percentage__c = sw.percentage;
                toUpdate.Amount__c = sw.amount;
                toUpdate.Payment_Schedule_Amount__c = sw.baseAmount;
                toUpdate.GST_Amount__c = sw.gstAmount;

                // Recalculate pending amount = amount - amount_paid
                Decimal amountPaid = existing.Amount_Paid__c != null ? existing.Amount_Paid__c : 0;
                Decimal newAmount = sw.amount != null ? sw.amount : 0;
                toUpdate.Pending_Amount__c = newAmount - amountPaid;

                schedulesToUpdate.add(toUpdate);
            }

            if (!schedulesToUpdate.isEmpty()) {
                update schedulesToUpdate;
            }

            // Return refreshed data
            return getSchedulesForEditing(bookingId);

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            System.debug('Error in saveEditedSchedules: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            throw new AuraHandledException('Error saving schedules: ' + e.getMessage());
        }
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────────

    /**
     * @description Internal helper to check if custom editing is enabled via configuration.
     * @param bookingId The Booking__c record Id (used for criteria-based config resolution)
     * @return true if Schedule_Edit_Mode__c = 'Custom'
     */
    private static Boolean checkEditingEnabled(Id bookingId) {
        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Schedule_Edit_Mode__c
            FROM Post_Sales_Configuration__c
            WHERE Configuration_Type__c = 'Payment Schedule'
            AND Is_Active__c = true
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            return false;
        }

        return configs[0].Schedule_Edit_Mode__c == 'Custom';
    }
}