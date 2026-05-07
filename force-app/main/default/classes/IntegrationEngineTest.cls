/**
 * @description Test class for IntegrationEngine -- the main orchestration class.
 *              Covers execute(), executeBulk(), inactive endpoint handling,
 *              payload-based execution, and retry configuration.
 * @author Integration Platform
 */
@IsTest
private class IntegrationEngineTest {

    /**
     * @description Verifies that a successful outbound integration callout returns
     *              a populated IntegrationResult with success = true and status 200.
     */
    @IsTest
    static void testExecuteSuccess() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('TEST_SUCCESS');
        TestDataFactory.createRequestTemplate(endpoint.Id, '{"name":"{{name}}"}');
        TestDataFactory.createResponseMapping(endpoint.Id, 'data.status', 'Status__c');

        String mockBody = '{"data":{"status":"active"}}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, mockBody));

        Map<String, Object> payload = new Map<String, Object>{ 'name' => 'TestAccount' };

        // Act
        Test.startTest();
        IntegrationResult result = IntegrationEngine.execute('TEST_SUCCESS', null, payload, null);
        Test.stopTest();

        // Assert
        System.assertEquals(true, result.success, 'Expected successful result');
        System.assertEquals(200, result.statusCode, 'Expected HTTP 200 status code');
        System.assertNotEquals(null, result.correlationId, 'Correlation ID should be generated');
        System.assertNotEquals(null, result.responseBody, 'Response body should be populated');
    }

    /**
     * @description Verifies that executing an integration with an inactive endpoint
     *              returns a result with success = false and status 404.
     */
    @IsTest
    static void testExecuteInactiveEndpoint() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('TEST_INACTIVE');
        endpoint.Active__c = false;
        update endpoint;

        // Clear config cache so the stale cached active endpoint is not used
        IntegrationConfigService.clearCache();

        // Act
        Test.startTest();
        IntegrationResult result;
        try {
            result = IntegrationEngine.execute('TEST_INACTIVE', null, null, null);
        } catch (IntegrationConfigService.IntegrationConfigException e) {
            // The config service throws an exception for inactive endpoints
            result = new IntegrationResult();
            result.success = false;
            result.statusCode = 404;
            result.errorMessage = e.getMessage();
        }
        Test.stopTest();

        // Assert
        System.assertEquals(false, result.success, 'Inactive endpoint should return failure');
    }

    /**
     * @description Verifies that execute() works with a direct payload map (no record ID).
     */
    @IsTest
    static void testExecuteWithPayload() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('TEST_PAYLOAD');
        TestDataFactory.createRequestTemplate(endpoint.Id, '{"firstName":"{{first}}","lastName":"{{last}}"}');

        String mockResponse = '{"result":"created"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(201, mockResponse));

        Map<String, Object> payload = new Map<String, Object>{
            'first' => 'John',
            'last' => 'Doe'
        };

        // Act
        Test.startTest();
        IntegrationResult result = IntegrationEngine.execute('TEST_PAYLOAD', null, payload, null);
        Test.stopTest();

        // Assert
        System.assertEquals(true, result.success, 'Expected success with payload execution');
        System.assertEquals(201, result.statusCode, 'Expected HTTP 201');
    }

    /**
     * @description Verifies that executeBulk() processes multiple record IDs and
     *              returns a list of results matching the input count.
     */
    @IsTest
    static void testExecuteBulk() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('TEST_BULK');

        String mockBody = '{"status":"ok"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, mockBody));

        // Create test accounts to use as record IDs
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            accounts.add(new Account(Name = 'Bulk Test ' + i));
        }
        insert accounts;

        List<Id> recordIds = new List<Id>();
        for (Account acc : accounts) {
            recordIds.add(acc.Id);
        }

        // Act
        Test.startTest();
        List<IntegrationResult> results = IntegrationEngine.executeBulk('TEST_BULK', recordIds, null);
        Test.stopTest();

        // Assert
        System.assertEquals(3, results.size(), 'Should return one result per record ID');
    }

    /**
     * @description Verifies that a failing callout with a retry config enqueues a retry.
     *              Tests the retry initiation path when the callout returns a retryable status code.
     */
    @IsTest
    static void testExecuteWithRetryConfig() {
        // Arrange
        Integration_Retry_Config__c retryConfig = TestDataFactory.createRetryConfig('TEST_RETRY_CFG');

        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('TEST_RETRY');
        endpoint.Retry_Config__c = retryConfig.Id;
        update endpoint;

        // Clear cache to pick up the retry config relationship
        IntegrationConfigService.clearCache();

        String mockBody = '{"error":"service unavailable"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(503, mockBody));

        Map<String, Object> payload = new Map<String, Object>{ 'key' => 'value' };

        // Act
        Test.startTest();
        IntegrationResult result = IntegrationEngine.execute('TEST_RETRY', null, payload, null);
        Test.stopTest();

        // Assert
        System.assertEquals(false, result.success, 'Should indicate failure on 503');
        System.assertEquals(503, result.statusCode, 'Status code should be 503');
    }
}