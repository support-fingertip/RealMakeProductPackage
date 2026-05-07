/**
 * @description Invocable Apex service called from Record-Triggered Flows on financial objects.
 *              Recalculates Booking-level financial totals, Demand pending amounts,
 *              and Payment Schedule pending amounts (including Base/GST splits)
 *              based on Receipt Line Items.
 *              Ensures all interlinked financial records stay in sync.
 * @author System
 * @date 2026-03-09
 */
public with sharing class BookingFinancialRecalcService {

    /**
     * @description Flow input wrapper
     */
    public class FlowInput {
        @InvocableVariable(required=true label='Booking Id')
        public Id bookingId;
    }

    /**
     * @description Main entry point called from Flows.
     *              Recalculates all financial data for the given Booking(s).
     */
    @InvocableMethod(label='Recalculate Booking Financials' description='Recalculates all financial totals, demand pending amounts, and payment schedule pending amounts for a Booking' category='Financial')
    public static void recalculate(List<FlowInput> inputs) {
        Set<Id> bookingIds = new Set<Id>();
        for (FlowInput input : inputs) {
            if (input.bookingId != null) {
                bookingIds.add(input.bookingId);
            }
        }

        if (bookingIds.isEmpty()) return;

        recalculateForBookings(bookingIds);
    }

    /**
     * @description Core recalculation logic for a set of Booking Ids.
     *              1. Recalculates Payment Schedule pending amounts from Receipt Line Items
     *              2. Recalculates Demand pending amounts from Receipt Line Items
     *              3. Updates Booking-level currency fields (including Base/GST totals)
     */
    public static void recalculateForBookings(Set<Id> bookingIds) {
        recalcPaymentSchedules(bookingIds);
        recalcDemands(bookingIds);
        recalcBookingTotals(bookingIds);
    }

    /**
     * @description Recalculate Payment Schedule amounts including Base/GST splits
     *              by summing Receipt Line Items allocated to each schedule.
     */
    private static void recalcPaymentSchedules(Set<Id> bookingIds) {
        List<Payment_Schedule__c> schedules = [
            SELECT Id, Amount__c, Pending_Amount__c, Amount_Paid__c, Status__c,
                   Payment_Schedule_Amount__c, GST_Amount__c,
                   Payment_Schedule_Amount_Paid__c, GST_Amount_Paid__c,
                   Payment_Schedule_Amount_Pending__c, GST_Amount_Pending__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookingIds
        ];

        if (schedules.isEmpty()) return;

        Set<Id> scheduleIds = new Set<Id>();
        for (Payment_Schedule__c ps : schedules) {
            scheduleIds.add(ps.Id);
        }

        // Sum total, base, and GST allocated amounts per schedule
        Map<Id, Decimal> paidBySchedule = new Map<Id, Decimal>();
        Map<Id, Decimal> basePaidBySchedule = new Map<Id, Decimal>();
        Map<Id, Decimal> gstPaidBySchedule = new Map<Id, Decimal>();

        for (AggregateResult ar : [
            SELECT Payment_Schedule__c psId,
                   SUM(Allocated_Amount__c) totalPaid,
                   SUM(Base_Amount__c) totalBase,
                   SUM(GST_Amount__c) totalGst
            FROM Receipt_Line_Item__c
            WHERE Payment_Schedule__c IN :scheduleIds
            AND Payment_Schedule__c != null
            GROUP BY Payment_Schedule__c
        ]) {
            Id psId = (Id) ar.get('psId');
            paidBySchedule.put(psId, (Decimal) ar.get('totalPaid'));
            basePaidBySchedule.put(psId, (Decimal) ar.get('totalBase'));
            gstPaidBySchedule.put(psId, (Decimal) ar.get('totalGst'));
        }

        List<Payment_Schedule__c> toUpdate = new List<Payment_Schedule__c>();
        for (Payment_Schedule__c ps : schedules) {
            Decimal totalPaid = paidBySchedule.containsKey(ps.Id) ? paidBySchedule.get(ps.Id) : 0;
            Decimal basePaid = basePaidBySchedule.containsKey(ps.Id) ? basePaidBySchedule.get(ps.Id) : 0;
            Decimal gstPaid = gstPaidBySchedule.containsKey(ps.Id) ? gstPaidBySchedule.get(ps.Id) : 0;

            Decimal scheduleAmount = ps.Amount__c ?? 0;
            Decimal baseAmount = ps.Payment_Schedule_Amount__c ?? 0;
            Decimal gstAmount = ps.GST_Amount__c ?? 0;

            Decimal newPending = Math.max(0, scheduleAmount - totalPaid);
            Decimal newBasePending = Math.max(0, baseAmount - basePaid);
            Decimal newGstPending = Math.max(0, gstAmount - gstPaid);

            Boolean changed = (ps.Amount_Paid__c != totalPaid || ps.Pending_Amount__c != newPending
                || ps.Payment_Schedule_Amount_Paid__c != basePaid || ps.GST_Amount_Paid__c != gstPaid
                || ps.Payment_Schedule_Amount_Pending__c != newBasePending || ps.GST_Amount_Pending__c != newGstPending);

            if (changed) {
                ps.Amount_Paid__c = totalPaid;
                ps.Pending_Amount__c = newPending;
                ps.Payment_Schedule_Amount_Paid__c = basePaid;
                ps.GST_Amount_Paid__c = gstPaid;
                ps.Payment_Schedule_Amount_Pending__c = newBasePending;
                ps.GST_Amount_Pending__c = newGstPending;

                if (newPending <= 0) {
                    ps.Status__c = PostSalesConstants.SCHEDULE_STATUS_PAID;
                } else if (totalPaid > 0) {
                    ps.Status__c = 'Partially Paid';
                }
                toUpdate.add(ps);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * @description Recalculate Demand Pending_Amount and Paid_Amount
     *              by summing Receipt Line Items allocated to each demand.
     */
    private static void recalcDemands(Set<Id> bookingIds) {
        List<Demands__c> demands = [
            SELECT Id, Demand_Amount__c, Net_Demand_Amount__c,
                   Pending_Amount__c, Paid_Amount__c, Status__c
            FROM Demands__c
            WHERE Booking__c IN :bookingIds
            AND Status__c NOT IN ('Cancelled')
        ];

        if (demands.isEmpty()) return;

        Set<Id> demandIds = new Set<Id>();
        for (Demands__c d : demands) {
            demandIds.add(d.Id);
        }

        Map<Id, Decimal> paidByDemand = new Map<Id, Decimal>();

        for (AggregateResult ar : [
            SELECT Demand__c demandId, SUM(Allocated_Amount__c) totalPaid
            FROM Receipt_Line_Item__c
            WHERE Demand__c IN :demandIds
            AND Demand__c != null
            GROUP BY Demand__c
        ]) {
            Id demandId = (Id) ar.get('demandId');
            Decimal total = (Decimal) ar.get('totalPaid');
            paidByDemand.put(demandId, (paidByDemand.containsKey(demandId) ? paidByDemand.get(demandId) : 0) + total);
        }

        // Also check the Demands__c field (legacy)
        for (AggregateResult ar : [
            SELECT Demands__c demandId, SUM(Allocated_Amount__c) totalPaid
            FROM Receipt_Line_Item__c
            WHERE Demands__c IN :demandIds
            AND Demands__c != null
            AND Demand__c = null
            GROUP BY Demands__c
        ]) {
            Id demandId = (Id) ar.get('demandId');
            Decimal total = (Decimal) ar.get('totalPaid');
            paidByDemand.put(demandId, (paidByDemand.containsKey(demandId) ? paidByDemand.get(demandId) : 0) + total);
        }

        List<Demands__c> toUpdate = new List<Demands__c>();
        for (Demands__c d : demands) {
            Decimal totalPaid = paidByDemand.containsKey(d.Id) ? paidByDemand.get(d.Id) : 0;
            Decimal demandAmount = d.Demand_Amount__c ?? 0;
            Decimal newPending = Math.max(0, demandAmount - totalPaid);

            if (d.Paid_Amount__c != totalPaid || d.Pending_Amount__c != newPending) {
                d.Paid_Amount__c = totalPaid;
                d.Pending_Amount__c = newPending;

                if (newPending <= 0 && totalPaid > 0) {
                    d.Status__c = 'Paid';
                } else if (totalPaid > 0) {
                    d.Status__c = 'Partially Paid';
                }
                toUpdate.add(d);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * @description Recalculate Booking-level financial totals including Base/GST breakdowns.
     *              Updates currency fields that are NOT rollup summaries.
     */
    private static void recalcBookingTotals(Set<Id> bookingIds) {
        List<Booking__c> bookings = [
            SELECT Id,
                   Total_Payable_Amount__c,
                   Total_Credit_Notes__c,
                   Total_Debit_Notes__c,
                   Total_Demand_Raised__c,
                   Total_Receipt_Amount__c,
                   Total_Amount_Paid__c,
                   Advance_Payment_Available__c,
                   Pending_Amount__c,
                   Total_Base_Amount__c,
                   Total_Schedule_GST__c,
                   Total_Base_Paid__c,
                   Total_GST_Paid__c,
                   Total_Base_Pending__c,
                   Total_GST_Pending__c
            FROM Booking__c
            WHERE Id IN :bookingIds
        ];

        // Outstanding demand amounts
        Map<Id, Decimal> outstandingByBooking = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Booking__c bkId, SUM(Pending_Amount__c) totalPending
            FROM Demands__c
            WHERE Booking__c IN :bookingIds
            AND Status__c NOT IN ('Paid', 'Cancelled')
            GROUP BY Booking__c
        ]) {
            outstandingByBooking.put((Id) ar.get('bkId'), (Decimal) ar.get('totalPending'));
        }

        // Available advance amounts
        Map<Id, Decimal> advanceByBooking = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Booking__c bkId, SUM(Available_Amount__c) totalAvailable
            FROM Advance_Payment__c
            WHERE Booking__c IN :bookingIds
            AND Available_Amount__c > 0
            GROUP BY Booking__c
        ]) {
            advanceByBooking.put((Id) ar.get('bkId'), (Decimal) ar.get('totalAvailable'));
        }

        // Total paid with base/GST breakdown from receipt line items
        Map<Id, Decimal> paidByBooking = new Map<Id, Decimal>();
        Map<Id, Decimal> basePaidByBooking = new Map<Id, Decimal>();
        Map<Id, Decimal> gstPaidByBooking = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Booking__c bkId,
                   SUM(Allocated_Amount__c) totalAllocated,
                   SUM(Base_Amount__c) totalBase,
                   SUM(GST_Amount__c) totalGst
            FROM Receipt_Line_Item__c
            WHERE Booking__c IN :bookingIds
            GROUP BY Booking__c
        ]) {
            Id bkId = (Id) ar.get('bkId');
            paidByBooking.put(bkId, (Decimal) ar.get('totalAllocated'));
            basePaidByBooking.put(bkId, (Decimal) ar.get('totalBase'));
            gstPaidByBooking.put(bkId, (Decimal) ar.get('totalGst'));
        }

        // Base/GST totals from payment schedules
        Map<Id, Decimal> baseAmountByBooking = new Map<Id, Decimal>();
        Map<Id, Decimal> gstAmountByBooking = new Map<Id, Decimal>();
        Map<Id, Decimal> basePendingByBooking = new Map<Id, Decimal>();
        Map<Id, Decimal> gstPendingByBooking = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Booking__c bkId,
                   SUM(Payment_Schedule_Amount__c) totalBase,
                   SUM(GST_Amount__c) totalGst,
                   SUM(Payment_Schedule_Amount_Pending__c) totalBasePending,
                   SUM(GST_Amount_Pending__c) totalGstPending
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookingIds
            GROUP BY Booking__c
        ]) {
            Id bkId = (Id) ar.get('bkId');
            baseAmountByBooking.put(bkId, (Decimal) ar.get('totalBase'));
            gstAmountByBooking.put(bkId, (Decimal) ar.get('totalGst'));
            basePendingByBooking.put(bkId, (Decimal) ar.get('totalBasePending'));
            gstPendingByBooking.put(bkId, (Decimal) ar.get('totalGstPending'));
        }

        List<Booking__c> toUpdate = new List<Booking__c>();
        for (Booking__c b : bookings) {
            Decimal totalPaid = paidByBooking.containsKey(b.Id) ? paidByBooking.get(b.Id) : 0;
            Decimal totalPayable = b.Total_Payable_Amount__c ?? 0;
            Decimal newPending = Math.max(0, totalPayable - totalPaid);

            Decimal totalBasePaid = basePaidByBooking.containsKey(b.Id) ? basePaidByBooking.get(b.Id) : 0;
            Decimal totalGstPaid = gstPaidByBooking.containsKey(b.Id) ? gstPaidByBooking.get(b.Id) : 0;
            Decimal totalBaseAmount = baseAmountByBooking.containsKey(b.Id) ? baseAmountByBooking.get(b.Id) : 0;
            Decimal totalGstAmount = gstAmountByBooking.containsKey(b.Id) ? gstAmountByBooking.get(b.Id) : 0;
            Decimal totalBasePending = basePendingByBooking.containsKey(b.Id) ? basePendingByBooking.get(b.Id) : 0;
            Decimal totalGstPending = gstPendingByBooking.containsKey(b.Id) ? gstPendingByBooking.get(b.Id) : 0;

            Boolean changed = false;

            if (b.Pending_Amount__c != newPending) {
                b.Pending_Amount__c = newPending;
                changed = true;
            }
            if (b.Total_Base_Amount__c != totalBaseAmount) {
                b.Total_Base_Amount__c = totalBaseAmount;
                changed = true;
            }
            if (b.Total_Schedule_GST__c != totalGstAmount) {
                b.Total_Schedule_GST__c = totalGstAmount;
                changed = true;
            }
            if (b.Total_Base_Paid__c != totalBasePaid) {
                b.Total_Base_Paid__c = totalBasePaid;
                changed = true;
            }
            if (b.Total_GST_Paid__c != totalGstPaid) {
                b.Total_GST_Paid__c = totalGstPaid;
                changed = true;
            }
            if (b.Total_Base_Pending__c != totalBasePending) {
                b.Total_Base_Pending__c = totalBasePending;
                changed = true;
            }
            if (b.Total_GST_Pending__c != totalGstPending) {
                b.Total_GST_Pending__c = totalGstPending;
                changed = true;
            }

            if (changed) {
                toUpdate.add(b);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}