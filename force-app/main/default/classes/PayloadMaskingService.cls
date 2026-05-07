/**
 * @description Service class for masking sensitive data in payloads and headers before
 *              logging or external exposure. Preserves JSON structure while replacing
 *              values of sensitive fields with a masked placeholder. Handles both JSON
 *              objects/arrays and simple key-value pair formats.
 *
 *              Governor-limit aware: operates purely on strings/maps without SOQL.
 *
 * @author Integration Platform
 * @date 2026-02-15
 */
public with sharing class PayloadMaskingService {

    // ── Constants ──
    public static final String MASK_PLACEHOLDER = '***MASKED***';

    // ── Default sensitive field patterns (case-insensitive matching) ──
    private static final List<String> DEFAULT_SENSITIVE_FIELDS = new List<String>{
        'password',
        'passwd',
        'secret',
        'client_secret',
        'token',
        'access_token',
        'refresh_token',
        'authorization',
        'api_key',
        'apikey',
        'api-key',
        'credit_card',
        'creditcard',
        'card_number',
        'cardnumber',
        'cvv',
        'cvc',
        'ssn',
        'social_security',
        'private_key',
        'privatekey'
    };

    // ── Default sensitive header names (case-insensitive matching) ──
    private static final Set<String> DEFAULT_SENSITIVE_HEADERS = new Set<String>{
        'authorization',
        'x-api-key',
        'x-auth-token',
        'cookie',
        'set-cookie',
        'proxy-authorization',
        'x-hmac-signature',
        'x-signature'
    };

    // ─────────────────────────────────────────────────────────────────────────
    //  Public API -- Payload Masking
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Masks sensitive fields in the provided payload string. Attempts to
     *              parse as JSON first; falls back to key-value pair masking.
     * @param payload         The raw payload string (JSON or key=value format).
     * @param sensitiveFields Optional list of field names to mask. If null or empty,
     *                        default patterns are used.
     * @return The masked payload string, or the original string if no masking was needed.
     */
    public static String maskPayload(String payload, List<String> sensitiveFields) {
        if (String.isBlank(payload)) {
            return payload;
        }

        List<String> fieldsToMask = (sensitiveFields != null && !sensitiveFields.isEmpty())
            ? sensitiveFields
            : DEFAULT_SENSITIVE_FIELDS;

        // Build a lowercase set for efficient lookup
        Set<String> sensitiveFieldSet = new Set<String>();
        for (String field : fieldsToMask) {
            if (String.isNotBlank(field)) {
                sensitiveFieldSet.add(field.toLowerCase().trim());
            }
        }

        // Attempt JSON masking first
        String trimmedPayload = payload.trim();
        if (trimmedPayload.startsWith('{') || trimmedPayload.startsWith('[')) {
            try {
                Object parsed = JSON.deserializeUntyped(trimmedPayload);
                Object masked = maskJsonValue(parsed, sensitiveFieldSet);
                return JSON.serialize(masked);
            } catch (Exception e) {
                // Not valid JSON -- fall through to key-value masking
                System.debug(LoggingLevel.FINE,
                    'Payload is not valid JSON, attempting key-value masking: ' + e.getMessage()
                );
            }
        }

        // Fallback: key-value pair masking (e.g. query strings, form data)
        return maskKeyValuePairs(payload, sensitiveFieldSet);
    }

    /**
     * @description Masks sensitive fields using the default sensitive field list.
     * @param payload The raw payload string.
     * @return The masked payload string.
     */
    public static String maskPayload(String payload) {
        return maskPayload(payload, null);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Public API -- Header Masking
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Masks values of sensitive headers in the provided map. Returns a new
     *              map with masked values; the original map is not modified.
     * @param headers The header map to mask. Keys are header names, values are header values.
     * @return A new map with sensitive header values replaced by the mask placeholder.
     */
    public static Map<String, String> maskHeaders(Map<String, String> headers) {
        if (headers == null || headers.isEmpty()) {
            return headers;
        }

        Map<String, String> maskedHeaders = new Map<String, String>();

        for (String headerName : headers.keySet()) {
            String headerValue = headers.get(headerName);

            if (isSensitiveHeader(headerName)) {
                maskedHeaders.put(headerName, MASK_PLACEHOLDER);
            } else {
                maskedHeaders.put(headerName, headerValue);
            }
        }

        return maskedHeaders;
    }

    /**
     * @description Masks values of sensitive headers, using a custom set of sensitive
     *              header names in addition to the defaults.
     * @param headers              The header map to mask.
     * @param additionalSensitive  Additional header names to treat as sensitive.
     * @return A new map with sensitive header values masked.
     */
    public static Map<String, String> maskHeaders(Map<String, String> headers, Set<String> additionalSensitive) {
        if (headers == null || headers.isEmpty()) {
            return headers;
        }

        Set<String> customSensitive = new Set<String>();
        if (additionalSensitive != null) {
            for (String h : additionalSensitive) {
                if (String.isNotBlank(h)) {
                    customSensitive.add(h.toLowerCase().trim());
                }
            }
        }

        Map<String, String> maskedHeaders = new Map<String, String>();

        for (String headerName : headers.keySet()) {
            String headerValue = headers.get(headerName);
            String lowerName = headerName != null ? headerName.toLowerCase().trim() : '';

            if (isSensitiveHeader(headerName) || customSensitive.contains(lowerName)) {
                maskedHeaders.put(headerName, MASK_PLACEHOLDER);
            } else {
                maskedHeaders.put(headerName, headerValue);
            }
        }

        return maskedHeaders;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  JSON Masking (recursive)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Recursively traverses a deserialized JSON value and masks sensitive
     *              fields. Handles Maps (JSON objects) and Lists (JSON arrays).
     */
    private static Object maskJsonValue(Object value, Set<String> sensitiveFieldSet) {
        if (value == null) {
            return null;
        }

        if (value instanceof Map<String, Object>) {
            return maskJsonObject((Map<String, Object>) value, sensitiveFieldSet);
        }

        if (value instanceof List<Object>) {
            return maskJsonArray((List<Object>) value, sensitiveFieldSet);
        }

        // Primitive values at the top level are returned as-is
        return value;
    }

    /**
     * @description Masks sensitive keys in a JSON object (Map). Recursively processes
     *              nested objects and arrays.
     */
    private static Map<String, Object> maskJsonObject(Map<String, Object> jsonObj, Set<String> sensitiveFieldSet) {
        Map<String, Object> masked = new Map<String, Object>();

        for (String key : jsonObj.keySet()) {
            Object val = jsonObj.get(key);
            String lowerKey = key.toLowerCase().trim();

            if (isSensitiveField(lowerKey, sensitiveFieldSet)) {
                // Mask the value but preserve the key
                masked.put(key, MASK_PLACEHOLDER);
            } else if (val instanceof Map<String, Object>) {
                masked.put(key, maskJsonObject((Map<String, Object>) val, sensitiveFieldSet));
            } else if (val instanceof List<Object>) {
                masked.put(key, maskJsonArray((List<Object>) val, sensitiveFieldSet));
            } else {
                masked.put(key, val);
            }
        }

        return masked;
    }

    /**
     * @description Iterates a JSON array and recursively masks any sensitive fields
     *              found in nested objects.
     */
    private static List<Object> maskJsonArray(List<Object> jsonArr, Set<String> sensitiveFieldSet) {
        List<Object> masked = new List<Object>();

        for (Object item : jsonArr) {
            masked.add(maskJsonValue(item, sensitiveFieldSet));
        }

        return masked;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Key-Value Pair Masking
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Masks sensitive values in key=value formatted strings (e.g. query
     *              strings, form-encoded bodies). Supports both '&' and newline delimiters.
     */
    private static String maskKeyValuePairs(String payload, Set<String> sensitiveFieldSet) {
        // Determine delimiter
        String delimiter;
        if (payload.contains('&')) {
            delimiter = '&';
        } else if (payload.contains('\n')) {
            delimiter = '\n';
        } else if (payload.contains(';')) {
            delimiter = ';';
        } else {
            // Single key=value or unrecognised format -- attempt single pair
            return maskSinglePair(payload, sensitiveFieldSet);
        }

        List<String> pairs = payload.split(delimiter.replace('\\', '\\\\'));
        List<String> maskedPairs = new List<String>();

        for (String pair : pairs) {
            maskedPairs.add(maskSinglePair(pair, sensitiveFieldSet));
        }

        return String.join(maskedPairs, delimiter);
    }

    /**
     * @description Masks a single key=value pair if the key matches a sensitive field.
     */
    private static String maskSinglePair(String pair, Set<String> sensitiveFieldSet) {
        if (String.isBlank(pair)) {
            return pair;
        }

        Integer equalsIndex = pair.indexOf('=');
        if (equalsIndex < 0) {
            // No equals sign -- check for colon separator (e.g. "key: value")
            Integer colonIndex = pair.indexOf(':');
            if (colonIndex < 0) {
                return pair;
            }
            String key = pair.substring(0, colonIndex).trim();
            if (isSensitiveField(key.toLowerCase(), sensitiveFieldSet)) {
                return key + ': ' + MASK_PLACEHOLDER;
            }
            return pair;
        }

        String key = pair.substring(0, equalsIndex).trim();
        if (isSensitiveField(key.toLowerCase(), sensitiveFieldSet)) {
            return key + '=' + MASK_PLACEHOLDER;
        }
        return pair;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Sensitivity Detection
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Checks if a field name (lowercase) matches any of the sensitive field
     *              patterns. Performs both exact match and substring/contains checks.
     */
    private static Boolean isSensitiveField(String lowerFieldName, Set<String> sensitiveFieldSet) {
        if (String.isBlank(lowerFieldName)) {
            return false;
        }

        // Exact match
        if (sensitiveFieldSet.contains(lowerFieldName)) {
            return true;
        }

        // Substring match: check if any sensitive pattern is contained within the field name
        for (String pattern : sensitiveFieldSet) {
            if (lowerFieldName.contains(pattern)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @description Checks if a header name is in the default sensitive headers set.
     */
    private static Boolean isSensitiveHeader(String headerName) {
        if (String.isBlank(headerName)) {
            return false;
        }
        return DEFAULT_SENSITIVE_HEADERS.contains(headerName.toLowerCase().trim());
    }
}