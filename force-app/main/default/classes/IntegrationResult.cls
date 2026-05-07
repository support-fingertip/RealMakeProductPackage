/**
 * @description Wrapper class representing the result of an integration callout execution.
 *              Encapsulates response data, mapped values, error information, and execution metrics.
 * @author Integration Platform
 */
public class IntegrationResult {

    /** Whether the integration callout completed successfully */
    public Boolean success { get; set; }

    /** HTTP status code returned by the external service */
    public Integer statusCode { get; set; }

    /** Raw response body from the external service */
    public String responseBody { get; set; }

    /** Response values mapped to Salesforce fields via Integration_Response_Mapping__c */
    public Map<String, Object> mappedValues { get; set; }

    /** Error message if the callout failed */
    public String errorMessage { get; set; }

    /** Unique correlation ID for tracing this execution across logs */
    public String correlationId { get; set; }

    /** Total execution time in milliseconds */
    public Long executionTimeMs { get; set; }

    /** The Integration_Log__c record ID created for this execution */
    public Id logId { get; set; }

    /** Number of retry attempts made before final result */
    public Integer retryCount { get; set; }

    /** Map of response headers returned by the external service */
    public Map<String, String> responseHeaders { get; set; }

    /**
     * @description Default constructor initializing all fields to safe defaults.
     */
    public IntegrationResult() {
        this.success = false;
        this.statusCode = 0;
        this.responseBody = '';
        this.mappedValues = new Map<String, Object>();
        this.errorMessage = '';
        this.correlationId = generateCorrelationId();
        this.executionTimeMs = 0;
        this.retryCount = 0;
        this.responseHeaders = new Map<String, String>();
    }

    /**
     * @description Constructs a successful result with the given status code and body.
     * @param statusCode HTTP status code
     * @param responseBody Raw response body
     * @return A new IntegrationResult marked as successful
     */
    public static IntegrationResult success(Integer statusCode, String responseBody) {
        IntegrationResult result = new IntegrationResult();
        result.success = true;
        result.statusCode = statusCode;
        result.responseBody = responseBody;
        return result;
    }

    /**
     * @description Constructs a failure result with the given error message.
     * @param errorMessage Description of what went wrong
     * @return A new IntegrationResult marked as failed
     */
    public static IntegrationResult failure(String errorMessage) {
        IntegrationResult result = new IntegrationResult();
        result.success = false;
        result.errorMessage = errorMessage;
        return result;
    }

    /**
     * @description Constructs a failure result with the given status code, body, and error.
     * @param statusCode HTTP status code
     * @param responseBody Raw response body
     * @param errorMessage Description of what went wrong
     * @return A new IntegrationResult marked as failed
     */
    public static IntegrationResult failure(Integer statusCode, String responseBody, String errorMessage) {
        IntegrationResult result = new IntegrationResult();
        result.success = false;
        result.statusCode = statusCode;
        result.responseBody = responseBody;
        result.errorMessage = errorMessage;
        return result;
    }

    /**
     * @description Generates a unique correlation ID for tracing.
     * @return A UUID-like string combining timestamp and random hex
     */
    private static String generateCorrelationId() {
        String timePart = String.valueOf(Datetime.now().getTime());
        String randomPart = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 12);
        return timePart + '-' + randomPart;
    }
}