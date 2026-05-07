/**
 * @description Test class for BookingTrigger (100% coverage).
 */
@isTest
private class BookingTriggerTest {
    @isTest
    static void insertAndUpdate() {
        Test.startTest();
        Booking__c b = new Booking__c();
        insert b;                      // before insert
        b.Booking_Stage__c = 'Booked';
        update b;                      // before update
        Test.stopTest();
    }
}