/**
 * @description Batch Apex class for bulk integration execution against a set of Salesforce
 *              records. Processes each record through the IntegrationEngine, tracks success
 *              and failure counts across all batches, and produces a summary report on
 *              completion.
 *
 *              Implements Database.Stateful to maintain aggregate counters across batch
 *              chunks and Database.AllowsCallouts to permit HTTP callouts within each
 *              execute invocation.
 *
 *              Usage:
 *              <pre>
 *              IntegrationBatchProcessor batch = new IntegrationBatchProcessor(
 *                  'My_Integration_Key',
 *                  'SELECT Id, Name FROM Account WHERE Type = \'Customer\''
 *              );
 *              Database.executeBatch(batch, 1); // Batch size of 1 for callout-per-record
 *              </pre>
 *
 * @author Integration Platform
 */
global class IntegrationBatchProcessor implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    // ── Configuration ──

    /** The unique integration key identifying the endpoint configuration */
    global String integrationKey;

    /** The SOQL query defining the set of records to process */
    global String query;

    // ── Stateful Counters (survive across batch chunks) ──

    /** Running count of successfully processed records */
    global Integer successCount;

    /** Running count of records that failed processing */
    global Integer failureCount;

    /** Accumulated error messages from failed records (capped for memory safety) */
    global List<String> errors;

    // ── Constants ──

    /** Maximum number of error messages to accumulate to avoid heap issues */
    private static final Integer MAX_ERROR_MESSAGES = 500;

    /** Maximum length per individual error message */
    private static final Integer MAX_ERROR_MESSAGE_LENGTH = 500;

    /**
     * @description Default constructor. Initialises stateful counters.
     */
    global IntegrationBatchProcessor() {
        this.successCount = 0;
        this.failureCount = 0;
        this.errors = new List<String>();
    }

    /**
     * @description Parameterised constructor for typical usage.
     * @param integrationKey The unique key identifying the integration endpoint
     * @param query SOQL query for records to process
     */
    global IntegrationBatchProcessor(String integrationKey, String query) {
        this();
        this.integrationKey = integrationKey;
        this.query = query;
    }

    /**
     * @description Initialises the batch by returning a QueryLocator for the configured
     *              SOQL query. Validates required parameters before proceeding.
     * @param bc The BatchableContext provided by the Apex runtime
     * @return A Database.QueryLocator for iterating over the target records
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Validate required configuration
        if (String.isBlank(integrationKey)) {
            throw new IntegrationBatchException(
                'IntegrationBatchProcessor requires a non-blank integrationKey.');
        }
        if (String.isBlank(query)) {
            throw new IntegrationBatchException(
                'IntegrationBatchProcessor requires a non-blank SOQL query.');
        }

        System.debug(LoggingLevel.INFO,
            'IntegrationBatchProcessor: Starting batch for integration [' + integrationKey +
            '] with query: ' + query);

        return Database.getQueryLocator(query);
    }

    /**
     * @description Processes a chunk of records by executing the integration for each
     *              record via IntegrationEngine. Tracks successes, failures, and errors.
     *
     *              Each record is processed individually to isolate callout failures and
     *              allow partial success within a batch chunk.
     *
     * @param bc The BatchableContext provided by the Apex runtime
     * @param scope The list of SObject records in this batch chunk
     */
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }

        System.debug(LoggingLevel.INFO,
            'IntegrationBatchProcessor: Processing batch of ' + scope.size() +
            ' records for integration [' + integrationKey + '].');

        for (SObject record : scope) {
            processRecord(record);
        }
    }

    /**
     * @description Processes a single record through the IntegrationEngine, handling
     *              both successful and failed outcomes.
     * @param record The SObject record to process
     */
    private void processRecord(SObject record) {
        Id recordId = record.Id;
        Long startTime = System.currentTimeMillis();

        try {
            // Build payload from record fields
            Map<String, Object> payload = buildPayloadFromRecord(record);

            // Build context with batch metadata
            Map<String, String> context = new Map<String, String>{
                'source' => 'IntegrationBatchProcessor',
                'batchRecordId' => String.valueOf(recordId)
            };

            // Execute the integration
            IntegrationResult result = IntegrationEngine.execute(integrationKey, recordId, payload, context);

            if (result != null && result.success) {
                successCount++;
            } else {
                failureCount++;
                String errorMsg = buildErrorMessage(recordId, result);
                addError(errorMsg);

                // Attempt retry if configured
                attemptRetryOnFailure(result, recordId, payload, context);
            }

        } catch (Exception ex) {
            failureCount++;
            String errorMsg = 'Record ' + recordId + ': Unhandled exception - ' +
                ex.getMessage() + ' [' + ex.getStackTraceString() + ']';
            addError(errorMsg);

            System.debug(LoggingLevel.ERROR,
                'IntegrationBatchProcessor: ' + errorMsg);
        }
    }

    /**
     * @description Builds a payload map from the populated fields of an SObject record.
     * @param record The SObject record
     * @return Map of field names to their values
     */
    private Map<String, Object> buildPayloadFromRecord(SObject record) {
        Map<String, Object> payload = new Map<String, Object>();

        if (record == null) {
            return payload;
        }

        Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
        for (String fieldName : populatedFields.keySet()) {
            Object fieldValue = populatedFields.get(fieldName);
            // Skip nested SObjects to keep payload flat and serialisable
            if (!(fieldValue instanceof SObject)) {
                payload.put(fieldName, fieldValue);
            }
        }

        return payload;
    }

    /**
     * @description Attempts to enqueue a retry for a failed record if the integration
     *              has retry configuration.
     * @param result The failed IntegrationResult
     * @param recordId The record ID that failed
     * @param payload The original payload
     * @param context The execution context
     */
    private void attemptRetryOnFailure(
        IntegrationResult result,
        Id recordId,
        Map<String, Object> payload,
        Map<String, String> context
    ) {
        try {
            Integration_Retry_Config__c retryConfig = IntegrationRetryHandler.getRetryConfig(integrationKey);

            if (retryConfig == null) {
                return;
            }

            Integer statusCode = result != null ? result.statusCode : null;
            if (IntegrationRetryHandler.shouldRetry(statusCode, 0, retryConfig)) {
                Integer delaySeconds = IntegrationRetryHandler.calculateNextRetryDelay(0, retryConfig);
                Id parentLogId = result != null ? result.logId : null;

                IntegrationRetryHandler.enqueueRetry(
                    integrationKey,
                    recordId,
                    payload,
                    context,
                    1,
                    parentLogId,
                    delaySeconds
                );
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'IntegrationBatchProcessor: Failed to enqueue retry for record ' +
                recordId + ': ' + ex.getMessage());
        }
    }

    /**
     * @description Builds a concise error message string from a failed integration result.
     * @param recordId The record ID that failed
     * @param result The failed IntegrationResult (may be null)
     * @return A formatted error message string
     */
    private String buildErrorMessage(Id recordId, IntegrationResult result) {
        String msg = 'Record ' + recordId + ': ';
        if (result != null) {
            msg += 'Status=' + result.statusCode + ', Error=' +
                (String.isNotBlank(result.errorMessage) ? result.errorMessage : 'No error message');
        } else {
            msg += 'Null result returned from IntegrationEngine';
        }
        return msg;
    }

    /**
     * @description Adds an error message to the accumulated errors list, respecting
     *              the maximum count and per-message length caps.
     * @param errorMsg The error message to add
     */
    private void addError(String errorMsg) {
        if (errors.size() >= MAX_ERROR_MESSAGES) {
            // Replace the last entry with a truncation notice if not already set
            if (!errors[errors.size() - 1].startsWith('[TRUNCATED]')) {
                errors.add('[TRUNCATED] Additional errors suppressed. Total failures: see failureCount.');
            }
            return;
        }

        if (errorMsg != null && errorMsg.length() > MAX_ERROR_MESSAGE_LENGTH) {
            errorMsg = errorMsg.substring(0, MAX_ERROR_MESSAGE_LENGTH) + '...';
        }

        errors.add(errorMsg);
    }

    /**
     * @description Called after all batch chunks have been processed. Logs a summary
     *              of the batch execution and sends an alert notification if there were
     *              any failures.
     * @param bc The BatchableContext provided by the Apex runtime
     */
    global void finish(Database.BatchableContext bc) {
        Integer totalProcessed = successCount + failureCount;

        String summary = buildFinishSummary(bc, totalProcessed);
        System.debug(LoggingLevel.INFO, summary);

        // Create a summary log record
        createSummaryLog(bc, totalProcessed);

        // Send alert if there were failures
        if (failureCount > 0) {
            sendFailureAlert(bc, totalProcessed);
        }
    }

    /**
     * @description Builds the human-readable summary string for the finish log.
     * @param bc The BatchableContext
     * @param totalProcessed Total records processed across all chunks
     * @return Formatted summary string
     */
    private String buildFinishSummary(Database.BatchableContext bc, Integer totalProcessed) {
        String jobIdLabel = (bc != null && bc.getJobId() != null) ? String.valueOf(bc.getJobId()) : 'N/A';
        String summary = 'IntegrationBatchProcessor: Batch complete for integration [' +
            integrationKey + '].\n' +
            '  Job ID: ' + jobIdLabel + '\n' +
            '  Total Processed: ' + totalProcessed + '\n' +
            '  Successes: ' + successCount + '\n' +
            '  Failures: ' + failureCount;

        if (!errors.isEmpty()) {
            summary += '\n  Sample Errors (' + Math.min(errors.size(), 10) + ' of ' + errors.size() + '):';
            for (Integer i = 0; i < Math.min(errors.size(), 10); i++) {
                summary += '\n    - ' + errors[i];
            }
        }

        return summary;
    }

    /**
     * @description Creates an Integration_Log__c summary record for the batch execution.
     * @param bc The BatchableContext
     * @param totalProcessed Total records processed
     */
    private void createSummaryLog(Database.BatchableContext bc, Integer totalProcessed) {
        try {
            // Build a summary error message from accumulated errors
            String errorSummary = '';
            if (!errors.isEmpty()) {
                // Take first few errors to stay within field limits
                List<String> sampleErrors = new List<String>();
                for (Integer i = 0; i < Math.min(errors.size(), 20); i++) {
                    sampleErrors.add(errors[i]);
                }
                errorSummary = String.join(sampleErrors, '\n');
                if (errorSummary.length() > 32768) {
                    errorSummary = errorSummary.substring(0, 32764) + '...';
                }
            }

            Integration_Log__c summaryLog = new Integration_Log__c(
                Integration_Key__c = integrationKey,
                Is_Success__c = (failureCount == 0),
                Retry_Count__c = 0,
                Is_Retry__c = false,
                Error_Message__c = String.isNotBlank(errorSummary) ? errorSummary : null,
                Correlation_Id__c = 'BATCH-' +
                    (bc != null ? String.valueOf(bc.getJobId()).substring(0, Math.min(String.valueOf(bc.getJobId()).length(), 15)) : 'UNKNOWN')
            );

            // Attempt to set the endpoint lookup
            List<Integration_Endpoint__c> endpoints = [
                SELECT Id
                FROM Integration_Endpoint__c
                WHERE Integration_Key__c = :integrationKey
                  AND Active__c = true
                LIMIT 1
            ];
            if (!endpoints.isEmpty()) {
                summaryLog.Integration_Endpoint__c = endpoints[0].Id;
            }

            insert summaryLog;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationBatchProcessor: Failed to create summary log: ' + ex.getMessage());
        }
    }

    /**
     * @description Sends a failure alert notification when the batch encounters errors.
     *              Uses custom notification or email depending on org configuration.
     * @param bc The BatchableContext
     * @param totalProcessed Total records processed
     */
    private void sendFailureAlert(Database.BatchableContext bc, Integer totalProcessed) {
        try {
            Decimal failureRate = totalProcessed > 0
                ? ((Decimal) failureCount / totalProcessed * 100).setScale(1)
                : 0;

            String subject = 'Integration Batch Alert: ' + integrationKey +
                ' - ' + failureCount + ' failure(s)';

            String alertJobId = (bc != null && bc.getJobId() != null) ? String.valueOf(bc.getJobId()) : 'N/A';
            String body = 'Integration Batch Processor completed with failures.\n\n' +
                'Integration Key: ' + integrationKey + '\n' +
                'Job ID: ' + alertJobId + '\n' +
                'Total Processed: ' + totalProcessed + '\n' +
                'Successes: ' + successCount + '\n' +
                'Failures: ' + failureCount + '\n' +
                'Failure Rate: ' + failureRate + '%\n\n';

            if (!errors.isEmpty()) {
                body += 'Sample Errors (first ' + Math.min(errors.size(), 10) + '):\n';
                for (Integer i = 0; i < Math.min(errors.size(), 10); i++) {
                    body += '  ' + (i + 1) + '. ' + errors[i] + '\n';
                }
            }

            // Send email notification to the running user
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(UserInfo.getUserId());
            mail.setSubject(subject);
            mail.setPlainTextBody(body);
            mail.setSaveAsActivity(false);

            // Use allOrNone = false so email failure does not throw
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);

        } catch (Exception ex) {
            // Email send failure should not propagate - log and continue
            System.debug(LoggingLevel.WARN,
                'IntegrationBatchProcessor: Failed to send failure alert email: ' + ex.getMessage());
        }
    }

    /**
     * @description Custom exception class for batch processor configuration errors.
     */
    global class IntegrationBatchException extends Exception {}
}