/**
 * @description Service class responsible for executing HTTP callouts. Builds HttpRequest
 *              objects from IntegrationCalloutRequest wrappers, handles Named Credential
 *              resolution, authentication header injection, content type management,
 *              and timeout configuration.
 * @author Integration Platform
 */
public class IntegrationCalloutService {

    private static final Integer DEFAULT_TIMEOUT_MS = 120000;
    private static final Integer MIN_TIMEOUT_MS = 1;
    private static final Integer MAX_TIMEOUT_MS = 120000;

    // OAuth token cache to avoid repeated token endpoint callouts within a transaction
    private static Map<String, CachedToken> tokenCache = new Map<String, CachedToken>();

    /**
     * @description Executes an HTTP callout using the provided request configuration.
     * @param request The IntegrationCalloutRequest containing all callout details
     * @return The HttpResponse from the external service
     * @throws IntegrationCalloutException if the request is invalid or the callout fails
     */
    public static HttpResponse makeCallout(IntegrationCalloutRequest request) {
        if (request == null) {
            throw new IntegrationCalloutException('Callout request cannot be null.');
        }

        if (!request.isValid()) {
            throw new IntegrationCalloutException(
                'Callout request is invalid. Ensure endpoint/namedCredential and method are set.'
            );
        }

        // Check governor limits before making callout
        validateGovernorLimits();

        HttpRequest httpReq = buildHttpRequest(request);

        try {
            Http http = new Http();
            HttpResponse httpRes = http.send(httpReq);
            return httpRes;
        } catch (System.CalloutException calloutEx) {
            throw new IntegrationCalloutException(
                'Callout failed: ' + calloutEx.getMessage(), calloutEx
            );
        }
    }

    /**
     * @description Executes an HTTP callout with authentication headers injected from the
     *              given auth profile configuration.
     * @param request The callout request
     * @param authProfile The auth profile defining authentication method
     * @return The HttpResponse from the external service
     */
    public static HttpResponse makeCalloutWithAuth(
        IntegrationCalloutRequest request,
        Integration_Auth_Profile__c authProfile
    ) {
        if (request == null) {
            throw new IntegrationCalloutException('Callout request cannot be null.');
        }

        if (authProfile != null && authProfile.Active__c == true) {
            applyAuthentication(request, authProfile);
        }

        return makeCallout(request);
    }

    /**
     * @description Builds an HttpRequest object from the IntegrationCalloutRequest wrapper.
     *              Exposed as public so the IntegrationEngine can build the request separately
     *              for logging purposes before executing.
     * @param request The callout request configuration
     * @return A configured HttpRequest ready for sending
     */
    public static HttpRequest buildHttpRequest(IntegrationCalloutRequest request) {
        HttpRequest httpReq = new HttpRequest();

        // Set endpoint URL
        String fullEndpoint = request.getFullEndpoint();
        httpReq.setEndpoint(fullEndpoint);

        // Set HTTP method
        httpReq.setMethod(request.method.toUpperCase());

        // Set timeout
        Integer timeout = request.timeout != null ? request.timeout : DEFAULT_TIMEOUT_MS;
        timeout = Math.max(MIN_TIMEOUT_MS, Math.min(timeout, MAX_TIMEOUT_MS));
        httpReq.setTimeout(timeout);

        // Set Content-Type header
        if (String.isNotBlank(request.contentType)) {
            httpReq.setHeader('Content-Type', request.contentType);
        }

        // Set custom headers
        if (request.headers != null) {
            for (String headerName : request.headers.keySet()) {
                String headerValue = request.headers.get(headerName);
                if (String.isNotBlank(headerName) && headerValue != null) {
                    httpReq.setHeader(headerName, headerValue);
                }
            }
        }

        // Set correlation ID as a tracking header
        if (String.isNotBlank(request.correlationId)) {
            httpReq.setHeader('X-Correlation-Id', request.correlationId);
        }

        // Set request body for methods that support it
        if (String.isNotBlank(request.body) && methodSupportsBody(request.method)) {
            httpReq.setBody(request.body);
        }

        // Set compressed request if configured
        if (request.compressRequest == true) {
            httpReq.setCompressed(true);
        }

        // Set client certificate if specified
        if (String.isNotBlank(request.clientCertificateName)) {
            httpReq.setClientCertificateName(request.clientCertificateName);
        }

        return httpReq;
    }

    /**
     * @description Execute a pre-built HttpRequest directly. Useful when the caller
     *              has already constructed or modified the HttpRequest (e.g., after
     *              applying custom auth headers via IntegrationAuthManager).
     * @param req The fully configured HttpRequest
     * @return The HttpResponse from the external service
     */
    public static HttpResponse executeCallout(HttpRequest req) {
        validateGovernorLimits();
        Http http = new Http();
        return http.send(req);
    }

    /**
     * @description Applies authentication headers to the request based on the auth profile type.
     *              Supports API Key, Basic Auth, Bearer Token, OAuth 2.0 Client Credentials,
     *              and HMAC signature authentication.
     * @param request The callout request to modify
     * @param authProfile The auth profile configuration
     */
    private static void applyAuthentication(
        IntegrationCalloutRequest request,
        Integration_Auth_Profile__c authProfile
    ) {
        if (authProfile == null || String.isBlank(authProfile.Auth_Type__c)) {
            return;
        }

        String authType = authProfile.Auth_Type__c.toLowerCase().trim();

        if (authType == 'api_key' || authType == 'apikey' || authType == 'api key') {
            applyApiKeyAuth(request, authProfile);
        } else if (authType == 'basic' || authType == 'basic_auth') {
            applyBasicAuth(request, authProfile);
        } else if (authType == 'bearer' || authType == 'bearer_token') {
            applyBearerAuth(request, authProfile);
        } else if (authType == 'oauth2' || authType == 'oauth' || authType == 'oauth2_client_credentials') {
            applyOAuth2Auth(request, authProfile);
        } else if (authType == 'hmac' || authType == 'hmac_signature') {
            applyHmacAuth(request, authProfile);
        } else {
            System.debug(LoggingLevel.WARN,
                'IntegrationCalloutService: Unsupported auth type "' + authProfile.Auth_Type__c + '"'
            );
        }
    }

    /**
     * @description Applies API Key authentication (header or query parameter).
     */
    private static void applyApiKeyAuth(
        IntegrationCalloutRequest request,
        Integration_Auth_Profile__c authProfile
    ) {
        String headerName = String.isNotBlank(authProfile.Auth_Header_Name__c)
            ? authProfile.Auth_Header_Name__c
            : 'X-API-Key';

        String apiKey = authProfile.API_Key__c;
        if (String.isNotBlank(apiKey)) {
            String prefix = String.isNotBlank(authProfile.Auth_Token_Prefix__c)
                ? authProfile.Auth_Token_Prefix__c + ' '
                : '';
            request.addHeader(headerName, prefix + apiKey);
        }
    }

    /**
     * @description Applies Basic authentication (Base64-encoded username:password).
     */
    private static void applyBasicAuth(
        IntegrationCalloutRequest request,
        Integration_Auth_Profile__c authProfile
    ) {
        String username = authProfile.Username__c != null ? authProfile.Username__c : '';
        String password = authProfile.Password__c != null ? authProfile.Password__c : '';

        String credentials = username + ':' + password;
        String encodedCredentials = EncodingUtil.base64Encode(Blob.valueOf(credentials));

        String headerName = String.isNotBlank(authProfile.Auth_Header_Name__c)
            ? authProfile.Auth_Header_Name__c
            : 'Authorization';

        request.addHeader(headerName, 'Basic ' + encodedCredentials);
    }

    /**
     * @description Applies Bearer token authentication.
     */
    private static void applyBearerAuth(
        IntegrationCalloutRequest request,
        Integration_Auth_Profile__c authProfile
    ) {
        String token = authProfile.API_Key__c; // API_Key__c stores the bearer token
        if (String.isNotBlank(token)) {
            String prefix = String.isNotBlank(authProfile.Auth_Token_Prefix__c)
                ? authProfile.Auth_Token_Prefix__c
                : 'Bearer';

            String headerName = String.isNotBlank(authProfile.Auth_Header_Name__c)
                ? authProfile.Auth_Header_Name__c
                : 'Authorization';

            request.addHeader(headerName, prefix + ' ' + token);
        }
    }

    /**
     * @description Applies OAuth 2.0 Client Credentials authentication.
     *              Fetches and caches the access token from the token endpoint.
     */
    private static void applyOAuth2Auth(
        IntegrationCalloutRequest request,
        Integration_Auth_Profile__c authProfile
    ) {
        String accessToken = getOAuthToken(authProfile);

        if (String.isNotBlank(accessToken)) {
            String prefix = String.isNotBlank(authProfile.Auth_Token_Prefix__c)
                ? authProfile.Auth_Token_Prefix__c
                : 'Bearer';

            String headerName = String.isNotBlank(authProfile.Auth_Header_Name__c)
                ? authProfile.Auth_Header_Name__c
                : 'Authorization';

            request.addHeader(headerName, prefix + ' ' + accessToken);
        }
    }

    /**
     * @description Fetches an OAuth 2.0 access token, using the transaction cache when available.
     * @param authProfile The auth profile with OAuth configuration
     * @return The access token string, or null on failure
     */
    private static String getOAuthToken(Integration_Auth_Profile__c authProfile) {
        String cacheKey = String.valueOf(authProfile.Id);

        // Check cache
        if (tokenCache.containsKey(cacheKey)) {
            CachedToken cached = tokenCache.get(cacheKey);
            if (cached.isValid()) {
                return cached.token;
            }
            tokenCache.remove(cacheKey);
        }

        // Validate required OAuth fields
        if (String.isBlank(authProfile.OAuth_Token_Endpoint__c)) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationCalloutService: OAuth_Token_Endpoint__c is required for OAuth2 auth.'
            );
            return null;
        }

        try {
            validateGovernorLimits();

            // Build token request
            HttpRequest tokenReq = new HttpRequest();
            tokenReq.setEndpoint(authProfile.OAuth_Token_Endpoint__c);
            tokenReq.setMethod('POST');
            tokenReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            tokenReq.setTimeout(30000);

            String grantType = String.isNotBlank(authProfile.OAuth_Grant_Type__c)
                ? authProfile.OAuth_Grant_Type__c
                : 'client_credentials';

            String body = 'grant_type=' + EncodingUtil.urlEncode(grantType, 'UTF-8');

            if (String.isNotBlank(authProfile.OAuth_Client_Id__c)) {
                body += '&client_id=' + EncodingUtil.urlEncode(authProfile.OAuth_Client_Id__c, 'UTF-8');
            }
            if (String.isNotBlank(authProfile.OAuth_Client_Secret__c)) {
                body += '&client_secret=' + EncodingUtil.urlEncode(authProfile.OAuth_Client_Secret__c, 'UTF-8');
            }
            if (String.isNotBlank(authProfile.OAuth_Scope__c)) {
                body += '&scope=' + EncodingUtil.urlEncode(authProfile.OAuth_Scope__c, 'UTF-8');
            }

            tokenReq.setBody(body);

            Http http = new Http();
            HttpResponse tokenRes = http.send(tokenReq);

            if (tokenRes.getStatusCode() == 200) {
                Map<String, Object> tokenData =
                    (Map<String, Object>) JSON.deserializeUntyped(tokenRes.getBody());

                String accessToken = (String) tokenData.get('access_token');

                if (String.isNotBlank(accessToken)) {
                    // Calculate cache duration
                    Integer cacheDurationSeconds = 3600; // Default 1 hour
                    if (authProfile.Token_Cache_Duration__c != null &&
                        authProfile.Token_Cache_Duration__c > 0) {
                        cacheDurationSeconds = (Integer) authProfile.Token_Cache_Duration__c;
                    } else if (tokenData.containsKey('expires_in')) {
                        Object expiresIn = tokenData.get('expires_in');
                        if (expiresIn instanceof Integer) {
                            cacheDurationSeconds = (Integer) expiresIn - 60; // Buffer
                        } else if (expiresIn instanceof Decimal) {
                            cacheDurationSeconds = ((Decimal) expiresIn).intValue() - 60;
                        }
                    }

                    CachedToken cached = new CachedToken();
                    cached.token = accessToken;
                    cached.expiresAt = Datetime.now().addSeconds(Math.max(cacheDurationSeconds, 60));
                    tokenCache.put(cacheKey, cached);

                    return accessToken;
                }
            }

            System.debug(LoggingLevel.ERROR,
                'IntegrationCalloutService: OAuth token request failed with status ' +
                tokenRes.getStatusCode() + ': ' + tokenRes.getBody()
            );
            return null;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationCalloutService: OAuth token request exception: ' + ex.getMessage()
            );
            return null;
        }
    }

    /**
     * @description Applies HMAC signature authentication. Computes an HMAC signature of the
     *              request body and adds it as a header.
     */
    private static void applyHmacAuth(
        IntegrationCalloutRequest request,
        Integration_Auth_Profile__c authProfile
    ) {
        if (String.isBlank(authProfile.HMAC_Secret__c)) {
            System.debug(LoggingLevel.WARN,
                'IntegrationCalloutService: HMAC_Secret__c is required for HMAC auth.'
            );
            return;
        }

        String payload = String.isNotBlank(request.body) ? request.body : '';
        String algorithm = String.isNotBlank(authProfile.HMAC_Algorithm__c)
            ? authProfile.HMAC_Algorithm__c
            : 'HmacSHA256';

        // Map common algorithm names to Crypto class names
        String cryptoAlgorithm = mapHmacAlgorithm(algorithm);

        try {
            Blob signatureBlob = Crypto.generateMac(
                cryptoAlgorithm,
                Blob.valueOf(payload),
                Blob.valueOf(authProfile.HMAC_Secret__c)
            );
            String signature = EncodingUtil.convertToHex(signatureBlob);

            String headerName = String.isNotBlank(authProfile.HMAC_Header_Name__c)
                ? authProfile.HMAC_Header_Name__c
                : 'X-HMAC-Signature';

            request.addHeader(headerName, signature);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationCalloutService: HMAC signature generation failed: ' + ex.getMessage()
            );
        }
    }

    /**
     * @description Maps common HMAC algorithm names to Salesforce Crypto class algorithm strings.
     * @param algorithm The algorithm name from configuration
     * @return The Salesforce Crypto algorithm string
     */
    private static String mapHmacAlgorithm(String algorithm) {
        if (String.isBlank(algorithm)) {
            return 'HmacSHA256';
        }

        String normalizedAlg = algorithm.toLowerCase().replaceAll('[^a-z0-9]', '');

        if (normalizedAlg.contains('sha256') || normalizedAlg == 'hmacsha256') {
            return 'HmacSHA256';
        } else if (normalizedAlg.contains('sha1') || normalizedAlg == 'hmacsha1') {
            return 'hmacSHA1';
        } else if (normalizedAlg.contains('sha512') || normalizedAlg == 'hmacsha512') {
            return 'HmacSHA512';
        } else if (normalizedAlg.contains('md5') || normalizedAlg == 'hmacmd5') {
            return 'hmacMD5';
        }

        // Return as-is and let Crypto.generateMac handle validation
        return algorithm;
    }

    /**
     * @description Determines whether the given HTTP method typically supports a request body.
     * @param method The HTTP method name
     * @return True if the method supports a body
     */
    private static Boolean methodSupportsBody(String method) {
        if (String.isBlank(method)) {
            return false;
        }
        Set<String> bodyMethods = new Set<String>{ 'POST', 'PUT', 'PATCH' };
        return bodyMethods.contains(method.toUpperCase());
    }

    /**
     * @description Checks that we have not exceeded governor limits for callouts.
     * @throws IntegrationCalloutException if limits would be exceeded
     */
    private static void validateGovernorLimits() {
        Integer calloutsUsed = Limits.getCallouts();
        Integer calloutsLimit = Limits.getLimitCallouts();

        if (calloutsUsed >= calloutsLimit) {
            throw new IntegrationCalloutException(
                'Cannot make callout: governor limit reached (' +
                calloutsUsed + '/' + calloutsLimit + ' callouts used).'
            );
        }
    }

    /**
     * @description Extracts response headers from an HttpResponse into a map.
     * @param response The HttpResponse to extract headers from
     * @return Map of header names to values
     */
    public static Map<String, String> extractResponseHeaders(HttpResponse response) {
        Map<String, String> headers = new Map<String, String>();

        if (response == null) {
            return headers;
        }

        List<String> headerKeys = response.getHeaderKeys();
        if (headerKeys != null) {
            for (String key : headerKeys) {
                if (key != null) {
                    headers.put(key, response.getHeader(key));
                }
            }
        }

        return headers;
    }

    /**
     * @description Inner class for caching OAuth tokens within a transaction.
     */
    private class CachedToken {
        public String token;
        public Datetime expiresAt;

        public Boolean isValid() {
            return String.isNotBlank(token) && expiresAt != null && Datetime.now() < expiresAt;
        }
    }

    /**
     * @description Custom exception for callout errors.
     */
    public class IntegrationCalloutException extends Exception {}
}