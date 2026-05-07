/**
 * @description Central logging service for the Integration Orchestration Platform.
 *              Buffers Integration_Log__c and Integration_Error_Log__c records during a transaction
 *              and flushes them in a single DML operation at the end. Handles payload masking,
 *              governor-limit-safe truncation, and correlation ID generation.
 * @author Integration Platform
 */
public class IntegrationLogger {

    /** Maximum character length for Long Text Area fields (131072 = 128 KB) */
    private static final Integer MAX_LONG_TEXT_LENGTH = 131072;

    /** Maximum character length for standard text fields used for headers */
    private static final Integer MAX_TEXT_LENGTH = 32768;

    /** Buffered log records awaiting flush */
    private static List<Integration_Log__c> logBuffer = new List<Integration_Log__c>();

    /** Buffered error log records awaiting flush (keyed by temporary index into logBuffer) */
    private static Map<Integer, List<Integration_Error_Log__c>> errorLogBuffer = new Map<Integer, List<Integration_Error_Log__c>>();

    /** Standalone error logs linked to already-persisted Integration_Log__c records */
    private static List<Integration_Error_Log__c> standaloneErrorLogs = new List<Integration_Error_Log__c>();

    /**
     * @description Logs an outbound HTTP callout.
     * @param endpoint The Integration_Endpoint__c record associated with this call
     * @param correlationId Unique correlation ID for tracing
     * @param req The HttpRequest that was sent
     * @param res The HttpResponse received (may be null on exception)
     * @param executionMs Execution time in milliseconds
     * @param isSuccess Whether the callout was considered successful
     * @return The index of the buffered log entry (can be used with logError before flush)
     */
    public static Integer logOutbound(
        Integration_Endpoint__c endpoint,
        String correlationId,
        HttpRequest req,
        HttpResponse res,
        Long executionMs,
        Boolean isSuccess
    ) {
        Integration_Log__c log = new Integration_Log__c();

        // Endpoint reference
        if (endpoint != null) {
            log.Integration_Endpoint__c = endpoint.Id;
            log.Integration_Key__c = endpoint.Integration_Key__c;
        }

        log.Correlation_Id__c = correlationId;
        log.Direction__c = 'Outbound';
        log.Execution_Mode__c = System.isBatch() ? 'Batch' : (System.isFuture() ? 'Future' : (System.isQueueable() ? 'Queueable' : 'Synchronous'));
        log.Triggered_By__c = UserInfo.getUserId();
        log.Execution_Time_ms__c = executionMs;
        log.Execution_Start__c = Datetime.now().addSeconds(-1 * (Integer) Math.ceil((executionMs != null ? executionMs : 0) / 1000.0));
        log.Execution_End__c = Datetime.now();
        log.Is_Success__c = isSuccess == true;

        // Request details
        if (req != null) {
            log.HTTP_Method__c = req.getMethod();
            log.Request_URL__c = truncateText(req.getEndpoint(), 255);
            log.Request_Headers__c = truncateText(maskPayload(serializeHeaders(req)), MAX_TEXT_LENGTH);
            log.Request_Body__c = truncateText(maskPayload(req.getBody()), MAX_LONG_TEXT_LENGTH);
        }

        // Response details
        if (res != null) {
            log.Response_Status_Code__c = res.getStatusCode();
            log.Response_Headers__c = truncateText(serializeResponseHeaders(res), MAX_TEXT_LENGTH);
            log.Response_Body__c = truncateText(maskPayload(res.getBody()), MAX_LONG_TEXT_LENGTH);
            if (!isSuccess && String.isBlank(log.Error_Message__c)) {
                log.Error_Message__c = truncateText('HTTP ' + res.getStatusCode() + ': ' + res.getStatus(), MAX_TEXT_LENGTH);
            }
        }

        logBuffer.add(log);
        return logBuffer.size() - 1;
    }

    /**
     * @description Logs an inbound REST API call.
     * @param integrationKey The integration key identifier
     * @param correlationId Unique correlation ID for tracing
     * @param req The RestRequest received
     * @param res The RestResponse being returned
     * @param executionMs Execution time in milliseconds
     * @param isSuccess Whether the inbound processing was successful
     * @return The index of the buffered log entry
     */
    public static Integer logInbound(
        String integrationKey,
        String correlationId,
        RestRequest req,
        RestResponse res,
        Long executionMs,
        Boolean isSuccess
    ) {
        Integration_Log__c log = new Integration_Log__c();

        log.Integration_Key__c = integrationKey;
        log.Correlation_Id__c = correlationId;
        log.Direction__c = 'Inbound';
        log.Execution_Mode__c = 'Synchronous';
        log.Triggered_By__c = UserInfo.getUserId();
        log.Execution_Time_ms__c = executionMs;
        log.Execution_Start__c = Datetime.now().addSeconds(-1 * (Integer) Math.ceil((executionMs != null ? executionMs : 0) / 1000.0));
        log.Execution_End__c = Datetime.now();
        log.Is_Success__c = isSuccess == true;

        // Request details
        if (req != null) {
            log.HTTP_Method__c = req.httpMethod;
            log.Request_URL__c = truncateText(req.requestURI, 255);
            log.Request_Headers__c = truncateText(maskPayload(serializeRestHeaders(req)), MAX_TEXT_LENGTH);
            String requestBody = req.requestBody != null ? req.requestBody.toString() : null;
            log.Request_Body__c = truncateText(maskPayload(requestBody), MAX_LONG_TEXT_LENGTH);
        }

        // Response details
        if (res != null) {
            log.Response_Status_Code__c = res.statusCode;
            log.Response_Headers__c = truncateText(serializeRestResponseHeaders(res), MAX_TEXT_LENGTH);
            String responseBody = res.responseBody != null ? res.responseBody.toString() : null;
            log.Response_Body__c = truncateText(maskPayload(responseBody), MAX_LONG_TEXT_LENGTH);
        }

        logBuffer.add(log);
        return logBuffer.size() - 1;
    }

    /**
     * @description Creates an error log entry. If logId is provided, the error is linked to an
     *              already-persisted log. If logId is null but a bufferIndex was obtained from
     *              logOutbound/logInbound, use logErrorByIndex instead.
     * @param logId The persisted Integration_Log__c record Id
     * @param errorType The type of error (e.g., Callout_Exception, Timeout, Auth_Failure)
     * @param errorMessage Human-readable error description
     * @param stackTrace The Apex stack trace at the point of failure
     * @param severity Error severity: Low, Medium, High, or Critical
     * @param originalPayload The original payload that caused the error
     */
    public static void logError(
        Id logId,
        String errorType,
        String errorMessage,
        String stackTrace,
        String severity,
        String originalPayload
    ) {
        Integration_Error_Log__c errorLog = buildErrorLog(
            errorType, errorMessage, stackTrace, severity, originalPayload
        );

        if (logId != null) {
            errorLog.Integration_Log__c = logId;
            standaloneErrorLogs.add(errorLog);
        }
    }

    /**
     * @description Creates an error log entry linked to a buffered (not yet persisted) log record
     *              by its buffer index. The actual lookup is resolved during flush().
     * @param bufferIndex Index returned by logOutbound or logInbound
     * @param errorType The type of error
     * @param errorMessage Human-readable error description
     * @param stackTrace The Apex stack trace
     * @param severity Error severity level
     * @param originalPayload The original payload that caused the error
     */
    public static void logErrorByIndex(
        Integer bufferIndex,
        String errorType,
        String errorMessage,
        String stackTrace,
        String severity,
        String originalPayload
    ) {
        if (bufferIndex == null || bufferIndex < 0 || bufferIndex >= logBuffer.size()) {
            return;
        }

        Integration_Error_Log__c errorLog = buildErrorLog(
            errorType, errorMessage, stackTrace, severity, originalPayload
        );

        if (!errorLogBuffer.containsKey(bufferIndex)) {
            errorLogBuffer.put(bufferIndex, new List<Integration_Error_Log__c>());
        }
        errorLogBuffer.get(bufferIndex).add(errorLog);
    }

    /**
     * @description Flushes all buffered log and error log records to the database.
     *              Inserts Integration_Log__c records first, then resolves parent lookups
     *              on Integration_Error_Log__c records before inserting those.
     *              Clears all buffers after completion.
     */
    public static void flush() {
        if (logBuffer.isEmpty() && standaloneErrorLogs.isEmpty()) {
            return;
        }

        Savepoint sp = Database.setSavepoint();
        try {
            // Insert buffered log records
            if (!logBuffer.isEmpty()) {
                List<Database.SaveResult> logResults = Database.insert(logBuffer, false);

                // Resolve error log parent references
                List<Integration_Error_Log__c> allErrorLogs = new List<Integration_Error_Log__c>();

                for (Integer i = 0; i < logBuffer.size(); i++) {
                    if (logResults[i].isSuccess() && errorLogBuffer.containsKey(i)) {
                        Id parentLogId = logResults[i].getId();
                        for (Integration_Error_Log__c errLog : errorLogBuffer.get(i)) {
                            errLog.Integration_Log__c = parentLogId;
                            allErrorLogs.add(errLog);
                        }
                    }
                }

                // Add standalone error logs
                allErrorLogs.addAll(standaloneErrorLogs);

                // Insert all error logs
                if (!allErrorLogs.isEmpty()) {
                    Database.insert(allErrorLogs, false);
                }
            } else if (!standaloneErrorLogs.isEmpty()) {
                Database.insert(standaloneErrorLogs, false);
            }
        } catch (Exception ex) {
            Database.rollback(sp);
            // Log to system debug as last resort - cannot recurse into logging
            System.debug(LoggingLevel.ERROR, 'IntegrationLogger.flush() failed: ' + ex.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + ex.getStackTraceString());
        } finally {
            // Always clear buffers to prevent stale data in subsequent operations
            clearBuffers();
        }
    }

    /**
     * @description Generates a UUID-like correlation ID for tracing requests across the platform.
     *              Format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
     * @return A unique correlation ID string
     */
    public static String generateCorrelationId() {
        String hexString = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        return hexString.substring(0, 8) + '-' +
               hexString.substring(8, 12) + '-' +
               hexString.substring(12, 16) + '-' +
               hexString.substring(16, 20) + '-' +
               hexString.substring(20, 32);
    }

    /**
     * @description Returns the current number of buffered log records.
     * @return Count of buffered Integration_Log__c records
     */
    public static Integer getBufferSize() {
        return logBuffer.size();
    }

    /**
     * @description Clears all internal buffers without persisting. Use when a transaction
     *              is being abandoned or rolled back.
     */
    public static void clearBuffers() {
        logBuffer = new List<Integration_Log__c>();
        errorLogBuffer = new Map<Integer, List<Integration_Error_Log__c>>();
        standaloneErrorLogs = new List<Integration_Error_Log__c>();
    }

    // ─── LogEntry Inner Class (used by CPRegistrationAPI, GenericIntegrationAPI) ──

    /**
     * @description Lightweight wrapper for building a log entry before committing.
     *              Bridge between the simple startLog/commitLog pattern and the
     *              buffered logOutbound/logInbound/flush pattern.
     */
    public class LogEntry {
        public String direction;
        public String httpMethod;
        public String requestUrl;
        public String integrationSource;
        public String request;
        public String response;
        public String inputParameters;
        public Integer httpStatusCode;
        public String status;
        public String errorMessage;
    }

    /**
     * @description Creates a new LogEntry for tracking an API call.
     * @param direction 'Inbound' or 'Outbound'
     * @param httpMethod The HTTP method (GET, POST, etc.)
     * @param requestUrl The request URL or path
     * @return A new LogEntry instance
     */
    public static LogEntry startLog(String direction, String httpMethod, String requestUrl) {
        LogEntry entry = new LogEntry();
        entry.direction = direction;
        entry.httpMethod = httpMethod;
        entry.requestUrl = requestUrl;
        return entry;
    }

    /**
     * @description Commits a LogEntry to the database as an Integration_Log__c record.
     * @param entry The LogEntry to persist
     */
    public static void commitLog(LogEntry entry) {
        if (entry == null) return;
        try {
            Integration_Log__c log = new Integration_Log__c();
            log.Direction__c = entry.direction;
            log.HTTP_Method__c = entry.httpMethod;
            log.Request_URL__c = truncateText(entry.requestUrl, 255);
            log.Integration_Key__c = entry.integrationSource;
            log.Request_Body__c = truncateText(entry.request, MAX_LONG_TEXT_LENGTH);
            log.Response_Body__c = truncateText(entry.response, MAX_LONG_TEXT_LENGTH);
            log.Response_Status_Code__c = entry.httpStatusCode;
            log.Is_Success__c = (entry.status == 'Success');
            log.Error_Message__c = truncateText(entry.errorMessage, MAX_TEXT_LENGTH);
            log.Correlation_Id__c = generateCorrelationId();
            log.Execution_Mode__c = 'REST';
            log.Execution_End__c = Datetime.now();
            log.Triggered_By__c = UserInfo.getUserId();
            insert log;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'IntegrationLogger.commitLog() failed: ' + ex.getMessage());
        }
    }

    // ─── Private Helper Methods ──────────────────────────────────────────

    /**
     * @description Builds an Integration_Error_Log__c record from the provided parameters.
     */
    private static Integration_Error_Log__c buildErrorLog(
        String errorType,
        String errorMessage,
        String stackTrace,
        String severity,
        String originalPayload
    ) {
        Integration_Error_Log__c errorLog = new Integration_Error_Log__c();
        errorLog.Error_Type__c = errorType;
        errorLog.Error_Message__c = truncateText(errorMessage, MAX_TEXT_LENGTH);
        errorLog.Stack_Trace__c = truncateText(stackTrace, MAX_LONG_TEXT_LENGTH);
        errorLog.Severity__c = String.isNotBlank(severity) ? severity : 'Medium';
        errorLog.Original_Payload__c = truncateText(maskPayload(originalPayload), MAX_LONG_TEXT_LENGTH);
        errorLog.Is_Resolved__c = false;
        errorLog.Is_Dead_Letter__c = false;
        errorLog.Retry_Eligible__c = isRetryEligible(errorType);
        return errorLog;
    }

    /**
     * @description Determines whether an error type is eligible for automatic retry.
     * @param errorType The error type picklist value
     * @return True if the error type can be retried
     */
    private static Boolean isRetryEligible(String errorType) {
        Set<String> retryableTypes = new Set<String>{
            'Callout_Exception', 'Timeout', 'Auth_Failure'
        };
        return String.isNotBlank(errorType) && retryableTypes.contains(errorType);
    }

    /**
     * @description Masks sensitive data in a payload string using PayloadMaskingService.
     *              Falls back to the raw value if the service is unavailable or throws.
     * @param payload The raw payload string
     * @return The masked payload, or the original if masking fails
     */
    private static String maskPayload(String payload) {
        if (String.isBlank(payload)) {
            return payload;
        }
        try {
            return PayloadMaskingService.maskPayload(payload);
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'PayloadMaskingService unavailable: ' + ex.getMessage());
        }
        return payload;
    }

    /**
     * @description Serializes HttpRequest headers to a JSON string.
     *              Note: Standard HttpRequest does not expose a getHeaders() method,
     *              so we capture commonly used header names.
     * @param req The HttpRequest
     * @return JSON string of captured headers
     */
    private static String serializeHeaders(HttpRequest req) {
        if (req == null) {
            return null;
        }
        Map<String, String> headers = new Map<String, String>();
        List<String> commonHeaders = new List<String>{
            'Content-Type', 'Accept', 'Authorization', 'X-Correlation-Id',
            'X-Request-Id', 'User-Agent', 'Cache-Control', 'Content-Length',
            'Host', 'Connection', 'X-Api-Key', 'X-Client-Id'
        };
        for (String headerName : commonHeaders) {
            String value = req.getHeader(headerName);
            if (value != null) {
                headers.put(headerName, value);
            }
        }
        return headers.isEmpty() ? null : JSON.serialize(headers);
    }

    /**
     * @description Serializes HttpResponse headers. Standard HttpResponse only provides
     *              getHeaderKeys() and getHeader(key).
     * @param res The HttpResponse
     * @return JSON string of response headers
     */
    private static String serializeResponseHeaders(HttpResponse res) {
        if (res == null) {
            return null;
        }
        Map<String, String> headers = new Map<String, String>();
        String[] headerKeys = res.getHeaderKeys();
        if (headerKeys != null) {
            for (String key : headerKeys) {
                if (key != null) {
                    headers.put(key, res.getHeader(key));
                }
            }
        }
        return headers.isEmpty() ? null : JSON.serialize(headers);
    }

    /**
     * @description Serializes RestRequest headers to a JSON string.
     * @param req The RestRequest
     * @return JSON string of request headers
     */
    private static String serializeRestHeaders(RestRequest req) {
        if (req == null || req.headers == null || req.headers.isEmpty()) {
            return null;
        }
        return JSON.serialize(req.headers);
    }

    /**
     * @description Serializes RestResponse headers to a JSON string.
     * @param res The RestResponse
     * @return JSON string of response headers
     */
    private static String serializeRestResponseHeaders(RestResponse res) {
        if (res == null || res.headers == null || res.headers.isEmpty()) {
            return null;
        }
        return JSON.serialize(res.headers);
    }

    /**
     * @description Safely truncates a string to the specified maximum length.
     *              Appends a truncation marker if the text was shortened.
     * @param text The text to truncate
     * @param maxLength The maximum allowed length
     * @return The truncated text, or the original if within limits
     */
    private static String truncateText(String text, Integer maxLength) {
        if (text == null) {
            return null;
        }
        if (text.length() <= maxLength) {
            return text;
        }
        String truncationMarker = '\n...[TRUNCATED at ' + maxLength + ' chars]';
        Integer safeLength = maxLength - truncationMarker.length();
        if (safeLength < 0) {
            safeLength = maxLength;
            truncationMarker = '';
        }
        return text.substring(0, safeLength) + truncationMarker;
    }
}