/**
 * @description Schedulable class for periodic retry of dead-lettered integration failures.
 *              Queries Integration_Error_Log__c records marked as dead letters that are
 *              still eligible for retry and have not been resolved, groups them by
 *              integration key, and re-enqueues each for retry via IntegrationRetryQueueable.
 *
 *              Includes convenience methods for scheduling hourly and daily executions.
 *              Enforces a batch size limit per execution to stay within governor limits.
 * @author Integration Platform
 */
global class IntegrationRetrySchedulable implements Schedulable {

    // ── Constants ──

    /** Maximum number of dead-letter records to process per scheduled execution */
    private static final Integer MAX_RECORDS_PER_EXECUTION = 50;

    /** Cron expression for hourly execution (every hour at minute 0) */
    private static final String CRON_HOURLY = '0 0 * * * ?';

    /** Cron expression for daily execution (every day at 2:00 AM) */
    private static final String CRON_DAILY = '0 0 2 * * ?';

    /** Job name prefix for identifying scheduled retry jobs */
    private static final String JOB_NAME_PREFIX = 'Integration_DeadLetter_Retry_';

    /**
     * @description Executes the scheduled retry of dead-lettered integration error logs.
     *              Queries eligible records, groups by integration key, and enqueues
     *              retry jobs while respecting governor limits.
     * @param sc The SchedulableContext provided by the Apex scheduler
     */
    global void execute(SchedulableContext sc) {
        try {
            // Query dead-letter records eligible for retry
            List<Integration_Error_Log__c> deadLetterRecords = queryDeadLetterRecords();

            if (deadLetterRecords.isEmpty()) {
                System.debug(LoggingLevel.INFO,
                    'IntegrationRetrySchedulable: No eligible dead-letter records found for retry.');
                return;
            }

            // Group records by integration key for organized processing
            Map<String, List<Integration_Error_Log__c>> recordsByKey = groupByIntegrationKey(deadLetterRecords);

            // Track how many queueable jobs we enqueue to respect limits
            Integer enqueueCount = 0;
            Integer maxQueueableJobs = calculateAvailableQueueableSlots();

            List<Integration_Error_Log__c> recordsToUpdate = new List<Integration_Error_Log__c>();

            for (String integrationKey : recordsByKey.keySet()) {
                if (enqueueCount >= maxQueueableJobs) {
                    System.debug(LoggingLevel.WARN,
                        'IntegrationRetrySchedulable: Reached queueable job limit (' +
                        maxQueueableJobs + '). Remaining records will be processed in the next execution.');
                    break;
                }

                List<Integration_Error_Log__c> records = recordsByKey.get(integrationKey);
                for (Integration_Error_Log__c errorLog : records) {
                    if (enqueueCount >= maxQueueableJobs) {
                        break;
                    }

                    try {
                        enqueueDeadLetterRetry(errorLog, integrationKey);
                        enqueueCount++;

                        // Mark as no longer eligible to prevent duplicate processing
                        recordsToUpdate.add(new Integration_Error_Log__c(
                            Id = errorLog.Id,
                            Retry_Eligible__c = false
                        ));
                    } catch (Exception ex) {
                        System.debug(LoggingLevel.ERROR,
                            'IntegrationRetrySchedulable: Failed to enqueue retry for error log ' +
                            errorLog.Id + ': ' + ex.getMessage());
                    }
                }
            }

            // Bulk update processed records to prevent re-processing
            if (!recordsToUpdate.isEmpty()) {
                updateProcessedRecords(recordsToUpdate);
            }

            System.debug(LoggingLevel.INFO,
                'IntegrationRetrySchedulable: Enqueued ' + enqueueCount +
                ' dead-letter retries from ' + deadLetterRecords.size() + ' eligible records.');

        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationRetrySchedulable: Unexpected error during scheduled execution: ' +
                ex.getMessage() + ' | Stack: ' + ex.getStackTraceString());
        }
    }

    /**
     * @description Queries Integration_Error_Log__c records that are dead-lettered,
     *              eligible for retry, and not yet resolved. Limited to MAX_RECORDS_PER_EXECUTION.
     * @return List of eligible dead-letter error log records
     */
    private List<Integration_Error_Log__c> queryDeadLetterRecords() {
        return [
            SELECT Id,
                   Integration_Log__c,
                   Integration_Log__r.Integration_Key__c,
                   Integration_Log__r.Integration_Endpoint__c,
                   Integration_Log__r.Correlation_Id__c,
                   Integration_Log__r.Retry_Count__c,
                   Error_Type__c,
                   Error_Message__c,
                   Original_Payload__c,
                   Severity__c
            FROM Integration_Error_Log__c
            WHERE Is_Dead_Letter__c = true
              AND Retry_Eligible__c = true
            ORDER BY CreatedDate ASC
            LIMIT :MAX_RECORDS_PER_EXECUTION
        ];
    }

    /**
     * @description Groups dead-letter error log records by their integration key.
     * @param records The list of error log records to group
     * @return Map of integration key to list of associated error log records
     */
    private Map<String, List<Integration_Error_Log__c>> groupByIntegrationKey(
        List<Integration_Error_Log__c> records
    ) {
        Map<String, List<Integration_Error_Log__c>> grouped = new Map<String, List<Integration_Error_Log__c>>();

        for (Integration_Error_Log__c record : records) {
            String integrationKey = record.Integration_Log__r != null
                ? record.Integration_Log__r.Integration_Key__c
                : null;

            if (String.isBlank(integrationKey)) {
                System.debug(LoggingLevel.WARN,
                    'IntegrationRetrySchedulable: Skipping error log ' + record.Id +
                    ' - no integration key found on parent log.');
                continue;
            }

            if (!grouped.containsKey(integrationKey)) {
                grouped.put(integrationKey, new List<Integration_Error_Log__c>());
            }
            grouped.get(integrationKey).add(record);
        }

        return grouped;
    }

    /**
     * @description Enqueues a single dead-letter record for retry by creating an
     *              IntegrationRetryQueueable with the original payload and context.
     * @param errorLog The dead-letter error log record
     * @param integrationKey The integration key for the retry
     */
    private void enqueueDeadLetterRetry(Integration_Error_Log__c errorLog, String integrationKey) {
        // Reconstruct payload from the stored original
        Map<String, Object> payload = new Map<String, Object>();
        if (String.isNotBlank(errorLog.Original_Payload__c)) {
            try {
                payload = (Map<String, Object>) JSON.deserializeUntyped(errorLog.Original_Payload__c);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN,
                    'IntegrationRetrySchedulable: Could not deserialize original payload for error log ' +
                    errorLog.Id + '. Proceeding with empty payload.');
            }
        }

        // Build context with dead-letter retry metadata
        Map<String, String> context = new Map<String, String>{
            'isDeadLetterRetry' => 'true',
            'originalErrorLogId' => String.valueOf(errorLog.Id),
            'isRetry' => 'true'
        };

        if (errorLog.Integration_Log__r != null && errorLog.Integration_Log__r.Correlation_Id__c != null) {
            context.put('correlationId', errorLog.Integration_Log__r.Correlation_Id__c);
        }

        // Determine retry count - reset to 0 for dead-letter retries to allow fresh retry cycle
        Integer retryCount = 0;

        // Parent log is the original integration log
        Id parentLogId = errorLog.Integration_Log__c;

        // Use a minimal delay for dead-letter retries (they have already waited)
        Integer delaySeconds = 0;

        IntegrationRetryHandler.enqueueRetry(
            integrationKey,
            null, // recordId not preserved in dead-letter; engine will resolve from payload if needed
            payload,
            context,
            retryCount,
            parentLogId,
            delaySeconds
        );
    }

    /**
     * @description Performs a bulk update on processed dead-letter records with partial
     *              success handling to avoid losing updates due to individual record failures.
     * @param records The list of error log records to update
     */
    private void updateProcessedRecords(List<Integration_Error_Log__c> records) {
        List<Database.SaveResult> results = Database.update(records, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                String errors = '';
                for (Database.Error err : results[i].getErrors()) {
                    errors += err.getStatusCode() + ': ' + err.getMessage() + '; ';
                }
                System.debug(LoggingLevel.ERROR,
                    'IntegrationRetrySchedulable: Failed to update error log ' +
                    records[i].Id + ': ' + errors);
            }
        }
    }

    /**
     * @description Calculates the number of available queueable job slots in the current
     *              transaction to avoid hitting the Limits.getQueueableJobs() governor limit.
     * @return The number of queueable jobs that can still be enqueued
     */
    private Integer calculateAvailableQueueableSlots() {
        Integer maxJobs = Limits.getLimitQueueableJobs();
        Integer usedJobs = Limits.getQueueableJobs();
        Integer available = maxJobs - usedJobs;

        // Further cap to our own maximum to be conservative
        return Math.min(available, MAX_RECORDS_PER_EXECUTION);
    }

    // ── Scheduling Convenience Methods ──

    /**
     * @description Schedules this class to run hourly (at the top of every hour).
     * @return The scheduled job ID
     */
    global static String scheduleHourly() {
        String jobName = JOB_NAME_PREFIX + 'Hourly';

        // Abort existing job with the same name to allow re-scheduling
        abortExistingJob(jobName);

        return System.schedule(jobName, CRON_HOURLY, new IntegrationRetrySchedulable());
    }

    /**
     * @description Schedules this class to run daily at 2:00 AM.
     * @return The scheduled job ID
     */
    global static String scheduleDaily() {
        String jobName = JOB_NAME_PREFIX + 'Daily';

        // Abort existing job with the same name to allow re-scheduling
        abortExistingJob(jobName);

        return System.schedule(jobName, CRON_DAILY, new IntegrationRetrySchedulable());
    }

    /**
     * @description Aborts an existing scheduled job by name to prevent duplicate schedules.
     * @param jobName The name of the scheduled job to abort
     */
    private static void abortExistingJob(String jobName) {
        List<CronTrigger> existingJobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :jobName
              AND State NOT IN ('DELETED', 'COMPLETE')
            LIMIT 1
        ];

        if (!existingJobs.isEmpty()) {
            try {
                System.abortJob(existingJobs[0].Id);
            } catch (Exception ex) {
                System.debug(LoggingLevel.WARN,
                    'IntegrationRetrySchedulable: Could not abort existing job "' + jobName +
                    '": ' + ex.getMessage());
            }
        }
    }
}