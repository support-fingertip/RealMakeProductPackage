/**
 * @description Resolves placeholder tokens in template strings using provided data maps.
 *              Supports {{fieldName}} syntax, nested dot-notation paths ({{Account.Name}}),
 *              null-safe resolution, default values ({{field:defaultVal}}), and conditional
 *              inclusion blocks ({{#if field}}...{{/if}}).
 * @author Integration Platform
 */
public class PlaceholderResolver {

    private static final String PLACEHOLDER_PATTERN = '\\{\\{([^}]+)\\}\\}';
    private static final String CONDITIONAL_START_PATTERN = '\\{\\{#if\\s+([^}]+)\\}\\}';
    private static final String CONDITIONAL_END_PATTERN = '\\{\\{/if\\}\\}';
    private static final String DEFAULT_VALUE_SEPARATOR = ':';
    private static final String NULL_REPLACEMENT = '';

    /**
     * @description Resolves all placeholders in the given template using the data map.
     * @param template The template string containing {{placeholder}} tokens
     * @param data Map of field names/paths to their values
     * @return The resolved string with all placeholders replaced
     */
    public static String resolve(String template, Map<String, Object> data) {
        if (String.isBlank(template)) {
            return template;
        }
        if (data == null) {
            data = new Map<String, Object>();
        }

        // Process conditional blocks first
        String processed = resolveConditionalBlocks(template, data);

        // Then resolve individual placeholders
        processed = resolvePlaceholders(processed, data);

        return processed;
    }

    /**
     * @description Resolves all {{fieldName}} placeholders in the template.
     * @param template The template string
     * @param data The data map
     * @return Template with placeholders replaced by values
     */
    private static String resolvePlaceholders(String template, Map<String, Object> data) {
        if (String.isBlank(template)) {
            return template;
        }

        String result = template;
        Pattern placeholderPattern = Pattern.compile(PLACEHOLDER_PATTERN);
        Matcher matcher = placeholderPattern.matcher(result);

        // Collect all matches first to avoid concurrent modification
        List<PlaceholderMatch> matches = new List<PlaceholderMatch>();
        while (matcher.find()) {
            PlaceholderMatch pm = new PlaceholderMatch();
            pm.fullMatch = matcher.group(0);
            pm.expression = matcher.group(1).trim();
            matches.add(pm);
        }

        // Replace each match
        for (PlaceholderMatch pm : matches) {
            String resolvedValue = resolveExpression(pm.expression, data);
            result = result.replace(pm.fullMatch, resolvedValue);
        }

        return result;
    }

    /**
     * @description Resolves a single placeholder expression, handling default values and nested paths.
     * @param expression The expression inside {{ }}, e.g. "Account.Name" or "field:default"
     * @param data The data map
     * @return The resolved value as a string
     */
    private static String resolveExpression(String expression, Map<String, Object> data) {
        String fieldPath = expression;
        String defaultValue = NULL_REPLACEMENT;

        // Check for default value syntax: {{field:defaultValue}}
        // Only split on the first colon to allow colons in default values
        Integer colonIndex = expression.indexOf(DEFAULT_VALUE_SEPARATOR);
        if (colonIndex > 0) {
            fieldPath = expression.substring(0, colonIndex).trim();
            defaultValue = expression.substring(colonIndex + 1).trim();
        }

        Object value = resolveNestedPath(fieldPath, data);

        if (value == null) {
            return defaultValue;
        }

        return convertToString(value);
    }

    /**
     * @description Resolves a dot-notation path against the data map.
     *              Supports paths like "Account.Name" or "data.items.count".
     * @param path Dot-separated field path
     * @param data The data map to resolve against
     * @return The value found at the path, or null if not found
     */
    public static Object resolveNestedPath(String path, Map<String, Object> data) {
        if (String.isBlank(path) || data == null) {
            return null;
        }

        // Try direct match first (handles keys with dots in them)
        if (data.containsKey(path)) {
            return data.get(path);
        }

        // Split by dot for nested resolution
        List<String> pathParts = path.split('\\.');
        Object current = data;

        for (String part : pathParts) {
            if (current == null) {
                return null;
            }

            // Handle array index notation, e.g. "items[0]"
            String fieldName = part;
            Integer arrayIndex = null;

            if (part.contains('[') && part.endsWith(']')) {
                Integer bracketStart = part.indexOf('[');
                fieldName = part.substring(0, bracketStart);
                String indexStr = part.substring(bracketStart + 1, part.length() - 1);
                try {
                    arrayIndex = Integer.valueOf(indexStr);
                } catch (Exception e) {
                    return null;
                }
            }

            if (current instanceof Map<String, Object>) {
                Map<String, Object> currentMap = (Map<String, Object>) current;
                if (!currentMap.containsKey(fieldName)) {
                    return null;
                }
                current = currentMap.get(fieldName);
            } else {
                return null;
            }

            // If an array index was specified, resolve it
            if (arrayIndex != null) {
                if (current instanceof List<Object>) {
                    List<Object> currentList = (List<Object>) current;
                    if (arrayIndex >= 0 && arrayIndex < currentList.size()) {
                        current = currentList.get(arrayIndex);
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
     * @description Processes conditional inclusion blocks: {{#if field}}content{{/if}}.
     *              Content is included only when the field resolves to a truthy value.
     * @param template The template with conditional blocks
     * @param data The data map
     * @return Template with conditional blocks resolved
     */
    private static String resolveConditionalBlocks(String template, Map<String, Object> data) {
        if (String.isBlank(template) || !template.contains('{{#if')) {
            return template;
        }

        String result = template;
        // Process from innermost blocks outward to handle nesting
        Boolean foundBlock = true;
        Integer safetyCounter = 0;
        Integer maxIterations = 100;

        while (foundBlock && safetyCounter < maxIterations) {
            safetyCounter++;
            foundBlock = false;

            Pattern startPattern = Pattern.compile(CONDITIONAL_START_PATTERN);
            Matcher startMatcher = startPattern.matcher(result);

            if (startMatcher.find()) {
                String fullStartTag = startMatcher.group(0);
                String conditionField = startMatcher.group(1).trim();
                Integer blockStart = startMatcher.start();
                Integer contentStart = startMatcher.end();

                // Find the matching {{/if}}
                Integer endIndex = result.indexOf('{{/if}}', contentStart);
                if (endIndex >= 0) {
                    foundBlock = true;
                    String blockContent = result.substring(contentStart, endIndex);
                    Integer blockEnd = endIndex + '{{/if}}'.length();

                    // Evaluate the condition
                    Boolean conditionMet = evaluateCondition(conditionField, data);

                    String replacement = conditionMet ? blockContent : '';
                    result = result.substring(0, blockStart) + replacement + result.substring(blockEnd);
                }
            }
        }

        return result;
    }

    /**
     * @description Evaluates whether a condition field is truthy.
     *              Truthy: non-null, non-empty string, non-zero number, Boolean true.
     * @param fieldPath The field path to evaluate
     * @param data The data map
     * @return True if the field is truthy
     */
    private static Boolean evaluateCondition(String fieldPath, Map<String, Object> data) {
        Object value = resolveNestedPath(fieldPath, data);

        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        if (value instanceof String) {
            return String.isNotBlank((String) value);
        }
        if (value instanceof Integer) {
            return ((Integer) value) != 0;
        }
        if (value instanceof Decimal) {
            return ((Decimal) value) != 0;
        }

        // Any other non-null object is truthy
        return true;
    }

    /**
     * @description Converts an object to its string representation safely.
     * @param value The object to convert
     * @return String representation of the value
     */
    private static String convertToString(Object value) {
        if (value == null) {
            return NULL_REPLACEMENT;
        }
        if (value instanceof String) {
            return (String) value;
        }
        if (value instanceof Boolean) {
            return String.valueOf((Boolean) value);
        }
        if (value instanceof Integer) {
            return String.valueOf((Integer) value);
        }
        if (value instanceof Decimal) {
            return String.valueOf((Decimal) value);
        }
        if (value instanceof Date) {
            return ((Date) value).format();
        }
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
        }
        return String.valueOf(value);
    }

    /**
     * @description Resolves placeholders in a template using SObject field values.
     *              Fields are accessed dynamically from the SObject.
     * @param template The template string
     * @param record The SObject record to pull values from
     * @return Resolved template string
     */
    public static String resolveFromSObject(String template, SObject record) {
        if (String.isBlank(template) || record == null) {
            return template;
        }

        Map<String, Object> data = new Map<String, Object>();
        Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
        for (String fieldName : populatedFields.keySet()) {
            Object fieldValue = populatedFields.get(fieldName);
            // Handle relationship fields (nested SObjects)
            if (fieldValue instanceof SObject) {
                SObject relatedRecord = (SObject) fieldValue;
                Map<String, Object> relatedFields = relatedRecord.getPopulatedFieldsAsMap();
                String relationshipName = fieldName;
                for (String relField : relatedFields.keySet()) {
                    data.put(relationshipName + '.' + relField, relatedFields.get(relField));
                }
            } else {
                data.put(fieldName, fieldValue);
            }
        }

        return resolve(template, data);
    }

    /**
     * @description Inner class to hold placeholder match data during processing.
     */
    private class PlaceholderMatch {
        public String fullMatch;
        public String expression;
    }
}