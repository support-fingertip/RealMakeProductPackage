/**
 * @description Main authentication orchestrator for the Integration Orchestration Platform.
 *              Routes authentication logic based on Auth_Type__c and applies appropriate
 *              headers/credentials to outbound HttpRequest instances.
 *
 *              Supports: Named Credential, OAuth 2.0, API Key, Basic Auth, HMAC, and None.
 *              Employs request-scope token caching via a static map to minimise redundant
 *              callouts and respect governor limits.
 *
 * @author Integration Platform
 * @date 2026-02-15
 */
public with sharing class IntegrationAuthManager {

    // ── Request-scope token cache keyed by Auth Profile Id ──
    private static final Map<Id, CachedToken> TOKEN_CACHE = new Map<Id, CachedToken>();

    // ── Lock flag to prevent re-entrant token refresh within the same transaction ──
    private static final Set<Id> REFRESH_IN_PROGRESS = new Set<Id>();

    /**
     * @description Applies the appropriate authentication mechanism to the given
     *              HttpRequest based on the supplied Integration_Auth_Profile__c record.
     * @param request   The outbound HttpRequest to be authenticated.
     * @param authProfile The auth profile configuration record.
     * @throws IntegrationAuthException when authentication cannot be applied.
     */
    public static void applyAuthentication(HttpRequest request, Integration_Auth_Profile__c authProfile) {
        if (request == null) {
            throw new IntegrationAuthException('HttpRequest cannot be null.');
        }
        if (authProfile == null) {
            throw new IntegrationAuthException('Integration_Auth_Profile__c cannot be null.');
        }
        if (authProfile.Active__c != true) {
            throw new IntegrationAuthException(
                'Auth profile "' + String.valueOf(authProfile.Profile_Name__c) + '" is not active.'
            );
        }

        String authType = authProfile.Auth_Type__c;
        if (String.isBlank(authType)) {
            throw new IntegrationAuthException('Auth_Type__c is not specified on the auth profile.');
        }

        switch on authType {
            when 'Named_Credential' {
                applyNamedCredential(request, authProfile);
            }
            when 'OAuth_2_0' {
                applyOAuth(request, authProfile);
            }
            when 'API_Key' {
                applyApiKey(request, authProfile);
            }
            when 'Basic_Auth' {
                applyBasicAuth(request, authProfile);
            }
            when 'HMAC' {
                applyHmac(request, authProfile);
            }
            when 'None' {
                // No authentication required - intentional no-op
            }
            when else {
                throw new IntegrationAuthException(
                    'Unsupported Auth_Type__c: ' + authType
                );
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Named Credential
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Prefixes the request endpoint with the Named Credential callout syntax.
     *              Expects the current endpoint to contain the path portion only (e.g. /api/v1/resource).
     */
    private static void applyNamedCredential(HttpRequest request, Integration_Auth_Profile__c authProfile) {
        String profileName = authProfile.Profile_Name__c;
        if (String.isBlank(profileName)) {
            throw new IntegrationAuthException('Profile_Name__c is required for Named_Credential auth type.');
        }

        String currentEndpoint = request.getEndpoint();
        if (String.isBlank(currentEndpoint)) {
            request.setEndpoint('callout:' + profileName);
        } else if (!currentEndpoint.startsWithIgnoreCase('callout:')) {
            // Preserve any path segments already set on the request
            String separator = currentEndpoint.startsWith('/') ? '' : '/';
            request.setEndpoint('callout:' + profileName + separator + currentEndpoint);
        }
        // If already prefixed with callout:, leave it as-is
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  OAuth 2.0
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Retrieves (or refreshes) an OAuth 2.0 access token and sets it as a
     *              Bearer token on the Authorization header. Uses request-scope caching.
     */
    private static void applyOAuth(HttpRequest request, Integration_Auth_Profile__c authProfile) {
        String accessToken = getOrRefreshOAuthToken(authProfile);
        if (String.isBlank(accessToken)) {
            throw new IntegrationAuthException('Failed to obtain OAuth access token for profile: ' + authProfile.Profile_Name__c);
        }

        String headerName = String.isNotBlank(authProfile.Auth_Header_Name__c)
            ? authProfile.Auth_Header_Name__c
            : 'Authorization';
        String tokenPrefix = String.isNotBlank(authProfile.Auth_Token_Prefix__c)
            ? authProfile.Auth_Token_Prefix__c
            : 'Bearer';

        request.setHeader(headerName, tokenPrefix + ' ' + accessToken);
    }

    /**
     * @description Returns a valid access token from cache or fetches a new one. Implements
     *              a simple re-entrancy guard to prevent concurrent refresh attempts within
     *              the same transaction.
     */
    private static String getOrRefreshOAuthToken(Integration_Auth_Profile__c authProfile) {
        Id profileId = authProfile.Id;

        // Check request-scope cache first
        if (profileId != null && TOKEN_CACHE.containsKey(profileId)) {
            CachedToken cached = TOKEN_CACHE.get(profileId);
            if (!cached.isExpired()) {
                return cached.token;
            }
        }

        // Guard against re-entrant refresh
        if (profileId != null && REFRESH_IN_PROGRESS.contains(profileId)) {
            throw new IntegrationAuthException(
                'Token refresh already in progress for profile: ' + authProfile.Profile_Name__c
            );
        }

        try {
            if (profileId != null) {
                REFRESH_IN_PROGRESS.add(profileId);
            }

            String accessToken = OAuthTokenService.getAccessToken(authProfile);

            // Cache the token for the duration of this transaction
            if (profileId != null && String.isNotBlank(accessToken)) {
                Long cacheDurationSeconds = authProfile.Token_Cache_Duration__c != null
                    ? (Long) authProfile.Token_Cache_Duration__c
                    : 3600;
                TOKEN_CACHE.put(profileId, new CachedToken(accessToken, cacheDurationSeconds));
            }

            return accessToken;
        } finally {
            if (profileId != null) {
                REFRESH_IN_PROGRESS.remove(profileId);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  API Key
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Injects the API key into the configured header (defaults to x-api-key).
     */
    private static void applyApiKey(HttpRequest request, Integration_Auth_Profile__c authProfile) {
        if (String.isBlank(authProfile.API_Key__c)) {
            throw new IntegrationAuthException('API_Key__c is required for API_Key auth type.');
        }

        String headerName = String.isNotBlank(authProfile.Auth_Header_Name__c)
            ? authProfile.Auth_Header_Name__c
            : 'x-api-key';
        String prefix = String.isNotBlank(authProfile.Auth_Token_Prefix__c)
            ? authProfile.Auth_Token_Prefix__c + ' '
            : '';

        request.setHeader(headerName, prefix + authProfile.API_Key__c);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Basic Auth
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Encodes username:password as Base64 and sets the Authorization header.
     */
    private static void applyBasicAuth(HttpRequest request, Integration_Auth_Profile__c authProfile) {
        if (String.isBlank(authProfile.Username__c)) {
            throw new IntegrationAuthException('Username__c is required for Basic_Auth auth type.');
        }
        // Password can technically be empty, but we guard against null
        String password = authProfile.Password__c != null ? authProfile.Password__c : '';

        String credentials = authProfile.Username__c + ':' + password;
        Blob credentialsBlob = Blob.valueOf(credentials);
        String encodedCredentials = EncodingUtil.base64Encode(credentialsBlob);

        String headerName = String.isNotBlank(authProfile.Auth_Header_Name__c)
            ? authProfile.Auth_Header_Name__c
            : 'Authorization';

        request.setHeader(headerName, 'Basic ' + encodedCredentials);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  HMAC
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Computes an HMAC signature of the request body and sets it in the
     *              configured header.
     */
    private static void applyHmac(HttpRequest request, Integration_Auth_Profile__c authProfile) {
        if (String.isBlank(authProfile.HMAC_Secret__c)) {
            throw new IntegrationAuthException('HMAC_Secret__c is required for HMAC auth type.');
        }

        String algorithm = String.isNotBlank(authProfile.HMAC_Algorithm__c)
            ? authProfile.HMAC_Algorithm__c
            : 'HmacSHA256';

        String payload = request.getBody();
        if (payload == null) {
            payload = '';
        }

        String signature = HMACSignatureService.generateSignature(
            payload,
            authProfile.HMAC_Secret__c,
            algorithm
        );

        String headerName = String.isNotBlank(authProfile.HMAC_Header_Name__c)
            ? authProfile.HMAC_Header_Name__c
            : 'X-HMAC-Signature';

        request.setHeader(headerName, signature);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Cache Utilities
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Clears the request-scope token cache. Useful in test contexts or when
     *              a forced re-authentication is needed within the same transaction.
     */
    public static void clearTokenCache() {
        TOKEN_CACHE.clear();
    }

    /**
     * @description Evicts a single profile's cached token.
     * @param profileId The Id of the auth profile whose token should be evicted.
     */
    public static void evictCachedToken(Id profileId) {
        if (profileId != null) {
            TOKEN_CACHE.remove(profileId);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Inner Classes
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Lightweight wrapper for a cached access token with expiry tracking.
     */
    @TestVisible
    private class CachedToken {
        public String token;
        public Long expiresAtMillis;

        public CachedToken(String token, Long cacheDurationSeconds) {
            this.token = token;
            // Subtract a 30-second buffer to avoid edge-case expiry during callout
            this.expiresAtMillis = System.currentTimeMillis() + ((cacheDurationSeconds - 30) * 1000);
        }

        public Boolean isExpired() {
            return System.currentTimeMillis() >= expiresAtMillis;
        }
    }

    /**
     * @description Custom exception for authentication failures.
     */
    public class IntegrationAuthException extends Exception {}
}