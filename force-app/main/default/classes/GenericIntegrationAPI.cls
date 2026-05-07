/**
 * @description Generic, dynamic REST API endpoint for all integration source configs.
 *
 * Routes requests based on the source name in the URL path:
 *   POST /services/apexrest/integration/WEBSITE_LEAD
 *   POST /services/apexrest/integration/CP_REGISTRATION
 *
 * The source name maps to an active Integration_Source_Config__c record.
 * All validation, field mapping, type conversion, and lookup resolution
 * is handled by IntegrationFieldMappingEngine (fully metadata-driven).
 *
 * Optional duplicate detection via Enable_Duplicate_Check__c flag on the config,
 * using DuplicationDetectionHelper with Duplication_Configuration__c rules.
 */
@RestResource(urlMapping='/integration/*')
global with sharing class GenericIntegrationAPI {

    @HttpPost
    global static IntegrationResponse handlePost() {
        RestRequest req = RestContext.request;
        IntegrationResponse resp = new IntegrationResponse();
        String sourceName = extractSourceName(req.requestURI);
        String requestBody = req.requestBody != null ? req.requestBody.toString() : '';

        IntegrationLogger.LogEntry logEntry = IntegrationLogger.startLog('Inbound', 'POST', req.requestURI);
        logEntry.integrationSource = sourceName;
        logEntry.request = requestBody;
        logEntry.inputParameters = req.requestURI;

        try {
            // 1. Extract source name from URL path
            if (String.isBlank(sourceName)) {
                resp.status = 'ERROR';
                resp.message = 'Source name is required in the URL path. Example: /services/apexrest/integration/WEBSITE_LEAD';
                RestContext.response.statusCode = 400;
                logEntry.status = 'Error';
                logEntry.httpStatusCode = 400;
                logEntry.errorMessage = resp.message;
                logEntry.response = JSON.serialize(resp);
                return resp;
            }

            // 2. Check config exists and is active
            if (!IntegrationFieldMappingEngine.hasActiveConfig(sourceName)) {
                resp.status = 'NOT_FOUND';
                resp.message = 'No active integration config found for source: ' + sourceName;
                RestContext.response.statusCode = 404;
                logEntry.status = 'Error';
                logEntry.httpStatusCode = 404;
                logEntry.errorMessage = resp.message;
                logEntry.response = JSON.serialize(resp);
                return resp;
            }

            // 3. Parse request body
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(requestBody);

            // 4. Validate payload (required fields + regex rules)
            List<String> errors = IntegrationFieldMappingEngine.validatePayload(sourceName, body);
            if (!errors.isEmpty()) {
                resp.status = 'VALIDATION_ERROR';
                resp.message = String.join(errors, ' ');
                RestContext.response.statusCode = 400;
                logEntry.status = 'Error';
                logEntry.httpStatusCode = 400;
                logEntry.errorMessage = resp.message;
                logEntry.response = JSON.serialize(resp);
                return resp;
            }

            // 5. Map payload to SObject
            SObject record = IntegrationFieldMappingEngine.mapPayload(sourceName, body);

            // 6. Optional duplicate detection
            Integration_Source_Config__c config = getConfig(sourceName);
            if (config.Enable_Duplicate_Check__c) {
                Map<String, Object> fieldValues = record.getPopulatedFieldsAsMap();
                if (!fieldValues.isEmpty()) {
                    List<SObject> duplicates = DuplicationDetectionHelper.findDuplicatesFromPayload(
                        config.Target_Object__c,
                        fieldValues,
                        'Id'
                    );
                    if (!duplicates.isEmpty()) {
                        resp.status = 'DUPLICATE';
                        resp.recordId = duplicates[0].Id;
                        resp.message = 'Duplicate record found. Existing record ID: ' + duplicates[0].Id;
                        RestContext.response.statusCode = 409;
                        logEntry.status = 'Error';
                        logEntry.httpStatusCode = 409;
                        logEntry.errorMessage = resp.message;
                        logEntry.response = JSON.serialize(resp);
                        return resp;
                    }
                }
            }

            // 7. Insert record
            insert record;

            resp.status = 'SUCCESS';
            resp.recordId = record.Id;
            resp.message = 'Record created successfully.';
            RestContext.response.statusCode = 200;
            logEntry.status = 'Success';
            logEntry.httpStatusCode = 200;
            logEntry.response = JSON.serialize(resp);
            return resp;

        } catch (IntegrationFieldMappingEngine.IntegrationMappingException e) {
            resp.status = 'VALIDATION_ERROR';
            resp.message = e.getMessage();
            RestContext.response.statusCode = 400;
            logEntry.status = 'Error';
            logEntry.httpStatusCode = 400;
            logEntry.errorMessage = e.getMessage() + '\n' + e.getStackTraceString();
            logEntry.response = JSON.serialize(resp);
            return resp;
        } catch (Exception e) {
            resp.status = 'SYSTEM_ERROR';
            resp.message = 'An unexpected error occurred: ' + e.getMessage();
            RestContext.response.statusCode = 500;
            logEntry.status = 'Error';
            logEntry.httpStatusCode = 500;
            logEntry.errorMessage = e.getMessage() + '\n' + e.getStackTraceString();
            logEntry.response = JSON.serialize(resp);
            return resp;
        } finally {
            IntegrationLogger.commitLog(logEntry);
        }
    }

    /**
     * @description Extract the source name from the URL path.
     *              /services/apexrest/integration/WEBSITE_LEAD -> WEBSITE_LEAD
     */
    private static String extractSourceName(String requestURI) {
        if (String.isBlank(requestURI)) return null;

        // Remove trailing slash if present
        if (requestURI.endsWith('/')) {
            requestURI = requestURI.substring(0, requestURI.length() - 1);
        }

        // Get the last segment after the final '/'
        Integer lastSlash = requestURI.lastIndexOf('/');
        if (lastSlash < 0 || lastSlash >= requestURI.length() - 1) {
            return null;
        }

        String sourceName = requestURI.substring(lastSlash + 1);

        // Guard against returning 'integration' itself as the source name
        if (sourceName.equalsIgnoreCase('integration')) {
            return null;
        }

        return sourceName;
    }

    /**
     * @description Get the active config record for duplicate check flag and target object.
     */
    private static Integration_Source_Config__c getConfig(String sourceName) {
        List<Integration_Source_Config__c> configs = [
            SELECT Id, Target_Object__c, Enable_Duplicate_Check__c
            FROM Integration_Source_Config__c
            WHERE Source_Name__c = :sourceName AND Is_Active__c = true
            ORDER BY Version__c DESC
            LIMIT 1
        ];
        return configs.isEmpty() ? new Integration_Source_Config__c() : configs[0];
    }

    global class IntegrationResponse {
        public String status;
        public Id recordId;
        public String message;
    }
}