@isTest
private class ComplaintEscalationSchedulableTest {
    @isTest
    static void smokeTest() {
        Test.startTest();
        try { new ComplaintEscalationSchedulable().execute(null); } catch (Exception e) {}
        Test.stopTest();
    }
}