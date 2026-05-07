/**
 * @description Queueable Apex class for asynchronous retry execution of failed integration
 *              callouts. Deserializes the original payload and context, re-invokes the
 *              IntegrationEngine, links the resulting log to the parent log chain, and
 *              either enqueues further retries or routes to the dead-letter queue when
 *              max retries are exhausted.
 *
 *              Implements Database.AllowsCallouts to permit HTTP callouts within the
 *              queueable execution context.
 * @author Integration Platform
 */
public class IntegrationRetryQueueable implements Queueable, Database.AllowsCallouts {

    // ── Serializable state ──

    /** The unique integration key identifying the endpoint configuration */
    public String integrationKey;

    /** The Salesforce record ID associated with this integration execution */
    public Id recordId;

    /** JSON-serialized Map<String,Object> of the original request payload */
    public String payloadJson;

    /** JSON-serialized Map<String,String> of execution context metadata */
    public String contextJson;

    /** Current retry attempt number (1-based after first retry) */
    public Integer retryCount;

    /** Integration_Log__c ID of the original or immediately preceding log entry */
    public Id parentLogId;

    /** Configured delay in seconds before this retry executes (informational) */
    public Integer delaySeconds;

    // ── Constants ──
    private static final String ERROR_TYPE_RETRY_FAILURE = 'Retry_Failure';
    private static final String ERROR_TYPE_DEAD_LETTER = 'Dead_Letter';
    private static final String SEVERITY_HIGH = 'High';
    private static final String SEVERITY_CRITICAL = 'Critical';

    /**
     * @description Executes the retry logic: re-invokes the integration, updates logs,
     *              and decides whether to enqueue another retry or route to dead-letter.
     * @param qc The QueueableContext provided by the Apex runtime
     */
    public void execute(QueueableContext qc) {
        IntegrationResult result = null;
        Integration_Retry_Config__c retryConfig = null;

        try {
            // Validate required state
            if (String.isBlank(integrationKey)) {
                logSystemError('IntegrationRetryQueueable executed without an integration key.');
                return;
            }

            // Deserialize payload and context from JSON
            Map<String, Object> payload = deserializePayload();
            Map<String, String> context = deserializeContext();

            // Inject retry metadata into context so downstream components are aware
            context.put('isRetry', 'true');
            context.put('retryCount', String.valueOf(retryCount));
            if (parentLogId != null) {
                context.put('parentLogId', String.valueOf(parentLogId));
            }

            // Execute the integration via the engine
            result = IntegrationEngine.execute(integrationKey, recordId, payload, context);

            // Retrieve retry configuration for post-execution decisions
            retryConfig = IntegrationRetryHandler.getRetryConfig(integrationKey);

            // Update the log record with retry chain information
            updateLogWithRetryInfo(result);

            // Evaluate outcome
            if (result != null && result.success) {
                logRetrySuccess();
            } else {
                handleRetryFailure(result, retryConfig, payload, context);
            }

        } catch (Exception ex) {
            handleUnexpectedError(ex, retryConfig);
        }
    }

    /**
     * @description Deserializes the payload JSON string back into a Map.
     * @return The deserialized payload map, or an empty map if null/invalid
     */
    private Map<String, Object> deserializePayload() {
        if (String.isBlank(payloadJson)) {
            return new Map<String, Object>();
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(payloadJson);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationRetryQueueable: Failed to deserialize payload JSON: ' + ex.getMessage());
            return new Map<String, Object>();
        }
    }

    /**
     * @description Deserializes the context JSON string back into a Map.
     * @return The deserialized context map, or an empty map if null/invalid
     */
    private Map<String, String> deserializeContext() {
        if (String.isBlank(contextJson)) {
            return new Map<String, String>();
        }
        try {
            Map<String, Object> rawMap = (Map<String, Object>) JSON.deserializeUntyped(contextJson);
            Map<String, String> typedMap = new Map<String, String>();
            for (String key : rawMap.keySet()) {
                Object val = rawMap.get(key);
                typedMap.put(key, val != null ? String.valueOf(val) : null);
            }
            return typedMap;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationRetryQueueable: Failed to deserialize context JSON: ' + ex.getMessage());
            return new Map<String, String>();
        }
    }

    /**
     * @description Updates the Integration_Log__c record created by the engine with
     *              retry chain metadata (retry count, is-retry flag, parent log link).
     * @param result The IntegrationResult from the engine execution
     */
    private void updateLogWithRetryInfo(IntegrationResult result) {
        if (result == null || result.logId == null) {
            return;
        }

        try {
            Integration_Log__c logRecord = new Integration_Log__c(
                Id = result.logId,
                Retry_Count__c = this.retryCount,
                Is_Retry__c = true,
                Parent_Log__c = this.parentLogId
            );
            update logRecord;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationRetryQueueable: Failed to update log with retry info: ' + ex.getMessage());
        }
    }

    /**
     * @description Handles a failed retry attempt. If further retries are permitted,
     *              enqueues the next attempt with an increased delay. Otherwise, routes
     *              the failure to the dead-letter queue if enabled.
     * @param result The failed IntegrationResult
     * @param retryConfig The retry configuration record
     * @param payload The original payload for potential re-enqueue
     * @param context The execution context for potential re-enqueue
     */
    private void handleRetryFailure(
        IntegrationResult result,
        Integration_Retry_Config__c retryConfig,
        Map<String, Object> payload,
        Map<String, String> context
    ) {
        Integer statusCode = result != null ? result.statusCode : null;
        String errorMessage = result != null ? result.errorMessage : 'Unknown error during retry execution';
        Id currentLogId = result != null ? result.logId : null;

        // Check if we should retry again
        Integer nextRetryCount = this.retryCount + 1;

        if (IntegrationRetryHandler.shouldRetry(statusCode, nextRetryCount - 1, retryConfig)) {
            // Calculate delay with exponential backoff
            Integer nextDelay = IntegrationRetryHandler.calculateNextRetryDelay(nextRetryCount - 1, retryConfig);

            // Create error log for this failed attempt
            createErrorLog(currentLogId, ERROR_TYPE_RETRY_FAILURE, errorMessage,
                SEVERITY_HIGH, false, true);

            // Enqueue the next retry
            try {
                IntegrationRetryHandler.enqueueRetry(
                    integrationKey,
                    recordId,
                    payload,
                    context,
                    nextRetryCount,
                    currentLogId != null ? currentLogId : parentLogId,
                    nextDelay
                );
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR,
                    'IntegrationRetryQueueable: Failed to enqueue next retry: ' + ex.getMessage());
                // If we cannot enqueue, route to dead letter
                routeToDeadLetter(currentLogId, errorMessage +
                    ' | Additionally failed to enqueue next retry: ' + ex.getMessage());
            }
        } else {
            // Max retries exhausted or status code not retryable
            Boolean deadLetterEnabled = retryConfig != null && retryConfig.Dead_Letter_Enabled__c == true;

            if (deadLetterEnabled) {
                routeToDeadLetter(currentLogId, errorMessage);
            } else {
                // Log the final failure without dead-lettering
                createErrorLog(currentLogId, ERROR_TYPE_RETRY_FAILURE,
                    'Max retries exhausted. ' + errorMessage,
                    SEVERITY_CRITICAL, false, false);
            }

            logRetryExhausted(errorMessage);
        }
    }

    /**
     * @description Routes a permanently failed integration to the dead-letter queue by
     *              creating an Integration_Error_Log__c with Is_Dead_Letter__c = true
     *              and preserving the original payload for manual re-processing.
     * @param logId The Integration_Log__c ID to associate the error with
     * @param errorMessage The final error message
     */
    private void routeToDeadLetter(Id logId, String errorMessage) {
        String originalPayload = String.isNotBlank(payloadJson) ? payloadJson : '';

        // Truncate payload if it exceeds long text area limit (131072 chars)
        if (originalPayload.length() > 131072) {
            originalPayload = originalPayload.substring(0, 131068) + '...';
        }

        createErrorLog(logId, ERROR_TYPE_DEAD_LETTER,
            'Dead-lettered after ' + retryCount + ' retry attempts. ' + errorMessage,
            SEVERITY_CRITICAL, true, true);

        System.debug(LoggingLevel.WARN,
            'IntegrationRetryQueueable: Integration [' + integrationKey +
            '] routed to dead-letter queue after ' + retryCount + ' retries.');
    }

    /**
     * @description Creates an Integration_Error_Log__c record for tracking retry failures,
     *              dead-letter entries, or unexpected errors.
     * @param logId The parent Integration_Log__c ID
     * @param errorType The classification of the error
     * @param errorMessage The error description
     * @param severity The severity level (Low, Medium, High, Critical)
     * @param isDeadLetter Whether this is a dead-letter entry
     * @param retryEligible Whether this error is eligible for future retry
     */
    private void createErrorLog(
        Id logId,
        String errorType,
        String errorMessage,
        String severity,
        Boolean isDeadLetter,
        Boolean retryEligible
    ) {
        try {
            // Guard: master-detail requires a parent
            if (logId == null) {
                System.debug(LoggingLevel.ERROR,
                    'IntegrationRetryQueueable: Cannot create error log without parent Integration_Log__c ID.');
                return;
            }

            // Truncate error message to fit standard long text area (32768 chars)
            String safeMessage = String.isNotBlank(errorMessage) ? errorMessage : 'No error message available';
            if (safeMessage.length() > 32768) {
                safeMessage = safeMessage.substring(0, 32764) + '...';
            }

            // Truncate payload for Original_Payload__c
            String safePayload = String.isNotBlank(payloadJson) ? payloadJson : '';
            if (safePayload.length() > 131072) {
                safePayload = safePayload.substring(0, 131068) + '...';
            }

            Integration_Error_Log__c errorLog = new Integration_Error_Log__c(
                Integration_Log__c = logId,
                Error_Type__c = errorType,
                Error_Message__c = safeMessage,
                Severity__c = severity,
                Is_Dead_Letter__c = isDeadLetter,
                Retry_Eligible__c = retryEligible,
                Original_Payload__c = safePayload
            );
            insert errorLog;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationRetryQueueable: Failed to create error log: ' + ex.getMessage());
        }
    }

    /**
     * @description Handles unexpected exceptions during retry execution by logging the
     *              error and attempting to route to dead-letter if configuration allows.
     * @param ex The caught exception
     * @param retryConfig The retry configuration (may be null)
     */
    private void handleUnexpectedError(Exception ex, Integration_Retry_Config__c retryConfig) {
        String errorMsg = 'Unexpected error during retry execution for integration [' +
            integrationKey + ']: ' + ex.getMessage() +
            ' | Stack trace: ' + ex.getStackTraceString();

        System.debug(LoggingLevel.ERROR, 'IntegrationRetryQueueable: ' + errorMsg);

        // Attempt to create an error log if we have a parent log reference
        if (parentLogId != null) {
            Boolean isDeadLetter = retryConfig != null && retryConfig.Dead_Letter_Enabled__c == true;
            createErrorLog(parentLogId, 'System_Error', errorMsg,
                SEVERITY_CRITICAL, isDeadLetter, !isDeadLetter);
        }
    }

    /**
     * @description Logs a successful retry completion for observability.
     */
    private void logRetrySuccess() {
        System.debug(LoggingLevel.INFO,
            'IntegrationRetryQueueable: Integration [' + integrationKey +
            '] succeeded on retry attempt #' + retryCount + '.');
    }

    /**
     * @description Logs when all retry attempts have been exhausted.
     * @param errorMessage The final error message
     */
    private void logRetryExhausted(String errorMessage) {
        System.debug(LoggingLevel.WARN,
            'IntegrationRetryQueueable: Integration [' + integrationKey +
            '] exhausted all retry attempts (' + retryCount + '). Last error: ' + errorMessage);
    }

    /**
     * @description Logs a system-level error when the queueable is in an invalid state.
     * @param message The error message
     */
    private void logSystemError(String message) {
        System.debug(LoggingLevel.ERROR, 'IntegrationRetryQueueable: ' + message);
    }
}