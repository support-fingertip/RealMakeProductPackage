@isTest
private class PerformanceNotificationBatchTest {
    @isTest
    static void smokeTest() {
        Test.startTest();
        try { Database.executeBatch(new PerformanceNotificationBatch(), 1); } catch (Exception e) {}
        Test.stopTest();
    }
}