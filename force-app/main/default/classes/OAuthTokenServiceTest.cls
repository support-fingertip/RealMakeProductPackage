/**
 * @description Test class for OAuthTokenService.
 * Covers getAccessToken, refreshToken, clearCache, evictToken,
 * client_credentials grant, password grant, error grant types,
 * token caching, expired token refresh, and response parsing errors.
 */
@isTest
private class OAuthTokenServiceTest {

    private static final String TOKEN_ENDPOINT = 'https://auth.example.com/token';

    // ── Mock HTTP responses ──────────────────────────────────────────

    private class SuccessTokenMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"access_token":"test_access_token_123","token_type":"Bearer","expires_in":3600,"refresh_token":"test_refresh_token_456"}');
            return res;
        }
    }

    private class NoRefreshTokenMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"access_token":"no_refresh_token","token_type":"Bearer","expires_in":60}');
            return res;
        }
    }

    private class ErrorTokenMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"error":"invalid_client","error_description":"Client authentication failed"}');
            return res;
        }
    }

    private class EmptyBodyMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('');
            return res;
        }
    }

    private class InvalidJsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('NOT_JSON');
            return res;
        }
    }

    private class NoAccessTokenMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"token_type":"Bearer","expires_in":3600}');
            return res;
        }
    }

    private class NonJsonErrorMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    // ── Helper ───────────────────────────────────────────────────────

    private static Integration_Auth_Profile__c createOAuthProfile(String grantType) {
        Integration_Auth_Profile__c profile = new Integration_Auth_Profile__c(
            Profile_Name__c = 'Test OAuth ' + grantType,
            Auth_Type__c = 'OAuth_2_0',
            Active__c = true,
            OAuth_Token_Endpoint__c = TOKEN_ENDPOINT,
            OAuth_Client_Id__c = 'client123',
            OAuth_Client_Secret__c = 'secret456',
            OAuth_Scope__c = 'read write',
            OAuth_Grant_Type__c = grantType,
            Token_Cache_Duration__c = 3600,
            Username__c = 'testuser@example.com',
            Password__c = 'testpass123'
        );
        insert profile;
        return profile;
    }

    // ── Null profile throws ──────────────────────────────────────────

    @isTest
    static void getAccessToken_nullProfile_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            OAuthTokenService.getAccessToken(null);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('null'));
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── Missing token endpoint throws ────────────────────────────────

    @isTest
    static void getAccessToken_missingEndpoint_throws() {
        Integration_Auth_Profile__c profile = new Integration_Auth_Profile__c(
            Profile_Name__c = 'No Endpoint',
            Auth_Type__c = 'OAuth_2_0',
            Active__c = true
        );
        insert profile;

        Boolean thrown = false;
        Test.startTest();
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('OAuth_Token_Endpoint__c'));
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── Client credentials grant success ─────────────────────────────

    @isTest
    static void getAccessToken_clientCredentials_success() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        String token = OAuthTokenService.getAccessToken(profile);
        Test.stopTest();

        System.assertEquals('test_access_token_123', token);
    }

    // ── Password grant success ───────────────────────────────────────

    @isTest
    static void getAccessToken_passwordGrant_success() {
        Integration_Auth_Profile__c profile = createOAuthProfile('password');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        String token = OAuthTokenService.getAccessToken(profile);
        Test.stopTest();

        System.assertEquals('test_access_token_123', token);
    }

    // ── Authorization code grant throws ──────────────────────────────

    @isTest
    static void getAccessToken_authCodeGrant_throws() {
        Integration_Auth_Profile__c profile = createOAuthProfile('authorization_code');

        Boolean thrown = false;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('authorization_code'));
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── Refresh_token grant type (no prior token) throws ─────────────

    @isTest
    static void getAccessToken_refreshTokenGrantType_throws() {
        Integration_Auth_Profile__c profile = createOAuthProfile('refresh_token');

        Boolean thrown = false;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('refresh_token'));
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── Unsupported grant type throws ────────────────────────────────

    @isTest
    static void getAccessToken_unsupportedGrant_throws() {
        // Insert with a valid picklist value, then mutate the in-memory copy to an
        // unsupported value so the service's "Unsupported" branch is exercised.
        // (The org-level picklist is restricted, so DML cannot persist 'implicit'.)
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');
        profile.OAuth_Grant_Type__c = 'implicit';

        Boolean thrown = false;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Unsupported'));
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── Error response from token endpoint ───────────────────────────

    @isTest
    static void getAccessToken_errorResponse_throws() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        Boolean thrown = false;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ErrorTokenMock());
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('failed'));
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── Non-JSON error response ──────────────────────────────────────

    @isTest
    static void getAccessToken_nonJsonError_throws() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        Boolean thrown = false;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new NonJsonErrorMock());
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── Empty body response ──────────────────────────────────────────

    @isTest
    static void getAccessToken_emptyBody_throws() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        Boolean thrown = false;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new EmptyBodyMock());
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('empty'));
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── Invalid JSON response ────────────────────────────────────────

    @isTest
    static void getAccessToken_invalidJson_throws() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        Boolean thrown = false;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new InvalidJsonMock());
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('JSON'));
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── No access_token in response ──────────────────────────────────

    @isTest
    static void getAccessToken_noAccessToken_throws() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        Boolean thrown = false;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new NoAccessTokenMock());
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('access_token'));
        }
        Test.stopTest();
        System.assert(thrown);
    }

    // ── Cache hit returns cached token ───────────────────────────────

    @isTest
    static void getAccessToken_cacheHit_returnsCached() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        // Pre-populate cache
        OAuthTokenService.CachedOAuthToken cached = new OAuthTokenService.CachedOAuthToken(
            'cached_token', 'refresh_val', 'Bearer', 3600
        );
        OAuthTokenService.TOKEN_CACHE.put(profile.Id, cached);

        Test.startTest();
        // No mock needed — should hit cache
        String token = OAuthTokenService.getAccessToken(profile);
        Test.stopTest();

        System.assertEquals('cached_token', token);
    }

    // ── Expired cache with refresh token attempts refresh ────────────

    @isTest
    static void getAccessToken_expiredCacheWithRefresh_attemptsRefresh() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        // Pre-populate expired cache with refresh token
        OAuthTokenService.CachedOAuthToken cached = new OAuthTokenService.CachedOAuthToken(
            'old_token', 'old_refresh', 'Bearer', -10 // already expired
        );
        OAuthTokenService.TOKEN_CACHE.put(profile.Id, cached);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        String token = OAuthTokenService.getAccessToken(profile);
        Test.stopTest();

        System.assertEquals('test_access_token_123', token);
    }

    // ── refreshToken with no cached refresh does full request ────────

    @isTest
    static void refreshToken_noCachedRefresh_fullRequest() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        String token = OAuthTokenService.refreshToken(profile);
        Test.stopTest();

        System.assertEquals('test_access_token_123', token);
    }

    // ── refreshToken with cached refresh token ───────────────────────

    @isTest
    static void refreshToken_withCachedRefresh_usesRefresh() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        OAuthTokenService.CachedOAuthToken cached = new OAuthTokenService.CachedOAuthToken(
            'old', 'valid_refresh', 'Bearer', 3600
        );
        OAuthTokenService.TOKEN_CACHE.put(profile.Id, cached);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        String token = OAuthTokenService.refreshToken(profile);
        Test.stopTest();

        System.assertEquals('test_access_token_123', token);
    }

    // ── clearCache ───────────────────────────────────────────────────

    @isTest
    static void clearCache_removesAllTokens() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        OAuthTokenService.CachedOAuthToken cached = new OAuthTokenService.CachedOAuthToken(
            'token', null, 'Bearer', 3600
        );
        OAuthTokenService.TOKEN_CACHE.put(profile.Id, cached);

        Test.startTest();
        OAuthTokenService.clearCache();
        Test.stopTest();

        System.assertEquals(0, OAuthTokenService.TOKEN_CACHE.size());
    }

    // ── evictToken ───────────────────────────────────────────────────

    @isTest
    static void evictToken_removesSpecificToken() {
        Integration_Auth_Profile__c profile = createOAuthProfile('client_credentials');

        OAuthTokenService.CachedOAuthToken cached = new OAuthTokenService.CachedOAuthToken(
            'token', null, 'Bearer', 3600
        );
        OAuthTokenService.TOKEN_CACHE.put(profile.Id, cached);

        Test.startTest();
        OAuthTokenService.evictToken(profile.Id);
        Test.stopTest();

        System.assertEquals(false, OAuthTokenService.TOKEN_CACHE.containsKey(profile.Id));
    }

    @isTest
    static void evictToken_nullId_noop() {
        Test.startTest();
        OAuthTokenService.evictToken(null);
        Test.stopTest();
        System.assert(true, 'Should handle null gracefully');
    }

    // ── Password grant missing username throws ───────────────────────

    @isTest
    static void getAccessToken_passwordGrantMissingUsername_throws() {
        Integration_Auth_Profile__c profile = new Integration_Auth_Profile__c(
            Profile_Name__c = 'No Username',
            Auth_Type__c = 'OAuth_2_0',
            Active__c = true,
            OAuth_Token_Endpoint__c = TOKEN_ENDPOINT,
            OAuth_Client_Id__c = 'client',
            OAuth_Client_Secret__c = 'secret',
            OAuth_Grant_Type__c = 'password'
        );
        insert profile;

        Boolean thrown = false;
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new SuccessTokenMock());
        try {
            OAuthTokenService.getAccessToken(profile);
        } catch (OAuthTokenService.OAuthTokenException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Username__c'));
        }
        Test.stopTest();
        System.assert(thrown);
    }
}