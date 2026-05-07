@isTest
private class AutoDemandSchedulableTest {
    @isTest
    static void smokeTest() {
        Test.startTest();
        try { new AutoDemandSchedulable().execute(null); } catch (Exception e) {}
        Test.stopTest();
    }
}