/**
 * @description Apex controller for Integration Monitoring LWC dashboard components.
 *              Provides aggregated statistics, recent logs, error summaries, endpoint health,
 *              log detail views, and failure heatmap data. All cacheable methods support
 *              wire service caching in Lightning components.
 * @author Integration Platform
 */
public with sharing class IntegrationDashboardController {

    /** Maximum number of records to return for list queries (safety net) */
    private static final Integer ABSOLUTE_MAX_RECORDS = 2000;

    /** Default record limit when none specified */
    private static final Integer DEFAULT_LIMIT = 50;

    // Time range constants
    private static final String TIME_RANGE_24H = 'Last24Hours';
    private static final String TIME_RANGE_7D = 'Last7Days';
    private static final String TIME_RANGE_30D = 'Last30Days';

    // Health status constants
    private static final String HEALTH_UNKNOWN = 'Unknown';
    private static final String HEALTH_HEALTHY = 'Healthy';
    private static final String HEALTH_DEGRADED = 'Degraded';
    private static final String HEALTH_UNHEALTHY = 'Unhealthy';
    private static final String HEALTH_CRITICAL = 'Critical';
    private static final String HEALTH_NO_DATA = 'No Data';

    // ─── Inner Classes for Structured Responses ──────────────────────────

    /**
     * @description Aggregated log statistics for a single integration endpoint.
     */
    public class LogSummary {
        @AuraEnabled public String integrationKey { get; set; }
        @AuraEnabled public String endpointName { get; set; }
        @AuraEnabled public Integer totalCount { get; set; }
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failureCount { get; set; }
        @AuraEnabled public Decimal successRate { get; set; }

        public LogSummary() {
            this.totalCount = 0;
            this.successCount = 0;
            this.failureCount = 0;
            this.successRate = 0;
        }
    }

    /**
     * @description Error count grouped by error type and severity.
     */
    public class ErrorSummary {
        @AuraEnabled public String errorType { get; set; }
        @AuraEnabled public String severity { get; set; }
        @AuraEnabled public Integer errorCount { get; set; }

        public ErrorSummary() {
            this.errorCount = 0;
        }
    }

    /**
     * @description Health status for a single integration endpoint.
     */
    public class EndpointHealth {
        @AuraEnabled public String integrationKey { get; set; }
        @AuraEnabled public String endpointName { get; set; }
        @AuraEnabled public Id endpointId { get; set; }
        @AuraEnabled public Decimal successRate { get; set; }
        @AuraEnabled public Decimal avgResponseTimeMs { get; set; }
        @AuraEnabled public Integer totalCalls { get; set; }
        @AuraEnabled public Integer failedCalls { get; set; }
        @AuraEnabled public String healthStatus { get; set; }
        @AuraEnabled public Datetime lastCallTime { get; set; }

        public EndpointHealth() {
            this.successRate = 0;
            this.avgResponseTimeMs = 0;
            this.totalCalls = 0;
            this.failedCalls = 0;
            this.healthStatus = HEALTH_UNKNOWN;
        }
    }

    /**
     * @description Full detail view of a single log record including child error logs.
     */
    public class LogDetail {
        @AuraEnabled public Integration_Log__c log { get; set; }
        @AuraEnabled public List<Integration_Error_Log__c> errorLogs { get; set; }

        public LogDetail() {
            this.errorLogs = new List<Integration_Error_Log__c>();
        }
    }

    /**
     * @description Single data point for the failure heatmap (failures per hour/day).
     */
    public class HeatmapEntry {
        @AuraEnabled public Integer dayOfWeek { get; set; }
        @AuraEnabled public Integer hourOfDay { get; set; }
        @AuraEnabled public Date entryDate { get; set; }
        @AuraEnabled public Integer failureCount { get; set; }

        public HeatmapEntry() {
            this.failureCount = 0;
        }
    }

    // ─── AuraEnabled Controller Methods ──────────────────────────────────

    /**
     * @description Returns aggregated log statistics grouped by integration key for the
     *              specified time range. Includes total, success, and failure counts plus
     *              success rate per endpoint.
     * @param timeRange One of: Last24Hours, Last7Days, Last30Days
     * @return List of LogSummary wrapper objects
     */
    @AuraEnabled(cacheable=true)
    public static List<LogSummary> getLogSummary(String timeRange) {
        Datetime startDate = resolveStartDate(timeRange);
        Map<String, LogSummary> summaryMap = new Map<String, LogSummary>();

        try {
            // Query total counts per integration key
            List<AggregateResult> totalResults = [
                SELECT Integration_Key__c integrationKey,
                       COUNT(Id) total
                FROM Integration_Log__c
                WHERE Execution_End__c >= :startDate
                  AND Integration_Key__c != null
                GROUP BY Integration_Key__c
                ORDER BY COUNT(Id) DESC
                LIMIT :ABSOLUTE_MAX_RECORDS
            ];

            for (AggregateResult ar : totalResults) {
                LogSummary summary = new LogSummary();
                summary.integrationKey = (String) ar.get('integrationKey');
                summary.totalCount = (Integer) ar.get('total');
                summaryMap.put(summary.integrationKey, summary);
            }

            // Query success counts per integration key
            List<AggregateResult> successResults = [
                SELECT Integration_Key__c integrationKey,
                       COUNT(Id) successes
                FROM Integration_Log__c
                WHERE Execution_End__c >= :startDate
                  AND Integration_Key__c != null
                  AND Is_Success__c = true
                GROUP BY Integration_Key__c
                LIMIT :ABSOLUTE_MAX_RECORDS
            ];

            for (AggregateResult ar : successResults) {
                String key = (String) ar.get('integrationKey');
                if (summaryMap.containsKey(key)) {
                    LogSummary summary = summaryMap.get(key);
                    summary.successCount = (Integer) ar.get('successes');
                    summary.failureCount = summary.totalCount - summary.successCount;
                    summary.successRate = summary.totalCount > 0
                        ? ((Decimal) summary.successCount / summary.totalCount * 100).setScale(2)
                        : 0;
                }
            }

            // Compute failure counts and success rates for keys with zero successes
            for (LogSummary summary : summaryMap.values()) {
                if (summary.successCount == 0) {
                    summary.failureCount = summary.totalCount;
                    summary.successRate = 0;
                }
            }

            // Enrich with endpoint names
            if (!summaryMap.isEmpty()) {
                for (Integration_Endpoint__c ep : [
                    SELECT Integration_Key__c, Name
                    FROM Integration_Endpoint__c
                    WHERE Integration_Key__c IN :summaryMap.keySet()
                ]) {
                    if (summaryMap.containsKey(ep.Integration_Key__c)) {
                        summaryMap.get(ep.Integration_Key__c).endpointName = ep.Name;
                    }
                }
            }
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Error retrieving log summary: ' + ex.getMessage()
            );
        }

        return summaryMap.values();
    }

    /**
     * @description Returns recent log entries filtered optionally by integration key.
     * @param integrationKey Optional integration key filter (null returns all)
     * @param limitCount Number of records to return (capped at ABSOLUTE_MAX_RECORDS)
     * @return List of Integration_Log__c records
     */
    @AuraEnabled(cacheable=true)
    public static List<Integration_Log__c> getRecentLogs(String integrationKey, Integer limitCount) {
        Integer safeLimit = sanitizeLimit(limitCount);

        try {
            if (String.isNotBlank(integrationKey)) {
                return [
                    SELECT Id, Name, Integration_Key__c, Correlation_Id__c, Direction__c,
                           HTTP_Method__c, Request_URL__c, Response_Status_Code__c,
                           Is_Success__c, Execution_Time_ms__c, Execution_Start__c,
                           Execution_End__c, Record_Id__c, Source_Object__c,
                           Retry_Count__c, Is_Retry__c, Error_Message__c,
                           Execution_Mode__c, Triggered_By__c
                    FROM Integration_Log__c
                    WHERE Integration_Key__c = :integrationKey
                    ORDER BY Execution_End__c DESC NULLS LAST
                    LIMIT :safeLimit
                ];
            } else {
                return [
                    SELECT Id, Name, Integration_Key__c, Correlation_Id__c, Direction__c,
                           HTTP_Method__c, Request_URL__c, Response_Status_Code__c,
                           Is_Success__c, Execution_Time_ms__c, Execution_Start__c,
                           Execution_End__c, Record_Id__c, Source_Object__c,
                           Retry_Count__c, Is_Retry__c, Error_Message__c,
                           Execution_Mode__c, Triggered_By__c
                    FROM Integration_Log__c
                    ORDER BY Execution_End__c DESC NULLS LAST
                    LIMIT :safeLimit
                ];
            }
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Error retrieving recent logs: ' + ex.getMessage()
            );
        }
    }

    /**
     * @description Returns error counts aggregated by error type and severity for the
     *              specified time range.
     * @param timeRange One of: Last24Hours, Last7Days, Last30Days
     * @return List of ErrorSummary wrapper objects
     */
    @AuraEnabled(cacheable=true)
    public static List<ErrorSummary> getErrorSummary(String timeRange) {
        Datetime startDate = resolveStartDate(timeRange);
        List<ErrorSummary> summaries = new List<ErrorSummary>();

        try {
            List<AggregateResult> results = [
                SELECT Error_Type__c errorType,
                       Severity__c severity,
                       COUNT(Id) errorCount
                FROM Integration_Error_Log__c
                WHERE CreatedDate >= :startDate
                GROUP BY Error_Type__c, Severity__c
                ORDER BY COUNT(Id) DESC
                LIMIT :ABSOLUTE_MAX_RECORDS
            ];

            for (AggregateResult ar : results) {
                ErrorSummary summary = new ErrorSummary();
                summary.errorType = (String) ar.get('errorType');
                summary.severity = (String) ar.get('severity');
                summary.errorCount = (Integer) ar.get('errorCount');
                summaries.add(summary);
            }
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Error retrieving error summary: ' + ex.getMessage()
            );
        }

        return summaries;
    }

    /**
     * @description Returns health status for each active integration endpoint,
     *              including success rate, average response time, and overall health rating.
     *              Health is assessed over the last 24 hours.
     * @return List of EndpointHealth wrapper objects
     */
    @AuraEnabled(cacheable=true)
    public static List<EndpointHealth> getEndpointHealth() {
        List<EndpointHealth> healthList = new List<EndpointHealth>();
        Datetime last24Hours = Datetime.now().addHours(-24);

        try {
            // Get all active endpoints
            Map<String, Integration_Endpoint__c> endpointMap = new Map<String, Integration_Endpoint__c>();
            for (Integration_Endpoint__c ep : [
                SELECT Id, Name, Integration_Key__c, Active__c
                FROM Integration_Endpoint__c
                WHERE Active__c = true
                ORDER BY Name
                LIMIT :ABSOLUTE_MAX_RECORDS
            ]) {
                endpointMap.put(ep.Integration_Key__c, ep);
            }

            if (endpointMap.isEmpty()) {
                return healthList;
            }

            // Aggregate log data for active endpoints (totals, avg time, last call)
            List<AggregateResult> totalResults = [
                SELECT Integration_Key__c integrationKey,
                       COUNT(Id) total,
                       AVG(Execution_Time_ms__c) avgTime,
                       MAX(Execution_End__c) lastCall
                FROM Integration_Log__c
                WHERE Integration_Key__c IN :endpointMap.keySet()
                  AND Execution_End__c >= :last24Hours
                GROUP BY Integration_Key__c
            ];

            // Aggregate success counts separately
            Map<String, Integer> successCountMap = new Map<String, Integer>();
            for (AggregateResult ar : [
                SELECT Integration_Key__c integrationKey,
                       COUNT(Id) successes
                FROM Integration_Log__c
                WHERE Integration_Key__c IN :endpointMap.keySet()
                  AND Execution_End__c >= :last24Hours
                  AND Is_Success__c = true
                GROUP BY Integration_Key__c
            ]) {
                successCountMap.put((String) ar.get('integrationKey'), (Integer) ar.get('successes'));
            }

            // Build health entries from aggregated data
            Set<String> keysWithData = new Set<String>();
            for (AggregateResult ar : totalResults) {
                String key = (String) ar.get('integrationKey');
                keysWithData.add(key);

                EndpointHealth health = new EndpointHealth();
                health.integrationKey = key;
                health.totalCalls = (Integer) ar.get('total');
                Integer successes = successCountMap.containsKey(key) ? successCountMap.get(key) : 0;
                health.failedCalls = health.totalCalls - successes;
                health.avgResponseTimeMs = ar.get('avgTime') != null
                    ? ((Decimal) ar.get('avgTime')).setScale(2)
                    : 0;
                health.lastCallTime = (Datetime) ar.get('lastCall');
                health.successRate = health.totalCalls > 0
                    ? ((Decimal) successes / health.totalCalls * 100).setScale(2)
                    : 0;

                if (endpointMap.containsKey(key)) {
                    health.endpointName = endpointMap.get(key).Name;
                    health.endpointId = endpointMap.get(key).Id;
                }

                health.healthStatus = calculateHealthStatus(health.successRate, health.avgResponseTimeMs);
                healthList.add(health);
            }

            // Include active endpoints with no recent traffic
            for (String key : endpointMap.keySet()) {
                if (!keysWithData.contains(key)) {
                    EndpointHealth health = new EndpointHealth();
                    health.integrationKey = key;
                    health.endpointName = endpointMap.get(key).Name;
                    health.endpointId = endpointMap.get(key).Id;
                    health.healthStatus = HEALTH_NO_DATA;
                    healthList.add(health);
                }
            }
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Error retrieving endpoint health: ' + ex.getMessage()
            );
        }

        return healthList;
    }

    /**
     * @description Returns full detail for a single log record including all child error logs.
     * @param logId The Integration_Log__c record Id
     * @return LogDetail wrapper with log and error log records
     */
    @AuraEnabled
    public static LogDetail getLogDetail(Id logId) {
        if (logId == null) {
            throw new AuraHandledException('Log ID is required.');
        }

        LogDetail detail = new LogDetail();

        try {
            List<Integration_Log__c> logs = [
                SELECT Id, Name, Integration_Endpoint__c, Integration_Key__c,
                       Correlation_Id__c, Direction__c, HTTP_Method__c, Request_URL__c,
                       Request_Headers__c, Request_Body__c, Response_Status_Code__c,
                       Response_Headers__c, Response_Body__c, Is_Success__c,
                       Execution_Time_ms__c, Execution_Start__c, Execution_End__c,
                       Record_Id__c, Source_Object__c, Retry_Count__c, Is_Retry__c,
                       Parent_Log__c, Error_Message__c, Execution_Mode__c, Triggered_By__c
                FROM Integration_Log__c
                WHERE Id = :logId
                LIMIT 1
            ];

            if (logs.isEmpty()) {
                throw new AuraHandledException('Log record not found for ID: ' + logId);
            }

            detail.log = logs[0];

            detail.errorLogs = [
                SELECT Id, Name, Integration_Log__c, Error_Type__c, Error_Message__c,
                       Stack_Trace__c, Error_Code__c, Severity__c, Is_Resolved__c,
                       Resolved_Date__c, Resolved_By__c, Resolution_Notes__c,
                       Is_Dead_Letter__c, Retry_Eligible__c, Original_Payload__c,
                       CreatedDate
                FROM Integration_Error_Log__c
                WHERE Integration_Log__c = :logId
                ORDER BY CreatedDate DESC
                LIMIT 100
            ];
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Error retrieving log detail: ' + ex.getMessage()
            );
        }

        return detail;
    }

    /**
     * @description Returns failure counts grouped by date and hour-of-day for rendering
     *              a heatmap visualization. Each entry represents the number of failures
     *              in a specific hour on a specific date.
     * @param days Number of days to look back (max 90)
     * @return List of HeatmapEntry wrapper objects
     */
    @AuraEnabled(cacheable=true)
    public static List<HeatmapEntry> getFailureHeatmap(Integer days) {
        Integer safeDays = (days != null && days > 0 && days <= 90) ? days : 7;
        Datetime startDate = Datetime.now().addDays(-safeDays);
        List<HeatmapEntry> entries = new List<HeatmapEntry>();

        try {
            List<AggregateResult> results = [
                SELECT DAY_ONLY(Execution_End__c) logDate,
                       HOUR_IN_DAY(Execution_End__c) logHour,
                       COUNT(Id) failureCount
                FROM Integration_Log__c
                WHERE Is_Success__c = false
                  AND Execution_End__c >= :startDate
                  AND Execution_End__c != null
                GROUP BY DAY_ONLY(Execution_End__c), HOUR_IN_DAY(Execution_End__c)
                ORDER BY DAY_ONLY(Execution_End__c) ASC, HOUR_IN_DAY(Execution_End__c) ASC
                LIMIT :ABSOLUTE_MAX_RECORDS
            ];

            for (AggregateResult ar : results) {
                HeatmapEntry entry = new HeatmapEntry();
                entry.entryDate = (Date) ar.get('logDate');
                entry.hourOfDay = (Integer) ar.get('logHour');
                entry.failureCount = (Integer) ar.get('failureCount');

                // Calculate day of week (1 = Monday ... 7 = Sunday)
                if (entry.entryDate != null) {
                    Datetime dt = Datetime.newInstance(entry.entryDate, Time.newInstance(0, 0, 0, 0));
                    String dayName = dt.format('u'); // ISO day of week
                    entry.dayOfWeek = Integer.valueOf(dayName);
                }

                entries.add(entry);
            }
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Error retrieving failure heatmap: ' + ex.getMessage()
            );
        }

        return entries;
    }

    // ─── Endpoint Save Method ────────────────────────────────────────────

    /**
     * @description Saves an Integration Endpoint record, creating or updating as appropriate.
     *              Uses Schema describe to gracefully skip fields that do not exist or are
     *              not accessible, preventing errors when the org schema differs from the
     *              component's expectations (e.g., a field has not been deployed yet).
     * @param endpointData Map of field API names to values
     * @param recordId Existing record Id for updates; null to create a new record
     * @return The saved record's Id
     */
    @AuraEnabled
    public static Id saveEndpoint(Map<String, Object> endpointData, Id recordId) {
        if (endpointData == null || endpointData.isEmpty()) {
            throw new AuraHandledException('No endpoint data provided.');
        }

        try {
            Integration_Endpoint__c endpoint = recordId != null
                ? new Integration_Endpoint__c(Id = recordId)
                : new Integration_Endpoint__c();

            Map<String, Schema.SObjectField> fieldMap =
                Schema.SObjectType.Integration_Endpoint__c.fields.getMap();

            for (String fieldName : endpointData.keySet()) {
                String lowerName = fieldName.toLowerCase();

                // Skip fields that do not exist on the object
                if (!fieldMap.containsKey(lowerName)) {
                    continue;
                }

                Schema.DescribeFieldResult dfr = fieldMap.get(lowerName).getDescribe();

                // Skip fields the running user cannot write
                Boolean canWrite = recordId != null ? dfr.isUpdateable() : dfr.isCreateable();
                if (!canWrite) {
                    continue;
                }

                Object value = endpointData.get(fieldName);
                if (value != null) {
                    endpoint.put(fieldName, value);
                }
            }

            if (recordId != null) {
                update endpoint;
            } else {
                insert endpoint;
            }

            return endpoint.Id;
        } catch (DmlException dmlEx) {
            throw new AuraHandledException('Save failed: ' + dmlEx.getDmlMessage(0));
        } catch (Exception ex) {
            throw new AuraHandledException('Error saving endpoint: ' + ex.getMessage());
        }
    }

    // ─── Private Helper Methods ──────────────────────────────────────────

    /**
     * @description Resolves a time range string to a start Datetime.
     * @param timeRange One of: Last24Hours, Last7Days, Last30Days
     * @return The calculated start Datetime (defaults to last 24 hours for invalid input)
     */
    private static Datetime resolveStartDate(String timeRange) {
        if (String.isBlank(timeRange)) {
            return Datetime.now().addHours(-24);
        }

        switch on timeRange {
            when 'Last24Hours' {
                return Datetime.now().addHours(-24);
            }
            when 'Last7Days' {
                return Datetime.now().addDays(-7);
            }
            when 'Last30Days' {
                return Datetime.now().addDays(-30);
            }
            when else {
                return Datetime.now().addHours(-24); // default to 24h
            }
        }
    }

    /**
     * @description Sanitizes a record limit value to prevent abuse and governor limit issues.
     * @param limitCount The requested limit
     * @return A safe limit between 1 and ABSOLUTE_MAX_RECORDS
     */
    private static Integer sanitizeLimit(Integer limitCount) {
        if (limitCount == null || limitCount <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(limitCount, ABSOLUTE_MAX_RECORDS);
    }

    /**
     * @description Calculates a human-readable health status based on success rate and
     *              average response time.
     * @param successRate Success percentage (0-100)
     * @param avgResponseTimeMs Average response time in milliseconds
     * @return Health status string: Healthy, Degraded, Unhealthy, or Critical
     */
    private static String calculateHealthStatus(Decimal successRate, Decimal avgResponseTimeMs) {
        if (successRate == null) {
            return HEALTH_UNKNOWN;
        }

        if (successRate >= 99 && (avgResponseTimeMs == null || avgResponseTimeMs < 2000)) {
            return HEALTH_HEALTHY;
        } else if (successRate >= 95) {
            return HEALTH_DEGRADED;
        } else if (successRate >= 80) {
            return HEALTH_UNHEALTHY;
        } else {
            return HEALTH_CRITICAL;
        }
    }
}