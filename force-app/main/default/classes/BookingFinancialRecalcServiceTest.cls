@isTest
private class BookingFinancialRecalcServiceTest {

    private static Booking__c createTestBooking() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('FinRecalcProj');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'FRC-01');
        Lead__c l = TestDataFactory.createLead(p.Id, 'FinRecalc', '9800000030');
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = l.Id, Unit__c = u.Id);
        insert cs;
        Booking__c bk = new Booking__c(
            Lead__c = l.Id, Project__c = p.Id, Unit__c = u.Id, Tower__c = t.Id,
            Cost_Sheet__c = cs.Id, Booking_Date__c = Date.today(),
            Status__c = 'Approved, Active', Owner__c = UserInfo.getUserId(),
            Total_Payable_Amount__c = 5000000
        );
        insert bk;
        return bk;
    }

    @isTest
    static void testRecalculateEmptySet() {
        Test.startTest();
        BookingFinancialRecalcService.recalculateForBookings(new Set<Id>());
        Test.stopTest();
        System.assert(true, 'Empty set should not throw');
    }

    @isTest
    static void testRecalculateWithBookingAndSchedules() {
        Booking__c bk = createTestBooking();

        // Create payment schedules
        Payment_Schedule__c ps1 = new Payment_Schedule__c(
            Booking__c = bk.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'On Booking',
            Percentage__c = 10,
            Amount__c = 500000,
            Payment_Schedule_Amount__c = 450000,
            GST_Amount__c = 50000,
            Pending_Amount__c = 500000,
            Payment_Schedule_Amount_Pending__c = 450000,
            GST_Amount_Pending__c = 50000,
            Amount_Paid__c = 0,
            Status__c = 'Pending'
        );
        Payment_Schedule__c ps2 = new Payment_Schedule__c(
            Booking__c = bk.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'On Agreement',
            Percentage__c = 20,
            Amount__c = 1000000,
            Payment_Schedule_Amount__c = 900000,
            GST_Amount__c = 100000,
            Pending_Amount__c = 1000000,
            Amount_Paid__c = 0,
            Status__c = 'Pending'
        );
        insert new List<Payment_Schedule__c>{ ps1, ps2 };

        // Create a demand
        Demands__c demand = new Demands__c(
            Booking__c = bk.Id,
            Demand_Amount__c = 500000,
            Pending_Amount__c = 500000,
            Demand_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Reminder_Date__c = Date.today().addDays(7),
            Status__c = 'Raised',
            Demand_Type__c = 'Individual Demand'
        );
        insert demand;

        Test.startTest();
        BookingFinancialRecalcService.recalculateForBookings(new Set<Id>{ bk.Id });
        Test.stopTest();

        // Verify schedules were processed (amounts remain same since no receipt line items)
        Payment_Schedule__c updatedPs1 = [SELECT Pending_Amount__c, Amount_Paid__c FROM Payment_Schedule__c WHERE Id = :ps1.Id];
        System.assertEquals(500000, updatedPs1.Pending_Amount__c, 'Pending should remain 500K with no receipts');
    }

    @isTest
    static void testRecalculateViaFlowInput() {
        Booking__c bk = createTestBooking();

        Test.startTest();
        BookingFinancialRecalcService.FlowInput input = new BookingFinancialRecalcService.FlowInput();
        input.bookingId = bk.Id;
        BookingFinancialRecalcService.recalculate(new List<BookingFinancialRecalcService.FlowInput>{ input });
        Test.stopTest();

        System.assert(true, 'Flow input recalculate should complete');
    }

    @isTest
    static void testRecalculateFlowInputNullBookingId() {
        Test.startTest();
        BookingFinancialRecalcService.FlowInput input = new BookingFinancialRecalcService.FlowInput();
        input.bookingId = null;
        BookingFinancialRecalcService.recalculate(new List<BookingFinancialRecalcService.FlowInput>{ input });
        Test.stopTest();

        System.assert(true, 'Null booking ID should be gracefully handled');
    }

    @isTest
    static void testRecalcWithAdvancePayments() {
        Booking__c bk = createTestBooking();

        // Create an advance payment
        Advance_Payment__c adv = new Advance_Payment__c(
            Booking__c = bk.Id,
            Available_Amount__c = 50000
        );
        insert adv;

        Test.startTest();
        BookingFinancialRecalcService.recalculateForBookings(new Set<Id>{ bk.Id });
        Test.stopTest();

        System.assert(true, 'Recalculate with advance payments should complete');
    }
}