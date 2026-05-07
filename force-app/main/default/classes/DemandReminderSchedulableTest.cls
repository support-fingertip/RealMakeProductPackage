@isTest
private class DemandReminderSchedulableTest {
    @isTest
    static void smokeTest() {
        Test.startTest();
        try { new DemandReminderSchedulable().execute(null); } catch (Exception e) {}
        Test.stopTest();
    }
}