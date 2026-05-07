/**
 * @description Maps JSON response data to Salesforce field values using Integration_Response_Mapping__c
 *              configuration records. Supports JSONPath-like dot notation (e.g., "data.items[0].name"),
 *              type conversion, default values, and error path detection.
 * @author Integration Platform
 */
public class ResponseMapper {

    /**
     * @description Maps response body JSON to a flat key-value map using the provided mapping records.
     * @param responseBody The raw JSON response string
     * @param mappings List of Integration_Response_Mapping__c records defining the mapping rules
     * @return Map of Target_Object__c.Target_Field__c to resolved, typed values
     */
    public static Map<String, Object> mapResponse(String responseBody, List<Integration_Response_Mapping__c> mappings) {
        Map<String, Object> result = new Map<String, Object>();

        if (String.isBlank(responseBody) || mappings == null || mappings.isEmpty()) {
            return result;
        }

        Object parsedResponse;
        try {
            parsedResponse = JSON.deserializeUntyped(responseBody);
        } catch (JSONException jsonEx) {
            throw new IntegrationMappingException(
                'Failed to parse response body as JSON: ' + jsonEx.getMessage()
            );
        }

        // Sort mappings by Order__c to ensure deterministic processing
        List<Integration_Response_Mapping__c> sortedMappings = sortMappingsByOrder(mappings);

        for (Integration_Response_Mapping__c mapping : sortedMappings) {
            if (mapping.Active__c != true) {
                continue;
            }

            try {
                String jsonPath = mapping.Response_JSON_Path__c;
                if (String.isBlank(jsonPath)) {
                    continue;
                }

                Object rawValue = resolveJsonPath(parsedResponse, jsonPath);

                // Apply default value if the path resolved to null
                if (rawValue == null && String.isNotBlank(mapping.Default_Value__c)) {
                    rawValue = mapping.Default_Value__c;
                }

                // Convert to the specified data type
                Object typedValue = convertType(rawValue, mapping.Data_Type__c);

                // Build the result key as TargetObject.TargetField
                String resultKey = buildResultKey(mapping.Target_Object__c, mapping.Target_Field__c);
                result.put(resultKey, typedValue);
            } catch (Exception ex) {
                // Log the mapping error but continue processing other mappings
                System.debug(LoggingLevel.WARN,
                    'ResponseMapper: Failed to map path "' + mapping.Response_JSON_Path__c +
                    '" to "' + mapping.Target_Field__c + '": ' + ex.getMessage()
                );
            }
        }

        return result;
    }

    /**
     * @description Checks the response body for error indicators using error path mappings.
     * @param responseBody The raw JSON response string
     * @param mappings List of mapping records; only those with Is_Error_Path__c = true are used
     * @return An error message if an error path matched, null otherwise
     */
    public static String detectError(String responseBody, List<Integration_Response_Mapping__c> mappings) {
        if (String.isBlank(responseBody) || mappings == null) {
            return null;
        }

        Object parsedResponse;
        try {
            parsedResponse = JSON.deserializeUntyped(responseBody);
        } catch (JSONException jsonEx) {
            return 'Response is not valid JSON: ' + jsonEx.getMessage();
        }

        for (Integration_Response_Mapping__c mapping : mappings) {
            if (mapping.Active__c != true || mapping.Is_Error_Path__c != true) {
                continue;
            }

            Object errorValue = resolveJsonPath(parsedResponse, mapping.Response_JSON_Path__c);
            if (errorValue != null && String.isNotBlank(String.valueOf(errorValue))) {
                return String.valueOf(errorValue);
            }
        }

        return null;
    }

    /**
     * @description Determines if the HTTP status code indicates success based on mapping configuration.
     * @param statusCode The HTTP status code to check
     * @param mappings List of mapping records to extract Success_Status_Codes__c from
     * @return True if the status code is in the success list (defaults to 200-299 range)
     */
    public static Boolean isSuccessStatusCode(Integer statusCode, List<Integration_Response_Mapping__c> mappings) {
        Set<Integer> successCodes = new Set<Integer>();

        // Collect success codes from all mappings that define them
        if (mappings != null) {
            for (Integration_Response_Mapping__c mapping : mappings) {
                if (String.isNotBlank(mapping.Success_Status_Codes__c)) {
                    for (String code : mapping.Success_Status_Codes__c.split(',')) {
                        String trimmedCode = code.trim();
                        if (String.isNotBlank(trimmedCode)) {
                            try {
                                successCodes.add(Integer.valueOf(trimmedCode));
                            } catch (Exception e) {
                                // Skip invalid status code entries
                            }
                        }
                    }
                }
            }
        }

        // Default to 200-299 range if no success codes configured
        if (successCodes.isEmpty()) {
            return statusCode >= 200 && statusCode < 300;
        }

        return successCodes.contains(statusCode);
    }

    /**
     * @description Resolves a JSONPath-like expression against a parsed JSON object.
     *              Supports dot notation and array index access.
     *              Examples: "data.name", "results[0].id", "response.items[2].address.city"
     * @param jsonObject The parsed JSON (Map or List from JSON.deserializeUntyped)
     * @param path The dot-notation path to resolve
     * @return The value found at the path, or null if not found
     */
    public static Object resolveJsonPath(Object jsonObject, String path) {
        if (jsonObject == null || String.isBlank(path)) {
            return null;
        }

        // Handle root-level array access like "[0].field"
        List<String> segments = splitJsonPath(path);
        Object current = jsonObject;

        for (String segment : segments) {
            if (current == null) {
                return null;
            }

            // Check for array index in segment: "items[0]" or just "[0]"
            if (segment.contains('[')) {
                current = resolveArraySegment(current, segment);
            } else {
                // Simple field access on a map
                if (current instanceof Map<String, Object>) {
                    Map<String, Object> currentMap = (Map<String, Object>) current;
                    if (currentMap.containsKey(segment)) {
                        current = currentMap.get(segment);
                    } else {
                        return null;
                    }
                } else {
                    return null;
                }
            }
        }

        return current;
    }

    /**
     * @description Splits a JSON path into segments, respecting dots inside brackets.
     * @param path The JSON path string
     * @return List of path segments
     */
    private static List<String> splitJsonPath(String path) {
        List<String> segments = new List<String>();
        String remaining = path;

        while (String.isNotBlank(remaining)) {
            // Skip leading dots
            if (remaining.startsWith('.')) {
                remaining = remaining.substring(1);
                continue;
            }

            Integer dotIndex = remaining.indexOf('.');
            Integer bracketIndex = remaining.indexOf('[');

            if (dotIndex == -1 && bracketIndex == -1) {
                // No more dots or brackets - rest is the final segment
                segments.add(remaining);
                break;
            }

            if (bracketIndex >= 0 && (dotIndex == -1 || bracketIndex < dotIndex)) {
                if (bracketIndex > 0) {
                    // There's a field name before the bracket
                    String fieldPart = remaining.substring(0, bracketIndex);
                    Integer closeBracket = remaining.indexOf(']', bracketIndex);
                    if (closeBracket >= 0) {
                        String fullSegment = remaining.substring(0, closeBracket + 1);
                        segments.add(fullSegment);
                        remaining = (closeBracket + 1 < remaining.length()) ?
                            remaining.substring(closeBracket + 1) : '';
                    } else {
                        segments.add(remaining);
                        break;
                    }
                } else {
                    // Bracket at position 0: "[0]"
                    Integer closeBracket = remaining.indexOf(']');
                    if (closeBracket >= 0) {
                        segments.add(remaining.substring(0, closeBracket + 1));
                        remaining = (closeBracket + 1 < remaining.length()) ?
                            remaining.substring(closeBracket + 1) : '';
                    } else {
                        segments.add(remaining);
                        break;
                    }
                }
            } else {
                // Dot comes first
                segments.add(remaining.substring(0, dotIndex));
                remaining = remaining.substring(dotIndex + 1);
            }
        }

        return segments;
    }

    /**
     * @description Resolves a path segment containing an array index, e.g. "items[0]" or "[2]".
     * @param current The current JSON object context
     * @param segment The segment containing array notation
     * @return The resolved value or null
     */
    private static Object resolveArraySegment(Object current, String segment) {
        Integer bracketStart = segment.indexOf('[');
        Integer bracketEnd = segment.indexOf(']');

        if (bracketEnd < 0) {
            return null;
        }

        String indexStr = segment.substring(bracketStart + 1, bracketEnd);
        Integer arrayIndex;
        try {
            arrayIndex = Integer.valueOf(indexStr.trim());
        } catch (Exception e) {
            return null;
        }

        Object target = current;

        // If there's a field name before the bracket, resolve it first
        if (bracketStart > 0) {
            String fieldName = segment.substring(0, bracketStart);
            if (target instanceof Map<String, Object>) {
                Map<String, Object> targetMap = (Map<String, Object>) target;
                if (targetMap.containsKey(fieldName)) {
                    target = targetMap.get(fieldName);
                } else {
                    return null;
                }
            } else {
                return null;
            }
        }

        // Now resolve the array index
        if (target instanceof List<Object>) {
            List<Object> targetList = (List<Object>) target;
            if (arrayIndex >= 0 && arrayIndex < targetList.size()) {
                return targetList.get(arrayIndex);
            }
        }

        return null;
    }

    /**
     * @description Converts a raw value to the specified Salesforce data type.
     * @param rawValue The raw value from JSON parsing
     * @param dataType The target data type (String, Integer, Decimal, Boolean, Date, Datetime, Id)
     * @return The converted value, or the raw value if no conversion is needed
     */
    public static Object convertType(Object rawValue, String dataType) {
        if (rawValue == null || String.isBlank(dataType)) {
            return rawValue;
        }

        String normalizedType = dataType.toLowerCase().trim();
        String stringValue = String.valueOf(rawValue);

        try {
            if (normalizedType == 'string' || normalizedType == 'text') {
                return stringValue;
            } else if (normalizedType == 'integer' || normalizedType == 'int') {
                if (rawValue instanceof Integer) {
                    return rawValue;
                }
                return Integer.valueOf(stringValue);
            } else if (normalizedType == 'decimal' || normalizedType == 'double' || normalizedType == 'currency' || normalizedType == 'number') {
                if (rawValue instanceof Decimal) {
                    return rawValue;
                }
                return Decimal.valueOf(stringValue);
            } else if (normalizedType == 'boolean') {
                if (rawValue instanceof Boolean) {
                    return rawValue;
                }
                return Boolean.valueOf(stringValue);
            } else if (normalizedType == 'date') {
                return Date.valueOf(stringValue);
            } else if (normalizedType == 'datetime') {
                // Handle ISO 8601 format
                if (stringValue.contains('T')) {
                    return (Datetime) JSON.deserialize('"' + stringValue + '"', Datetime.class);
                }
                return Datetime.valueOf(stringValue);
            } else if (normalizedType == 'id') {
                return Id.valueOf(stringValue);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN,
                'ResponseMapper: Type conversion failed for value "' + stringValue +
                '" to type "' + dataType + '": ' + ex.getMessage()
            );
            return stringValue;
        }

        // Return as-is for unrecognized types
        return rawValue;
    }

    /**
     * @description Builds a result map key from target object and field names.
     * @param targetObject The target Salesforce object API name
     * @param targetField The target field API name
     * @return Combined key in "Object.Field" format, or just the field name
     */
    private static String buildResultKey(String targetObject, String targetField) {
        if (String.isNotBlank(targetObject) && String.isNotBlank(targetField)) {
            return targetObject + '.' + targetField;
        }
        return String.isNotBlank(targetField) ? targetField : '';
    }

    /**
     * @description Sorts mapping records by Order__c in ascending order. Null orders sort last.
     * @param mappings The list of mapping records to sort
     * @return A new sorted list
     */
    private static List<Integration_Response_Mapping__c> sortMappingsByOrder(
        List<Integration_Response_Mapping__c> mappings
    ) {
        // Create wrapper list for sorting
        List<OrderedMapping> orderedList = new List<OrderedMapping>();
        for (Integration_Response_Mapping__c mapping : mappings) {
            OrderedMapping om = new OrderedMapping();
            om.mapping = mapping;
            om.sortOrder = mapping.Order__c != null ? mapping.Order__c : 999999;
            orderedList.add(om);
        }
        orderedList.sort();

        List<Integration_Response_Mapping__c> sorted = new List<Integration_Response_Mapping__c>();
        for (OrderedMapping om : orderedList) {
            sorted.add(om.mapping);
        }
        return sorted;
    }

    /**
     * @description Creates SObject records from mapped response values.
     * @param mappedValues The mapped key-value pairs (Object.Field -> value)
     * @return Map of object API name to list of SObject records with fields populated
     */
    public static Map<String, List<SObject>> createSObjectsFromMappedValues(
        Map<String, Object> mappedValues
    ) {
        Map<String, List<SObject>> result = new Map<String, List<SObject>>();

        if (mappedValues == null || mappedValues.isEmpty()) {
            return result;
        }

        // Group fields by target object
        Map<String, Map<String, Object>> objectFieldMap = new Map<String, Map<String, Object>>();

        for (String key : mappedValues.keySet()) {
            if (key.contains('.')) {
                List<String> parts = key.split('\\.');
                String objectName = parts[0];
                String fieldName = parts[1];

                if (!objectFieldMap.containsKey(objectName)) {
                    objectFieldMap.put(objectName, new Map<String, Object>());
                }
                objectFieldMap.get(objectName).put(fieldName, mappedValues.get(key));
            }
        }

        // Create SObject instances
        for (String objectName : objectFieldMap.keySet()) {
            try {
                Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
                if (objectType == null) {
                    System.debug(LoggingLevel.WARN,
                        'ResponseMapper: Unknown SObject type "' + objectName + '"'
                    );
                    continue;
                }

                SObject record = objectType.newSObject();
                Map<String, Object> fields = objectFieldMap.get(objectName);

                for (String fieldName : fields.keySet()) {
                    try {
                        record.put(fieldName, fields.get(fieldName));
                    } catch (Exception fieldEx) {
                        System.debug(LoggingLevel.WARN,
                            'ResponseMapper: Failed to set field "' + fieldName +
                            '" on "' + objectName + '": ' + fieldEx.getMessage()
                        );
                    }
                }

                if (!result.containsKey(objectName)) {
                    result.put(objectName, new List<SObject>());
                }
                result.get(objectName).add(record);
            } catch (Exception objEx) {
                System.debug(LoggingLevel.WARN,
                    'ResponseMapper: Failed to create SObject "' + objectName + '": ' + objEx.getMessage()
                );
            }
        }

        return result;
    }

    /**
     * @description Comparable wrapper for sorting mappings by order.
     */
    private class OrderedMapping implements Comparable {
        public Integration_Response_Mapping__c mapping;
        public Decimal sortOrder;

        public Integer compareTo(Object compareTo) {
            OrderedMapping other = (OrderedMapping) compareTo;
            if (this.sortOrder == other.sortOrder) {
                return 0;
            }
            return this.sortOrder > other.sortOrder ? 1 : -1;
        }
    }

    /**
     * @description Custom exception for mapping errors.
     */
    public class IntegrationMappingException extends Exception {}
}