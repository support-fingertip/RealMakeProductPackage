/**
 * @description Single REST endpoint for ALL inbound integrations in the Integration Orchestration Platform.
 *              Routes requests to InboundIntegrationService based on the integration key extracted
 *              from the URL path. Supports POST, GET, PUT, PATCH, and DELETE HTTP methods.
 *
 *              URL patterns supported:
 *              - Standard:  /services/apexrest/integration/{integrationKey}
 *              - Site URL:  /MySiteName/services/apexrest/integration/{integrationKey}
 *              - Param:     /services/apexrest/integration?integrationKey={integrationKey}
 *
 *              Request body input methods:
 *              - JSON body:  Content-Type: application/json with JSON payload
 *              - URL params: Query parameters converted to JSON (all HTTP methods)
 *              - Form body:  Content-Type: application/x-www-form-urlencoded
 *              - Merged:     JSON body + URL params combined (URL params supplement body)
 *
 *              Processing flow for each handler:
 *              1. Extract integration key from path segment or ?integrationKey= parameter
 *              2. Collect request headers into a case-insensitive map
 *              3. Build request body from JSON body, URL params, or form-encoded data
 *              4. Delegate to InboundIntegrationService.processInbound()
 *              5. Set the appropriate HTTP status code and return a JSON response
 *
 * @author Integration Platform
 */
@RestResource(urlMapping='/restConnection/*')
global with sharing class IntegrationRestResource {

    // ─────────────────────────────────────────────────────────────────────────
    //  HTTP Handlers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Handles inbound HTTP POST requests. Primary method for receiving
     *              data from external systems (create / upsert operations).
     */
    @HttpPost
    global static void handlePost() {
        processRequest('POST');
    }

    /**
     * @description Handles inbound HTTP GET requests. Useful for health-check or
     *              status-query integrations that do not send a body.
     */
    @HttpGet
    global static void handleGet() {
        processRequest('GET');
    }

    /**
     * @description Handles inbound HTTP PUT requests for full-record replacement
     *              style integrations.
     */
    @HttpPut
    global static void handlePut() {
        processRequest('PUT');
    }

    /**
     * @description Handles inbound HTTP PATCH requests for partial-record update
     *              style integrations.
     */
    @HttpPatch
    global static void handlePatch() {
        processRequest('PATCH');
    }

    /**
     * @description Handles inbound HTTP DELETE requests for record-removal
     *              style integrations.
     */
    @HttpDelete
    global static void handleDelete() {
        processRequest('DELETE');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Core Processing
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Central processing method invoked by all HTTP verb handlers.
     *              Extracts the integration key, collects headers, delegates to
     *              InboundIntegrationService, and writes the response.
     * @param httpMethod The HTTP method string (POST, GET, PUT, PATCH, DELETE)
     */
    private static void processRequest(String httpMethod) {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        // Ensure response object is available
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }

        try {
            // ── Step 1: Extract integration key from URL path ──
            String integrationKey = extractIntegrationKey(req);
            if (String.isBlank(integrationKey)) {
                sendErrorResponse(res, 400, 'Integration key is required in the URL path. '
                    + 'Expected: /integration/{integrationKey}');
                return;
            }

            // ── Step 2: Collect request headers ──
            Map<String, String> headers = collectHeaders(req);

            // ── Step 3: Extract request body ──
            String requestBody = extractRequestBody(req, httpMethod);

            // ── Step 4: Delegate to InboundIntegrationService ──
            InboundResult result = InboundIntegrationService.processInbound(
                integrationKey, requestBody, headers, httpMethod
            );

            // ── Step 5: Send response ──
            sendResponse(res, result);

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'IntegrationRestResource unhandled exception: '
                + ex.getMessage() + '\n' + ex.getStackTraceString());
            sendErrorResponse(res, 500, 'An unexpected error occurred: ' + ex.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  URL & Header Extraction
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Extracts the integration key from the request URI or URL parameters.
     *              Supports standard Apex REST paths, Salesforce Site URL prefixes, and
     *              query-parameter fallback.
     *
     *              Extraction priority:
     *              1. Path segment after /integration/ (works with Site prefixes)
     *              2. URL parameter: ?integrationKey={key}
     *
     *              Examples:
     *              - /services/apexrest/integration/my_key  ->  my_key
     *              - /MySite/services/apexrest/integration/my_key  ->  my_key
     *              - /services/apexrest/integration?integrationKey=my_key  ->  my_key
     *
     * @param req The RestRequest
     * @return The integration key string or null
     */
    @TestVisible
    private static String extractIntegrationKey(RestRequest req) {
        if (req == null) {
            return null;
        }

        // ── Strategy 1: Extract from the URL path (handles both standard and Site URLs) ──
        if (String.isNotBlank(req.requestURI)) {
            String uri = req.requestURI;

            // Remove trailing slash if present
            if (uri.endsWith('/')) {
                uri = uri.substring(0, uri.length() - 1);
            }

            // Find '/integration/' in the path and take what comes after it.
            // This works for both standard paths and Site-prefixed paths:
            //   /services/apexrest/integration/KEY
            //   /MySite/services/apexrest/integration/KEY
            Integer integrationIdx = uri.toLowerCase().indexOf('/integration/');
            if (integrationIdx >= 0) {
                String afterIntegration = uri.substring(integrationIdx + '/integration/'.length());
                // Take the first segment after /integration/ (ignore anything beyond another slash)
                Integer nextSlash = afterIntegration.indexOf('/');
                String key = nextSlash > 0 ? afterIntegration.substring(0, nextSlash) : afterIntegration;
                if (String.isNotBlank(key)) {
                    return EncodingUtil.urlDecode(key, 'UTF-8');
                }
            }

            // Fallback: last path segment (original behaviour)
            Integer lastSlash = uri.lastIndexOf('/');
            if (lastSlash >= 0 && lastSlash < uri.length() - 1) {
                String key = uri.substring(lastSlash + 1);
                if (!key.equalsIgnoreCase('integration')) {
                    return EncodingUtil.urlDecode(key, 'UTF-8');
                }
            }
        }

        // ── Strategy 2: Fallback to URL parameter ──
        // Useful when the key cannot be embedded in the path (some Site/proxy configurations)
        if (req.params != null && req.params.containsKey('integrationKey')) {
            String paramKey = req.params.get('integrationKey');
            if (String.isNotBlank(paramKey)) {
                return paramKey.trim();
            }
        }

        return null;
    }

    /**
     * @description Collects all request headers into a flat Map for downstream consumption.
     *              Salesforce's RestRequest.headers is already a Map<String, String>.
     * @param req The RestRequest
     * @return Map of header name to value
     */
    @TestVisible
    private static Map<String, String> collectHeaders(RestRequest req) {
        Map<String, String> headers = new Map<String, String>();
        if (req != null && req.headers != null) {
            headers.putAll(req.headers);
        }
        return headers;
    }

    /**
     * @description Extracts the request body from the most appropriate source. Supports three
     *              input modes that work for ALL HTTP methods:
     *
     *              1. JSON body        -- Content-Type: application/json with a JSON payload
     *              2. Form-encoded body -- Content-Type: application/x-www-form-urlencoded
     *              3. URL parameters   -- Query parameters (?key=value&key2=value2)
     *
     *              When BOTH a JSON body AND URL parameters are present the two are merged:
     *              URL parameter values are added to the JSON object as supplemental fields
     *              (existing body keys take precedence over URL params of the same name).
     *
     * @param req        The RestRequest
     * @param httpMethod The HTTP method
     * @return The request body string as JSON (may be null when no input is provided)
     */
    @TestVisible
    private static String extractRequestBody(RestRequest req, String httpMethod) {
        String bodyStr = null;
        Boolean hasBody = (req.requestBody != null && req.requestBody.size() > 0);
        Boolean hasParams = (req.params != null && !req.params.isEmpty());

        // ── Determine the raw body string ──
        if (hasBody) {
            bodyStr = req.requestBody.toString();

            // Check if the body is form-encoded (application/x-www-form-urlencoded)
            String contentType = getContentType(req);
            if (String.isNotBlank(contentType) && contentType.containsIgnoreCase('x-www-form-urlencoded')) {
                bodyStr = convertFormEncodedToJson(bodyStr);
            }
        }

        // ── Build a JSON object from URL parameters (excluding the integrationKey param) ──
        Map<String, Object> paramMap = null;
        if (hasParams) {
            paramMap = new Map<String, Object>();
            for (String key : req.params.keySet()) {
                // Skip the routing parameter used for key extraction
                if (key == 'integrationKey') {
                    continue;
                }
                paramMap.put(key, req.params.get(key));
            }
            if (paramMap.isEmpty()) {
                paramMap = null;
            }
        }

        // ── Merge or return the appropriate source ──
        if (bodyStr != null && paramMap != null) {
            // Merge: body fields take precedence; URL params fill in the gaps
            try {
                Object parsed = JSON.deserializeUntyped(bodyStr);
                if (parsed instanceof Map<String, Object>) {
                    Map<String, Object> bodyMap = (Map<String, Object>) parsed;
                    for (String key : paramMap.keySet()) {
                        if (!bodyMap.containsKey(key)) {
                            bodyMap.put(key, paramMap.get(key));
                        }
                    }
                    return JSON.serialize(bodyMap);
                } else if (parsed instanceof List<Object>) {
                    // Array body -- attach URL params as a wrapper
                    Map<String, Object> wrapper = new Map<String, Object>();
                    wrapper.put('records', parsed);
                    wrapper.putAll(paramMap);
                    return JSON.serialize(wrapper);
                }
            } catch (Exception ex) {
                // If merge fails, return body as-is
                return bodyStr;
            }
        }

        if (bodyStr != null) {
            return bodyStr;
        }

        if (paramMap != null) {
            return JSON.serialize(paramMap);
        }

        return null;
    }

    /**
     * @description Converts a form-encoded body string (key=value&key2=value2) into a JSON string.
     *              Properly URL-decodes both keys and values.
     * @param formBody The raw form-encoded body
     * @return JSON string representation
     */
    @TestVisible
    private static String convertFormEncodedToJson(String formBody) {
        Map<String, Object> result = new Map<String, Object>();
        if (String.isBlank(formBody)) {
            return JSON.serialize(result);
        }

        List<String> pairs = formBody.split('&');
        for (String pair : pairs) {
            if (String.isBlank(pair)) {
                continue;
            }
            List<String> kv = pair.split('=', 2);
            String key = EncodingUtil.urlDecode(kv[0].trim(), 'UTF-8');
            String value = kv.size() > 1 ? EncodingUtil.urlDecode(kv[1].trim(), 'UTF-8') : '';
            result.put(key, value);
        }

        return JSON.serialize(result);
    }

    /**
     * @description Extracts the Content-Type header from the request (case-insensitive).
     * @param req The RestRequest
     * @return The Content-Type header value or null
     */
    private static String getContentType(RestRequest req) {
        if (req.headers == null) {
            return null;
        }
        // Try exact match first
        if (req.headers.containsKey('Content-Type')) {
            return req.headers.get('Content-Type');
        }
        // Case-insensitive fallback
        for (String key : req.headers.keySet()) {
            if (key != null && key.equalsIgnoreCase('Content-Type')) {
                return req.headers.get(key);
            }
        }
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Response Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Writes the InboundResult as a JSON response with proper status code and headers.
     * @param res    The RestResponse to populate
     * @param result The InboundResult from processing
     */
    private static void sendResponse(RestResponse res, InboundResult result) {
        if (result == null) {
            sendErrorResponse(res, 500, 'Processing returned no result.');
            return;
        }

        res.statusCode = result.statusCode;
        res.addHeader('Content-Type', 'application/json');
        res.addHeader('X-Correlation-Id', result.correlationId);
        res.responseBody = Blob.valueOf(JSON.serialize(result.toResponseMap()));
    }

    /**
     * @description Sends a standardized error response with the given status code and message.
     * @param res        The RestResponse to populate
     * @param statusCode The HTTP status code
     * @param message    The error message
     */
    private static void sendErrorResponse(RestResponse res, Integer statusCode, String message) {
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json');

        Map<String, Object> errorBody = new Map<String, Object>{
            'success' => false,
            'errorMessage' => message,
            'statusCode' => statusCode
        };

        res.responseBody = Blob.valueOf(JSON.serialize(errorBody));
    }
}