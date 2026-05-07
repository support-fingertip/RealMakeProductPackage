/**
 * @description Test class for PayloadMaskingService -- sensitive data masking.
 *              Covers JSON payload masking, header masking, custom field masking,
 *              and null/empty input handling.
 * @author Integration Platform
 */
@IsTest
private class PayloadMaskingServiceTest {

    /**
     * @description Verifies that default sensitive fields are masked in a JSON payload.
     */
    @IsTest
    static void testMaskPayload() {
        // Arrange
        String payload = '{"username":"john","password":"secret123","data":"visible"}';

        // Act
        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        // Assert
        System.assert(!masked.contains('secret123'), 'Password value should be masked');
        System.assert(masked.contains(PayloadMaskingService.MASK_PLACEHOLDER),
            'Masked value should contain the mask placeholder');
        System.assert(masked.contains('"data"'), 'Non-sensitive fields should be preserved');
        System.assert(masked.contains('"visible"'), 'Non-sensitive values should be preserved');
    }

    /**
     * @description Verifies that sensitive headers (Authorization, x-api-key, etc.) are masked.
     */
    @IsTest
    static void testMaskHeaders() {
        // Arrange
        Map<String, String> headers = new Map<String, String>{
            'Authorization' => 'Bearer some-secret-token',
            'Content-Type' => 'application/json',
            'x-api-key' => 'api-key-value-123',
            'Accept' => 'application/json'
        };

        // Act
        Test.startTest();
        Map<String, String> maskedHeaders = PayloadMaskingService.maskHeaders(headers);
        Test.stopTest();

        // Assert
        System.assertEquals(PayloadMaskingService.MASK_PLACEHOLDER, maskedHeaders.get('Authorization'),
            'Authorization header should be masked');
        System.assertEquals(PayloadMaskingService.MASK_PLACEHOLDER, maskedHeaders.get('x-api-key'),
            'x-api-key header should be masked');
        System.assertEquals('application/json', maskedHeaders.get('Content-Type'),
            'Content-Type header should not be masked');
        System.assertEquals('application/json', maskedHeaders.get('Accept'),
            'Accept header should not be masked');
    }

    /**
     * @description Verifies that custom sensitive field names are correctly masked.
     */
    @IsTest
    static void testMaskWithCustomFields() {
        // Arrange
        String payload = '{"myCustomSecret":"hidden","normalField":"visible"}';
        List<String> customFields = new List<String>{ 'mycustomsecret' };

        // Act
        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload, customFields);
        Test.stopTest();

        // Assert
        System.assert(!masked.contains('hidden'), 'Custom secret value should be masked');
        System.assert(masked.contains('"visible"'), 'Normal field should not be masked');
    }

    /**
     * @description Verifies that null and blank payloads are handled gracefully.
     */
    @IsTest
    static void testNullPayload() {
        // Act
        Test.startTest();
        String resultNull = PayloadMaskingService.maskPayload(null);
        String resultEmpty = PayloadMaskingService.maskPayload('');
        String resultBlank = PayloadMaskingService.maskPayload('   ');
        Test.stopTest();

        // Assert
        System.assertEquals(null, resultNull, 'Null input should return null');
        System.assertEquals('', resultEmpty, 'Empty input should return empty');
        System.assertEquals('   ', resultBlank, 'Blank input should return as-is');
    }

    /**
     * @description Verifies that null header maps are returned as-is.
     */
    @IsTest
    static void testMaskNullHeaders() {
        // Act
        Test.startTest();
        Map<String, String> result = PayloadMaskingService.maskHeaders(null);
        Test.stopTest();

        // Assert
        System.assertEquals(null, result, 'Null headers should return null');
    }

    /**
     * @description Verifies that nested JSON objects have their sensitive fields masked.
     */
    @IsTest
    static void testMaskNestedPayload() {
        // Arrange
        String payload = '{"user":{"name":"John","password":"secret"},"api_key":"key123"}';

        // Act
        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        // Assert
        System.assert(!masked.contains('secret'), 'Nested password should be masked');
        System.assert(!masked.contains('key123'), 'Top-level api_key should be masked');
        System.assert(masked.contains('"John"'), 'Non-sensitive nested name should be preserved');
    }

    /**
     * @description Verifies that key=value format payloads are also masked.
     */
    @IsTest
    static void testMaskKeyValuePayload() {
        // Arrange
        String payload = 'username=john&password=secret&data=visible';

        // Act
        Test.startTest();
        String masked = PayloadMaskingService.maskPayload(payload);
        Test.stopTest();

        // Assert
        System.assert(!masked.contains('=secret'), 'Password in key-value format should be masked');
        System.assert(masked.contains('data=visible'), 'Non-sensitive key-value should be preserved');
    }
}