/**
 * @description Wrapper class encapsulating all details needed to execute an HTTP callout.
 *              Built by the IntegrationEngine and consumed by IntegrationCalloutService.
 * @author Integration Platform
 */
public class IntegrationCalloutRequest {

    /** Full endpoint URL (or path when using Named Credentials) */
    public String endpoint { get; set; }

    /** HTTP method (GET, POST, PUT, PATCH, DELETE) */
    public String method { get; set; }

    /** Request body content */
    public String body { get; set; }

    /** Content-Type header value */
    public String contentType { get; set; }

    /** HTTP headers to include in the request */
    public Map<String, String> headers { get; set; }

    /** Query parameters to append to the URL */
    public Map<String, String> queryParams { get; set; }

    /** Timeout in milliseconds for the callout */
    public Integer timeout { get; set; }

    /** Salesforce Named Credential developer name (if used instead of direct URL) */
    public String namedCredential { get; set; }

    /** Correlation ID for tracing this request across the platform */
    public String correlationId { get; set; }

    /** Whether the request should use compressed encoding */
    public Boolean compressRequest { get; set; }

    /** Client certificate name for mutual TLS */
    public String clientCertificateName { get; set; }

    /** The Integration_Endpoint__c record ID for reference */
    public Id endpointId { get; set; }

    /**
     * @description Default constructor initializing all collections and safe defaults.
     */
    public IntegrationCalloutRequest() {
        this.headers = new Map<String, String>();
        this.queryParams = new Map<String, String>();
        this.timeout = 120000; // Salesforce max default
        this.compressRequest = false;
        this.method = 'GET';
        this.contentType = 'application/json';
    }

    /**
     * @description Constructs a request with the essential parameters.
     * @param endpoint The full URL or Named Credential path
     * @param method HTTP method
     * @param body Request body
     */
    public IntegrationCalloutRequest(String endpoint, String method, String body) {
        this();
        this.endpoint = endpoint;
        this.method = method;
        this.body = body;
    }

    /**
     * @description Adds a header to the request. Null keys or values are ignored.
     * @param key Header name
     * @param value Header value
     * @return This request instance for fluent chaining
     */
    public IntegrationCalloutRequest addHeader(String key, String value) {
        if (String.isNotBlank(key) && value != null) {
            this.headers.put(key, value);
        }
        return this;
    }

    /**
     * @description Adds a query parameter. Null keys or values are ignored.
     * @param key Parameter name
     * @param value Parameter value
     * @return This request instance for fluent chaining
     */
    public IntegrationCalloutRequest addQueryParam(String key, String value) {
        if (String.isNotBlank(key) && value != null) {
            this.queryParams.put(key, value);
        }
        return this;
    }

    /**
     * @description Builds the full endpoint URL including query parameters.
     *              If a Named Credential is set, prefixes with callout: protocol.
     * @return The fully constructed endpoint URL
     */
    public String getFullEndpoint() {
        String baseUrl = this.endpoint;

        // Prefix Named Credential if configured
        if (String.isNotBlank(this.namedCredential)) {
            baseUrl = 'callout:' + this.namedCredential;
            if (String.isNotBlank(this.endpoint)) {
                baseUrl += (this.endpoint.startsWith('/') ? '' : '/') + this.endpoint;
            }
        }

        // Append query parameters
        if (this.queryParams != null && !this.queryParams.isEmpty()) {
            String queryString = buildQueryString();
            String separator = baseUrl.contains('?') ? '&' : '?';
            baseUrl += separator + queryString;
        }

        return baseUrl;
    }

    /**
     * @description Builds URL-encoded query string from the queryParams map.
     * @return Encoded query string
     */
    private String buildQueryString() {
        List<String> parts = new List<String>();
        for (String key : this.queryParams.keySet()) {
            String value = this.queryParams.get(key);
            parts.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(value, 'UTF-8'));
        }
        return String.join(parts, '&');
    }

    /**
     * @description Validates the request has all required fields for a callout.
     * @return True if the request is valid, false otherwise
     */
    public Boolean isValid() {
        Boolean hasEndpoint = String.isNotBlank(this.endpoint) || String.isNotBlank(this.namedCredential);
        Boolean hasMethod = String.isNotBlank(this.method);
        return hasEndpoint && hasMethod;
    }
}