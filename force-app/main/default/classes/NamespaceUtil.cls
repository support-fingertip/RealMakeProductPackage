/**
 * @description Single source of truth for namespace handling.
 * In a managed package the namespace prefix (e.g. "RealMake__") is automatically applied
 * to every custom object/field API name at runtime. Unpackaged code that hard-codes
 * un-prefixed names must be normalised through this util before passing strings to
 * Schema.getGlobalDescribe(), AggregateResult.get(), or reflective SObject.put().
 */
public with sharing class NamespaceUtil {

    @TestVisible private static String cachedPrefix;

    /**
     * Returns the running namespace prefix including trailing "__", or empty string
     * when the code is executing un-namespaced.
     */
    public static String prefix() {
        if (cachedPrefix == null) {
            String name = NamespaceUtil.class.getName();
            cachedPrefix = name.contains('.') ? name.substringBefore('.') + '__' : '';
        }
        return cachedPrefix;
    }

    /**
     * Strip our namespace prefix from an API name. Returns the input unchanged when
     * the prefix is empty or the input does not start with it.
     */
    public static String strip(String apiName) {
        if (String.isBlank(apiName) || String.isBlank(prefix())) {
            return apiName;
        }
        return apiName.startsWithIgnoreCase(prefix()) ? apiName.substring(prefix().length()) : apiName;
    }

    /**
     * Add the namespace prefix to a custom-object/field API name when missing.
     * Standard fields (no "__") and already-prefixed names are returned unchanged.
     */
    public static String qualify(String apiName) {
        if (String.isBlank(apiName) || String.isBlank(prefix())) {
            return apiName;
        }
        if (!apiName.contains('__')) {
            return apiName;
        }
        return apiName.startsWithIgnoreCase(prefix()) ? apiName : prefix() + apiName;
    }

    /**
     * Schema.getGlobalDescribe().get() that tolerates an un-prefixed lookup string.
     * Returns null when neither the literal nor the qualified name resolves.
     */
    public static Schema.SObjectType describeObject(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        Schema.SObjectType t = Schema.getGlobalDescribe().get(apiName);
        if (t == null && String.isNotBlank(prefix())) {
            t = Schema.getGlobalDescribe().get(prefix() + apiName);
        }
        return t;
    }

    /**
     * Resolve a field on a given SObjectType, tolerating callers that pass either
     * the prefixed or un-prefixed field name.
     */
    public static Schema.SObjectField describeField(Schema.SObjectType sType, String fieldName) {
        if (sType == null || String.isBlank(fieldName)) {
            return null;
        }
        Map<String, Schema.SObjectField> fields = sType.getDescribe().fields.getMap();
        Schema.SObjectField f = fields.get(fieldName);
        if (f == null && String.isNotBlank(prefix())) {
            f = fields.get(prefix() + fieldName);
        }
        return f;
    }
}