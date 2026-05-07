/**
 * @description Test class for IntegrationCalloutService.
 *              Covers makeCallout, makeCalloutWithAuth (all auth types),
 *              buildHttpRequest, executeCallout, extractResponseHeaders,
 *              and error/validation paths.
 */
@IsTest
private class IntegrationCalloutServiceTest {

    @IsTest
    static void testMakeCallout_success() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'POST';
        req.body = '{"key":"value"}';
        req.contentType = 'application/json';
        req.timeout = 30000;
        req.correlationId = 'corr-123';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCallout(req);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
        System.assertEquals('{"status":"ok"}', res.getBody());
    }

    @IsTest
    static void testMakeCallout_nullRequest() {
        Test.startTest();
        try {
            IntegrationCalloutService.makeCallout(null);
            System.assert(false, 'Should throw exception');
        } catch (IntegrationCalloutService.IntegrationCalloutException e) {
            System.assert(e.getMessage().contains('null'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testMakeCallout_invalidRequest() {
        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        // No endpoint or method set properly
        req.endpoint = '';
        req.method = '';

        Test.startTest();
        try {
            IntegrationCalloutService.makeCallout(req);
            System.assert(false, 'Should throw exception');
        } catch (IntegrationCalloutService.IntegrationCalloutException e) {
            System.assert(e.getMessage().contains('invalid'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testBuildHttpRequest_fullConfig() {
        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/test';
        req.method = 'POST';
        req.body = '{"data":"test"}';
        req.contentType = 'application/json';
        req.timeout = 5000;
        req.correlationId = 'build-test-123';
        req.compressRequest = true;
        // Skip client cert binding: the dev cert isn't installed in this org.
        req.addHeader('X-Custom', 'CustomValue');

        Test.startTest();
        HttpRequest httpReq = IntegrationCalloutService.buildHttpRequest(req);
        Test.stopTest();

        System.assertEquals('POST', httpReq.getMethod());
        System.assert(httpReq.getEndpoint().contains('api.example.com'));
        System.assertEquals('CustomValue', httpReq.getHeader('X-Custom'));
        System.assertEquals('build-test-123', httpReq.getHeader('X-Correlation-Id'));
        System.assertEquals('application/json', httpReq.getHeader('Content-Type'));
    }

    @IsTest
    static void testBuildHttpRequest_getMethodNoBody() {
        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/resource';
        req.method = 'GET';
        req.body = 'should be ignored for GET';

        Test.startTest();
        HttpRequest httpReq = IntegrationCalloutService.buildHttpRequest(req);
        Test.stopTest();

        System.assertEquals('GET', httpReq.getMethod());
        // GET method should not have body set
    }

    @IsTest
    static void testBuildHttpRequest_namedCredential() {
        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.namedCredential = 'MyCredential';
        req.endpoint = '/api/v1/resource';
        req.method = 'GET';

        Test.startTest();
        HttpRequest httpReq = IntegrationCalloutService.buildHttpRequest(req);
        Test.stopTest();

        System.assert(httpReq.getEndpoint().contains('callout:MyCredential'));
    }

    @IsTest
    static void testBuildHttpRequest_timeoutClamping() {
        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/test';
        req.method = 'GET';
        req.timeout = 999999; // Exceeds max

        Test.startTest();
        HttpRequest httpReq = IntegrationCalloutService.buildHttpRequest(req);
        Test.stopTest();

        // Should be clamped to 120000 (max)
        System.assertNotEquals(null, httpReq);
    }

    @IsTest
    static void testExecuteCallout() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"ok":true}'));

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.example.com/test');
        req.setMethod('GET');

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.executeCallout(req);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testExtractResponseHeaders() {
        Test.startTest();
        // Null response
        Map<String, String> headers = IntegrationCalloutService.extractResponseHeaders(null);
        System.assertNotEquals(null, headers);
        System.assertEquals(0, headers.size());
        Test.stopTest();
    }

    @IsTest
    static void testMakeCalloutWithAuth_apiKey() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('API_KEY_TEST', 'API_Key');

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'GET';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, profile);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testMakeCalloutWithAuth_basic() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('BASIC_TEST', 'Basic_Auth');
        // Already created with Basic_Auth — no remap needed

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'GET';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, profile);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testMakeCalloutWithAuth_bearer() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('BEARER_TEST', 'API_Key');
        profile.API_Key__c = 'my-bearer-token-123';
        update profile;

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'GET';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, profile);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testMakeCalloutWithAuth_hmac() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('HMAC_TEST', 'HMAC');
        profile.Auth_Type__c = 'hmac';
        update profile;

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'POST';
        req.body = '{"payload":"data"}';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, profile);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testMakeCalloutWithAuth_oauth2() {
        // First callout is for OAuth token, second for actual request
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"access_token":"tok123","expires_in":3600}'));

        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('OAUTH_TEST', 'OAuth_2_0');
        profile.Auth_Type__c = 'OAuth_2_0';
        profile.OAuth_Token_Endpoint__c = 'https://auth.example.com/token';
        profile.OAuth_Client_Id__c = 'cid';
        profile.OAuth_Client_Secret__c = 'csecret';
        profile.OAuth_Scope__c = 'read';
        update profile;

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'GET';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, profile);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testMakeCalloutWithAuth_unsupportedType() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        // Restricted picklist: cannot DML 'custom_unsupported'. Mutate in-memory only
        // so the service treats the auth as an unrecognized type.
        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('UNSUP_TEST', 'API_Key');
        profile.Auth_Type__c = 'custom_unsupported';

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'GET';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, profile);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testMakeCalloutWithAuth_nullProfile() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'GET';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, null);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testMakeCalloutWithAuth_nullRequestThrows() {
        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('NULL_REQ', 'API_Key');

        Test.startTest();
        try {
            IntegrationCalloutService.makeCalloutWithAuth(null, profile);
            System.assert(false, 'Should throw');
        } catch (IntegrationCalloutService.IntegrationCalloutException e) {
            System.assert(e.getMessage().contains('null'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testMakeCalloutWithAuth_inactiveProfile() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('INACTIVE_TEST', 'API_Key');
        profile.Active__c = false;
        update profile;

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'GET';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, profile);
        Test.stopTest();

        // Inactive profile should skip auth but still make callout
        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testMakeCalloutWithAuth_hmacBlankSecret() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('HMAC_BLANK', 'HMAC');
        profile.Auth_Type__c = 'hmac';
        profile.HMAC_Secret__c = null;
        update profile;

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'POST';
        req.body = '{"data":"test"}';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, profile);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testMakeCalloutWithAuth_oauth2NoEndpoint() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"status":"ok"}'));

        Integration_Auth_Profile__c profile = TestDataFactory.createAuthProfile('OAUTH_NO_EP', 'OAuth_2_0');
        profile.Auth_Type__c = 'OAuth_2_0';
        profile.OAuth_Token_Endpoint__c = null;
        update profile;

        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/v1/test';
        req.method = 'GET';

        Test.startTest();
        HttpResponse res = IntegrationCalloutService.makeCalloutWithAuth(req, profile);
        Test.stopTest();

        System.assertEquals(200, res.getStatusCode());
    }

    @IsTest
    static void testBuildHttpRequest_patchMethod() {
        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/test';
        req.method = 'PATCH';
        req.body = '{"update":"data"}';
        req.contentType = 'application/json';

        Test.startTest();
        HttpRequest httpReq = IntegrationCalloutService.buildHttpRequest(req);
        Test.stopTest();

        System.assertEquals('PATCH', httpReq.getMethod());
    }

    @IsTest
    static void testBuildHttpRequest_deleteMethodNoBody() {
        IntegrationCalloutRequest req = new IntegrationCalloutRequest();
        req.endpoint = 'https://api.example.com/resource/123';
        req.method = 'DELETE';
        req.body = 'should be ignored';

        Test.startTest();
        HttpRequest httpReq = IntegrationCalloutService.buildHttpRequest(req);
        Test.stopTest();

        System.assertEquals('DELETE', httpReq.getMethod());
    }

    @IsTest
    static void testExtractResponseHeaders_withResponse() {
        Test.setMock(HttpCalloutMock.class, new MockHttpCallout(200, '{"ok":true}'));

        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.example.com/test');
        req.setMethod('GET');

        Test.startTest();
        Http http = new Http();
        HttpResponse res = http.send(req);
        Map<String, String> headers = IntegrationCalloutService.extractResponseHeaders(res);
        Test.stopTest();

        System.assertNotEquals(null, headers);
    }
}