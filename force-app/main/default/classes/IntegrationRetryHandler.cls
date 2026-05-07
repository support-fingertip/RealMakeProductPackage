/**
 * @description Determines whether a failed integration callout should be retried based on
 *              metadata-driven retry configuration. Evaluates status codes, retry counts,
 *              and active status before authorising a retry. Calculates exponential backoff
 *              delays with a configurable cap and orchestrates retry enqueueing.
 * @author Integration Platform
 */
public class IntegrationRetryHandler {

    // ── Constants ──
    private static final String DEFAULT_RETRYABLE_CODES = '408,429,500,502,503,504';
    private static final Integer DEFAULT_MAX_RETRIES = 3;
    private static final Integer DEFAULT_RETRY_INTERVAL = 60;
    private static final Decimal DEFAULT_BACKOFF_MULTIPLIER = 2.0;
    private static final Integer DEFAULT_MAX_RETRY_INTERVAL = 3600;

    /**
     * @description Evaluates whether a failed integration should be retried based on the
     *              response status code, current retry count, and retry configuration.
     * @param statusCode The HTTP status code returned by the external service
     * @param currentRetryCount The number of retries already attempted
     * @param retryConfig The Integration_Retry_Config__c record governing retry behaviour
     * @return True if the integration should be retried, false otherwise
     */
    public static Boolean shouldRetry(Integer statusCode, Integer currentRetryCount, Integration_Retry_Config__c retryConfig) {
        // Null-safe guard on retry configuration
        if (retryConfig == null) {
            return false;
        }

        // Configuration must be active
        if (retryConfig.Active__c != true) {
            return false;
        }

        // Validate retry count has not been exceeded
        Integer maxRetries = retryConfig.Max_Retries__c != null
            ? (Integer) retryConfig.Max_Retries__c
            : DEFAULT_MAX_RETRIES;

        Integer safeCurrentCount = currentRetryCount != null ? currentRetryCount : 0;
        if (safeCurrentCount >= maxRetries) {
            return false;
        }

        // Check whether the status code is in the retryable set
        if (statusCode == null) {
            return false;
        }

        Set<Integer> retryableCodes = parseRetryStatusCodes(retryConfig.Retry_On_Status_Codes__c);
        return retryableCodes.contains(statusCode);
    }

    /**
     * @description Calculates the delay in seconds before the next retry attempt using
     *              exponential backoff: min(interval * multiplier^retryCount, maxInterval).
     * @param currentRetryCount The number of retries already attempted (0-based)
     * @param retryConfig The Integration_Retry_Config__c record with backoff parameters
     * @return Delay in seconds before the next retry
     */
    public static Integer calculateNextRetryDelay(Integer currentRetryCount, Integration_Retry_Config__c retryConfig) {
        Integer safeRetryCount = currentRetryCount != null ? currentRetryCount : 0;

        // Extract configuration with safe defaults
        Decimal baseInterval = DEFAULT_RETRY_INTERVAL;
        Decimal backoffMultiplier = DEFAULT_BACKOFF_MULTIPLIER;
        Decimal maxInterval = DEFAULT_MAX_RETRY_INTERVAL;

        if (retryConfig != null) {
            if (retryConfig.Retry_Interval__c != null) {
                baseInterval = retryConfig.Retry_Interval__c;
            }
            if (retryConfig.Backoff_Multiplier__c != null) {
                backoffMultiplier = retryConfig.Backoff_Multiplier__c;
            }
            if (retryConfig.Max_Retry_Interval__c != null) {
                maxInterval = retryConfig.Max_Retry_Interval__c;
            }
        }

        // Guard against invalid multiplier values
        if (backoffMultiplier <= 0) {
            backoffMultiplier = 1;
        }

        // Calculate: interval * (multiplier ^ retryCount)
        Decimal multiplierPow = Math.pow(backoffMultiplier.doubleValue(), safeRetryCount);
        Decimal calculatedDelay = baseInterval * multiplierPow;

        // Apply ceiling cap
        Decimal effectiveDelay = Math.min(calculatedDelay, maxInterval);

        // Ensure non-negative and return as Integer seconds
        return Math.max(effectiveDelay.intValue(), 0);
    }

    /**
     * @description Creates and enqueues an IntegrationRetryQueueable for asynchronous retry
     *              execution with the specified parameters.
     * @param integrationKey The unique key identifying the integration endpoint configuration
     * @param recordId The Salesforce record ID related to this integration
     * @param payload The request payload to be retried
     * @param context Additional context metadata for the retry execution
     * @param retryCount The current retry attempt number (will be passed to the queueable)
     * @param parentLogId The Integration_Log__c ID of the original (or previous) log entry
     * @param delaySeconds The number of seconds to delay before retry execution
     */
    public static void enqueueRetry(
        String integrationKey,
        Id recordId,
        Map<String, Object> payload,
        Map<String, String> context,
        Integer retryCount,
        Id parentLogId,
        Integer delaySeconds
    ) {
        // Validate required parameters
        if (String.isBlank(integrationKey)) {
            throw new IntegrationRetryException('Integration key is required to enqueue a retry.');
        }

        IntegrationRetryQueueable retryJob = new IntegrationRetryQueueable();
        retryJob.integrationKey = integrationKey;
        retryJob.recordId = recordId;
        retryJob.payloadJson = payload != null ? JSON.serialize(payload) : null;
        retryJob.contextJson = context != null ? JSON.serialize(context) : null;
        retryJob.retryCount = retryCount != null ? retryCount : 0;
        retryJob.parentLogId = parentLogId;
        retryJob.delaySeconds = delaySeconds != null ? delaySeconds : 0;

        // Enqueue the retry job - Salesforce will execute it asynchronously
        if (!Test.isRunningTest()) {
            System.enqueueJob(retryJob);
        } else {
            // In test context, enqueue without delay to allow test execution
            System.enqueueJob(retryJob);
        }
    }

    /**
     * @description Retrieves the Integration_Retry_Config__c associated with a given
     *              integration key by traversing the endpoint's Retry_Config__c lookup.
     * @param integrationKey The unique integration key
     * @return The retry configuration record, or null if not found or inactive
     */
    public static Integration_Retry_Config__c getRetryConfig(String integrationKey) {
        if (String.isBlank(integrationKey)) {
            return null;
        }

        List<Integration_Endpoint__c> endpoints = [
            SELECT Id, Retry_Config__c,
                   Retry_Config__r.Config_Name__c,
                   Retry_Config__r.Max_Retries__c,
                   Retry_Config__r.Retry_Interval__c,
                   Retry_Config__r.Backoff_Multiplier__c,
                   Retry_Config__r.Max_Retry_Interval__c,
                   Retry_Config__r.Retry_On_Status_Codes__c,
                   Retry_Config__r.Dead_Letter_Enabled__c,
                   Retry_Config__r.Active__c
            FROM Integration_Endpoint__c
            WHERE Integration_Key__c = :integrationKey
              AND Active__c = true
            LIMIT 1
        ];

        if (endpoints.isEmpty() || endpoints[0].Retry_Config__c == null) {
            return null;
        }

        return endpoints[0].Retry_Config__r;
    }

    /**
     * @description Parses a comma-separated string of HTTP status codes into a Set of Integers.
     * @param statusCodesStr Comma-separated status codes (e.g. "408,429,500,502,503,504")
     * @return Set of parsed integer status codes
     */
    @TestVisible
    private static Set<Integer> parseRetryStatusCodes(String statusCodesStr) {
        Set<Integer> codes = new Set<Integer>();

        String rawCodes = String.isNotBlank(statusCodesStr)
            ? statusCodesStr
            : DEFAULT_RETRYABLE_CODES;

        for (String codeStr : rawCodes.split(',')) {
            String trimmed = codeStr.trim();
            if (String.isNotBlank(trimmed)) {
                try {
                    codes.add(Integer.valueOf(trimmed));
                } catch (TypeException e) {
                    // Skip malformed entries - log at debug level
                    System.debug(LoggingLevel.WARN,
                        'IntegrationRetryHandler: Ignoring non-numeric retry status code: ' + trimmed);
                }
            }
        }

        return codes;
    }

    /**
     * @description Custom exception class for retry-related errors.
     */
    public class IntegrationRetryException extends Exception {}
}