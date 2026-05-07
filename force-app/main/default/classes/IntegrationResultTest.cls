/**
 * @description Test class for IntegrationResult wrapper.
 *              Covers default constructor, success factory, failure factories,
 *              and correlation ID generation.
 */
@IsTest
private class IntegrationResultTest {

    @IsTest
    static void testDefaultConstructor() {
        Test.startTest();
        IntegrationResult result = new IntegrationResult();
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(0, result.statusCode);
        System.assertEquals('', result.responseBody);
        System.assertNotEquals(null, result.mappedValues);
        System.assertEquals('', result.errorMessage);
        System.assertNotEquals(null, result.correlationId);
        System.assert(result.correlationId.length() > 0, 'Correlation ID should be generated');
        System.assertEquals(0, result.executionTimeMs);
        System.assertEquals(0, result.retryCount);
        System.assertNotEquals(null, result.responseHeaders);
    }

    @IsTest
    static void testSuccessFactory() {
        Test.startTest();
        IntegrationResult result = IntegrationResult.success(200, '{"data":"ok"}');
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(200, result.statusCode);
        System.assertEquals('{"data":"ok"}', result.responseBody);
        System.assertNotEquals(null, result.correlationId);
    }

    @IsTest
    static void testSuccessFactory201() {
        Test.startTest();
        IntegrationResult result = IntegrationResult.success(201, '{"id":"123"}');
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(201, result.statusCode);
    }

    @IsTest
    static void testFailureFactorySimple() {
        Test.startTest();
        IntegrationResult result = IntegrationResult.failure('Something went wrong');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals('Something went wrong', result.errorMessage);
        System.assertNotEquals(null, result.correlationId);
    }

    @IsTest
    static void testFailureFactoryFull() {
        Test.startTest();
        IntegrationResult result = IntegrationResult.failure(500, '{"error":"internal"}', 'Server error');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(500, result.statusCode);
        System.assertEquals('{"error":"internal"}', result.responseBody);
        System.assertEquals('Server error', result.errorMessage);
    }

    @IsTest
    static void testFailureFactory404() {
        Test.startTest();
        IntegrationResult result = IntegrationResult.failure(404, 'Not found', 'Resource missing');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(404, result.statusCode);
    }

    @IsTest
    static void testCorrelationIdUniqueness() {
        Test.startTest();
        IntegrationResult r1 = new IntegrationResult();
        IntegrationResult r2 = new IntegrationResult();
        Test.stopTest();

        System.assertNotEquals(r1.correlationId, r2.correlationId,
            'Two results should have different correlation IDs');
    }

    @IsTest
    static void testMutableFields() {
        Test.startTest();
        IntegrationResult result = new IntegrationResult();
        result.success = true;
        result.statusCode = 201;
        result.responseBody = '{"created":true}';
        result.errorMessage = '';
        result.executionTimeMs = 250;
        result.retryCount = 2;
        result.logId = null;
        result.mappedValues.put('Name', 'TestValue');
        result.responseHeaders.put('Content-Type', 'application/json');
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(201, result.statusCode);
        System.assertEquals(250, result.executionTimeMs);
        System.assertEquals(2, result.retryCount);
        System.assertEquals('TestValue', result.mappedValues.get('Name'));
        System.assertEquals('application/json', result.responseHeaders.get('Content-Type'));
    }
}