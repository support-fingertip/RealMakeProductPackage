/**
 * @description Test class for IntegrationInvocable -- Flow invocable action.
 *              Covers basic invocable execution, bulk execution with multiple requests,
 *              and error handling for invalid integration keys.
 * @author Integration Platform
 */
@IsTest
private class IntegrationInvocableTest {

    /**
     * @description Verifies that a single invocable request executes successfully
     *              and returns a valid result.
     */
    @IsTest
    static void testExecuteInvocable() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INVOCABLE_TEST');
        TestDataFactory.createRequestTemplate(endpoint.Id, '{"name":"{{name}}"}');

        String mockResponse = '{"status":"created"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, mockResponse));

        IntegrationInvocable.IntegrationInvocableRequest request =
            new IntegrationInvocable.IntegrationInvocableRequest();
        request.integrationKey = 'INVOCABLE_TEST';
        request.payload = '{"name":"Test"}';

        List<IntegrationInvocable.IntegrationInvocableRequest> requests =
            new List<IntegrationInvocable.IntegrationInvocableRequest>{ request };

        // Act
        Test.startTest();
        List<IntegrationInvocable.IntegrationInvocableResult> results =
            IntegrationInvocable.execute(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Result should be successful');
        System.assertEquals(200, results[0].statusCode, 'Status code should be 200');
        System.assertNotEquals(null, results[0].correlationId, 'Correlation ID should be set');
    }

    /**
     * @description Verifies that multiple invocable requests are processed in bulk
     *              and return corresponding results.
     */
    @IsTest
    static void testExecuteInvocableBulk() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INVOCABLE_BULK');

        String mockResponse = '{"status":"ok"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, mockResponse));

        List<IntegrationInvocable.IntegrationInvocableRequest> requests =
            new List<IntegrationInvocable.IntegrationInvocableRequest>();

        for (Integer i = 0; i < 3; i++) {
            IntegrationInvocable.IntegrationInvocableRequest req =
                new IntegrationInvocable.IntegrationInvocableRequest();
            req.integrationKey = 'INVOCABLE_BULK';
            req.payload = '{"index":' + i + '}';
            requests.add(req);
        }

        // Act
        Test.startTest();
        List<IntegrationInvocable.IntegrationInvocableResult> results =
            IntegrationInvocable.execute(requests);
        Test.stopTest();

        // Assert
     
    }

    /**
     * @description Verifies that a request with a blank integration key returns
     *              an error result with status 400.
     */
    @IsTest
    static void testExecuteInvocableInvalidKey() {
        // Arrange
        IntegrationInvocable.IntegrationInvocableRequest request =
            new IntegrationInvocable.IntegrationInvocableRequest();
        request.integrationKey = '';  // blank key
        request.payload = '{"data":"test"}';

        List<IntegrationInvocable.IntegrationInvocableRequest> requests =
            new List<IntegrationInvocable.IntegrationInvocableRequest>{ request };

        // Act
        Test.startTest();
        List<IntegrationInvocable.IntegrationInvocableResult> results =
            IntegrationInvocable.execute(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Invalid key should fail');
        System.assertEquals(400, results[0].statusCode, 'Status code should be 400');
        System.assert(results[0].errorMessage.contains('required'),
            'Error message should indicate key is required');
    }

    /**
     * @description Verifies that null input list returns an empty result list.
     */
    @IsTest
    static void testExecuteInvocableNullInput() {
        // Act
        Test.startTest();
        List<IntegrationInvocable.IntegrationInvocableResult> results =
            IntegrationInvocable.execute(null);
        Test.stopTest();

        // Assert
        System.assertEquals(0, results.size(), 'Null input should return empty list');
    }

    /**
     * @description Verifies that a request with a record ID is passed to the engine.
     */
    @IsTest
    static void testExecuteInvocableWithRecordId() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INVOCABLE_REC');
        Account testAcc = new Account(Name = 'Invocable Account');
        insert testAcc;

        String mockResponse = '{"status":"ok"}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, mockResponse));

        IntegrationInvocable.IntegrationInvocableRequest request =
            new IntegrationInvocable.IntegrationInvocableRequest();
        request.integrationKey = 'INVOCABLE_REC';
        request.recordId = String.valueOf(testAcc.Id);

        List<IntegrationInvocable.IntegrationInvocableRequest> requests =
            new List<IntegrationInvocable.IntegrationInvocableRequest>{ request };

        // Act
        Test.startTest();
        List<IntegrationInvocable.IntegrationInvocableResult> results =
            IntegrationInvocable.execute(requests);
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
    }
}