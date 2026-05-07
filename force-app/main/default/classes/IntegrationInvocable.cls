/**
 * @description Flow Invocable Action providing a single, universal action for executing
 *              outbound integrations from Salesforce Flows. Accepts an integration key,
 *              optional record ID, optional JSON payload, and optional context JSON.
 *              Delegates execution to IntegrationEngine and maps the result back to
 *              Flow-compatible output variables.
 *
 *              Designed for bulkification: the execute method receives a list of requests
 *              (one per Flow interview in a bulk trigger context) and returns a corresponding
 *              list of results.
 *
 *              Usage in Flow:
 *              - Action label: "Execute Integration"
 *              - Category: Integration
 *              - Input: Integration Key (required), Record ID, JSON Payload, Context JSON
 *              - Output: Success flag, Status Code, Response Body, Mapped Values, Error, Correlation ID
 *
 * @author Integration Platform
 */
global with sharing class IntegrationInvocable {

    /**
     * @description Invocable method entry point. Iterates through the list of requests,
     *              executes each integration via IntegrationEngine, and returns the mapped results.
     *              Handles errors gracefully so that one failing request does not block others.
     * @param requests List of IntegrationInvocableRequest instances from Flow
     * @return List of IntegrationInvocableResult instances, one per request (positional match)
     */
    @InvocableMethod(label='Execute Integration' description='Executes an outbound integration by key' category='Integration')
    global static List<IntegrationInvocableResult> execute(List<IntegrationInvocableRequest> requests) {
        List<IntegrationInvocableResult> results = new List<IntegrationInvocableResult>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (IntegrationInvocableRequest request : requests) {
            IntegrationInvocableResult invocableResult = new IntegrationInvocableResult();

            try {
                // ── Validate required inputs ──
                if (request == null || String.isBlank(request.integrationKey)) {
                    invocableResult.success = false;
                    invocableResult.statusCode = 400;
                    invocableResult.errorMessage = 'Integration Key is required.';
                    results.add(invocableResult);
                    continue;
                }

                // ── Build payload and context for the engine ──
                Map<String, Object> payload = buildPayloadMap(request);
                Map<String, String> contextMap = buildContextMap(request);
                Id recordId = String.isNotBlank(request.recordId) ? Id.valueOf(request.recordId) : null;

                // ── Execute via IntegrationEngine ──
                IntegrationResult engineResult = IntegrationEngine.execute(
                    request.integrationKey,
                    recordId,
                    payload,
                    contextMap
                );

                // ── Map engine result to invocable result ──
                invocableResult = mapToInvocableResult(engineResult);

            } catch (Exception ex) {
                invocableResult.success = false;
                invocableResult.statusCode = 500;
                invocableResult.errorMessage = 'Integration execution failed: ' + ex.getMessage();
                invocableResult.correlationId = '';

                // Attempt to log the error without blocking the remaining requests
                logInvocableError(request, ex);
            }

            results.add(invocableResult);
        }

        return results;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Context Building
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Builds the payload map from the invocable request's JSON payload.
     *              Attempts to deserialize the payload string into a Map; if it is not valid
     *              JSON or not an object, wraps the raw string under a 'payload' key.
     * @param request The invocable request from Flow
     * @return A payload map for IntegrationEngine.execute(), or null if no payload
     */
    private static Map<String, Object> buildPayloadMap(IntegrationInvocableRequest request) {
        if (String.isBlank(request.payload)) {
            return null;
        }

        try {
            Object payloadObj = JSON.deserializeUntyped(request.payload);
            if (payloadObj instanceof Map<String, Object>) {
                return (Map<String, Object>) payloadObj;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.FINE, 'Payload is not valid JSON object, wrapping as raw string.');
        }

        // Wrap the raw payload string
        return new Map<String, Object>{ 'payload' => request.payload };
    }

    /**
     * @description Builds the context map (String keys and String values) consumed by
     *              IntegrationEngine from the invocable request's context JSON string.
     *              Used for path parameter resolution and other string-based context values.
     * @param request The invocable request from Flow
     * @return A context map for IntegrationEngine.execute()
     */
    private static Map<String, String> buildContextMap(IntegrationInvocableRequest request) {
        Map<String, String> contextMap = new Map<String, String>();

        // Add record ID to context for path parameter resolution
        if (String.isNotBlank(request.recordId)) {
            contextMap.put('recordId', request.recordId);
        }

        // Merge additional context JSON if provided
        if (String.isNotBlank(request.context)) {
            try {
                Object contextObj = JSON.deserializeUntyped(request.context);
                if (contextObj instanceof Map<String, Object>) {
                    Map<String, Object> additionalContext = (Map<String, Object>) contextObj;
                    for (String key : additionalContext.keySet()) {
                        Object val = additionalContext.get(key);
                        contextMap.put(key, val != null ? String.valueOf(val) : null);
                    }
                }
            } catch (Exception ex) {
                // Invalid context JSON -- log and continue without it
                System.debug(LoggingLevel.WARN, 'Invalid context JSON provided: ' + ex.getMessage());
            }
        }

        return contextMap;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Result Mapping
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Maps an IntegrationResult (from IntegrationEngine) to the Flow-compatible
     *              IntegrationInvocableResult. Serializes mappedValues to a JSON string so it
     *              can be consumed by Flow as a text variable.
     * @param engineResult The result returned by IntegrationEngine.execute()
     * @return A new IntegrationInvocableResult populated from the engine result
     */
    private static IntegrationInvocableResult mapToInvocableResult(IntegrationResult engineResult) {
        IntegrationInvocableResult invocableResult = new IntegrationInvocableResult();

        if (engineResult == null) {
            invocableResult.success = false;
            invocableResult.statusCode = 500;
            invocableResult.errorMessage = 'Integration engine returned no result.';
            return invocableResult;
        }

        invocableResult.success = engineResult.success;
        invocableResult.statusCode = engineResult.statusCode;
        invocableResult.responseBody = engineResult.responseBody;
        invocableResult.errorMessage = engineResult.errorMessage;
        invocableResult.correlationId = engineResult.correlationId;

        // Serialize mapped values to JSON for Flow consumption
        if (engineResult.mappedValues != null && !engineResult.mappedValues.isEmpty()) {
            try {
                invocableResult.mappedValues = JSON.serialize(engineResult.mappedValues);
            } catch (Exception ex) {
                invocableResult.mappedValues = '{}';
                System.debug(LoggingLevel.WARN, 'Failed to serialize mapped values: ' + ex.getMessage());
            }
        } else {
            invocableResult.mappedValues = '{}';
        }

        return invocableResult;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Error Logging
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Attempts to log an invocable execution error via IntegrationLogger.
     *              Wrapped in try/catch to ensure logging failures never propagate.
     *              Uses the logError(Id, String, String, String, String, String) signature.
     * @param request The request that caused the error
     * @param ex      The exception that occurred
     */
    private static void logInvocableError(IntegrationInvocableRequest request, Exception ex) {
        try {
            String payload = request != null ? request.payload : null;
            IntegrationLogger.logError(
                null,                               // logId - no parent log record
                'Invocable_Exception',              // errorType
                ex.getMessage(),                    // errorMessage
                ex.getStackTraceString(),           // stackTrace
                'High',                             // severity
                payload                             // originalPayload
            );
            IntegrationLogger.flush();
        } catch (Exception logEx) {
            System.debug(LoggingLevel.ERROR, 'Failed to log invocable error: ' + logEx.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Inner Classes: Request & Result
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Input wrapper for the Flow Invocable Action. Each field is annotated with
     *              @InvocableVariable so it appears in the Flow builder's action configuration.
     */
    global class IntegrationInvocableRequest {

        @InvocableVariable(label='Integration Key' description='The unique key identifying the integration endpoint to execute' required=true)
        global String integrationKey;

        @InvocableVariable(label='Record ID' description='The Salesforce record ID to use as context for the integration')
        global String recordId;

        @InvocableVariable(label='JSON Payload' description='Custom JSON payload to send with the integration request')
        global String payload;

        @InvocableVariable(label='Context JSON' description='Additional context as a JSON string (key-value pairs merged into the execution context)')
        global String context;
    }

    /**
     * @description Output wrapper for the Flow Invocable Action. Each field is annotated with
     *              @InvocableVariable so it can be captured in Flow output variables.
     */
    global class IntegrationInvocableResult {

        @InvocableVariable(label='Success' description='Whether the integration executed successfully')
        global Boolean success;

        @InvocableVariable(label='Status Code' description='HTTP status code from the external service response')
        global Integer statusCode;

        @InvocableVariable(label='Response Body' description='Raw response body from the external service')
        global String responseBody;

        @InvocableVariable(label='Mapped Values' description='JSON-serialized map of response values mapped to Salesforce fields')
        global String mappedValues;

        @InvocableVariable(label='Error Message' description='Error message if the integration failed')
        global String errorMessage;

        @InvocableVariable(label='Correlation ID' description='Unique ID for tracing this execution across logs')
        global String correlationId;

        /**
         * @description Default constructor initializing fields to safe defaults.
         */
        global IntegrationInvocableResult() {
            this.success = false;
            this.statusCode = 0;
            this.responseBody = '';
            this.mappedValues = '{}';
            this.errorMessage = '';
            this.correlationId = '';
        }
    }
}