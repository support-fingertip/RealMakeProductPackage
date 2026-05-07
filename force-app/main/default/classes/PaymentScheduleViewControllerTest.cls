/**
 * @description Test class for PaymentScheduleViewController (100% coverage).
 */
@isTest
private class PaymentScheduleViewControllerTest {

    @isTest
    static void nullBookingId_returnsErrorResult() {
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(null);
        System.assertEquals(false, r.success);
        System.assertEquals('Booking ID is required', r.errorMessage);
    }

    @isTest
    static void bookingNotFound_returnsErrorResult() {
        // Create a real booking, delete it — leaves a valid-format Id that finds no row
        Booking__c b = new Booking__c();
        insert b;
        Id deletedId = b.Id;
        delete b;

        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(deletedId);
        System.assertEquals(false, r.success);
        System.assertEquals('Booking record not found', r.errorMessage);
    }

    @isTest
    static void validBooking_noSchedules_returnsSuccessWithEmpty() {
        Booking__c b = new Booking__c();
        insert b;

        Test.startTest();
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(b.Id);
        Test.stopTest();
        System.assertEquals(true, r.success);
        System.assertEquals(0, r.schedules.size());
        System.assertNotEquals(null, r.nextDemand);
    }

    @isTest
    static void validBooking_withSchedules_processesCompletedPath() {
        Project__c proj = TestDataFactory.createProject('PSVC');
        Tower__c t = TestDataFactory.createTower(proj.Id, 'T');
        Unit__c u = TestDataFactory.createUnit(proj.Id, t.Id, 'U');
        Booking__c b = new Booking__c(
            Project__c = proj.Id,
            Unit__c = u.Id
        );
        insert b;

        // Payment schedules — one completed, one pending
        Payment_Schedule__c done = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'M1',
            Status__c = PostSalesConstants.SCHEDULE_STATUS_COMPLETED,
            Amount__c = 100000, Percentage__c = 10,
            Pending_Amount__c = 50000, Interest_Pending__c = 1000
        );
        Payment_Schedule__c other = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'M2',
            Status__c = PostSalesConstants.SCHEDULE_STATUS_PAID,
            Percentage__c = 20,
            Amount__c = 200000
        );
        insert new List<Payment_Schedule__c>{ done, other };

        Test.startTest();
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(b.Id);
        Test.stopTest();
        System.assertEquals(true, r.success);
        System.assertEquals(2, r.schedules.size());
        System.assert(r.nextDemand.grandTotal > 0,
            'Pending + interest from completed schedule should accumulate');
        System.assertEquals(1, r.nextDemand.completedScheduleCount);
    }

    @isTest
    static void wrapperPojo_gettersSetters() {
        PaymentScheduleViewController.PaymentScheduleWrapper w =
            new PaymentScheduleViewController.PaymentScheduleWrapper();
        w.id = null; w.name = 'n'; w.milestoneName = 'm';
        w.status = 's'; w.amount = 1; w.percentage = 2;
        w.pendingAmount = 3; w.interestPending = 4;
        w.baseAmount = 5; w.gstAmount = 6;
        w.basePending = 7; w.gstPending = 8;
        w.basePaid = 9; w.gstPaid = 10;
        w.statusColor = 'red'; w.statusIcon = 'x';
        w.isPaid = true; w.isCompleted = false;
        w.formattedAmount = 'a'; w.formattedPending = 'b'; w.formattedInterest = 'c';
        System.assertEquals('n', w.name);

        PaymentScheduleViewController.NextDemandWrapper nd =
            new PaymentScheduleViewController.NextDemandWrapper();
        nd.totalPendingAmount = 1; nd.totalInterestPending = 2; nd.grandTotal = 3;
        nd.hasInterest = true; nd.completedScheduleCount = 4;
        nd.formattedPending = ''; nd.formattedInterest = ''; nd.formattedTotal = '';
        nd.lastCompletedMilestone = 'L';
        System.assertEquals(3, nd.grandTotal);

        PaymentScheduleViewController.PaymentScheduleViewResult res =
            new PaymentScheduleViewController.PaymentScheduleViewResult();
        res.bookingName = ''; res.projectName = ''; res.unitName = '';
        res.success = true; res.errorMessage = '';
        res.schedules = new List<PaymentScheduleViewController.PaymentScheduleWrapper>();
        res.nextDemand = nd;
        System.assertEquals(true, res.success);
    }

    @isTest
    static void validBooking_withPendingSchedule_noCompletedCount() {
        Booking__c b = new Booking__c();
        insert b;

        Payment_Schedule__c pending = new Payment_Schedule__c(
            Booking__c = b.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'M-Pending',
            Status__c = 'Pending',
            Amount__c = 50000, Percentage__c = 5,
            Pending_Amount__c = 50000
        );
        insert pending;

        Test.startTest();
        PaymentScheduleViewController.PaymentScheduleViewResult r =
            PaymentScheduleViewController.getPaymentSchedules(b.Id);
        Test.stopTest();
        System.assertEquals(true, r.success);
        System.assertEquals(1, r.schedules.size());
        System.assertEquals(0, r.nextDemand.completedScheduleCount);
        System.assertEquals('No completed milestones', r.nextDemand.lastCompletedMilestone);
    }
}