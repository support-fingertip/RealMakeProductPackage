/**
 * @description Test class for IntegrationAuthManager -- authentication application.
 *              Covers API Key, Basic Auth, HMAC, None, and OAuth authentication types.
 * @author Integration Platform
 */
@IsTest
private class IntegrationAuthManagerTest {

    /**
     * @description Verifies that API Key authentication correctly injects the API key
     *              into the configured header.
     */
    @IsTest
    static void testAPIKeyAuth() {
        // Arrange
        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('API_KEY_PROFILE', 'API_Key');
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.example.com/v1/resource');
        req.setMethod('GET');

        // Act
        Test.startTest();
        IntegrationAuthManager.applyAuthentication(req, profile);
        Test.stopTest();

        // Assert
        String headerValue = req.getHeader('x-api-key');
        System.assertNotEquals(null, headerValue, 'API key header should be set');
        System.assert(headerValue.contains('test-api-key-12345'),
            'Header should contain the API key value');
    }

    /**
     * @description Verifies that Basic Auth correctly encodes username:password as Base64
     *              and sets the Authorization header.
     */
    @IsTest
    static void testBasicAuth() {
        // Arrange
        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('BASIC_PROFILE', 'Basic_Auth');
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.example.com/v1/resource');
        req.setMethod('GET');

        // Act
        Test.startTest();
        IntegrationAuthManager.applyAuthentication(req, profile);
        Test.stopTest();

        // Assert
        String authHeader = req.getHeader('Authorization');
        System.assertNotEquals(null, authHeader, 'Authorization header should be set');
        System.assert(authHeader.startsWith('Basic '), 'Header should start with Basic prefix');

        // Verify encoding
        String expectedEncoded = EncodingUtil.base64Encode(Blob.valueOf('testuser:testpass'));
        System.assertEquals('Basic ' + expectedEncoded, authHeader,
            'Basic auth header should contain correct Base64 encoding');
    }

    /**
     * @description Verifies that HMAC authentication generates a signature and sets it
     *              in the configured header.
     */
    @IsTest
    static void testHMACAuth() {
        // Arrange
        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('HMAC_PROFILE', 'HMAC');
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.example.com/v1/resource');
        req.setMethod('POST');
        req.setBody('{"test":"data"}');

        // Act
        Test.startTest();
        IntegrationAuthManager.applyAuthentication(req, profile);
        Test.stopTest();

        // Assert
        String signatureHeader = req.getHeader('X-HMAC-Signature');
        System.assertNotEquals(null, signatureHeader, 'HMAC signature header should be set');
        System.assert(signatureHeader.length() > 0, 'Signature should not be empty');

        // Verify the signature matches what HMACSignatureService would generate
        String expectedSignature = HMACSignatureService.generateSignature(
            '{"test":"data"}', 'hmac-test-secret-key', 'HmacSHA256'
        );
        System.assertEquals(expectedSignature, signatureHeader,
            'HMAC signature should match expected value');
    }

    /**
     * @description Verifies that None auth type does not modify the request headers.
     */
    @IsTest
    static void testNoAuth() {
        // Arrange
        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('NONE_PROFILE', 'None');
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.example.com/v1/resource');
        req.setMethod('GET');

        // Act
        Test.startTest();
        IntegrationAuthManager.applyAuthentication(req, profile);
        Test.stopTest();

        // Assert -- Authorization header should remain unset
        String authHeader = req.getHeader('Authorization');
        System.assertEquals(null, authHeader, 'None auth should not set Authorization header');
    }

    /**
     * @description Verifies that OAuth authentication retrieves an access token via
     *              HttpCalloutMock and sets it as a Bearer token on the request.
     */
    @IsTest
    static void testOAuthAuth() {
        // Arrange
        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('OAUTH_PROFILE', 'OAuth_2_0');

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.example.com/v1/resource');
        req.setMethod('GET');

        // Mock the OAuth token endpoint response
        String tokenResponse = '{"access_token":"mock_access_token_123","token_type":"Bearer","expires_in":3600}';
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, tokenResponse));

        // Act
        Test.startTest();
        IntegrationAuthManager.applyAuthentication(req, profile);
        Test.stopTest();

        // Assert
        String authHeader = req.getHeader('Authorization');
        System.assertNotEquals(null, authHeader, 'Authorization header should be set for OAuth');
        System.assert(authHeader.contains('mock_access_token_123'),
            'Header should contain the mocked access token');
    }

    /**
     * @description Verifies that applyAuthentication throws IntegrationAuthException
     *              when the request is null.
     */
    @IsTest
    static void testNullRequestThrowsException() {
        // Arrange
        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('NULL_REQ', 'API_Key');

        // Act & Assert
        Test.startTest();
        try {
            IntegrationAuthManager.applyAuthentication(null, profile);
            System.assert(false, 'Should have thrown IntegrationAuthException');
        } catch (IntegrationAuthManager.IntegrationAuthException e) {
            System.assert(e.getMessage().contains('null'),
                'Exception should mention null request');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies that applyAuthentication throws for inactive profile.
     */
    @IsTest
    static void testInactiveProfileThrowsException() {
        // Arrange
        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('INACTIVE_PROF', 'API_Key');
        profile.Active__c = false;
        update profile;

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.example.com/test');
        req.setMethod('GET');

        // Act & Assert
        Test.startTest();
        try {
            IntegrationAuthManager.applyAuthentication(req, profile);
            System.assert(false, 'Should have thrown IntegrationAuthException for inactive profile');
        } catch (IntegrationAuthManager.IntegrationAuthException e) {
            System.assert(e.getMessage().contains('not active'),
                'Exception should mention inactive');
        }
        Test.stopTest();
    }
}