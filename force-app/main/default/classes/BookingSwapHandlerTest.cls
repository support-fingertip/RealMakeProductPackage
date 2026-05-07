@isTest
private class BookingSwapHandlerTest {

    private static Booking__c createTestBooking() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('SwapProj');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'SWP-01');
        Lead__c l = TestDataFactory.createLead(p.Id, 'Swap', '9800000010');
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = l.Id, Unit__c = u.Id);
        insert cs;
        Booking__c bk = new Booking__c(Lead__c = l.Id, Project__c = p.Id, Unit__c = u.Id, Tower__c = t.Id, Cost_Sheet__c = cs.Id, Booking_Date__c = Date.today(), Status__c = 'Approved, Active', Owner__c = UserInfo.getUserId());
        insert bk;
        return bk;
    }

    @isTest
    static void testSwapBookingNullOldBookingId() {
        Test.startTest();
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = null;
        req.newUnitId = null;
        req.newBookingStatus = null;
        List<BookingSwapHandler.SwapResult> results = BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Old Booking ID'), 'Should require old booking ID');
    }

    @isTest
    static void testSwapBookingNullNewUnitId() {
        Booking__c bk = createTestBooking();

        Test.startTest();
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = bk.Id;
        req.newUnitId = null;
        req.newBookingStatus = 'Draft';
        List<BookingSwapHandler.SwapResult> results = BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('New Unit ID'), 'Should require new unit ID');
    }

    @isTest
    static void testSwapBookingBlankStatus() {
        Booking__c bk = createTestBooking();

        Test.startTest();
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = bk.Id;
        req.newUnitId = bk.Unit__c;
        req.newBookingStatus = '';
        List<BookingSwapHandler.SwapResult> results = BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('New Booking Status'), 'Should require status');
    }

    @isTest
    static void testSwapBookingSuccess() {
        Booking__c bk = createTestBooking();

        // Create a new unit to swap to
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Tower__c t = [SELECT Id FROM Tower__c LIMIT 1];
        Unit__c newUnit = new Unit__c(
            Project__c = p.Id,
            Tower__c = t.Id,
            Unit_Number__c = 'SWP-02',
            Unit_Type__c = 'Apartment',
            BHK_Type__c = '2BHK',
            Carpet_Area__c = 900,
            Super_Builtup_Area__c = 1200,
            Base_Rate_Sqft__c = 5000,
            Base_Price__c = 6000000,
            Status__c = 'Available'
        );
        insert newUnit;

        Test.startTest();
        BookingSwapHandler.SwapRequest req = new BookingSwapHandler.SwapRequest();
        req.oldBookingId = bk.Id;
        req.newUnitId = newUnit.Id;
        req.newBookingStatus = 'Approved, Active';
        List<BookingSwapHandler.SwapResult> results = BookingSwapHandler.swapBookings(new List<BookingSwapHandler.SwapRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'Swap should succeed: ' + results[0].message);
        System.assertNotEquals(null, results[0].newBookingId, 'New booking ID should be returned');

        // Verify old booking is marked as swapped
        Booking__c oldBk = [SELECT Is_Swapped__c, Swap_Date__c, Swapped_To_Booking__c FROM Booking__c WHERE Id = :bk.Id];
        System.assertEquals(true, oldBk.Is_Swapped__c);
        System.assertEquals(Date.today(), oldBk.Swap_Date__c);
        System.assertEquals(results[0].newBookingId, oldBk.Swapped_To_Booking__c);

        // Verify new unit is Booked
        Unit__c updatedNewUnit = [SELECT Status__c FROM Unit__c WHERE Id = :newUnit.Id];
        System.assertEquals('Booked', updatedNewUnit.Status__c);
    }

    @isTest
    static void testChildCloneConfigConstructors() {
        // Test 2-arg constructor
        BookingSwapHandler.ChildCloneConfig config2 = new BookingSwapHandler.ChildCloneConfig('Co_Applicants__c', 'Booking__c');
        System.assertEquals('Co_Applicants__c', config2.objectApiName);
        System.assertEquals('Booking__c', config2.bookingLookupField);
        System.assertEquals(null, config2.lineItemObjectApiName);

        // Test 5-arg constructor
        BookingSwapHandler.ChildCloneConfig config5 = new BookingSwapHandler.ChildCloneConfig(
            'Receipt__c', 'Booking__c', 'Receipt_Line_Item__c', 'Receipt__c', 'Booking__c'
        );
        System.assertEquals('Receipt__c', config5.objectApiName);
        System.assertEquals('Receipt_Line_Item__c', config5.lineItemObjectApiName);
    }

    @isTest
    static void testSwapResultWrapper() {
        BookingSwapHandler.SwapResult result = new BookingSwapHandler.SwapResult();
        result.success = true;
        result.message = 'Test';
        result.newBookingId = null;
        System.assertEquals(true, result.success);
    }
}