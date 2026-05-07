/**
 * @description Main orchestration class for the metadata-driven Integration Platform.
 *              Coordinates the full lifecycle of outbound integration callouts:
 *              loading endpoint configuration, resolving authentication, building requests
 *              from templates and field mappings, executing callouts, mapping responses,
 *              and logging all activity. Supports both synchronous and asynchronous
 *              execution modes and is designed to be bulk-capable and governor-limit safe.
 * @author Integration Platform
 */
public class IntegrationEngine {

    /** Buffer of Integration_Log__c records to insert at the end of execution */
    private static List<Integration_Log__c> pendingLogs = new List<Integration_Log__c>();

    /** Buffer of Integration_Error_Log__c records to insert at the end of execution */
    private static List<Integration_Error_Log__c> pendingErrorLogs = new List<Integration_Error_Log__c>();

    // ─────────────────────────────────────────────────────────────────────────
    // PUBLIC ENTRY POINTS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Primary execution method. Runs a single integration callout identified
     *              by its unique integration key. Orchestrates the full pipeline from
     *              config loading through response mapping and logging.
     * @param integrationKey The unique Integration_Key__c identifying the endpoint
     * @param recordId Optional Salesforce record ID to source data from
     * @param payload Optional explicit payload map (takes precedence over record-based data)
     * @param context Optional context map for path variable substitution and metadata
     * @return IntegrationResult containing success/failure, response data, and mapped values
     */
    public static IntegrationResult execute(
        String integrationKey,
        Id recordId,
        Map<String, Object> payload,
        Map<String, String> context
    ) {
        Long startTime = System.currentTimeMillis();
        IntegrationResult result = new IntegrationResult();

        try {
            // Step 1: Validate inputs
            if (String.isBlank(integrationKey)) {
                return IntegrationResult.failure('Integration key cannot be blank.');
            }

            // Step 2: Load endpoint configuration (cached)
            Integration_Endpoint__c endpoint;
            try {
                endpoint = IntegrationConfigService.getEndpoint(integrationKey);
            } catch (IntegrationConfigService.IntegrationConfigException configEx) {
                return IntegrationResult.failure(configEx.getMessage());
            }

            // Step 3: Validate configuration completeness
            List<String> configErrors = IntegrationConfigService.validateConfiguration(endpoint);
            if (!configErrors.isEmpty()) {
                return IntegrationResult.failure(
                    'Configuration validation failed: ' + String.join(configErrors, '; ')
                );
            }

            // Step 4: Check execution mode -- delegate to async if configured
            String executionMode = String.isNotBlank(endpoint.Execution_Mode__c)
                ? endpoint.Execution_Mode__c : 'Sync';

            if (executionMode.equalsIgnoreCase('Async') || executionMode.equalsIgnoreCase('Queueable')) {
                return enqueueAsyncExecution(integrationKey, recordId, payload, context, result.correlationId);
            }

            // Step 5: Execute synchronously
            result = executeSynchronous(endpoint, integrationKey, recordId, payload, context, startTime);

        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = 'Unhandled exception in IntegrationEngine: ' + ex.getMessage();
            result.executionTimeMs = System.currentTimeMillis() - startTime;

            createErrorLog(null, 'Unhandled_Exception', ex.getMessage(),
                ex.getStackTraceString(), 'Critical',
                payload != null ? JSON.serialize(payload) : null);
        } finally {
            flushLogs();
        }

        return result;
    }

    /**
     * @description Bulk execution method. Processes a list of record IDs against the same
     *              integration endpoint. Queries all records in a single SOQL call to stay
     *              within governor limits, then executes callouts individually.
     * @param integrationKey The unique Integration_Key__c
     * @param recordIds List of Salesforce record IDs to process
     * @param context Optional context map for path variable substitution
     * @return List of IntegrationResult, one per record ID in the same order
     */
    public static List<IntegrationResult> executeBulk(
        String integrationKey,
        List<Id> recordIds,
        Map<String, String> context
    ) {
        List<IntegrationResult> results = new List<IntegrationResult>();

        if (String.isBlank(integrationKey) || recordIds == null || recordIds.isEmpty()) {
            return results;
        }

        // Load configuration once for all records
        Integration_Endpoint__c endpoint;
        try {
            endpoint = IntegrationConfigService.getEndpoint(integrationKey);
        } catch (IntegrationConfigService.IntegrationConfigException configEx) {
            for (Id recId : recordIds) {
                results.add(IntegrationResult.failure(configEx.getMessage()));
            }
            return results;
        }

        // Load template and field mappings once (outside the loop)
        Integration_Request_Template__c template = IntegrationConfigService.getRequestTemplate(endpoint.Id);
        List<Integration_Field_Mapping__c> outboundMappings =
            IntegrationConfigService.getFieldMappings(endpoint.Id, 'Outbound');
        List<Integration_Response_Mapping__c> responseMappings =
            IntegrationConfigService.getResponseMappings(endpoint.Id);

        // Bulk-query record data if a template with source object is configured
        Map<Id, Map<String, Object>> recordDataMap = new Map<Id, Map<String, Object>>();
        if (template != null && String.isNotBlank(template.Source_Object__c)
            && String.isNotBlank(template.Source_Fields__c)) {
            recordDataMap = bulkQueryRecordData(template, new Set<Id>(recordIds));
        }

        // Execute callout for each record, respecting governor limits
        for (Id recId : recordIds) {
            // Check remaining callout capacity
            if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                results.add(IntegrationResult.failure(
                    'Governor limit: no remaining callouts available (' +
                    Limits.getCallouts() + '/' + Limits.getLimitCallouts() + ').'
                ));
                continue;
            }

            Long startTime = System.currentTimeMillis();
            try {
                Map<String, Object> recordData = recordDataMap.containsKey(recId)
                    ? recordDataMap.get(recId) : new Map<String, Object>();

                IntegrationResult singleResult = executeSingleCallout(
                    endpoint, template, outboundMappings, responseMappings,
                    integrationKey, recId, null, context, recordData, startTime
                );
                results.add(singleResult);
            } catch (Exception ex) {
                IntegrationResult errorResult = IntegrationResult.failure(ex.getMessage());
                errorResult.executionTimeMs = System.currentTimeMillis() - startTime;
                results.add(errorResult);
            }
        }

        flushLogs();
        return results;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SYNCHRONOUS EXECUTION PIPELINE
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Executes the full synchronous integration pipeline for a single invocation.
     */
    private static IntegrationResult executeSynchronous(
        Integration_Endpoint__c endpoint,
        String integrationKey,
        Id recordId,
        Map<String, Object> payload,
        Map<String, String> context,
        Long startTime
    ) {
        // Load related config
        Integration_Request_Template__c template =
            IntegrationConfigService.getRequestTemplate(endpoint.Id);
        List<Integration_Field_Mapping__c> outboundMappings =
            IntegrationConfigService.getFieldMappings(endpoint.Id, 'Outbound');
        List<Integration_Response_Mapping__c> responseMappings =
            IntegrationConfigService.getResponseMappings(endpoint.Id);

        // Query record data if needed
        Map<String, Object> recordData = new Map<String, Object>();
        if (payload != null && !payload.isEmpty()) {
            recordData.putAll(payload);
        } else if (recordId != null && template != null
            && String.isNotBlank(template.Source_Object__c)
            && String.isNotBlank(template.Source_Fields__c)) {
            recordData = queryRecordData(template, recordId);
        }

        return executeSingleCallout(
            endpoint, template, outboundMappings, responseMappings,
            integrationKey, recordId, payload, context, recordData, startTime
        );
    }

    /**
     * @description Core callout execution logic used by both single and bulk paths.
     *              Builds the request, applies auth, makes the callout, maps the response,
     *              handles retry eligibility, and creates log records.
     */
    private static IntegrationResult executeSingleCallout(
        Integration_Endpoint__c endpoint,
        Integration_Request_Template__c template,
        List<Integration_Field_Mapping__c> outboundMappings,
        List<Integration_Response_Mapping__c> responseMappings,
        String integrationKey,
        Id recordId,
        Map<String, Object> payload,
        Map<String, String> context,
        Map<String, Object> recordData,
        Long startTime
    ) {
        IntegrationResult result = new IntegrationResult();
        HttpResponse httpRes = null;
        String requestBody = null;
        String requestUrl = null;

        try {
            // Step A: Apply outbound field mappings to transform source data
            Map<String, Object> mappedData = applyOutboundFieldMappings(recordData, outboundMappings);

            // Step B: Build request body from template or serialized data
            requestBody = buildRequestBody(template, mappedData, payload);

            // Step C: Build the callout request object
            IntegrationCalloutRequest calloutRequest = buildCalloutRequest(
                endpoint, requestBody, context, result.correlationId
            );
            requestUrl = calloutRequest.getFullEndpoint();

            // Step D: Resolve authentication
            Integration_Auth_Profile__c authProfile =
                IntegrationConfigService.getAuthProfile(endpoint);

            // Step E: Make the callout
            if (authProfile != null) {
                httpRes = IntegrationCalloutService.makeCalloutWithAuth(calloutRequest, authProfile);
            } else {
                httpRes = IntegrationCalloutService.makeCallout(calloutRequest);
            }

            // Step F: Populate result from response
            Long executionMs = System.currentTimeMillis() - startTime;
            result.statusCode = httpRes.getStatusCode();
            result.responseBody = httpRes.getBody();
            result.executionTimeMs = executionMs;
            result.responseHeaders = IntegrationCalloutService.extractResponseHeaders(httpRes);

            // Step G: Determine success based on response mappings or default 2xx range
            result.success = ResponseMapper.isSuccessStatusCode(
                httpRes.getStatusCode(), responseMappings
            );

            // Step H: Check for error indicators in the response body
            if (result.success && responseMappings != null && !responseMappings.isEmpty()) {
                String errorFromBody = ResponseMapper.detectError(
                    httpRes.getBody(), responseMappings
                );
                if (String.isNotBlank(errorFromBody)) {
                    result.success = false;
                    result.errorMessage = errorFromBody;
                }
            }

            // Step I: Map response values to Salesforce fields
            if (responseMappings != null && !responseMappings.isEmpty()) {
                try {
                    result.mappedValues = ResponseMapper.mapResponse(
                        httpRes.getBody(), responseMappings
                    );
                } catch (ResponseMapper.IntegrationMappingException mapEx) {
                    System.debug(LoggingLevel.WARN,
                        'IntegrationEngine: Response mapping failed: ' + mapEx.getMessage()
                    );
                    if (result.success) {
                        // Mapping failure on a successful callout is a partial failure
                        result.errorMessage = 'Response mapping failed: ' + mapEx.getMessage();
                    }
                }
            }

            if (!result.success && String.isBlank(result.errorMessage)) {
                result.errorMessage = 'HTTP ' + httpRes.getStatusCode() + ': ' +
                    truncateString(httpRes.getBody(), 500);
            }

            // Step J: Create integration log
            createIntegrationLog(
                endpoint, result.correlationId, requestUrl, requestBody,
                httpRes, executionMs, result.success, recordId, 'Outbound', 0
            );

            // Step K: Handle retry if failed and retry config is present
            if (!result.success) {
                handleRetryEligibility(
                    endpoint, integrationKey, recordId, payload, context,
                    httpRes.getStatusCode(), result.correlationId
                );
            }

        } catch (IntegrationCalloutService.IntegrationCalloutException calloutEx) {
            Long executionMs = System.currentTimeMillis() - startTime;
            result.success = false;
            result.errorMessage = calloutEx.getMessage();
            result.executionTimeMs = executionMs;

            createIntegrationLog(
                endpoint, result.correlationId, requestUrl, requestBody,
                null, executionMs, false, recordId, 'Outbound', 0
            );
            createErrorLog(null, 'Callout_Exception', calloutEx.getMessage(),
                calloutEx.getStackTraceString(), 'High',
                requestBody);

            handleRetryEligibility(
                endpoint, integrationKey, recordId, payload, context,
                0, result.correlationId
            );
        } catch (Exception ex) {
            Long executionMs = System.currentTimeMillis() - startTime;
            result.success = false;
            result.errorMessage = ex.getMessage();
            result.executionTimeMs = executionMs;

            createErrorLog(null, 'Execution_Exception', ex.getMessage(),
                ex.getStackTraceString(), 'High',
                requestBody);
        }

        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // REQUEST BUILDING
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Applies outbound field mappings to transform source record data
     *              into the shape expected by the external API.
     * @param sourceData The raw source record data
     * @param fieldMappings The outbound field mapping configuration
     * @return A new map with keys/values transformed per the mapping rules
     */
    private static Map<String, Object> applyOutboundFieldMappings(
        Map<String, Object> sourceData,
        List<Integration_Field_Mapping__c> fieldMappings
    ) {
        if (fieldMappings == null || fieldMappings.isEmpty()) {
            return sourceData != null ? sourceData : new Map<String, Object>();
        }

        Map<String, Object> mappedData = new Map<String, Object>();

        for (Integration_Field_Mapping__c fm : fieldMappings) {
            if (fm.Active__c != true) {
                continue;
            }

            Object value = null;
            if (sourceData != null && String.isNotBlank(fm.Source_Field__c)) {
                value = sourceData.get(fm.Source_Field__c);
            }

            // Apply default value if source is null
            if (value == null && String.isNotBlank(fm.Default_Value__c)) {
                value = fm.Default_Value__c;
            }

            // Apply transform expression if present
            if (value != null && String.isNotBlank(fm.Transform_Expression__c)) {
                value = applyTransformExpression(value, fm.Transform_Expression__c);
            }

            // Convert data type if specified
            if (value != null && String.isNotBlank(fm.Data_Type__c)) {
                value = ResponseMapper.convertType(value, fm.Data_Type__c);
            }

            // Validate required fields
            if (fm.Is_Required__c == true && value == null) {
                throw new IntegrationEngineException(
                    'Required field mapping "' + fm.Source_Field__c +
                    '" -> "' + fm.Target_Field__c + '" resolved to null.'
                );
            }

            if (String.isNotBlank(fm.Target_Field__c)) {
                mappedData.put(fm.Target_Field__c, value);
            }
        }

        return mappedData;
    }

    /**
     * @description Applies a simple transform expression to a value.
     *              Supports: UPPER, LOWER, TRIM, TO_STRING, TRUNCATE(n).
     * @param value The source value
     * @param expression The transform expression
     * @return The transformed value
     */
    private static Object applyTransformExpression(Object value, String expression) {
        if (value == null || String.isBlank(expression)) {
            return value;
        }

        String expr = expression.trim().toUpperCase();

        if (expr == 'UPPER' && value instanceof String) {
            return ((String) value).toUpperCase();
        } else if (expr == 'LOWER' && value instanceof String) {
            return ((String) value).toLowerCase();
        } else if (expr == 'TRIM' && value instanceof String) {
            return ((String) value).trim();
        } else if (expr == 'TO_STRING') {
            return String.valueOf(value);
        } else if (expr.startsWith('TRUNCATE(') && expr.endsWith(')') && value instanceof String) {
            try {
                Integer maxLength = Integer.valueOf(expr.substringBetween('(', ')').trim());
                String strValue = (String) value;
                return strValue.length() > maxLength ? strValue.substring(0, maxLength) : strValue;
            } catch (Exception e) {
                return value;
            }
        }

        return value;
    }

    /**
     * @description Builds the request body string from template/mappings or direct payload.
     * @param template The request template (may be null)
     * @param mappedData The transformed data map
     * @param payload The original explicit payload (may be null)
     * @return The request body string, or null if no body is needed
     */
    private static String buildRequestBody(
        Integration_Request_Template__c template,
        Map<String, Object> mappedData,
        Map<String, Object> payload
    ) {
        // If an explicit payload was provided and there's a template, resolve placeholders
        if (payload != null && !payload.isEmpty() && template != null
            && String.isNotBlank(template.Body_Template__c)) {
            return PlaceholderResolver.resolve(template.Body_Template__c, payload);
        }

        // If we have a template with body content, resolve with mapped data
        if (template != null && String.isNotBlank(template.Body_Template__c)) {
            return PlaceholderResolver.resolve(template.Body_Template__c, mappedData);
        }

        // If we have mapped data, serialize as JSON
        if (mappedData != null && !mappedData.isEmpty()) {
            return JSON.serialize(mappedData);
        }

        // If only an explicit payload, serialize it
        if (payload != null && !payload.isEmpty()) {
            return JSON.serialize(payload);
        }

        return null;
    }

    /**
     * @description Builds an IntegrationCalloutRequest from endpoint configuration,
     *              applying path variable substitution and query parameters.
     * @param endpoint The endpoint configuration record
     * @param body The request body string
     * @param context Context map for path variable substitution
     * @param correlationId Correlation ID for tracing
     * @return A fully configured IntegrationCalloutRequest
     */
    private static IntegrationCalloutRequest buildCalloutRequest(
        Integration_Endpoint__c endpoint,
        String body,
        Map<String, String> context,
        String correlationId
    ) {
        IntegrationCalloutRequest request = new IntegrationCalloutRequest();

        // Build endpoint URL
        String url = '';
        if (String.isNotBlank(endpoint.Named_Credential__c)) {
            request.namedCredential = endpoint.Named_Credential__c;
            // When using Named Credential, endpoint is just the path portion
            url = buildPath(endpoint.Path__c, context);
        } else {
            String baseUrl = endpoint.Base_URL__c != null ? endpoint.Base_URL__c : '';
            String path = buildPath(endpoint.Path__c, context);

            if (String.isNotBlank(path)) {
                if (baseUrl.endsWith('/') && path.startsWith('/')) {
                    url = baseUrl + path.substring(1);
                } else if (!baseUrl.endsWith('/') && !path.startsWith('/') && String.isNotBlank(baseUrl)) {
                    url = baseUrl + '/' + path;
                } else {
                    url = baseUrl + path;
                }
            } else {
                url = baseUrl;
            }
        }

        request.endpoint = url;
        request.method = endpoint.HTTP_Method__c;
        request.body = body;
        request.contentType = String.isNotBlank(endpoint.Content_Type__c)
            ? endpoint.Content_Type__c : 'application/json';
        request.timeout = endpoint.Timeout__c != null
            ? Integer.valueOf(endpoint.Timeout__c) : 120000;
        request.correlationId = correlationId;
        request.endpointId = endpoint.Id;

        // Apply custom headers from endpoint configuration
        Map<String, String> customHeaders = IntegrationConfigService.parseCustomHeaders(endpoint);
        for (String headerName : customHeaders.keySet()) {
            request.addHeader(headerName, customHeaders.get(headerName));
        }

        // Apply query parameters from endpoint configuration
        Map<String, String> queryParams = IntegrationConfigService.parseQueryParameters(endpoint);
        for (String paramName : queryParams.keySet()) {
            request.addQueryParam(paramName, queryParams.get(paramName));
        }

        // Apply context-based query parameters (keys starting with "param_")
        if (context != null) {
            for (String key : context.keySet()) {
                if (key.startsWith('param_')) {
                    String paramName = key.substring(6); // Remove "param_" prefix
                    request.addQueryParam(paramName, context.get(key));
                } else if (key.startsWith('header_')) {
                    String headerName = key.substring(7); // Remove "header_" prefix
                    request.addHeader(headerName, context.get(key));
                }
            }
        }

        return request;
    }

    /**
     * @description Builds the URL path with context variable substitution.
     *              Replaces {variable} tokens in the path with values from the context map.
     * @param pathTemplate The raw path from endpoint configuration
     * @param context The context map with substitution values
     * @return The resolved path string
     */
    private static String buildPath(String pathTemplate, Map<String, String> context) {
        if (String.isBlank(pathTemplate)) {
            return '';
        }

        String path = pathTemplate;
        if (context != null) {
            for (String key : context.keySet()) {
                String value = context.get(key);
                if (value != null) {
                    path = path.replace('{' + key + '}', EncodingUtil.urlEncode(value, 'UTF-8'));
                }
            }
        }

        return path;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DATA QUERYING
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Queries record data for a single record using the request template config.
     * @param template The request template with Source_Object__c and Source_Fields__c
     * @param recordId The record ID to query
     * @return Map of field API names to values
     */
    private static Map<String, Object> queryRecordData(
        Integration_Request_Template__c template,
        Id recordId
    ) {
        Map<String, Object> recordData = new Map<String, Object>();

        try {
            String soql = DynamicSOQLBuilder.buildQuery(
                template.Source_Object__c,
                template.Source_Fields__c,
                template.SOQL_Filter__c,
                recordId
            );

            List<SObject> records = Database.query(soql);
            if (!records.isEmpty()) {
                recordData.putAll(records[0].getPopulatedFieldsAsMap());
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationEngine: Failed to query record data: ' + ex.getMessage()
            );
        }

        return recordData;
    }

    /**
     * @description Bulk-queries record data for multiple records in a single SOQL call.
     * @param template The request template configuration
     * @param recordIds Set of record IDs to query
     * @return Map of record ID to field-value map
     */
    private static Map<Id, Map<String, Object>> bulkQueryRecordData(
        Integration_Request_Template__c template,
        Set<Id> recordIds
    ) {
        Map<Id, Map<String, Object>> resultMap = new Map<Id, Map<String, Object>>();

        if (recordIds == null || recordIds.isEmpty()) {
            return resultMap;
        }

        try {
            String soql = DynamicSOQLBuilder.buildBulkQuery(
                template.Source_Object__c,
                template.Source_Fields__c,
                recordIds
            );

            List<SObject> records = Database.query(soql);
            for (SObject record : records) {
                resultMap.put(record.Id, record.getPopulatedFieldsAsMap());
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationEngine: Bulk query failed: ' + ex.getMessage()
            );
        }

        return resultMap;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ASYNC EXECUTION
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Enqueues the integration for asynchronous execution via Queueable.
     * @param integrationKey The integration key
     * @param recordId The record ID
     * @param payload The payload map
     * @param context The context map
     * @param correlationId The correlation ID for tracing
     * @return An IntegrationResult indicating async enqueue was successful
     */
    private static IntegrationResult enqueueAsyncExecution(
        String integrationKey,
        Id recordId,
        Map<String, Object> payload,
        Map<String, String> context,
        String correlationId
    ) {
        IntegrationResult result = new IntegrationResult();
        result.correlationId = correlationId;

        try {
            // Check queueable limit
            if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
                return IntegrationResult.failure(
                    'Cannot enqueue async execution: queueable job limit reached (' +
                    Limits.getQueueableJobs() + '/' + Limits.getLimitQueueableJobs() + ').'
                );
            }

            AsyncExecutionQueueable job = new AsyncExecutionQueueable(
                integrationKey, recordId, payload, context, correlationId
            );
            Id jobId = System.enqueueJob(job);

            result.success = true;
            result.errorMessage = '';
            result.statusCode = 202; // Accepted
            result.responseBody = '{"status":"queued","jobId":"' + jobId + '","correlationId":"' + correlationId + '"}';

        } catch (Exception ex) {
            result.success = false;
            result.errorMessage = 'Failed to enqueue async execution: ' + ex.getMessage();
        }

        return result;
    }

    /**
     * @description Queueable inner class for async integration execution.
     */
    public class AsyncExecutionQueueable implements Queueable, Database.AllowsCallouts {
        private String integrationKey;
        private Id recordId;
        private Map<String, Object> payload;
        private Map<String, String> context;
        private String correlationId;

        public AsyncExecutionQueueable(
            String integrationKey,
            Id recordId,
            Map<String, Object> payload,
            Map<String, String> context,
            String correlationId
        ) {
            this.integrationKey = integrationKey;
            this.recordId = recordId;
            this.payload = payload;
            this.context = context;
            this.correlationId = correlationId;
        }

        public void execute(QueueableContext qc) {
            // Force synchronous mode to avoid infinite async chaining
            if (this.context == null) {
                this.context = new Map<String, String>();
            }
            this.context.put('_executionMode', 'Sync');
            this.context.put('_correlationId', this.correlationId);
            this.context.put('_triggeredBy', 'Async_Queueable');

            IntegrationEngine.execute(
                this.integrationKey, this.recordId, this.payload, this.context
            );
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RETRY HANDLING
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Evaluates whether a failed callout is eligible for retry based on the
     *              retry configuration and the HTTP status code received.
     * @param endpoint The endpoint configuration
     * @param integrationKey The integration key for re-execution
     * @param recordId The record ID
     * @param payload The original payload
     * @param context The execution context
     * @param statusCode The HTTP status code from the failed callout
     * @param correlationId The correlation ID
     */
    private static void handleRetryEligibility(
        Integration_Endpoint__c endpoint,
        String integrationKey,
        Id recordId,
        Map<String, Object> payload,
        Map<String, String> context,
        Integer statusCode,
        String correlationId
    ) {
        Integration_Retry_Config__c retryConfig =
            IntegrationConfigService.getRetryConfig(endpoint);

        if (retryConfig == null || retryConfig.Active__c != true) {
            return;
        }

        Integer maxRetries = retryConfig.Max_Retries__c != null
            ? Integer.valueOf(retryConfig.Max_Retries__c) : 3;

        // Parse retry-eligible status codes
        Set<Integer> retryStatusCodes = IntegrationConfigService.parseRetryStatusCodes(retryConfig);

        // Only retry if the status code is in the retry-eligible set
        if (statusCode > 0 && !retryStatusCodes.contains(statusCode)) {
            return;
        }

        // Check if current retry count is within limits
        Integer currentRetryCount = 0;
        if (context != null && context.containsKey('_retryCount')) {
            try {
                currentRetryCount = Integer.valueOf(context.get('_retryCount'));
            } catch (Exception e) {
                currentRetryCount = 0;
            }
        }

        if (currentRetryCount >= maxRetries) {
            // Max retries exceeded -- create dead letter if enabled
            if (retryConfig.Dead_Letter_Enabled__c == true) {
                createErrorLog(null, 'Dead_Letter',
                    'Max retries (' + maxRetries + ') exceeded for ' + integrationKey,
                    null, 'Critical',
                    payload != null ? JSON.serialize(payload) : null);
            }
            return;
        }

        // Calculate retry delay with exponential backoff
        Decimal baseInterval = retryConfig.Retry_Interval__c != null
            ? retryConfig.Retry_Interval__c : 5;
        Decimal multiplier = retryConfig.Backoff_Multiplier__c != null
            ? retryConfig.Backoff_Multiplier__c : 2;
        Decimal maxInterval = retryConfig.Max_Retry_Interval__c != null
            ? retryConfig.Max_Retry_Interval__c : 300;

        Decimal delay = baseInterval * (Math.pow(multiplier.doubleValue(), currentRetryCount));
        if (delay > maxInterval) {
            delay = maxInterval;
        }

        // Enqueue retry (only if we have capacity)
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            Map<String, String> retryContext = context != null
                ? new Map<String, String>(context) : new Map<String, String>();
            retryContext.put('_retryCount', String.valueOf(currentRetryCount + 1));
            retryContext.put('_correlationId', correlationId);
            retryContext.put('_isRetry', 'true');
            retryContext.put('_executionMode', 'Sync');

            AsyncExecutionQueueable retryJob = new AsyncExecutionQueueable(
                integrationKey, recordId, payload, retryContext, correlationId
            );
            System.enqueueJob(retryJob);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LOGGING
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Creates an Integration_Log__c record and adds it to the pending buffer.
     */
    private static void createIntegrationLog(
        Integration_Endpoint__c endpoint,
        String correlationId,
        String requestUrl,
        String requestBody,
        HttpResponse httpRes,
        Long executionMs,
        Boolean isSuccess,
        Id recordId,
        String direction,
        Integer retryCount
    ) {
        try {
            Integration_Log__c logRecord = new Integration_Log__c();
            logRecord.Integration_Endpoint__c = endpoint != null ? endpoint.Id : null;
            logRecord.Integration_Key__c = endpoint != null ? endpoint.Integration_Key__c : null;
            logRecord.Correlation_Id__c = correlationId;
            logRecord.Direction__c = direction;
            logRecord.HTTP_Method__c = endpoint != null ? endpoint.HTTP_Method__c : null;
            logRecord.Request_URL__c = truncateString(requestUrl, 2000);
            logRecord.Request_Body__c = truncateString(requestBody, 131072);
            logRecord.Is_Success__c = isSuccess;
            logRecord.Execution_Time_ms__c = executionMs;
            logRecord.Execution_Start__c = Datetime.now().addSeconds(-1 * (Integer)(executionMs / 1000));
            logRecord.Execution_End__c = Datetime.now();
            logRecord.Record_Id__c = recordId != null ? String.valueOf(recordId) : null;
            logRecord.Source_Object__c = recordId != null ? recordId.getSObjectType().getDescribe().getName() : null;
            logRecord.Retry_Count__c = retryCount;
            logRecord.Is_Retry__c = retryCount > 0;
            logRecord.Execution_Mode__c = endpoint != null ? endpoint.Execution_Mode__c : 'Sync';
            logRecord.Triggered_By__c = UserInfo.getUserId();

            if (httpRes != null) {
                logRecord.Response_Status_Code__c = httpRes.getStatusCode();
                logRecord.Response_Body__c = truncateString(httpRes.getBody(), 131072);

                // Serialize response headers
                Map<String, String> resHeaders = IntegrationCalloutService.extractResponseHeaders(httpRes);
                if (!resHeaders.isEmpty()) {
                    logRecord.Response_Headers__c = truncateString(JSON.serialize(resHeaders), 32768);
                }
            }

            if (!isSuccess && httpRes != null) {
                logRecord.Error_Message__c = truncateString(
                    'HTTP ' + httpRes.getStatusCode() + ': ' + httpRes.getBody(), 32768
                );
            }

            pendingLogs.add(logRecord);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationEngine: Failed to create log record: ' + ex.getMessage()
            );
        }
    }

    /**
     * @description Creates an Integration_Error_Log__c record and adds it to the pending buffer.
     */
    private static void createErrorLog(
        Id integrationLogId,
        String errorType,
        String errorMessage,
        String stackTrace,
        String severity,
        String originalPayload
    ) {
        try {
            Integration_Error_Log__c errorLog = new Integration_Error_Log__c();
            if (integrationLogId != null) {
                errorLog.Integration_Log__c = integrationLogId;
            }
            errorLog.Error_Type__c = errorType;
            errorLog.Error_Message__c = truncateString(errorMessage, 32768);
            errorLog.Stack_Trace__c = truncateString(stackTrace, 32768);
            errorLog.Severity__c = severity;
            errorLog.Original_Payload__c = truncateString(originalPayload, 131072);
            errorLog.Is_Resolved__c = false;
            errorLog.Retry_Eligible__c = true;

            pendingErrorLogs.add(errorLog);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationEngine: Failed to create error log: ' + ex.getMessage()
            );
        }
    }

    /**
     * @description Flushes all pending log records to the database. Error logs that reference
     *              integration logs are linked after the integration logs are inserted.
     *              Uses Database.insert with allOrNone=false to prevent log failures from
     *              disrupting the main execution flow.
     */
    private static void flushLogs() {
        try {
            // Insert integration logs first to get their IDs
            if (!pendingLogs.isEmpty()) {
                Database.insert(pendingLogs, false);
            }

            // Link error logs to integration logs if possible
            if (!pendingErrorLogs.isEmpty()) {
                // For error logs without an integration log reference, try to link to the first log
                Id firstLogId = null;
                for (Integration_Log__c logRec : pendingLogs) {
                    if (logRec.Id != null) {
                        firstLogId = logRec.Id;
                        break;
                    }
                }

                for (Integration_Error_Log__c errorLog : pendingErrorLogs) {
                    if (errorLog.Integration_Log__c == null && firstLogId != null) {
                        errorLog.Integration_Log__c = firstLogId;
                    }
                }

                Database.insert(pendingErrorLogs, false);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'IntegrationEngine: Failed to flush logs: ' + ex.getMessage()
            );
        } finally {
            pendingLogs.clear();
            pendingErrorLogs.clear();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UTILITY
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Safely truncates a string to the given maximum length.
     * @param value The string to truncate
     * @param maxLength The maximum allowed length
     * @return The truncated string, or the original if within limits
     */
    private static String truncateString(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        if (value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    /**
     * @description Custom exception for integration engine errors.
     */
    public class IntegrationEngineException extends Exception {}
}