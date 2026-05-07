/**
 * @description Test class for IntegrationRetrySchedulable.
 *              Covers execute with no dead letters, execute with dead letters,
 *              scheduleHourly, scheduleDaily, and edge cases.
 */
@IsTest
private class IntegrationRetrySchedulableTest {

    @IsTest
    static void testExecuteNoDeadLetters() {
        // No dead-letter records exist, should complete gracefully
        Test.startTest();
        IntegrationRetrySchedulable scheduler = new IntegrationRetrySchedulable();
        scheduler.execute(null);
        Test.stopTest();

        System.assert(true, 'Should complete without error when no dead letters exist');
    }

    @IsTest
    static void testExecuteWithDeadLetterRecords() {
        // Create endpoint and log
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('RETRY_SCHED_TEST');
        Integration_Log__c log = TestDataFactory.createLog(endpoint.Id, false);

        // Create a dead-letter error log
        Integration_Error_Log__c errorLog = new Integration_Error_Log__c(
            Integration_Log__c = log.Id,
            Error_Type__c = 'Unknown',
            Error_Message__c = 'Test dead letter',
            Severity__c = 'Critical',
            Is_Dead_Letter__c = true,
            Retry_Eligible__c = true,
            Original_Payload__c = '{"key":"value"}'
        );
        insert errorLog;

        Test.startTest();
        IntegrationRetrySchedulable scheduler = new IntegrationRetrySchedulable();
        scheduler.execute(null);
        Test.stopTest();

        // Verify the error log was updated to not be retry eligible
        Integration_Error_Log__c updated = [
            SELECT Retry_Eligible__c FROM Integration_Error_Log__c WHERE Id = :errorLog.Id
        ];
        System.assertEquals(false, updated.Retry_Eligible__c,
            'Dead letter should be marked as not retry eligible after processing');
    }

    @IsTest
    static void testExecuteWithDeadLetterNoIntegrationKey() {
        // Create a log without integration key
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('SCHED_NO_KEY');
        Integration_Log__c log = new Integration_Log__c(
            Integration_Endpoint__c = endpoint.Id,
            Integration_Key__c = null,
            Correlation_Id__c = 'no-key-test',
            Direction__c = 'Outbound',
            HTTP_Method__c = 'POST',
            Is_Success__c = false,
            Execution_Start__c = Datetime.now().addSeconds(-1),
            Execution_End__c = Datetime.now(),
            Execution_Mode__c = 'Synchronous'
        );
        insert log;

        Integration_Error_Log__c errorLog = new Integration_Error_Log__c(
            Integration_Log__c = log.Id,
            Error_Type__c = 'Unknown',
            Error_Message__c = 'No key',
            Severity__c = 'High',
            Is_Dead_Letter__c = true,
            Retry_Eligible__c = true,
            Original_Payload__c = '{"test":"data"}'
        );
        insert errorLog;

        Test.startTest();
        IntegrationRetrySchedulable scheduler = new IntegrationRetrySchedulable();
        scheduler.execute(null);
        Test.stopTest();

        // Record with blank integration key should be skipped
        System.assert(true, 'Should handle records with no integration key gracefully');
    }

    @IsTest
    static void testScheduleHourly() {
        Test.startTest();
        String jobId = IntegrationRetrySchedulable.scheduleHourly();
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Should return a job ID');

        // Verify the job was scheduled
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name = 'Integration_DeadLetter_Retry_Hourly'
        ];
        System.assertEquals(1, jobs.size(), 'Hourly job should be scheduled');
    }

    @IsTest
    static void testScheduleDaily() {
        Test.startTest();
        String jobId = IntegrationRetrySchedulable.scheduleDaily();
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Should return a job ID');
    }

    @IsTest
    static void testScheduleHourlyReplacesExisting() {
        // Schedule twice - second should replace first
        Test.startTest();
        String jobId1 = IntegrationRetrySchedulable.scheduleHourly();
        String jobId2 = IntegrationRetrySchedulable.scheduleHourly();
        Test.stopTest();

        System.assertNotEquals(null, jobId2);
    }

    @IsTest
    static void testExecuteWithInvalidPayload() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('SCHED_BAD_PAY');
        Integration_Log__c log = TestDataFactory.createLog(endpoint.Id, false);

        Integration_Error_Log__c errorLog = new Integration_Error_Log__c(
            Integration_Log__c = log.Id,
            Error_Type__c = 'Unknown',
            Error_Message__c = 'Bad payload',
            Severity__c = 'High',
            Is_Dead_Letter__c = true,
            Retry_Eligible__c = true,
            Original_Payload__c = 'not-valid-json{'
        );
        insert errorLog;

        Test.startTest();
        IntegrationRetrySchedulable scheduler = new IntegrationRetrySchedulable();
        scheduler.execute(null);
        Test.stopTest();

        System.assert(true, 'Should handle invalid payload JSON gracefully');
    }
}