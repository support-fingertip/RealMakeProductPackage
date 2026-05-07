/**
 * @description Test class for HMACSignatureService -- signature generation and validation.
 *              Covers HmacSHA256 generation, HmacSHA512 generation, valid signature
 *              validation, and invalid signature detection.
 * @author Integration Platform
 */
@IsTest
private class HMACSignatureServiceTest {

    private static final String TEST_SECRET = 'my-super-secret-key';
    private static final String TEST_PAYLOAD = '{"action":"test","timestamp":"2026-01-01T00:00:00Z"}';

    /**
     * @description Verifies that generateSignature produces a valid hex-encoded HmacSHA256 signature.
     */
    @IsTest
    static void testGenerateHmacSHA256() {
        // Act
        Test.startTest();
        String signature = HMACSignatureService.generateSignature(TEST_PAYLOAD, TEST_SECRET, 'HmacSHA256');
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, signature, 'Signature should not be null');
        System.assert(signature.length() > 0, 'Signature should not be empty');
        // SHA256 produces 32 bytes = 64 hex characters
        System.assertEquals(64, signature.length(), 'SHA256 signature should be 64 hex chars');
        // Verify it is lowercase hex
        System.assertEquals(signature, signature.toLowerCase(),
            'Signature should be lowercase hex');
    }

    /**
     * @description Verifies that generateSignature produces a valid hex-encoded HmacSHA512 signature
     *              with the expected length.
     */
    @IsTest
    static void testGenerateHmacSHA512() {
        // Act
        Test.startTest();
        String signature = HMACSignatureService.generateSignature(TEST_PAYLOAD, TEST_SECRET, 'HmacSHA512');
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, signature, 'Signature should not be null');
        // SHA512 produces 64 bytes = 128 hex characters
        System.assertEquals(128, signature.length(), 'SHA512 signature should be 128 hex chars');
    }

    /**
     * @description Verifies that validateSignature returns true for a correctly generated signature.
     */
    @IsTest
    static void testValidateSignature() {
        // Arrange -- generate a known-good signature
        String validSignature = HMACSignatureService.generateSignature(
            TEST_PAYLOAD, TEST_SECRET, 'HmacSHA256'
        );

        // Act
        Test.startTest();
        Boolean isValid = HMACSignatureService.validateSignature(
            TEST_PAYLOAD, validSignature, TEST_SECRET, 'HmacSHA256'
        );
        Test.stopTest();

        // Assert
        System.assertEquals(true, isValid, 'Valid signature should pass validation');
    }

    /**
     * @description Verifies that validateSignature returns false for an incorrect signature.
     */
    @IsTest
    static void testValidateSignatureInvalid() {
        // Arrange
        String invalidSignature = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';

        // Act
        Test.startTest();
        Boolean isValid = HMACSignatureService.validateSignature(
            TEST_PAYLOAD, invalidSignature, TEST_SECRET, 'HmacSHA256'
        );
        Test.stopTest();

        // Assert
        System.assertEquals(false, isValid, 'Invalid signature should fail validation');
    }

    /**
     * @description Verifies that the default overload uses HmacSHA256.
     */
    @IsTest
    static void testDefaultAlgorithm() {
        // Arrange
        String sigExplicit = HMACSignatureService.generateSignature(TEST_PAYLOAD, TEST_SECRET, 'HmacSHA256');

        // Act
        Test.startTest();
        String sigDefault = HMACSignatureService.generateSignature(TEST_PAYLOAD, TEST_SECRET);
        Test.stopTest();

        // Assert
        System.assertEquals(sigExplicit, sigDefault,
            'Default algorithm should produce same result as explicit HmacSHA256');
    }

    /**
     * @description Verifies that null payload is treated as empty string for signature generation.
     */
    @IsTest
    static void testNullPayload() {
        // Act
        Test.startTest();
        String sigNull = HMACSignatureService.generateSignature(null, TEST_SECRET, 'HmacSHA256');
        String sigEmpty = HMACSignatureService.generateSignature('', TEST_SECRET, 'HmacSHA256');
        Test.stopTest();

        // Assert
        System.assertEquals(sigEmpty, sigNull,
            'Null payload should produce same signature as empty string');
    }

    /**
     * @description Verifies that blank secret throws HMACSignatureException.
     */
    @IsTest
    static void testBlankSecretThrows() {
        Test.startTest();
        try {
            HMACSignatureService.generateSignature(TEST_PAYLOAD, '', 'HmacSHA256');
            System.assert(false, 'Should have thrown HMACSignatureException');
        } catch (HMACSignatureService.HMACSignatureException e) {
            System.assert(e.getMessage().contains('blank'),
                'Exception should mention blank secret');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies that an unsupported algorithm throws HMACSignatureException.
     */
    @IsTest
    static void testUnsupportedAlgorithm() {
        Test.startTest();
        try {
            HMACSignatureService.generateSignature(TEST_PAYLOAD, TEST_SECRET, 'UnsupportedAlg');
            System.assert(false, 'Should have thrown HMACSignatureException');
        } catch (HMACSignatureService.HMACSignatureException e) {
            System.assert(e.getMessage().contains('Unsupported'),
                'Exception should mention unsupported algorithm');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies validateSignature with blank signature returns false.
     */
    @IsTest
    static void testValidateBlankSignature() {
        Test.startTest();
        Boolean result = HMACSignatureService.validateSignature(TEST_PAYLOAD, '', TEST_SECRET, 'HmacSHA256');
        Test.stopTest();

        System.assertEquals(false, result, 'Blank signature should return false');
    }
}