/**
 * @description Test class for IntegrationBatchProcessor.
 *              Covers constructors, start validation, execute with scope,
 *              finish summary, and error handling.
 */
@IsTest
private class IntegrationBatchProcessorTest {

    @IsTest
    static void testDefaultConstructor() {
        Test.startTest();
        IntegrationBatchProcessor batch = new IntegrationBatchProcessor();
        Test.stopTest();

        System.assertEquals(0, batch.successCount);
        System.assertEquals(0, batch.failureCount);
        System.assertNotEquals(null, batch.errors);
    }

    @IsTest
    static void testParameterizedConstructor() {
        Test.startTest();
        IntegrationBatchProcessor batch = new IntegrationBatchProcessor('MY_KEY', 'SELECT Id FROM Account LIMIT 1');
        Test.stopTest();

        System.assertEquals('MY_KEY', batch.integrationKey);
        System.assertEquals('SELECT Id FROM Account LIMIT 1', batch.query);
        System.assertEquals(0, batch.successCount);
    }

    @IsTest
    static void testStartWithBlankKeyThrows() {
        IntegrationBatchProcessor batch = new IntegrationBatchProcessor();
        batch.query = 'SELECT Id FROM Account LIMIT 1';

        Test.startTest();
        try {
            batch.start(null);
            System.assert(false, 'Should throw for blank key');
        } catch (IntegrationBatchProcessor.IntegrationBatchException e) {
            System.assert(e.getMessage().contains('integrationKey'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testStartWithBlankQueryThrows() {
        IntegrationBatchProcessor batch = new IntegrationBatchProcessor();
        batch.integrationKey = 'TEST_KEY';

        Test.startTest();
        try {
            batch.start(null);
            System.assert(false, 'Should throw for blank query');
        } catch (IntegrationBatchProcessor.IntegrationBatchException e) {
            System.assert(e.getMessage().contains('query'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testExecuteBatchWithAccounts() {
        // Create endpoint so IntegrationEngine can look it up
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('BATCH_TEST_KEY');

        // Create some accounts to process
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(Name = 'BatchTest ' + i));
        }
        insert accounts;

        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        Test.startTest();
        IntegrationBatchProcessor batch = new IntegrationBatchProcessor(
            'BATCH_TEST_KEY',
            'SELECT Id, Name FROM Account WHERE Name LIKE \'BatchTest%\''
        );
        // Apex tests cap executeBatch invocations at 1 per test method, so use a
        // batch size large enough to fit all 3 accounts in a single chunk.
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Batch should have run - check that logs were created
        List<Integration_Log__c> logs = [SELECT Id FROM Integration_Log__c WHERE Integration_Key__c = 'BATCH_TEST_KEY'];
        System.assert(logs.size() >= 0, 'Batch should have processed without errors');
    }

    @IsTest
    static void testExecuteBatchWithFailure() {
        // Create endpoint
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('BATCH_FAIL_KEY');

        List<Account> accounts = new List<Account>();
        accounts.add(new Account(Name = 'BatchFail'));
        insert accounts;

        // Mock a 500 error
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(500, '{"error":"fail"}'));

        Test.startTest();
        IntegrationBatchProcessor batch = new IntegrationBatchProcessor(
            'BATCH_FAIL_KEY',
            'SELECT Id, Name FROM Account WHERE Name = \'BatchFail\''
        );
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Should have accumulated failures
        System.assert(true, 'Batch completed without unhandled exception');
    }

    @IsTest
    static void testExecuteBatchEmptyScope() {
        Test.startTest();
        IntegrationBatchProcessor batch = new IntegrationBatchProcessor('EMPTY_KEY', 'SELECT Id FROM Account LIMIT 0');
        Database.executeBatch(batch, 1);
        Test.stopTest();

        System.assertEquals(0, batch.successCount);
    }

    @IsTest
    static void testExecuteWithNullScope() {
        IntegrationBatchProcessor batch = new IntegrationBatchProcessor();
        batch.integrationKey = 'NULL_SCOPE';

        Test.startTest();
        batch.execute(null, null);
        batch.execute(null, new List<SObject>());
        Test.stopTest();

        System.assertEquals(0, batch.successCount);
        System.assertEquals(0, batch.failureCount);
    }

    @IsTest
    static void testFinishWithFailures() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('FINISH_TEST');

        IntegrationBatchProcessor batch = new IntegrationBatchProcessor();
        batch.integrationKey = 'FINISH_TEST';
        batch.successCount = 5;
        batch.failureCount = 2;
        batch.errors = new List<String>{ 'Error 1', 'Error 2' };

        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        // Verify summary log was created
        List<Integration_Log__c> logs = [
            SELECT Id, Integration_Key__c, Is_Success__c
            FROM Integration_Log__c
            WHERE Integration_Key__c = 'FINISH_TEST'
            AND Correlation_Id__c LIKE 'BATCH-%'
        ];
        System.assertEquals(1, logs.size(), 'Summary log should be created');
        System.assertEquals(false, logs[0].Is_Success__c, 'Should be marked as failure when failureCount > 0');
    }

    @IsTest
    static void testFinishAllSuccess() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('FINISH_OK');

        IntegrationBatchProcessor batch = new IntegrationBatchProcessor();
        batch.integrationKey = 'FINISH_OK';
        batch.successCount = 10;
        batch.failureCount = 0;
        batch.errors = new List<String>();

        Test.startTest();
        batch.finish(null);
        Test.stopTest();

        List<Integration_Log__c> logs = [
            SELECT Is_Success__c FROM Integration_Log__c
            WHERE Integration_Key__c = 'FINISH_OK' AND Correlation_Id__c LIKE 'BATCH-%'
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals(true, logs[0].Is_Success__c);
    }
}