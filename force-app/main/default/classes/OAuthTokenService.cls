/**
 * @description Service class responsible for OAuth 2.0 token acquisition, caching, and refresh.
 *              Supports client_credentials, password, authorization_code, and refresh_token
 *              grant types. Maintains a static request-scope cache with expiry tracking to
 *              minimise callouts and respect Salesforce governor limits.
 *
 * @author Integration Platform
 * @date 2026-02-15
 */
public with sharing class OAuthTokenService {

    // ── Constants ──
    private static final String CONTENT_TYPE_FORM = 'application/x-www-form-urlencoded';
    private static final Integer DEFAULT_EXPIRY_SECONDS = 3600;
    private static final Integer EXPIRY_BUFFER_SECONDS = 30;

    // ── Request-scope token cache keyed by profile Id ──
    @TestVisible
    private static final Map<Id, CachedOAuthToken> TOKEN_CACHE = new Map<Id, CachedOAuthToken>();

    // ─────────────────────────────────────────────────────────────────────────
    //  Public API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Retrieves a valid access token for the given auth profile. Returns a
     *              cached token when available and not expired; otherwise performs a new
     *              token request against the configured token endpoint.
     * @param authProfile The OAuth-configured Integration_Auth_Profile__c record.
     * @return The access token string.
     * @throws OAuthTokenException on any failure during token acquisition.
     */
    public static String getAccessToken(Integration_Auth_Profile__c authProfile) {
        validateOAuthProfile(authProfile);

        Id profileId = authProfile.Id;

        // Attempt cache hit
        if (profileId != null && TOKEN_CACHE.containsKey(profileId)) {
            CachedOAuthToken cached = TOKEN_CACHE.get(profileId);
            if (!cached.isExpired()) {
                return cached.accessToken;
            }
            // Token expired -- attempt refresh if we have a refresh token
            if (String.isNotBlank(cached.refreshTokenValue)) {
                try {
                    return refreshTokenInternal(authProfile, cached.refreshTokenValue);
                } catch (Exception e) {
                    // Refresh failed -- fall through to full token request
                    System.debug(LoggingLevel.WARN,
                        'OAuth refresh failed for profile ' + authProfile.Profile_Name__c +
                        '. Falling back to full token request. Error: ' + e.getMessage()
                    );
                }
            }
        }

        // Full token request
        return requestNewToken(authProfile);
    }

    /**
     * @description Forces a token refresh for the given auth profile, bypassing the cache.
     *              If no refresh token is available, performs a full token request instead.
     * @param authProfile The OAuth-configured Integration_Auth_Profile__c record.
     * @return The new access token string.
     * @throws OAuthTokenException on any failure during token refresh.
     */
    public static String refreshToken(Integration_Auth_Profile__c authProfile) {
        validateOAuthProfile(authProfile);

        Id profileId = authProfile.Id;

        // Check if we have a cached refresh token
        if (profileId != null && TOKEN_CACHE.containsKey(profileId)) {
            CachedOAuthToken cached = TOKEN_CACHE.get(profileId);
            if (String.isNotBlank(cached.refreshTokenValue)) {
                return refreshTokenInternal(authProfile, cached.refreshTokenValue);
            }
        }

        // No refresh token available -- do a full request
        return requestNewToken(authProfile);
    }

    /**
     * @description Clears all cached tokens. Useful during testing or forced re-auth scenarios.
     */
    public static void clearCache() {
        TOKEN_CACHE.clear();
    }

    /**
     * @description Evicts the cached token for a single profile.
     * @param profileId The Id of the auth profile to evict.
     */
    public static void evictToken(Id profileId) {
        if (profileId != null) {
            TOKEN_CACHE.remove(profileId);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Token Request Logic
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Performs a new token request based on the configured grant type.
     */
    private static String requestNewToken(Integration_Auth_Profile__c authProfile) {
        String grantType = authProfile.OAuth_Grant_Type__c;

        if (String.isBlank(grantType)) {
            throw new OAuthTokenException('OAuth_Grant_Type__c is required for OAuth 2.0 authentication.');
        }

        String requestBody;

        if (grantType == 'client_credentials') {
            requestBody = buildClientCredentialsBody(authProfile);
        } else if (grantType == 'password') {
            requestBody = buildPasswordGrantBody(authProfile);
        } else if (grantType == 'authorization_code') {
            throw new OAuthTokenException(
                'authorization_code grant type requires an authorization code which must be ' +
                'obtained interactively. Use the refresh_token grant type for server-to-server flows.'
            );
        } else if (grantType == 'refresh_token') {
            throw new OAuthTokenException(
                'refresh_token grant type requires a refresh token. ' +
                'Obtain an initial token using client_credentials or password grant first.'
            );
        } else {
            throw new OAuthTokenException('Unsupported OAuth_Grant_Type__c: ' + grantType);
        }

        return executeTokenRequest(authProfile, requestBody);
    }

    /**
     * @description Builds the request body for the client_credentials grant type.
     */
    private static String buildClientCredentialsBody(Integration_Auth_Profile__c authProfile) {
        if (String.isBlank(authProfile.OAuth_Client_Id__c)) {
            throw new OAuthTokenException('OAuth_Client_Id__c is required for client_credentials grant.');
        }
        if (String.isBlank(authProfile.OAuth_Client_Secret__c)) {
            throw new OAuthTokenException('OAuth_Client_Secret__c is required for client_credentials grant.');
        }

        String body = 'grant_type=client_credentials'
            + '&client_id=' + EncodingUtil.urlEncode(authProfile.OAuth_Client_Id__c, 'UTF-8')
            + '&client_secret=' + EncodingUtil.urlEncode(authProfile.OAuth_Client_Secret__c, 'UTF-8');

        if (String.isNotBlank(authProfile.OAuth_Scope__c)) {
            body += '&scope=' + EncodingUtil.urlEncode(authProfile.OAuth_Scope__c, 'UTF-8');
        }

        return body;
    }

    /**
     * @description Builds the request body for the password (Resource Owner) grant type.
     */
    private static String buildPasswordGrantBody(Integration_Auth_Profile__c authProfile) {
        if (String.isBlank(authProfile.OAuth_Client_Id__c)) {
            throw new OAuthTokenException('OAuth_Client_Id__c is required for password grant.');
        }
        if (String.isBlank(authProfile.OAuth_Client_Secret__c)) {
            throw new OAuthTokenException('OAuth_Client_Secret__c is required for password grant.');
        }
        if (String.isBlank(authProfile.Username__c)) {
            throw new OAuthTokenException('Username__c is required for password grant.');
        }

        String password = authProfile.Password__c != null ? authProfile.Password__c : '';

        String body = 'grant_type=password'
            + '&client_id=' + EncodingUtil.urlEncode(authProfile.OAuth_Client_Id__c, 'UTF-8')
            + '&client_secret=' + EncodingUtil.urlEncode(authProfile.OAuth_Client_Secret__c, 'UTF-8')
            + '&username=' + EncodingUtil.urlEncode(authProfile.Username__c, 'UTF-8')
            + '&password=' + EncodingUtil.urlEncode(password, 'UTF-8');

        if (String.isNotBlank(authProfile.OAuth_Scope__c)) {
            body += '&scope=' + EncodingUtil.urlEncode(authProfile.OAuth_Scope__c, 'UTF-8');
        }

        return body;
    }

    /**
     * @description Performs a refresh_token grant request.
     */
    private static String refreshTokenInternal(Integration_Auth_Profile__c authProfile, String refreshTokenValue) {
        if (String.isBlank(authProfile.OAuth_Client_Id__c)) {
            throw new OAuthTokenException('OAuth_Client_Id__c is required for token refresh.');
        }

        String body = 'grant_type=refresh_token'
            + '&refresh_token=' + EncodingUtil.urlEncode(refreshTokenValue, 'UTF-8')
            + '&client_id=' + EncodingUtil.urlEncode(authProfile.OAuth_Client_Id__c, 'UTF-8');

        if (String.isNotBlank(authProfile.OAuth_Client_Secret__c)) {
            body += '&client_secret=' + EncodingUtil.urlEncode(authProfile.OAuth_Client_Secret__c, 'UTF-8');
        }

        return executeTokenRequest(authProfile, body);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  HTTP Execution & Response Parsing
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Executes the token endpoint HTTP request and parses the response.
     */
    private static String executeTokenRequest(Integration_Auth_Profile__c authProfile, String requestBody) {
        if (String.isBlank(authProfile.OAuth_Token_Endpoint__c)) {
            throw new OAuthTokenException('OAuth_Token_Endpoint__c is required for OAuth 2.0 authentication.');
        }

        HttpRequest req = new HttpRequest();
        req.setEndpoint(authProfile.OAuth_Token_Endpoint__c);
        req.setMethod('POST');
        req.setHeader('Content-Type', CONTENT_TYPE_FORM);
        req.setHeader('Accept', 'application/json');
        req.setBody(requestBody);
        req.setTimeout(30000); // 30 second timeout

        HttpResponse resp;
        try {
            Http http = new Http();
            resp = http.send(req);
        } catch (Exception e) {
            throw new OAuthTokenException(
                'Failed to connect to OAuth token endpoint (' +
                authProfile.OAuth_Token_Endpoint__c + '): ' + e.getMessage(), e
            );
        }

        return parseTokenResponse(authProfile, resp);
    }

    /**
     * @description Parses the OAuth token endpoint HTTP response. Extracts access_token,
     *              expires_in, token_type, and optionally refresh_token. Caches the result.
     */
    private static String parseTokenResponse(Integration_Auth_Profile__c authProfile, HttpResponse resp) {
        Integer statusCode = resp.getStatusCode();
        String responseBody = resp.getBody();

        if (statusCode < 200 || statusCode >= 300) {
            String errorDetail = '';
            try {
                Map<String, Object> errorMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
                if (errorMap.containsKey('error_description')) {
                    errorDetail = ' - ' + String.valueOf(errorMap.get('error_description'));
                } else if (errorMap.containsKey('error')) {
                    errorDetail = ' - ' + String.valueOf(errorMap.get('error'));
                }
            } catch (Exception e) {
                // Response is not valid JSON -- use raw body (truncated)
                errorDetail = String.isNotBlank(responseBody)
                    ? ' - ' + responseBody.abbreviate(500)
                    : '';
            }

            throw new OAuthTokenException(
                'OAuth token request failed with status ' + statusCode +
                ' for profile "' + authProfile.Profile_Name__c + '"' + errorDetail
            );
        }

        if (String.isBlank(responseBody)) {
            throw new OAuthTokenException('OAuth token endpoint returned an empty response body.');
        }

        Map<String, Object> tokenData;
        try {
            tokenData = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        } catch (Exception e) {
            throw new OAuthTokenException(
                'Failed to parse OAuth token response as JSON: ' + e.getMessage(), e
            );
        }

        String accessToken = getStringValue(tokenData, 'access_token');
        if (String.isBlank(accessToken)) {
            throw new OAuthTokenException(
                'OAuth token response did not contain an access_token for profile "' +
                authProfile.Profile_Name__c + '".'
            );
        }

        // Extract expiry -- default to configured cache duration or 3600s
        Integer expiresIn = getIntegerValue(tokenData, 'expires_in');
        if (expiresIn == null || expiresIn <= 0) {
            expiresIn = authProfile.Token_Cache_Duration__c != null
                ? Integer.valueOf(authProfile.Token_Cache_Duration__c)
                : DEFAULT_EXPIRY_SECONDS;
        }

        String refreshTokenValue = getStringValue(tokenData, 'refresh_token');
        String tokenType = getStringValue(tokenData, 'token_type');

        // Cache the token
        Id profileId = authProfile.Id;
        if (profileId != null) {
            TOKEN_CACHE.put(profileId, new CachedOAuthToken(
                accessToken,
                refreshTokenValue,
                tokenType,
                expiresIn
            ));
        }

        return accessToken;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Validation
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Validates that the auth profile has the minimum required OAuth fields.
     */
    private static void validateOAuthProfile(Integration_Auth_Profile__c authProfile) {
        if (authProfile == null) {
            throw new OAuthTokenException('Integration_Auth_Profile__c cannot be null.');
        }
        if (String.isBlank(authProfile.OAuth_Token_Endpoint__c)) {
            throw new OAuthTokenException(
                'OAuth_Token_Endpoint__c must be configured for OAuth 2.0 authentication.'
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Utility Methods
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Safely extracts a String value from a deserialized JSON map.
     */
    private static String getStringValue(Map<String, Object> data, String key) {
        if (data == null || !data.containsKey(key) || data.get(key) == null) {
            return null;
        }
        return String.valueOf(data.get(key));
    }

    /**
     * @description Safely extracts an Integer value from a deserialized JSON map.
     */
    private static Integer getIntegerValue(Map<String, Object> data, String key) {
        if (data == null || !data.containsKey(key) || data.get(key) == null) {
            return null;
        }
        try {
            return Integer.valueOf(data.get(key));
        } catch (Exception e) {
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Inner Classes
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Cached OAuth token with expiry tracking and optional refresh token storage.
     */
    @TestVisible
    private class CachedOAuthToken {
        public String accessToken;
        public String refreshTokenValue;
        public String tokenType;
        public Long expiresAtMillis;

        public CachedOAuthToken(String accessToken, String refreshTokenValue, String tokenType, Integer expiresInSeconds) {
            this.accessToken = accessToken;
            this.refreshTokenValue = refreshTokenValue;
            this.tokenType = tokenType;
            // Apply buffer to avoid edge-case expiry
            Long bufferSeconds = Math.min(EXPIRY_BUFFER_SECONDS, expiresInSeconds > 60 ? 30 : 0);
            this.expiresAtMillis = System.currentTimeMillis() + ((expiresInSeconds - bufferSeconds) * 1000);
        }

        public Boolean isExpired() {
            return System.currentTimeMillis() >= expiresAtMillis;
        }
    }

    /**
     * @description Custom exception for OAuth token failures.
     */
    public class OAuthTokenException extends Exception {}
}