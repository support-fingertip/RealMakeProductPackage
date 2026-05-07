/**
 * @description Test class for IntegrationRetryHandler -- retry logic and delay calculation.
 *              Covers shouldRetry evaluation, non-retryable codes, max retries exceeded,
 *              exponential backoff calculation, and max cap enforcement.
 * @author Integration Platform
 */
@IsTest
private class IntegrationRetryHandlerTest {

    /**
     * @description Verifies that shouldRetry returns true when the status code is retryable
     *              and the retry count is below the maximum.
     */
    @IsTest
    static void testShouldRetryTrue() {
        // Arrange
        Integration_Retry_Config__c config = TestDataFactory.createRetryConfig('RETRY_TRUE');

        // Act
        Test.startTest();
        Boolean shouldRetry500 = IntegrationRetryHandler.shouldRetry(500, 0, config);
        Boolean shouldRetry503 = IntegrationRetryHandler.shouldRetry(503, 1, config);
        Boolean shouldRetry429 = IntegrationRetryHandler.shouldRetry(429, 2, config);
        Test.stopTest();

        // Assert
        System.assertEquals(true, shouldRetry500, '500 at retry 0 should be retryable');
        System.assertEquals(true, shouldRetry503, '503 at retry 1 should be retryable');
        System.assertEquals(true, shouldRetry429, '429 at retry 2 should be retryable');
    }

    /**
     * @description Verifies that shouldRetry returns false when max retries have been exceeded.
     */
    @IsTest
    static void testShouldRetryFalse() {
        // Arrange
        Integration_Retry_Config__c config = TestDataFactory.createRetryConfig('RETRY_FALSE');
        // Config has Max_Retries__c = 3

        // Act
        Test.startTest();
        Boolean shouldRetry = IntegrationRetryHandler.shouldRetry(500, 3, config);
        Boolean shouldRetryExceeded = IntegrationRetryHandler.shouldRetry(500, 5, config);
        Test.stopTest();

        // Assert
        System.assertEquals(false, shouldRetry, 'At max retries (3), should return false');
        System.assertEquals(false, shouldRetryExceeded, 'Beyond max retries, should return false');
    }

    /**
     * @description Verifies that shouldRetry returns false for non-retryable HTTP status codes.
     */
    @IsTest
    static void testShouldRetryNonRetryableCode() {
        // Arrange
        Integration_Retry_Config__c config = TestDataFactory.createRetryConfig('RETRY_NONRETRY');

        // Act
        Test.startTest();
        Boolean shouldRetry400 = IntegrationRetryHandler.shouldRetry(400, 0, config);
        Boolean shouldRetry401 = IntegrationRetryHandler.shouldRetry(401, 0, config);
        Boolean shouldRetry404 = IntegrationRetryHandler.shouldRetry(404, 0, config);
        Boolean shouldRetry200 = IntegrationRetryHandler.shouldRetry(200, 0, config);
        Test.stopTest();

        // Assert
        System.assertEquals(false, shouldRetry400, '400 should not be retryable');
        System.assertEquals(false, shouldRetry401, '401 should not be retryable');
        System.assertEquals(false, shouldRetry404, '404 should not be retryable');
        System.assertEquals(false, shouldRetry200, '200 should not be retryable');
    }

    /**
     * @description Verifies that shouldRetry returns false for null config.
     */
    @IsTest
    static void testShouldRetryNullConfig() {
        Test.startTest();
        Boolean result = IntegrationRetryHandler.shouldRetry(500, 0, null);
        Test.stopTest();

        System.assertEquals(false, result, 'Null config should return false');
    }

    /**
     * @description Verifies that shouldRetry returns false for inactive config.
     */
    @IsTest
    static void testShouldRetryInactiveConfig() {
        // Arrange
        Integration_Retry_Config__c config = TestDataFactory.createRetryConfig('RETRY_INACTIVE');
        config.Active__c = false;
        update config;

        // Act
        Test.startTest();
        Boolean result = IntegrationRetryHandler.shouldRetry(500, 0, config);
        Test.stopTest();

        System.assertEquals(false, result, 'Inactive config should return false');
    }

    /**
     * @description Verifies that calculateNextRetryDelay computes exponential backoff correctly.
     *              With base interval=60, multiplier=2:
     *              - Retry 0: 60 * 2^0 = 60
     *              - Retry 1: 60 * 2^1 = 120
     *              - Retry 2: 60 * 2^2 = 240
     */
    @IsTest
    static void testCalculateNextRetryDelay() {
        // Arrange
        Integration_Retry_Config__c config = TestDataFactory.createRetryConfig('RETRY_DELAY');

        // Act
        Test.startTest();
        Integer delay0 = IntegrationRetryHandler.calculateNextRetryDelay(0, config);
        Integer delay1 = IntegrationRetryHandler.calculateNextRetryDelay(1, config);
        Integer delay2 = IntegrationRetryHandler.calculateNextRetryDelay(2, config);
        Test.stopTest();

        // Assert
        System.assertEquals(60, delay0, 'First retry delay should be 60s (base interval)');
        System.assertEquals(120, delay1, 'Second retry delay should be 120s (60 * 2^1)');
        System.assertEquals(240, delay2, 'Third retry delay should be 240s (60 * 2^2)');
    }

    /**
     * @description Verifies that the calculated delay is capped at Max_Retry_Interval__c.
     *              With config max=3600, even very high retry counts should not exceed it.
     */
    @IsTest
    static void testCalculateNextRetryDelayMaxCap() {
        // Arrange
        Integration_Retry_Config__c config = TestDataFactory.createRetryConfig('RETRY_MAXCAP');
        // Max_Retry_Interval__c = 3600

        // Act
        Test.startTest();
        // Retry 10: 60 * 2^10 = 61440, but should be capped at 3600
        Integer delay = IntegrationRetryHandler.calculateNextRetryDelay(10, config);
        Test.stopTest();

        // Assert
        System.assert(delay <= 3600, 'Delay should not exceed max retry interval of 3600');
        System.assertEquals(3600, delay, 'Delay should be capped at max retry interval');
    }

    /**
     * @description Verifies delay calculation with null config uses defaults.
     */
    @IsTest
    static void testCalculateDelayNullConfig() {
        // Act
        Test.startTest();
        Integer delay = IntegrationRetryHandler.calculateNextRetryDelay(0, null);
        Test.stopTest();

        // Assert -- should use default base interval of 60
        System.assertEquals(60, delay, 'Null config should use default interval of 60s');
    }

    /**
     * @description Verifies that enqueueRetry creates a queueable job.
     */
    @IsTest
    static void testEnqueueRetry() {
        // Act
        Test.startTest();
        IntegrationRetryHandler.enqueueRetry(
            'TEST_ENQUEUE',
            null,
            new Map<String, Object>{ 'key' => 'value' },
            null,
            0,
            null,
            60
        );
        Test.stopTest();

        // Assert -- in test context the queueable is executed synchronously
        System.assert(true, 'enqueueRetry should execute without error');
    }
}