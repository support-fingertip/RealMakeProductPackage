@isTest
private class DiscountApprovalEscalationBatchTest {

    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        String jobId = System.schedule(
            'Test Escalation',
            '0 0 * * * ?',
            new DiscountApprovalEscalationBatch()
        );
        Test.stopTest();
        System.assertNotEquals(null, jobId, 'Scheduled job should be created');
    }

    @isTest
    static void testBatchWithNoRecords() {
        Test.startTest();
        Database.executeBatch(new DiscountApprovalEscalationBatch(), 50);
        Test.stopTest();
        // Should complete without errors when no pending cost sheets exist
    }
}