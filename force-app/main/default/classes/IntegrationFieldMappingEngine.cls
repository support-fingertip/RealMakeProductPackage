/**
 * @description Generic, metadata-driven field mapping engine for API integrations.
 *
 * Reads mapping rules from Integration_Source_Config__c → Integration_Field_Rule__c
 * → Integration_Lookup_Rule__c and applies them to convert a Map<String, Object>
 * (incoming API payload) into a populated SObject record.
 *
 * Zero hardcoded field references — all mappings are UI-configurable.
 *
 * Usage:
 *   Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(body);
 *   SObject record = IntegrationFieldMappingEngine.mapPayload('CP_REGISTRATION', payload);
 *   insert record;
 */
public with sharing class IntegrationFieldMappingEngine {

    // ════════════════════════════════════════════════════════════
    // PUBLIC API
    // ════════════════════════════════════════════════════════════

    /**
     * @description Map an API payload to a fully populated SObject using the named source config.
     * @param sourceName  The unique Source_Name__c value (e.g., 'CP_REGISTRATION', 'CP_LEAD_SUBMISSION')
     * @param payload     The raw API payload as key-value pairs
     * @return A populated SObject ready for DML (not yet inserted)
     * @throws IntegrationMappingException on validation or lookup failures
     */
    public static SObject mapPayload(String sourceName, Map<String, Object> payload) {
        Integration_Source_Config__c config = getActiveConfig(sourceName);
        List<Integration_Field_Rule__c> rules = getActiveRules(config.Id);

        // Validate required fields
        validateRequiredFields(rules, payload);

        // Create target SObject
        Schema.SObjectType targetType = NamespaceUtil.describeObject(config.Target_Object__c);
        if (targetType == null) {
            throw new IntegrationMappingException('Target object not found: ' + config.Target_Object__c);
        }
        SObject record = targetType.newSObject();

        // Apply each field rule
        for (Integration_Field_Rule__c rule : rules) {
            Object rawValue;

            if (rule.Is_Static__c && String.isNotBlank(rule.Default_Value__c)) {
                // Static value — use Default_Value__c directly, skip payload lookup
                rawValue = rule.Default_Value__c;
            } else {
                rawValue = payload.get(rule.API_Field_Name__c);

                // Apply default if blank
                if (rawValue == null || (rawValue instanceof String && String.isBlank((String) rawValue))) {
                    if (String.isNotBlank(rule.Default_Value__c)) {
                        rawValue = rule.Default_Value__c;
                    } else {
                        continue; // Skip — no value and no default
                    }
                }
            }

            // Convert and set the value (skip nulls to avoid restricted picklist errors)
            Object convertedValue = convertValue(rawValue, rule);
            if (convertedValue != null) {
                Schema.SObjectField sfField = NamespaceUtil.describeField(targetType, rule.SF_Field_API_Name__c);
                if (sfField != null) {
                    record.put(sfField, convertedValue);
                }
            }
        }

        return record;
    }

    /**
     * @description Map an API payload and return as a Map<String, Object> instead of SObject.
     *              Useful when you need to apply additional logic before creating the record.
     * @param sourceName  The unique Source_Name__c value
     * @param payload     The raw API payload
     * @return A Map of SF field API names to converted values
     */
    public static Map<String, Object> mapPayloadToFieldMap(String sourceName, Map<String, Object> payload) {
        Integration_Source_Config__c config = getActiveConfig(sourceName);
        List<Integration_Field_Rule__c> rules = getActiveRules(config.Id);

        validateRequiredFields(rules, payload);

        Schema.SObjectType targetType = NamespaceUtil.describeObject(config.Target_Object__c);
        Map<String, Object> fieldMap = new Map<String, Object>();

        for (Integration_Field_Rule__c rule : rules) {
            Object rawValue;

            if (rule.Is_Static__c && String.isNotBlank(rule.Default_Value__c)) {
                rawValue = rule.Default_Value__c;
            } else {
                rawValue = payload.get(rule.API_Field_Name__c);

                if (rawValue == null || (rawValue instanceof String && String.isBlank((String) rawValue))) {
                    if (String.isNotBlank(rule.Default_Value__c)) {
                        rawValue = rule.Default_Value__c;
                    } else {
                        continue;
                    }
                }
            }

            Object convertedValue = convertValue(rawValue, rule);
            if (convertedValue != null) {
                String fieldKey = rule.SF_Field_API_Name__c;
                if (targetType != null) {
                    Schema.SObjectField sfField = NamespaceUtil.describeField(targetType, fieldKey);
                    if (sfField != null) {
                        fieldKey = sfField.getDescribe().getName();
                    }
                }
                fieldMap.put(fieldKey, convertedValue);
            }
        }

        return fieldMap;
    }

    /**
     * @description Apply a field map onto an existing SObject record.
     *              Merges mapped values into the record without overwriting fields not in the mapping.
     * @param record   The target SObject to populate
     * @param fieldMap The field map from mapPayloadToFieldMap
     */
    public static void applyFieldMap(SObject record, Map<String, Object> fieldMap) {
        Schema.SObjectType sType = record.getSObjectType();
        for (String fieldName : fieldMap.keySet()) {
            Schema.SObjectField sfField = NamespaceUtil.describeField(sType, fieldName);
            if (sfField != null) {
                record.put(sfField, fieldMap.get(fieldName));
            } else {
                record.put(fieldName, fieldMap.get(fieldName));
            }
        }
    }

    /**
     * @description Validate only the required fields from an API payload without mapping.
     * @param sourceName  The unique Source_Name__c value
     * @param payload     The raw API payload
     * @return List of validation error messages (empty if valid)
     */
    public static List<String> validatePayload(String sourceName, Map<String, Object> payload) {
        Integration_Source_Config__c config = getActiveConfig(sourceName);
        List<Integration_Field_Rule__c> rules = getActiveRules(config.Id);

        List<String> errors = new List<String>();
        for (Integration_Field_Rule__c rule : rules) {
            // Skip static rules — they don't depend on the payload
            if (rule.Is_Required__c && !rule.Is_Static__c) {
                Object val = payload.get(rule.API_Field_Name__c);
                if (val == null || (val instanceof String && String.isBlank((String) val))) {
                    String label = String.isNotBlank(rule.API_Field_Label__c) ? rule.API_Field_Label__c : rule.API_Field_Name__c;
                    errors.add(label + ' is required.');
                }
            }
        }

        // Also run regex validations from parent config
        if (String.isNotBlank(config.Validation_Rules_JSON__c)) {
            errors.addAll(runValidationRules(config.Validation_Rules_JSON__c, payload));
        }

        return errors;
    }

    /**
     * @description Check if a mapping config exists and is active for the given source name.
     * @param sourceName The unique Source_Name__c value
     * @return true if an active config exists
     */
    public static Boolean hasActiveConfig(String sourceName) {
        List<Integration_Source_Config__c> configs = [
            SELECT Id FROM Integration_Source_Config__c
            WHERE Source_Name__c = :sourceName AND Is_Active__c = true
            LIMIT 1
        ];
        return !configs.isEmpty();
    }

    // ════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ════════════════════════════════════════════════════════════

    private static Integration_Source_Config__c getActiveConfig(String sourceName) {
        List<Integration_Source_Config__c> configs = [
            SELECT Id, Source_Name__c, Target_Object__c, Validation_Rules_JSON__c, Version__c
            FROM Integration_Source_Config__c
            WHERE Source_Name__c = :sourceName AND Is_Active__c = true
            ORDER BY Version__c DESC
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            throw new IntegrationMappingException(
                'No active integration mapping config found for source: ' + sourceName
            );
        }

        return configs[0];
    }

    private static List<Integration_Field_Rule__c> getActiveRules(Id configId) {
        return [
            SELECT Id, API_Field_Name__c, API_Field_Label__c, SF_Field_API_Name__c,
                   Is_Required__c, Default_Value__c, Data_Type__c, Transform_Expression__c,
                   Is_Active__c, Is_Static__c, Sequence__c,
                   (SELECT Id, Lookup_Object__c, Match_Field__c, Return_Field__c,
                           Fail_On_No_Match__c, Additional_Filter__c
                    FROM Integration_Lookup_Rules__r
                    LIMIT 1)
            FROM Integration_Field_Rule__c
            WHERE Integration_Source_Config__c = :configId
            AND Is_Active__c = true
            ORDER BY Sequence__c ASC NULLS LAST
        ];
    }

    private static void validateRequiredFields(List<Integration_Field_Rule__c> rules, Map<String, Object> payload) {
        List<String> errors = new List<String>();

        for (Integration_Field_Rule__c rule : rules) {
            // Skip static rules — they don't depend on the payload
            if (rule.Is_Required__c && !rule.Is_Static__c) {
                Object val = payload.get(rule.API_Field_Name__c);
                if (val == null || (val instanceof String && String.isBlank((String) val))) {
                    String label = String.isNotBlank(rule.API_Field_Label__c) ? rule.API_Field_Label__c : rule.API_Field_Name__c;
                    errors.add(label + ' is required.');
                }
            }
        }

        if (!errors.isEmpty()) {
            throw new IntegrationMappingException('Validation failed: ' + String.join(errors, ' '));
        }
    }

    private static List<String> runValidationRules(String rulesJson, Map<String, Object> payload) {
        List<String> errors = new List<String>();

        try {
            List<Object> rules = (List<Object>) JSON.deserializeUntyped(rulesJson);
            for (Object ruleObj : rules) {
                Map<String, Object> rule = (Map<String, Object>) ruleObj;
                String fieldName = (String) rule.get('field');
                String regex = (String) rule.get('regex');
                String message = (String) rule.get('message');

                Object val = payload.get(fieldName);
                if (val != null && val instanceof String && String.isNotBlank((String) val)) {
                    if (!Pattern.matches(regex, (String) val)) {
                        errors.add(String.isNotBlank(message) ? message : fieldName + ' has invalid format.');
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error parsing validation rules JSON: ' + e.getMessage());
        }

        return errors;
    }

    private static Object convertValue(Object rawValue, Integration_Field_Rule__c rule) {
        String stringValue = String.valueOf(rawValue);

        // Apply transformation if configured
        stringValue = applyTransform(stringValue, rule.Transform_Expression__c);

        String dataType = rule.Data_Type__c;
        if (String.isBlank(dataType)) {
            dataType = 'Text';
        }

        switch on dataType {
            when 'Text', 'Email', 'Phone', 'Picklist' {
                return stringValue;
            }
            when 'Number', 'Currency' {
                try {
                    return Decimal.valueOf(stringValue);
                } catch (Exception e) {
                    throw new IntegrationMappingException(
                        'Cannot convert "' + stringValue + '" to number for field: ' + rule.API_Field_Name__c
                    );
                }
            }
            when 'Boolean' {
                return Boolean.valueOf(stringValue);
            }
            when 'Date' {
                try {
                    return Date.valueOf(stringValue);
                } catch (Exception e) {
                    throw new IntegrationMappingException(
                        'Cannot convert "' + stringValue + '" to date for field: ' + rule.API_Field_Name__c
                            + '. Expected format: YYYY-MM-DD'
                    );
                }
            }
            when 'DateTime' {
                try {
                    return DateTime.valueOf(stringValue);
                } catch (Exception e) {
                    throw new IntegrationMappingException(
                        'Cannot convert "' + stringValue + '" to datetime for field: ' + rule.API_Field_Name__c
                    );
                }
            }
            when 'Lookup' {
                return resolveLookup(rule, stringValue);
            }
            when else {
                return stringValue;
            }
        }
    }

    private static String applyTransform(String value, String expression) {
        if (String.isBlank(expression) || String.isBlank(value)) {
            return value;
        }

        String expr = expression.trim();

        if (expr == 'UPPERCASE') {
            return value.toUpperCase();
        } else if (expr == 'LOWERCASE') {
            return value.toLowerCase();
        } else if (expr == 'TRIM') {
            return value.trim();
        } else if (expr.startsWith('PREFIX:')) {
            return expr.substringAfter('PREFIX:') + value;
        } else if (expr.startsWith('SUFFIX:')) {
            return value + expr.substringAfter('SUFFIX:');
        }

        return value;
    }

    private static Id resolveLookup(Integration_Field_Rule__c rule, String matchValue) {
        if (rule.Integration_Lookup_Rules__r == null || rule.Integration_Lookup_Rules__r.isEmpty()) {
            throw new IntegrationMappingException(
                'Lookup data type configured for "' + rule.API_Field_Name__c
                + '" but no Integration Lookup Rule defined.'
            );
        }

        Integration_Lookup_Rule__c lookupRule = rule.Integration_Lookup_Rules__r[0];

        // Build dynamic SOQL
        String query = 'SELECT ' + String.escapeSingleQuotes(lookupRule.Return_Field__c)
            + ' FROM ' + String.escapeSingleQuotes(lookupRule.Lookup_Object__c)
            + ' WHERE ' + String.escapeSingleQuotes(lookupRule.Match_Field__c)
            + ' = :matchValue';

        if (String.isNotBlank(lookupRule.Additional_Filter__c)) {
            query += ' AND ' + lookupRule.Additional_Filter__c;
        }

        query += ' LIMIT 1';

        List<SObject> results = Database.query(query);

        if (results.isEmpty()) {
            if (lookupRule.Fail_On_No_Match__c) {
                throw new IntegrationMappingException(
                    'Lookup failed: no ' + lookupRule.Lookup_Object__c
                    + ' found where ' + lookupRule.Match_Field__c + ' = "' + matchValue + '"'
                );
            }
            return null;
        }

        return (Id) results[0].get(lookupRule.Return_Field__c);
    }

    // ════════════════════════════════════════════════════════════
    // CUSTOM EXCEPTION
    // ════════════════════════════════════════════════════════════

    public class IntegrationMappingException extends Exception {}
}