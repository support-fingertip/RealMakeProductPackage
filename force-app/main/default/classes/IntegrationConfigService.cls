/**
 * @description Service class responsible for loading, caching, and validating integration
 *              configuration metadata. Uses request-scoped static caching to minimize SOQL
 *              queries when multiple integrations execute in the same transaction.
 * @author Integration Platform
 */
public class IntegrationConfigService {

    // Request-scoped caches (static maps reset per transaction)
    private static Map<String, Integration_Endpoint__c> endpointCacheByKey =
        new Map<String, Integration_Endpoint__c>();
    private static Map<Id, Integration_Endpoint__c> endpointCacheById =
        new Map<Id, Integration_Endpoint__c>();
    private static Map<Id, List<Integration_Request_Template__c>> templateCache =
        new Map<Id, List<Integration_Request_Template__c>>();
    private static Map<Id, List<Integration_Response_Mapping__c>> responseMappingCache =
        new Map<Id, List<Integration_Response_Mapping__c>>();
    private static Map<String, List<Integration_Field_Mapping__c>> fieldMappingCache =
        new Map<String, List<Integration_Field_Mapping__c>>();
    private static Map<Id, Integration_Auth_Profile__c> authProfileCache =
        new Map<Id, Integration_Auth_Profile__c>();
    private static Map<Id, Integration_Retry_Config__c> retryConfigCache =
        new Map<Id, Integration_Retry_Config__c>();

    /**
     * @description Retrieves an Integration_Endpoint__c record by its unique integration key,
     *              including all related child records (templates, mappings, auth, retry).
     * @param integrationKey The unique Integration_Key__c value
     * @return The fully loaded endpoint record with related data
     * @throws IntegrationConfigException if the endpoint is not found or inactive
     */
    public static Integration_Endpoint__c getEndpoint(String integrationKey) {
        if (String.isBlank(integrationKey)) {
            throw new IntegrationConfigException('Integration key cannot be blank.');
        }

        String cacheKey = integrationKey.trim().toUpperCase();

        if (endpointCacheByKey.containsKey(cacheKey)) {
            return endpointCacheByKey.get(cacheKey);
        }

        List<Integration_Endpoint__c> endpoints = [
            SELECT Id, Name, Integration_Key__c, Base_URL__c, Path__c,
                   HTTP_Method__c, Named_Credential__c, Content_Type__c,
                   Timeout__c, Active__c, Custom_Headers__c, Query_Parameters__c,
                   Execution_Mode__c, Auth_Profile__c, Retry_Config__c, Category__c,
                   Auth_Profile__r.Id, Auth_Profile__r.Profile_Name__c,
                   Auth_Profile__r.Auth_Type__c, Auth_Profile__r.Auth_Header_Name__c,
                   Auth_Profile__r.Auth_Token_Prefix__c, Auth_Profile__r.API_Key__c,
                   Auth_Profile__r.Username__c, Auth_Profile__r.Password__c,
                   Auth_Profile__r.OAuth_Token_Endpoint__c, Auth_Profile__r.OAuth_Client_Id__c,
                   Auth_Profile__r.OAuth_Client_Secret__c, Auth_Profile__r.OAuth_Scope__c,
                   Auth_Profile__r.OAuth_Grant_Type__c, Auth_Profile__r.HMAC_Secret__c,
                   Auth_Profile__r.HMAC_Algorithm__c, Auth_Profile__r.HMAC_Header_Name__c,
                   Auth_Profile__r.Token_Cache_Duration__c, Auth_Profile__r.Active__c,
                   Retry_Config__r.Id, Retry_Config__r.Config_Name__c,
                   Retry_Config__r.Max_Retries__c, Retry_Config__r.Retry_Interval__c,
                   Retry_Config__r.Backoff_Multiplier__c, Retry_Config__r.Max_Retry_Interval__c,
                   Retry_Config__r.Retry_On_Status_Codes__c, Retry_Config__r.Dead_Letter_Enabled__c,
                   Retry_Config__r.Active__c
            FROM Integration_Endpoint__c
            WHERE Integration_Key__c = :integrationKey
            LIMIT 1
        ];

        if (endpoints.isEmpty()) {
            throw new IntegrationConfigException(
                'No Integration Endpoint found for key: "' + integrationKey + '"'
            );
        }

        Integration_Endpoint__c endpoint = endpoints[0];

        if (endpoint.Active__c != true) {
            throw new IntegrationConfigException(
                'Integration Endpoint "' + integrationKey + '" is inactive.'
            );
        }

        // Populate caches
        endpointCacheByKey.put(cacheKey, endpoint);
        endpointCacheById.put(endpoint.Id, endpoint);

        if (endpoint.Auth_Profile__c != null && endpoint.Auth_Profile__r != null) {
            authProfileCache.put(endpoint.Auth_Profile__c, endpoint.Auth_Profile__r);
        }
        if (endpoint.Retry_Config__c != null && endpoint.Retry_Config__r != null) {
            retryConfigCache.put(endpoint.Retry_Config__c, endpoint.Retry_Config__r);
        }

        return endpoint;
    }

    /**
     * @description Retrieves the active request template for the given endpoint.
     * @param endpointId The Integration_Endpoint__c record ID
     * @return The active Integration_Request_Template__c, or null if none found
     */
    public static Integration_Request_Template__c getRequestTemplate(Id endpointId) {
        if (endpointId == null) {
            return null;
        }

        if (templateCache.containsKey(endpointId)) {
            List<Integration_Request_Template__c> cached = templateCache.get(endpointId);
            return cached.isEmpty() ? null : cached[0];
        }

        List<Integration_Request_Template__c> templates = [
            SELECT Id, Name, Template_Name__c, Body_Template__c,
                   Source_Object__c, Source_Fields__c, SOQL_Filter__c,
                   Transformation_Logic__c, Active__c,
                   Integration_Endpoint__c
            FROM Integration_Request_Template__c
            WHERE Integration_Endpoint__c = :endpointId
              AND Active__c = true
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        templateCache.put(endpointId, templates);
        return templates.isEmpty() ? null : templates[0];
    }

    /**
     * @description Retrieves all active response mappings for the given endpoint, ordered by Order__c.
     * @param endpointId The Integration_Endpoint__c record ID
     * @return List of active Integration_Response_Mapping__c records
     */
    public static List<Integration_Response_Mapping__c> getResponseMappings(Id endpointId) {
        if (endpointId == null) {
            return new List<Integration_Response_Mapping__c>();
        }

        if (responseMappingCache.containsKey(endpointId)) {
            return responseMappingCache.get(endpointId);
        }

        List<Integration_Response_Mapping__c> mappings = [
            SELECT Id, Name, Response_JSON_Path__c, Target_Object__c,
                   Target_Field__c, Data_Type__c, Default_Value__c,
                   Is_Error_Path__c, Success_Status_Codes__c, Active__c, Order__c,
                   Integration_Endpoint__c
            FROM Integration_Response_Mapping__c
            WHERE Integration_Endpoint__c = :endpointId
              AND Active__c = true
            ORDER BY Order__c ASC NULLS LAST
        ];

        responseMappingCache.put(endpointId, mappings);
        return mappings;
    }

    /**
     * @description Retrieves active field mappings for the given endpoint and direction.
     * @param endpointId The Integration_Endpoint__c record ID
     * @param direction The mapping direction ('Inbound', 'Outbound', or 'Both')
     * @return List of active Integration_Field_Mapping__c records
     */
    public static List<Integration_Field_Mapping__c> getFieldMappings(Id endpointId, String direction) {
        if (endpointId == null) {
            return new List<Integration_Field_Mapping__c>();
        }

        String cacheKey = String.valueOf(endpointId) + '_' + (direction != null ? direction : 'ALL');

        if (fieldMappingCache.containsKey(cacheKey)) {
            return fieldMappingCache.get(cacheKey);
        }

        String queryStr = 'SELECT Id, Name, Direction__c, Source_Field__c, Target_Field__c, '
            + 'Target_Object__c, Data_Type__c, Transform_Expression__c, Is_Required__c, '
            + 'Default_Value__c, External_Id_Field__c, Order__c, Active__c, '
            + 'Integration_Endpoint__c '
            + 'FROM Integration_Field_Mapping__c '
            + 'WHERE Integration_Endpoint__c = :endpointId '
            + 'AND Active__c = true ';

        if (String.isNotBlank(direction)) {
            queryStr += 'AND (Direction__c = :direction OR Direction__c = \'Both\') ';
        }

        queryStr += 'ORDER BY Order__c ASC NULLS LAST';

        List<Integration_Field_Mapping__c> mappings = Database.query(queryStr);
        fieldMappingCache.put(cacheKey, mappings);
        return mappings;
    }

    /**
     * @description Retrieves the auth profile for the given endpoint.
     * @param endpoint The Integration_Endpoint__c record with Auth_Profile__c populated
     * @return The Integration_Auth_Profile__c record, or null if not configured
     */
    public static Integration_Auth_Profile__c getAuthProfile(Integration_Endpoint__c endpoint) {
        if (endpoint == null || endpoint.Auth_Profile__c == null) {
            return null;
        }

        if (authProfileCache.containsKey(endpoint.Auth_Profile__c)) {
            return authProfileCache.get(endpoint.Auth_Profile__c);
        }

        // If the endpoint was loaded with getEndpoint(), the related data is already present
        if (endpoint.Auth_Profile__r != null) {
            authProfileCache.put(endpoint.Auth_Profile__c, endpoint.Auth_Profile__r);
            return endpoint.Auth_Profile__r;
        }

        List<Integration_Auth_Profile__c> profiles = [
            SELECT Id, Profile_Name__c, Auth_Type__c, Auth_Header_Name__c,
                   Auth_Token_Prefix__c, API_Key__c, Username__c, Password__c,
                   OAuth_Token_Endpoint__c, OAuth_Client_Id__c, OAuth_Client_Secret__c,
                   OAuth_Scope__c, OAuth_Grant_Type__c, HMAC_Secret__c,
                   HMAC_Algorithm__c, HMAC_Header_Name__c, Token_Cache_Duration__c,
                   Active__c
            FROM Integration_Auth_Profile__c
            WHERE Id = :endpoint.Auth_Profile__c
              AND Active__c = true
            LIMIT 1
        ];

        Integration_Auth_Profile__c profile = profiles.isEmpty() ? null : profiles[0];
        if (profile != null) {
            authProfileCache.put(endpoint.Auth_Profile__c, profile);
        }
        return profile;
    }

    /**
     * @description Retrieves the retry configuration for the given endpoint.
     * @param endpoint The Integration_Endpoint__c record with Retry_Config__c populated
     * @return The Integration_Retry_Config__c record, or null if not configured
     */
    public static Integration_Retry_Config__c getRetryConfig(Integration_Endpoint__c endpoint) {
        if (endpoint == null || endpoint.Retry_Config__c == null) {
            return null;
        }

        if (retryConfigCache.containsKey(endpoint.Retry_Config__c)) {
            return retryConfigCache.get(endpoint.Retry_Config__c);
        }

        if (endpoint.Retry_Config__r != null) {
            retryConfigCache.put(endpoint.Retry_Config__c, endpoint.Retry_Config__r);
            return endpoint.Retry_Config__r;
        }

        List<Integration_Retry_Config__c> configs = [
            SELECT Id, Config_Name__c, Max_Retries__c, Retry_Interval__c,
                   Backoff_Multiplier__c, Max_Retry_Interval__c,
                   Retry_On_Status_Codes__c, Dead_Letter_Enabled__c, Active__c
            FROM Integration_Retry_Config__c
            WHERE Id = :endpoint.Retry_Config__c
              AND Active__c = true
            LIMIT 1
        ];

        Integration_Retry_Config__c config = configs.isEmpty() ? null : configs[0];
        if (config != null) {
            retryConfigCache.put(endpoint.Retry_Config__c, config);
        }
        return config;
    }

    /**
     * @description Retrieves the active version record for an endpoint.
     * @param endpointId The Integration_Endpoint__c record ID
     * @return The active Integration_Version__c record, or null
     */
    public static Integration_Version__c getActiveVersion(Id endpointId) {
        if (endpointId == null) {
            return null;
        }

        List<Integration_Version__c> versions = [
            SELECT Id, Version_Number__c, Is_Active__c, Change_Description__c,
                   Configuration_Snapshot__c, Activated_Date__c, Activated_By__c
            FROM Integration_Version__c
            WHERE Integration_Endpoint__c = :endpointId
              AND Is_Active__c = true
            ORDER BY Version_Number__c DESC
            LIMIT 1
        ];

        return versions.isEmpty() ? null : versions[0];
    }

    /**
     * @description Validates that an endpoint configuration is complete and ready for execution.
     *              Checks required fields, valid HTTP method, valid content type, etc.
     * @param endpoint The endpoint to validate
     * @return List of validation error messages; empty if configuration is valid
     */
    public static List<String> validateConfiguration(Integration_Endpoint__c endpoint) {
        List<String> errors = new List<String>();

        if (endpoint == null) {
            errors.add('Endpoint configuration is null.');
            return errors;
        }

        // Must have either a Named Credential or a Base URL
        if (String.isBlank(endpoint.Named_Credential__c) && String.isBlank(endpoint.Base_URL__c)) {
            errors.add('Either Named_Credential__c or Base_URL__c must be specified.');
        }

        // HTTP Method is required
        if (String.isBlank(endpoint.HTTP_Method__c)) {
            errors.add('HTTP_Method__c is required.');
        } else {
            Set<String> validMethods = new Set<String>{'GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'};
            if (!validMethods.contains(endpoint.HTTP_Method__c.toUpperCase())) {
                errors.add('Invalid HTTP_Method__c: "' + endpoint.HTTP_Method__c + '".');
            }
        }

        // Timeout must be within Salesforce limits
        if (endpoint.Timeout__c != null) {
            if (endpoint.Timeout__c < 1 || endpoint.Timeout__c > 120000) {
                errors.add('Timeout__c must be between 1 and 120000 milliseconds.');
            }
        }

        // Validate auth profile if referenced
        if (endpoint.Auth_Profile__c != null) {
            Integration_Auth_Profile__c authProfile = getAuthProfile(endpoint);
            if (authProfile == null) {
                errors.add('Referenced Auth_Profile__c is not found or inactive.');
            } else if (String.isBlank(authProfile.Auth_Type__c)) {
                errors.add('Auth_Profile__c is missing Auth_Type__c.');
            }
        }

        return errors;
    }

    /**
     * @description Parses the Custom_Headers__c JSON string from an endpoint into a map.
     * @param endpoint The endpoint with Custom_Headers__c populated
     * @return Map of header name to header value
     */
    public static Map<String, String> parseCustomHeaders(Integration_Endpoint__c endpoint) {
        Map<String, String> headers = new Map<String, String>();

        if (endpoint == null || String.isBlank(endpoint.Custom_Headers__c)) {
            return headers;
        }

        try {
            Object parsed = JSON.deserializeUntyped(endpoint.Custom_Headers__c);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> headerMap = (Map<String, Object>) parsed;
                for (String key : headerMap.keySet()) {
                    Object value = headerMap.get(key);
                    headers.put(key, value != null ? String.valueOf(value) : '');
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'IntegrationConfigService: Failed to parse Custom_Headers__c: ' + ex.getMessage()
            );
        }

        return headers;
    }

    /**
     * @description Parses the Query_Parameters__c JSON string from an endpoint into a map.
     * @param endpoint The endpoint with Query_Parameters__c populated
     * @return Map of parameter name to parameter value
     */
    public static Map<String, String> parseQueryParameters(Integration_Endpoint__c endpoint) {
        Map<String, String> queryParams = new Map<String, String>();

        if (endpoint == null || String.isBlank(endpoint.Query_Parameters__c)) {
            return queryParams;
        }

        try {
            Object parsed = JSON.deserializeUntyped(endpoint.Query_Parameters__c);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> paramMap = (Map<String, Object>) parsed;
                for (String key : paramMap.keySet()) {
                    Object value = paramMap.get(key);
                    queryParams.put(key, value != null ? String.valueOf(value) : '');
                }
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'IntegrationConfigService: Failed to parse Query_Parameters__c: ' + ex.getMessage()
            );
        }

        return queryParams;
    }

    /**
     * @description Parses the Retry_On_Status_Codes__c comma-separated string into a set of integers.
     * @param retryConfig The retry configuration record
     * @return Set of HTTP status codes that should trigger a retry
     */
    public static Set<Integer> parseRetryStatusCodes(Integration_Retry_Config__c retryConfig) {
        Set<Integer> statusCodes = new Set<Integer>();

        if (retryConfig == null || String.isBlank(retryConfig.Retry_On_Status_Codes__c)) {
            // Default retry-eligible codes
            statusCodes.addAll(new List<Integer>{ 408, 429, 500, 502, 503, 504 });
            return statusCodes;
        }

        for (String code : retryConfig.Retry_On_Status_Codes__c.split(',')) {
            String trimmedCode = code.trim();
            if (String.isNotBlank(trimmedCode)) {
                try {
                    statusCodes.add(Integer.valueOf(trimmedCode));
                } catch (Exception e) {
                    // Skip non-numeric entries
                }
            }
        }

        return statusCodes;
    }

    /**
     * @description Clears all request-scoped caches. Useful for testing or when
     *              configuration is known to have changed mid-transaction.
     */
    public static void clearCache() {
        endpointCacheByKey.clear();
        endpointCacheById.clear();
        templateCache.clear();
        responseMappingCache.clear();
        fieldMappingCache.clear();
        authProfileCache.clear();
        retryConfigCache.clear();
    }

    /**
     * @description Custom exception for configuration errors.
     */
    public class IntegrationConfigException extends Exception {}
}