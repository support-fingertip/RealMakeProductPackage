/**
 * @description Service class that orchestrates all inbound integration processing logic.
 *              Called by IntegrationRestResource after receiving an HTTP request, this class:
 *              1. Loads endpoint configuration via IntegrationConfigService
 *              2. Validates inbound authentication (API Key, HMAC, Basic Auth, None)
 *              3. Parses the JSON request body into structured data
 *              4. Applies field mappings from Integration_Field_Mapping__c
 *              5. Performs DML operations (upsert/insert) on mapped Salesforce records
 *              6. Returns an InboundResult with success/failure details and record IDs
 *
 *              Designed for governor limit awareness: bulk-processes arrays of records,
 *              uses a single DML statement per Target_Object__c, and limits SOQL queries.
 *
 * @author Integration Platform
 */
public with sharing class InboundIntegrationService {

    /** Maximum number of records that can be processed in a single inbound request */
    private static final Integer MAX_BATCH_SIZE = 2000;

    /** SOQL query limit safety margin -- stop processing before hitting the limit */
    private static final Integer SOQL_SAFETY_MARGIN = 10;

    /**
     * @description Main entry point for processing an inbound integration request.
     * @param integrationKey The Integration_Key__c used to look up the endpoint configuration
     * @param requestBody    Raw JSON request body (single object or array)
     * @param headers        HTTP headers from the inbound request (used for auth validation)
     * @param httpMethod     The HTTP method of the inbound request (POST, PUT, PATCH, etc.)
     * @return InboundResult containing success/failure status, record IDs, and error details
     */
    public static InboundResult processInbound(String integrationKey, String requestBody,
                                                Map<String, String> headers, String httpMethod) {
        InboundResult result = new InboundResult();
        Long startTime = System.currentTimeMillis();

        try {
            // ── Step 1: Validate inputs ──
            if (String.isBlank(integrationKey)) {
                return InboundResult.failure(400, 'Integration key is required.');
            }

            // ── Step 2: Load endpoint configuration ──
            Integration_Endpoint__c endpoint = loadEndpointConfig(integrationKey);
            if (endpoint == null) {
                return InboundResult.failure(404, 'No active integration endpoint found for key: ' + integrationKey);
            }

            // ── Step 3: Validate HTTP method matches configured method ──
            if (String.isNotBlank(endpoint.HTTP_Method__c) && endpoint.HTTP_Method__c != 'ANY') {
                if (!endpoint.HTTP_Method__c.equalsIgnoreCase(httpMethod)) {
                    return InboundResult.failure(405, 'HTTP method ' + httpMethod
                        + ' not allowed. Expected: ' + endpoint.HTTP_Method__c);
                }
            }

            // ── Step 4: Validate inbound authentication ──
            InboundResult authResult = validateAuthentication(endpoint, headers, requestBody);
            if (authResult != null) {
                return authResult;
            }

            // ── Step 5: Parse request body ──
            if (String.isBlank(requestBody)) {
                return InboundResult.failure(400, 'Request body is required.');
            }

            List<Map<String, Object>> parsedRecords = parseRequestBody(requestBody);
            if (parsedRecords == null || parsedRecords.isEmpty()) {
                return InboundResult.failure(400, 'Unable to parse request body or body is empty.');
            }

            // ── Step 6: Enforce batch size limit ──
            if (parsedRecords.size() > MAX_BATCH_SIZE) {
                return InboundResult.failure(400, 'Batch size ' + parsedRecords.size()
                    + ' exceeds maximum allowed: ' + MAX_BATCH_SIZE);
            }

            // ── Step 7: Load field mappings ──
            List<Integration_Field_Mapping__c> fieldMappings = loadFieldMappings(endpoint.Id);
            if (fieldMappings.isEmpty()) {
                return InboundResult.failure(500, 'No active field mappings configured for endpoint: ' + integrationKey);
            }

            // ── Step 8: Determine target object ──
            String targetObject = determineTargetObject(fieldMappings);
            if (String.isBlank(targetObject)) {
                return InboundResult.failure(500, 'No Target_Object__c defined in field mappings for endpoint: ' + integrationKey);
            }

            // ── Step 9: Map inbound data to SObjects ──
            String externalIdField = determineExternalIdField(fieldMappings);
            List<SObject> recordsToUpsert = new List<SObject>();
            List<String> mappingErrors = new List<String>();

            for (Integer i = 0; i < parsedRecords.size(); i++) {
                try {
                    SObject mappedRecord = mapToSObject(targetObject, parsedRecords[i], fieldMappings);
                    if (mappedRecord != null) {
                        recordsToUpsert.add(mappedRecord);
                    }
                } catch (Exception ex) {
                    mappingErrors.add('Record ' + (i + 1) + ': ' + ex.getMessage());
                }
            }

            if (recordsToUpsert.isEmpty()) {
                result = InboundResult.failure(400, 'No records could be mapped from request body.');
                result.errors = mappingErrors;
                return result;
            }

            // ── Step 10: Perform DML ──
            result = performDml(recordsToUpsert, targetObject, externalIdField, mappingErrors);

            // ── Step 11: Log the inbound request ──
            logInboundRequest(endpoint, requestBody, result, startTime);

            return result;

        } catch (Exception ex) {
            result = InboundResult.failure(500, 'Internal server error: ' + ex.getMessage());
            logException(integrationKey, requestBody, ex);
            return result;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Endpoint Configuration
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Loads the Integration_Endpoint__c record for the given key.
     *              Only returns active endpoints. Includes the related Auth Profile.
     * @param integrationKey The unique integration key
     * @return The endpoint configuration record or null if not found
     */
    private static Integration_Endpoint__c loadEndpointConfig(String integrationKey) {
        List<Integration_Endpoint__c> endpoints = [
            SELECT Id, Integration_Key__c, Base_URL__c, Path__c, HTTP_Method__c,
                   Active__c, Content_Type__c, Custom_Headers__c, Execution_Mode__c,
                   Auth_Profile__c,
                   Auth_Profile__r.Auth_Type__c,
                   Auth_Profile__r.API_Key__c,
                   Auth_Profile__r.HMAC_Secret__c,
                   Auth_Profile__r.HMAC_Algorithm__c,
                   Auth_Profile__r.HMAC_Header_Name__c,
                   Auth_Profile__r.Username__c,
                   Auth_Profile__r.Password__c
            FROM Integration_Endpoint__c
            WHERE Integration_Key__c = :integrationKey
              AND Active__c = true
            LIMIT 1
        ];
        return endpoints.isEmpty() ? null : endpoints[0];
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Inbound Authentication Validation
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Validates the inbound request authentication based on the endpoint's
     *              Auth Profile configuration.
     * @param endpoint The integration endpoint record with Auth Profile populated
     * @param headers  The HTTP headers from the inbound request
     * @param requestBody The raw request body (needed for HMAC signature validation)
     * @return An InboundResult with a 401/403 error if authentication fails, or null if valid
     */
    private static InboundResult validateAuthentication(Integration_Endpoint__c endpoint,
                                                         Map<String, String> headers,
                                                         String requestBody) {
        // If no auth profile is configured, skip validation
        if (endpoint.Auth_Profile__c == null) {
            return null;
        }

        String authType = endpoint.Auth_Profile__r.Auth_Type__c;
        if (String.isBlank(authType) || authType == 'None' || authType == 'Named_Credential' || authType == 'OAuth_2_0') {
            // Named_Credential and OAuth_2_0 are outbound-only auth types; skip for inbound
            return null;
        }

        switch on authType {
            when 'API_Key' {
                return validateApiKey(endpoint, headers);
            }
            when 'HMAC' {
                return validateHmac(endpoint, headers, requestBody);
            }
            when 'Basic_Auth' {
                return validateBasicAuth(endpoint, headers);
            }
            when else {
                return null;
            }
        }
    }

    /**
     * @description Validates an inbound API key against the stored key.
     *              Checks both x-api-key header and Authorization header.
     */
    private static InboundResult validateApiKey(Integration_Endpoint__c endpoint,
                                                 Map<String, String> headers) {
        String storedKey = endpoint.Auth_Profile__r.API_Key__c;
        if (String.isBlank(storedKey)) {
            return InboundResult.failure(500, 'API Key not configured on auth profile.');
        }

        // Look for the key in common header locations
        String providedKey = getHeaderCaseInsensitive(headers, 'x-api-key');
        if (String.isBlank(providedKey)) {
            providedKey = getHeaderCaseInsensitive(headers, 'Authorization');
            // Strip "Bearer " or "ApiKey " prefix if present
            if (String.isNotBlank(providedKey)) {
                if (providedKey.startsWithIgnoreCase('Bearer ')) {
                    providedKey = providedKey.substring(7).trim();
                } else if (providedKey.startsWithIgnoreCase('ApiKey ')) {
                    providedKey = providedKey.substring(7).trim();
                }
            }
        }

        if (String.isBlank(providedKey)) {
            return InboundResult.failure(401, 'Missing API key. Provide via x-api-key header.');
        }

        if (!storedKey.equals(providedKey)) {
            return InboundResult.failure(403, 'Invalid API key.');
        }

        return null; // Authentication passed
    }

    /**
     * @description Validates an inbound HMAC signature using HMACSignatureService.
     */
    private static InboundResult validateHmac(Integration_Endpoint__c endpoint,
                                               Map<String, String> headers,
                                               String requestBody) {
        String secret = endpoint.Auth_Profile__r.HMAC_Secret__c;
        if (String.isBlank(secret)) {
            return InboundResult.failure(500, 'HMAC secret not configured on auth profile.');
        }

        String algorithm = String.isNotBlank(endpoint.Auth_Profile__r.HMAC_Algorithm__c)
            ? endpoint.Auth_Profile__r.HMAC_Algorithm__c
            : 'HmacSHA256';

        String headerName = String.isNotBlank(endpoint.Auth_Profile__r.HMAC_Header_Name__c)
            ? endpoint.Auth_Profile__r.HMAC_Header_Name__c
            : 'X-HMAC-Signature';

        String providedSignature = getHeaderCaseInsensitive(headers, headerName);
        if (String.isBlank(providedSignature)) {
            return InboundResult.failure(401, 'Missing HMAC signature in header: ' + headerName);
        }

        // Compute expected signature
        String body = String.isNotBlank(requestBody) ? requestBody : '';
        String expectedSignature = HMACSignatureService.generateSignature(body, secret, algorithm);

        if (!expectedSignature.equals(providedSignature)) {
            return InboundResult.failure(403, 'Invalid HMAC signature.');
        }

        return null; // Authentication passed
    }

    /**
     * @description Validates inbound Basic Authentication credentials.
     *              Decodes the Base64-encoded username:password from the Authorization header.
     */
    private static InboundResult validateBasicAuth(Integration_Endpoint__c endpoint,
                                                    Map<String, String> headers) {
        String storedUsername = endpoint.Auth_Profile__r.Username__c;
        String storedPassword = endpoint.Auth_Profile__r.Password__c;

        if (String.isBlank(storedUsername)) {
            return InboundResult.failure(500, 'Username not configured on auth profile.');
        }
        if (storedPassword == null) {
            storedPassword = '';
        }

        String authHeader = getHeaderCaseInsensitive(headers, 'Authorization');
        if (String.isBlank(authHeader)) {
            return InboundResult.failure(401, 'Missing Authorization header for Basic authentication.');
        }

        if (!authHeader.startsWithIgnoreCase('Basic ')) {
            return InboundResult.failure(401, 'Invalid Authorization header format. Expected: Basic <credentials>.');
        }

        try {
            String encodedCredentials = authHeader.substring(6).trim();
            Blob decodedBlob = EncodingUtil.base64Decode(encodedCredentials);
            String decodedCredentials = decodedBlob.toString();

            Integer colonIndex = decodedCredentials.indexOf(':');
            if (colonIndex < 0) {
                return InboundResult.failure(401, 'Invalid Basic auth credentials format.');
            }

            String providedUsername = decodedCredentials.substring(0, colonIndex);
            String providedPassword = decodedCredentials.substring(colonIndex + 1);

            if (!storedUsername.equals(providedUsername) || !storedPassword.equals(providedPassword)) {
                return InboundResult.failure(403, 'Invalid credentials.');
            }

            return null; // Authentication passed

        } catch (Exception ex) {
            return InboundResult.failure(401, 'Unable to decode Basic auth credentials: ' + ex.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Request Parsing
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Parses the request body into a list of maps. Supports two input formats:
     *              1. JSON -- single object or array (application/json)
     *              2. Form-encoded -- key=value&key2=value2 (application/x-www-form-urlencoded)
     *
     *              The method auto-detects the format: if the body starts with '{' or '['
     *              it is treated as JSON; otherwise it falls back to form-encoded parsing.
     *
     * @param requestBody The raw request body (JSON or form-encoded)
     * @return A list of parsed data maps, one per record to process
     */
    @TestVisible
    private static List<Map<String, Object>> parseRequestBody(String requestBody) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();

        if (String.isBlank(requestBody)) {
            return records;
        }

        String trimmed = requestBody.trim();

        // ── Auto-detect JSON vs form-encoded ──
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
            // Parse as JSON
            try {
                Object parsed = JSON.deserializeUntyped(requestBody);

                if (parsed instanceof List<Object>) {
                    List<Object> items = (List<Object>) parsed;
                    for (Object item : items) {
                        if (item instanceof Map<String, Object>) {
                            records.add((Map<String, Object>) item);
                        }
                    }
                } else if (parsed instanceof Map<String, Object>) {
                    records.add((Map<String, Object>) parsed);
                }
            } catch (JSONException ex) {
                return records;
            }
        } else {
            // Parse as form-encoded: key=value&key2=value2
            Map<String, Object> formData = parseFormEncodedString(trimmed);
            if (!formData.isEmpty()) {
                records.add(formData);
            }
        }

        return records;
    }

    /**
     * @description Parses a form-encoded (application/x-www-form-urlencoded) string into a map.
     *              URL-decodes both keys and values.
     * @param formBody The raw form-encoded string (e.g. name=Acme&industry=Tech)
     * @return A map of decoded key-value pairs
     */
    @TestVisible
    private static Map<String, Object> parseFormEncodedString(String formBody) {
        Map<String, Object> result = new Map<String, Object>();
        if (String.isBlank(formBody)) {
            return result;
        }

        List<String> pairs = formBody.split('&');
        for (String pair : pairs) {
            if (String.isBlank(pair)) {
                continue;
            }
            List<String> kv = pair.split('=', 2);
            String key = EncodingUtil.urlDecode(kv[0].trim(), 'UTF-8');
            String value = kv.size() > 1 ? EncodingUtil.urlDecode(kv[1].trim(), 'UTF-8') : '';
            result.put(key, value);
        }

        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Field Mapping
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Loads active inbound or bidirectional field mappings for the given endpoint.
     * @param endpointId The Integration_Endpoint__c record ID
     * @return List of field mapping records ordered by Order__c
     */
    private static List<Integration_Field_Mapping__c> loadFieldMappings(Id endpointId) {
        return [
            SELECT Id, Source_Field__c, Target_Field__c, Target_Object__c,
                   Data_Type__c, Transform_Expression__c, Is_Required__c,
                   Default_Value__c, External_Id_Field__c, Order__c,
                   Direction__c, Active__c, Conditional_Rule__c
            FROM Integration_Field_Mapping__c
            WHERE Integration_Endpoint__c = :endpointId
              AND Direction__c IN ('Inbound', 'Both')
              AND Active__c = true
            ORDER BY Order__c ASC NULLS LAST
        ];
    }

    /**
     * @description Determines the primary target SObject API name from field mappings.
     *              Uses the Target_Object__c from the first mapping that has one set.
     * @param fieldMappings List of field mapping records
     * @return The SObject API name or null
     */
    private static String determineTargetObject(List<Integration_Field_Mapping__c> fieldMappings) {
        for (Integration_Field_Mapping__c mapping : fieldMappings) {
            if (String.isNotBlank(mapping.Target_Object__c)) {
                return mapping.Target_Object__c;
            }
        }
        return null;
    }

    /**
     * @description Determines the external ID field for upsert from field mappings.
     *              Returns the first non-blank External_Id_Field__c found.
     * @param fieldMappings List of field mapping records
     * @return The external ID field API name or null (signaling insert instead of upsert)
     */
    private static String determineExternalIdField(List<Integration_Field_Mapping__c> fieldMappings) {
        for (Integration_Field_Mapping__c mapping : fieldMappings) {
            if (String.isNotBlank(mapping.External_Id_Field__c)) {
                return mapping.External_Id_Field__c;
            }
        }
        return null;
    }

    /**
     * @description Maps a single parsed JSON data map to an SObject record using field mappings.
     * @param targetObjectName The SObject API name to create an instance of
     * @param data             The parsed JSON data for one record
     * @param fieldMappings    The list of field mappings to apply
     * @return An SObject instance with fields populated, or null if mapping fails validation
     */
    @TestVisible
    private static SObject mapToSObject(String targetObjectName, Map<String, Object> data,
                                         List<Integration_Field_Mapping__c> fieldMappings) {
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(targetObjectName);
        if (sObjectType == null) {
            throw new InboundProcessingException('Invalid Target_Object__c: ' + targetObjectName);
        }

        SObject record = sObjectType.newSObject();
        Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe().fields.getMap();

        for (Integration_Field_Mapping__c mapping : fieldMappings) {
            // Skip if target object differs (supports multi-object mappings in future)
            if (String.isNotBlank(mapping.Target_Object__c)
                && !mapping.Target_Object__c.equalsIgnoreCase(targetObjectName)) {
                continue;
            }

            String sourceField = mapping.Source_Field__c;
            String targetField = mapping.Target_Field__c;

            if (String.isBlank(sourceField) || String.isBlank(targetField)) {
                continue;
            }

            // ── Evaluate conditional rule ──
            if (String.isNotBlank(mapping.Conditional_Rule__c) && !evaluateCondition(mapping.Conditional_Rule__c, data)) {
                continue;
            }

            // ── Extract value from source data (supports dot-notation for nested JSON) ──
            Object rawValue = extractNestedValue(data, sourceField);

            // ── Apply default value if source is null ──
            if (rawValue == null && String.isNotBlank(mapping.Default_Value__c)) {
                rawValue = mapping.Default_Value__c;
            }

            // ── Required field validation ──
            if (rawValue == null && mapping.Is_Required__c == true) {
                throw new InboundProcessingException(
                    'Required field "' + sourceField + '" is missing or null.'
                );
            }

            if (rawValue == null) {
                continue;
            }

            // ── Apply transform expression ──
            if (String.isNotBlank(mapping.Transform_Expression__c)) {
                rawValue = applyTransform(rawValue, mapping.Transform_Expression__c);
            }

            // ── Type conversion and field assignment ──
            try {
                Object convertedValue = convertValue(rawValue, mapping.Data_Type__c, fieldMap.get(targetField.toLowerCase()));
                record.put(targetField, convertedValue);
            } catch (Exception ex) {
                throw new InboundProcessingException(
                    'Failed to set field "' + targetField + '": ' + ex.getMessage()
                );
            }
        }

        return record;
    }

    /**
     * @description Extracts a value from a nested map using dot-notation path.
     *              Example: "address.city" extracts data.get('address').get('city').
     * @param data The data map
     * @param path Dot-separated field path
     * @return The extracted value or null
     */
    @TestVisible
    private static Object extractNestedValue(Map<String, Object> data, String path) {
        if (data == null || String.isBlank(path)) {
            return null;
        }

        List<String> segments = path.split('\\.');
        Object current = data;

        for (String segment : segments) {
            if (current == null) {
                return null;
            }
            if (current instanceof Map<String, Object>) {
                current = ((Map<String, Object>) current).get(segment);
            } else {
                return null;
            }
        }

        return current;
    }

    /**
     * @description Converts a raw value to the appropriate Apex type based on the configured
     *              data type or the target field's schema describe.
     * @param rawValue  The value to convert
     * @param dataType  The configured data type (String, Integer, Decimal, Boolean, Date, Datetime)
     * @param fieldDescribe The schema field token (may be null)
     * @return The converted value
     */
    private static Object convertValue(Object rawValue, String dataType, Schema.SObjectField fieldDescribe) {
        if (rawValue == null) {
            return null;
        }

        String valueStr = String.valueOf(rawValue);
        String effectiveType = String.isNotBlank(dataType) ? dataType.toLowerCase() : '';

        // If no explicit data type configured, attempt to infer from schema
        if (String.isBlank(effectiveType) && fieldDescribe != null) {
            Schema.DisplayType displayType = fieldDescribe.getDescribe().getType();
            switch on displayType {
                when STRING, TEXTAREA, ID, REFERENCE, URL, EMAIL, PHONE, PICKLIST, MULTIPICKLIST {
                    effectiveType = 'string';
                }
                when INTEGER {
                    effectiveType = 'integer';
                }
                when DOUBLE, CURRENCY, PERCENT {
                    effectiveType = 'decimal';
                }
                when BOOLEAN {
                    effectiveType = 'boolean';
                }
                when DATE {
                    effectiveType = 'date';
                }
                when DATETIME {
                    effectiveType = 'datetime';
                }
                when else {
                    effectiveType = 'string';
                }
            }
        }

        switch on effectiveType {
            when 'integer' {
                return rawValue instanceof Integer ? (Integer) rawValue : Integer.valueOf(valueStr);
            }
            when 'decimal', 'double', 'currency' {
                return rawValue instanceof Decimal ? (Decimal) rawValue : Decimal.valueOf(valueStr);
            }
            when 'boolean' {
                return rawValue instanceof Boolean ? (Boolean) rawValue : Boolean.valueOf(valueStr);
            }
            when 'date' {
                return Date.valueOf(valueStr);
            }
            when 'datetime' {
                // Handle ISO 8601 format
                return valueStr.contains('T')
                    ? (Object) Datetime.valueOf(valueStr.replace('T', ' ').replace('Z', ''))
                    : (Object) Datetime.valueOf(valueStr);
            }
            when else {
                return valueStr;
            }
        }
    }

    /**
     * @description Applies a simple transform expression to a value.
     *              Supported transforms: UPPERCASE, LOWERCASE, TRIM, PREFIX:xxx, SUFFIX:xxx.
     * @param value      The value to transform
     * @param expression The transform expression
     * @return The transformed value
     */
    @TestVisible
    private static Object applyTransform(Object value, String expression) {
        if (value == null || String.isBlank(expression)) {
            return value;
        }

        String strValue = String.valueOf(value);
        String expr = expression.trim().toUpperCase();

        if (expr == 'UPPERCASE') {
            return strValue.toUpperCase();
        } else if (expr == 'LOWERCASE') {
            return strValue.toLowerCase();
        } else if (expr == 'TRIM') {
            return strValue.trim();
        } else if (expression.trim().startsWithIgnoreCase('PREFIX:')) {
            String prefix = expression.trim().substring(7);
            return prefix + strValue;
        } else if (expression.trim().startsWithIgnoreCase('SUFFIX:')) {
            String suffix = expression.trim().substring(7);
            return strValue + suffix;
        }

        // No recognized transform -- return value unchanged
        return value;
    }

    /**
     * @description Evaluates a simple conditional rule against the data.
     *              Supports simple equality checks: "fieldName=value" or "fieldName!=value".
     * @param rule The conditional rule string
     * @param data The source data map
     * @return True if the condition is met, false otherwise
     */
    @TestVisible
    private static Boolean evaluateCondition(String rule, Map<String, Object> data) {
        if (String.isBlank(rule) || data == null) {
            return true;
        }

        try {
            // Support != operator
            if (rule.contains('!=')) {
                List<String> parts = rule.split('!=', 2);
                if (parts.size() == 2) {
                    String fieldName = parts[0].trim();
                    String expectedValue = parts[1].trim();
                    Object actualValue = extractNestedValue(data, fieldName);
                    return actualValue == null || !String.valueOf(actualValue).equals(expectedValue);
                }
            }
            // Support = operator
            else if (rule.contains('=')) {
                List<String> parts = rule.split('=', 2);
                if (parts.size() == 2) {
                    String fieldName = parts[0].trim();
                    String expectedValue = parts[1].trim();
                    Object actualValue = extractNestedValue(data, fieldName);
                    return actualValue != null && String.valueOf(actualValue).equals(expectedValue);
                }
            }
        } catch (Exception ex) {
            // If rule evaluation fails, default to including the field
            return true;
        }

        return true;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  DML Operations
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Performs the DML operation (upsert or insert) on the mapped records.
     *              Uses Database methods for partial success handling.
     * @param records         The SObject records to persist
     * @param targetObject    The SObject API name
     * @param externalIdField The external ID field API name (null for insert)
     * @param priorErrors     Any errors from the mapping phase to include in the result
     * @return InboundResult with record IDs and error details
     */
    private static InboundResult performDml(List<SObject> records, String targetObject,
                                             String externalIdField, List<String> priorErrors) {
        List<Id> successIds = new List<Id>();
        List<String> dmlErrors = new List<String>();
        if (priorErrors != null) {
            dmlErrors.addAll(priorErrors);
        }

        Integer processed = 0;
        Integer failed = 0;

        try {
            if (String.isNotBlank(externalIdField)) {
                // ── Upsert using the external ID field ──
                Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(targetObject);
                Schema.SObjectField extIdFieldToken = sObjectType.getDescribe().fields.getMap().get(externalIdField.toLowerCase());

                if (extIdFieldToken == null) {
                    return InboundResult.failure(500, 'External ID field "' + externalIdField
                        + '" not found on ' + targetObject);
                }

                List<Database.UpsertResult> upsertResults = Database.upsert(records, extIdFieldToken, false);

                for (Integer i = 0; i < upsertResults.size(); i++) {
                    Database.UpsertResult ur = upsertResults[i];
                    if (ur.isSuccess()) {
                        successIds.add(ur.getId());
                        processed++;
                    } else {
                        failed++;
                        String errorMsg = 'Record ' + (i + 1) + ': ';
                        for (Database.Error err : ur.getErrors()) {
                            errorMsg += err.getStatusCode() + ' - ' + err.getMessage();
                        }
                        dmlErrors.add(errorMsg);
                    }
                }
            } else {
                // ── Insert ──
                List<Database.SaveResult> saveResults = Database.insert(records, false);

                for (Integer i = 0; i < saveResults.size(); i++) {
                    Database.SaveResult sr = saveResults[i];
                    if (sr.isSuccess()) {
                        successIds.add(sr.getId());
                        processed++;
                    } else {
                        failed++;
                        String errorMsg = 'Record ' + (i + 1) + ': ';
                        for (Database.Error err : sr.getErrors()) {
                            errorMsg += err.getStatusCode() + ' - ' + err.getMessage();
                        }
                        dmlErrors.add(errorMsg);
                    }
                }
            }
        } catch (Exception ex) {
            return InboundResult.failure(500, 'DML operation failed: ' + ex.getMessage());
        }

        // Build the result
        InboundResult result = InboundResult.partial(successIds, processed, failed, dmlErrors);

        // Set appropriate status code
        if (failed == 0 && processed > 0) {
            result.statusCode = 201;
            result.success = true;
        } else if (processed > 0 && failed > 0) {
            result.statusCode = 207; // Multi-Status
            result.success = false;
        } else if (processed == 0) {
            result.statusCode = 400;
            result.success = false;
            result.errorMessage = 'All records failed processing.';
        }

        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Logging
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Logs the inbound integration request and response via IntegrationLogger.
     *              Uses the logInbound(String, String, RestRequest, RestResponse, Long, Boolean) method
     *              when a RestContext is available, otherwise buffers a manual log. Always calls flush()
     *              to persist buffered records. Runs in a try/catch to ensure logging failures never
     *              affect the response.
     * @param endpoint    The endpoint configuration record
     * @param requestBody The raw request body
     * @param result      The processing result
     * @param startTime   Timestamp when processing started (for execution time calculation)
     */
    private static void logInboundRequest(Integration_Endpoint__c endpoint, String requestBody,
                                           InboundResult result, Long startTime) {
        try {
            Long executionTime = System.currentTimeMillis() - startTime;

            // Use IntegrationLogger.logInbound with the actual RestContext objects
            RestRequest restReq = RestContext.request;
            RestResponse restRes = RestContext.response;

            Integer bufferIndex = IntegrationLogger.logInbound(
                endpoint.Integration_Key__c,
                result.correlationId,
                restReq,
                restRes,
                executionTime,
                result.success
            );

            // If there were individual record errors, log them as error entries
            if (!result.errors.isEmpty()) {
                String combinedErrors = String.join(result.errors, '; ');
                IntegrationLogger.logErrorByIndex(
                    bufferIndex,
                    'Partial_Failure',
                    combinedErrors.length() > 32000 ? combinedErrors.substring(0, 32000) : combinedErrors,
                    null,
                    'Medium',
                    requestBody != null && requestBody.length() > 131072
                        ? requestBody.substring(0, 131072) : requestBody
                );
            }

            IntegrationLogger.flush();
        } catch (Exception ex) {
            // Swallow logging exceptions to never affect the caller's response
            System.debug(LoggingLevel.ERROR, 'Failed to log inbound request: ' + ex.getMessage());
        }
    }

    /**
     * @description Logs an unhandled exception to the error log using
     *              IntegrationLogger.logError(Id, String, String, String, String, String).
     *              Always calls flush() to persist. Wrapped in try/catch to never affect the response.
     * @param integrationKey The integration key for context
     * @param requestBody    The raw request body for context
     * @param ex             The exception that occurred
     */
    private static void logException(String integrationKey, String requestBody, Exception ex) {
        try {
            IntegrationLogger.logError(
                null,                               // logId - no parent log record
                'Inbound_Exception',                // errorType
                ex.getMessage(),                    // errorMessage
                ex.getStackTraceString(),           // stackTrace
                'Critical',                         // severity
                requestBody != null && requestBody.length() > 131072
                    ? requestBody.substring(0, 131072) : requestBody  // originalPayload
            );
            IntegrationLogger.flush();
        } catch (Exception logEx) {
            System.debug(LoggingLevel.ERROR, 'Failed to log exception: ' + logEx.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Utility
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Case-insensitive header lookup. HTTP headers are case-insensitive per RFC 7230.
     * @param headers    The map of headers
     * @param headerName The header name to find
     * @return The header value or null if not found
     */
    @TestVisible
    private static String getHeaderCaseInsensitive(Map<String, String> headers, String headerName) {
        if (headers == null || String.isBlank(headerName)) {
            return null;
        }

        // Try exact match first
        if (headers.containsKey(headerName)) {
            return headers.get(headerName);
        }

        // Fall back to case-insensitive search
        String lowerTarget = headerName.toLowerCase();
        for (String key : headers.keySet()) {
            if (key != null && key.toLowerCase() == lowerTarget) {
                return headers.get(key);
            }
        }

        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Custom Exception
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Custom exception for inbound processing failures.
     */
    public class InboundProcessingException extends Exception {}
}