@isTest
private class BookingCancellationHandlerTest {

    private static Booking__c createTestBooking() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('CancelProj');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'CAN-01');
        Lead__c l = TestDataFactory.createLead(p.Id, 'Cancel', '9800000020');
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = l.Id, Unit__c = u.Id);
        insert cs;
        Booking__c bk = new Booking__c(Lead__c = l.Id, Project__c = p.Id, Unit__c = u.Id, Tower__c = t.Id, Cost_Sheet__c = cs.Id, Booking_Date__c = Date.today(), Status__c = 'Approved, Active', Owner__c = UserInfo.getUserId());
        insert bk;
        return bk;
    }

    @isTest
    static void testCancelBookingNullId() {
        Test.startTest();
        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = null;
        List<BookingCancellationHandler.CancellationResult> results = BookingCancellationHandler.cancelBookings(
            new List<BookingCancellationHandler.CancellationRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('required'), 'Should require booking ID');
    }

    @isTest
    static void testCancelBookingSuccess() {
        Booking__c bk = createTestBooking();

        Test.startTest();
        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = bk.Id;
        List<BookingCancellationHandler.CancellationResult> results = BookingCancellationHandler.cancelBookings(
            new List<BookingCancellationHandler.CancellationRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'Cancellation should succeed: ' + results[0].message);
        System.assert(results[0].message.contains('released'), 'Should indicate unit released');

        // Verify unit is released
        Unit__c unit = [SELECT Status__c FROM Unit__c WHERE Id = :bk.Unit__c];
        System.assertEquals('Available', unit.Status__c);
    }

    @isTest
    static void testCancelBookingNoUnit() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('NoUnitProj');
        Booking__c bk = new Booking__c(Project__c = p.Id, Booking_Date__c = Date.today(), Status__c = 'Approved, Active', Owner__c = UserInfo.getUserId());
        insert bk;

        Test.startTest();
        BookingCancellationHandler.CancellationRequest req = new BookingCancellationHandler.CancellationRequest();
        req.bookingId = bk.Id;
        List<BookingCancellationHandler.CancellationResult> results = BookingCancellationHandler.cancelBookings(
            new List<BookingCancellationHandler.CancellationRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Should succeed even without unit');
        System.assert(results[0].message.contains('No Unit'), 'Should note no unit linked');
    }

    @isTest
    static void testCancellationResultWrapper() {
        BookingCancellationHandler.CancellationResult res = new BookingCancellationHandler.CancellationResult();
        res.success = false;
        res.message = 'test';
        System.assertEquals(false, res.success);
    }
}