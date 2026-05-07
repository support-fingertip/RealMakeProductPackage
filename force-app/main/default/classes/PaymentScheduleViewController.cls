/**
 * @description Controller for Payment Schedule Viewer LWC
 * @author Arun Kumar N
 * @date 2026-01-29
 * @updated 2026-01-30 - Added last completed milestone tracking
 */
public with sharing class PaymentScheduleViewController {
    
    /**
     * Wrapper class for Payment Schedule display
     */
    public class PaymentScheduleWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String milestoneName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Decimal percentage { get; set; }
        @AuraEnabled public Decimal pendingAmount { get; set; }
        @AuraEnabled public Decimal interestPending { get; set; }
        @AuraEnabled public Decimal baseAmount { get; set; }
        @AuraEnabled public Decimal gstAmount { get; set; }
        @AuraEnabled public Decimal basePending { get; set; }
        @AuraEnabled public Decimal gstPending { get; set; }
        @AuraEnabled public Decimal basePaid { get; set; }
        @AuraEnabled public Decimal gstPaid { get; set; }
        @AuraEnabled public String statusColor { get; set; }
        @AuraEnabled public String statusIcon { get; set; }
        @AuraEnabled public Boolean isPaid { get; set; }
        @AuraEnabled public Boolean isCompleted { get; set; }
        @AuraEnabled public String formattedAmount { get; set; }
        @AuraEnabled public String formattedPending { get; set; }
        @AuraEnabled public String formattedInterest { get; set; }
    }
    
    /**
     * Wrapper class for Next Demand Summary
     */
    public class NextDemandWrapper {
        @AuraEnabled public Decimal totalPendingAmount { get; set; }
        @AuraEnabled public Decimal totalInterestPending { get; set; }
        @AuraEnabled public Decimal grandTotal { get; set; }
        @AuraEnabled public Boolean hasInterest { get; set; }
        @AuraEnabled public Integer completedScheduleCount { get; set; }
        @AuraEnabled public String formattedPending { get; set; }
        @AuraEnabled public String formattedInterest { get; set; }
        @AuraEnabled public String formattedTotal { get; set; }
        @AuraEnabled public String lastCompletedMilestone { get; set; }
    }
    
    /**
     * Result wrapper for the complete view
     */
    public class PaymentScheduleViewResult {
        @AuraEnabled public List<PaymentScheduleWrapper> schedules { get; set; }
        @AuraEnabled public NextDemandWrapper nextDemand { get; set; }
        @AuraEnabled public String bookingName { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public String unitName { get; set; }
        @AuraEnabled public Decimal totalPayableAmount { get; set; }
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
    }
    
    /**
     * @description Get all payment schedules for a booking with next demand calculation
     * @param bookingId The ID of the Booking record
     * @return PaymentScheduleViewResult
     */
    @AuraEnabled(cacheable=true)
    public static PaymentScheduleViewResult getPaymentSchedules(Id bookingId) {
        PaymentScheduleViewResult result = new PaymentScheduleViewResult();
        result.schedules = new List<PaymentScheduleWrapper>();
        result.success = false;
        
        try {
            // Validate bookingId
            if (bookingId == null) {
                result.errorMessage = 'Booking ID is required';
                return result;
            }
            
            // Query Booking details with null checks
            List<Booking__c> bookings = [
                SELECT Id, Name,
                       Project__c, Project__r.Name,
                       Unit__c, Unit__r.Name,
                       Total_Payable_Amount__c, Grand_Total__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];

            if (bookings.isEmpty()) {
                result.errorMessage = 'Booking record not found';
                return result;
            }

            Booking__c booking = bookings[0];
            result.bookingName = booking.Name;
            result.projectName = booking.Project__c != null ? booking.Project__r.Name : 'N/A';
            result.unitName = booking.Unit__c != null ? booking.Unit__r.Name : 'N/A';
            result.totalPayableAmount = booking.Total_Payable_Amount__c != null
                ? booking.Total_Payable_Amount__c
                : (booking.Grand_Total__c != null ? booking.Grand_Total__c : 0);
            
            // Query all Payment Schedules
            List<Payment_Schedule__c> schedules = [
                SELECT Id, Name, Milestone_Name__c, Status__c,
                       Amount__c, Percentage__c, Pending_Amount__c,
                       Interest_Pending__c,
                       Payment_Schedule_Amount__c, GST_Amount__c,
                       Payment_Schedule_Amount_Paid__c, GST_Amount_Paid__c,
                       Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c
                FROM Payment_Schedule__c
                WHERE Booking__c = :bookingId
                ORDER BY CreatedDate ASC
            ];
            
            // Process schedules and calculate next demand
            List<PaymentScheduleWrapper> wrappers = new List<PaymentScheduleWrapper>();
            Decimal totalPendingForNextDemand = 0;
            Decimal totalInterestForNextDemand = 0;
            Integer completedCount = 0;
            String lastCompletedMilestone = 'No completed milestones';
            
            for (Payment_Schedule__c schedule : schedules) {
                PaymentScheduleWrapper wrapper = new PaymentScheduleWrapper();
                wrapper.id = schedule.Id;
                wrapper.name = schedule.Name != null ? schedule.Name : '';
                wrapper.milestoneName = schedule.Milestone_Name__c != null ? schedule.Milestone_Name__c : '';
                wrapper.status = schedule.Status__c != null ? schedule.Status__c : '';
                wrapper.amount = schedule.Amount__c != null ? schedule.Amount__c : 0;
                wrapper.percentage = schedule.Percentage__c != null ? schedule.Percentage__c : 0;
                wrapper.pendingAmount = schedule.Pending_Amount__c != null ? schedule.Pending_Amount__c : 0;
                wrapper.interestPending = schedule.Interest_Pending__c != null ? schedule.Interest_Pending__c : 0;
                wrapper.baseAmount = schedule.Payment_Schedule_Amount__c;
                wrapper.gstAmount = schedule.GST_Amount__c;
                wrapper.basePending = schedule.Payment_Schedule_Amount_Pending__c;
                wrapper.gstPending = schedule.GST_Amount_Pending__c;
                wrapper.basePaid = schedule.Payment_Schedule_Amount_Paid__c;
                wrapper.gstPaid = schedule.GST_Amount_Paid__c;
                
                // Determine status color and icon
                wrapper.isPaid = (schedule.Status__c == PostSalesConstants.SCHEDULE_STATUS_PAID);
                wrapper.isCompleted = (schedule.Status__c == PostSalesConstants.SCHEDULE_STATUS_COMPLETED);
                wrapper.statusColor = PostSalesConstants.getStatusColor(schedule.Status__c);
                wrapper.statusIcon = PostSalesConstants.getStatusIcon(schedule.Status__c);

                if (schedule.Status__c == PostSalesConstants.SCHEDULE_STATUS_COMPLETED) {
                    completedCount++;

                    // Track last completed milestone
                    lastCompletedMilestone = schedule.Milestone_Name__c != null ?
                                            schedule.Milestone_Name__c : schedule.Name;

                    // Accumulate pending amounts for next demand
                    totalPendingForNextDemand += (schedule.Pending_Amount__c != null ? schedule.Pending_Amount__c : 0);
                    totalInterestForNextDemand += (schedule.Interest_Pending__c != null ? schedule.Interest_Pending__c : 0);
                }
                
                // Format currency values
                wrapper.formattedAmount = formatCurrency(wrapper.amount);
                wrapper.formattedPending = formatCurrency(wrapper.pendingAmount);
                wrapper.formattedInterest = formatCurrency(wrapper.interestPending);
                
                wrappers.add(wrapper);
            }
            
            // Build Next Demand Wrapper
            NextDemandWrapper nextDemand = new NextDemandWrapper();
            nextDemand.totalPendingAmount = totalPendingForNextDemand;
            nextDemand.totalInterestPending = totalInterestForNextDemand;
            nextDemand.grandTotal = totalPendingForNextDemand + totalInterestForNextDemand;
            nextDemand.hasInterest = (totalInterestForNextDemand > 0);
            nextDemand.completedScheduleCount = completedCount;
            nextDemand.formattedPending = formatCurrency(nextDemand.totalPendingAmount);
            nextDemand.formattedInterest = formatCurrency(nextDemand.totalInterestPending);
            nextDemand.formattedTotal = formatCurrency(nextDemand.grandTotal);
            nextDemand.lastCompletedMilestone = lastCompletedMilestone;
            
            // Build result
            result.schedules = wrappers;
            result.nextDemand = nextDemand;
            result.success = true;
            
            return result;
            
        } catch (Exception e) {
            result.errorMessage = 'Error: ' + e.getMessage() + ' (Line: ' + e.getLineNumber() + ')';
            result.success = false;
            System.debug('Error in getPaymentSchedules: ' + e.getMessage() + ' - ' + e.getStackTraceString());
            return result;
        }
    }
    
    /**
     * @description Format currency value
     * @param value Decimal value to format
     * @return Formatted currency string
     */
    private static String formatCurrency(Decimal value) {
        return PostSalesConstants.formatCurrency(value);
    }

    /**
     * @description Save edited payment schedule amounts.
     *              Only updates Amount__c, Pending_Amount__c, Payment_Schedule_Amount__c
     *              for schedules where demand has not been raised.
     * @param amountsJson JSON map of scheduleId -> newAmount
     */
    /**
     * @description Save edited payment schedule amounts with validation.
     *              Validates that total of all schedule amounts equals booking's
     *              Total_Payable_Amount__c before saving.
     * @param bookingId The booking these schedules belong to
     * @param amountsJson JSON map of scheduleId -> newAmount
     */
    @AuraEnabled
    public static void saveScheduleAmounts(String bookingId, String amountsJson) {
        try {
            Map<String, Object> amounts = (Map<String, Object>) JSON.deserializeUntyped(amountsJson);
            if (amounts.isEmpty()) return;

            // Get booking total
            Booking__c booking = [
                SELECT Id, Total_Payable_Amount__c, Grand_Total__c
                FROM Booking__c
                WHERE Id = :bookingId
                LIMIT 1
            ];

            Decimal bookingTotal = booking.Total_Payable_Amount__c != null
                ? booking.Total_Payable_Amount__c
                : (booking.Grand_Total__c != null ? booking.Grand_Total__c : 0);

            // Get ALL schedules for this booking (not just edited ones)
            List<Payment_Schedule__c> allSchedules = [
                SELECT Id, Amount__c, Pending_Amount__c, Amount_Paid__c,
                       Payment_Schedule_Amount__c, GST_Amount__c,
                       Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c,
                       Demand_Raised__c, Status__c
                FROM Payment_Schedule__c
                WHERE Booking__c = :bookingId
            ];

            // Calculate what the new total would be after applying changes
            Decimal newTotal = 0;
            List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();

            for (Payment_Schedule__c ps : allSchedules) {
                Object newAmountObj = amounts.get(ps.Id);

                if (newAmountObj != null) {
                    // This schedule is being edited
                    if (ps.Demand_Raised__c == true ||
                        ps.Status__c == PostSalesConstants.SCHEDULE_STATUS_PAID ||
                        ps.Status__c == PostSalesConstants.SCHEDULE_STATUS_COMPLETED) {
                        throw new AuraHandledException(
                            'Cannot edit schedule ' + ps.Id + ' — demand already raised or schedule is paid/completed.'
                        );
                    }

                    Decimal newAmount = Decimal.valueOf(String.valueOf(newAmountObj));
                    if (newAmount < 0) {
                        throw new AuraHandledException('Amount cannot be negative.');
                    }

                    newTotal += newAmount;

                    Decimal paid = ps.Amount_Paid__c != null ? ps.Amount_Paid__c : 0;
                    ps.Amount__c = newAmount;
                    ps.Pending_Amount__c = Math.max(0, newAmount - paid);
                    ps.Payment_Schedule_Amount__c = newAmount;
                    ps.Payment_Schedule_Amount_Pending__c = Math.max(0, newAmount - paid);
                    toUpdate.add(ps);
                } else {
                    // Unchanged schedule — use existing amount
                    newTotal += (ps.Amount__c != null ? ps.Amount__c : 0);
                }
            }

            // Validate total matches booking total
            if (bookingTotal > 0 && newTotal.setScale(2) != bookingTotal.setScale(2)) {
                throw new AuraHandledException(
                    'Total of all schedule amounts (₹' + newTotal.setScale(2).format() +
                    ') must equal the booking total payable amount (₹' + bookingTotal.setScale(2).format() +
                    '). Difference: ₹' + (bookingTotal - newTotal).setScale(2).format()
                );
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving amounts: ' + e.getMessage());
        }
    }
}