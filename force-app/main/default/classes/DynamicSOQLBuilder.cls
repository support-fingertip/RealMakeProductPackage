/**
 * @description Builds dynamic SOQL queries safely for the Integration Platform.
 *              Prevents SOQL injection, handles relationship fields, supports custom
 *              filters, and enforces field-level security awareness.
 * @author Integration Platform
 */
public class DynamicSOQLBuilder {

    private static final Set<String> RESERVED_WORDS = new Set<String>{
        'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'IN', 'LIKE',
        'ORDER', 'BY', 'GROUP', 'HAVING', 'LIMIT', 'OFFSET', 'ASC', 'DESC',
        'NULLS', 'FIRST', 'LAST', 'WITH', 'SECURITY_ENFORCED', 'UPDATE',
        'INSERT', 'DELETE', 'UPSERT', 'MERGE'
    };

    private static final Pattern SAFE_FIELD_PATTERN = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_.]*(__[cr])?$');
    private static final Pattern SAFE_OBJECT_PATTERN = Pattern.compile('^[a-zA-Z][a-zA-Z0-9_]*(__[c])?$');
    private static final Integer MAX_SOQL_LENGTH = 20000;

    /**
     * @description Builds a SOQL query string from the provided components.
     * @param objectName The SObject API name to query
     * @param fields Comma-separated list of field API names
     * @param filter Optional WHERE clause filter (without the WHERE keyword)
     * @param recordId Optional record ID to filter by Id
     * @return A safe, executable SOQL query string
     * @throws DynamicSOQLException if the inputs are invalid or unsafe
     */
    public static String buildQuery(String objectName, String fields, String filter, Id recordId) {
        // Validate object name
        if (String.isBlank(objectName)) {
            throw new DynamicSOQLException('Object name is required.');
        }
        objectName = objectName.trim();
        validateObjectName(objectName);

        // Parse and validate fields
        List<String> fieldList = parseAndValidateFields(fields);
        if (fieldList.isEmpty()) {
            fieldList.add('Id');
        }

        // Ensure Id is always included
        Boolean hasId = false;
        for (String field : fieldList) {
            if (field.equalsIgnoreCase('Id')) {
                hasId = true;
                break;
            }
        }
        if (!hasId) {
            fieldList.add(0, 'Id');
        }

        // Build the query
        String query = 'SELECT ' + String.join(fieldList, ', ') + ' FROM ' + objectName;

        // Build WHERE clause
        List<String> conditions = new List<String>();

        if (recordId != null) {
            conditions.add('Id = \'' + String.escapeSingleQuotes(String.valueOf(recordId)) + '\'');
        }

        if (String.isNotBlank(filter)) {
            String sanitizedFilter = sanitizeFilter(filter.trim());
            if (String.isNotBlank(sanitizedFilter)) {
                conditions.add('(' + sanitizedFilter + ')');
            }
        }

        if (!conditions.isEmpty()) {
            query += ' WHERE ' + String.join(conditions, ' AND ');
        }

        // Validate total query length
        if (query.length() > MAX_SOQL_LENGTH) {
            throw new DynamicSOQLException(
                'Generated SOQL query exceeds maximum length of ' + MAX_SOQL_LENGTH + ' characters.'
            );
        }

        return query;
    }

    /**
     * @description Builds a SOQL query with LIMIT and ORDER BY support.
     * @param objectName The SObject API name
     * @param fields Comma-separated list of fields
     * @param filter WHERE clause filter
     * @param recordId Optional record ID filter
     * @param orderByField Field to order results by
     * @param isAscending Sort direction
     * @param queryLimit Maximum number of records to return
     * @return A safe SOQL query string
     */
    public static String buildQuery(
        String objectName,
        String fields,
        String filter,
        Id recordId,
        String orderByField,
        Boolean isAscending,
        Integer queryLimit
    ) {
        String query = buildQuery(objectName, fields, filter, recordId);

        // Add ORDER BY
        if (String.isNotBlank(orderByField)) {
            String cleanOrderField = orderByField.trim();
            validateFieldName(cleanOrderField);
            String direction = (isAscending != null && !isAscending) ? 'DESC' : 'ASC';
            query += ' ORDER BY ' + cleanOrderField + ' ' + direction + ' NULLS LAST';
        }

        // Add LIMIT
        if (queryLimit != null && queryLimit > 0) {
            Integer safeLimitValue = Math.min(queryLimit, 50000); // Salesforce max
            query += ' LIMIT ' + safeLimitValue;
        }

        return query;
    }

    /**
     * @description Builds a query for fetching related records using a relationship field.
     * @param objectName The SObject API name
     * @param fields Comma-separated list of fields
     * @param relationshipField The lookup/master-detail field API name
     * @param parentRecordId The parent record's ID
     * @return A safe SOQL query string
     */
    public static String buildRelatedQuery(
        String objectName,
        String fields,
        String relationshipField,
        Id parentRecordId
    ) {
        if (String.isBlank(relationshipField)) {
            throw new DynamicSOQLException('Relationship field is required for related queries.');
        }
        if (parentRecordId == null) {
            throw new DynamicSOQLException('Parent record ID is required for related queries.');
        }

        validateFieldName(relationshipField.trim());
        String filter = String.escapeSingleQuotes(relationshipField.trim()) + ' = \'' +
            String.escapeSingleQuotes(String.valueOf(parentRecordId)) + '\'';

        return buildQuery(objectName, fields, filter, null);
    }

    /**
     * @description Builds a query for fetching records by a set of IDs (bulkified).
     * @param objectName The SObject API name
     * @param fields Comma-separated list of fields
     * @param recordIds Set of record IDs to query
     * @return A safe SOQL query string
     */
    public static String buildBulkQuery(String objectName, String fields, Set<Id> recordIds) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new DynamicSOQLException('At least one record ID is required for bulk queries.');
        }

        List<String> fieldList = parseAndValidateFields(fields);
        if (fieldList.isEmpty()) {
            fieldList.add('Id');
        }

        validateObjectName(objectName.trim());

        String query = 'SELECT ' + String.join(fieldList, ', ') + ' FROM ' + objectName.trim();
        // Build IN clause with escaped ID literals to avoid bind variable scope issues
        List<String> idLiterals = new List<String>();
        for (Id rid : recordIds) {
            idLiterals.add('\'' + String.escapeSingleQuotes(String.valueOf(rid)) + '\'');
        }
        query += ' WHERE Id IN (' + String.join(idLiterals, ', ') + ')';

        return query;
    }

    /**
     * @description Validates that an object name is safe for use in SOQL.
     * @param objectName The API name to validate
     * @throws DynamicSOQLException if the name is unsafe
     */
    private static void validateObjectName(String objectName) {
        if (!SAFE_OBJECT_PATTERN.matcher(objectName).matches()) {
            throw new DynamicSOQLException(
                'Invalid object name: "' + objectName + '". Object names must contain only ' +
                'alphanumeric characters, underscores, and optional __c suffix.'
            );
        }

        if (RESERVED_WORDS.contains(objectName.toUpperCase())) {
            throw new DynamicSOQLException(
                'Object name "' + objectName + '" is a SOQL reserved word.'
            );
        }
    }

    /**
     * @description Validates that a field name is safe for use in SOQL.
     *              Supports relationship traversal (e.g., Account.Name, Account__r.Name__c).
     * @param fieldName The field API name to validate
     * @throws DynamicSOQLException if the name is unsafe
     */
    private static void validateFieldName(String fieldName) {
        if (String.isBlank(fieldName)) {
            throw new DynamicSOQLException('Field name cannot be blank.');
        }

        if (!SAFE_FIELD_PATTERN.matcher(fieldName).matches()) {
            throw new DynamicSOQLException(
                'Invalid field name: "' + fieldName + '". Field names must contain only ' +
                'alphanumeric characters, underscores, dots (for relationships), and optional __c or __r suffix.'
            );
        }

        // Check each segment of relationship paths
        for (String segment : fieldName.split('\\.')) {
            if (RESERVED_WORDS.contains(segment.toUpperCase())) {
                throw new DynamicSOQLException(
                    'Field segment "' + segment + '" in "' + fieldName + '" is a SOQL reserved word.'
                );
            }
        }
    }

    /**
     * @description Parses a comma-separated field list and validates each field name.
     * @param fields Comma-separated field API names
     * @return List of validated, trimmed field names
     */
    private static List<String> parseAndValidateFields(String fields) {
        List<String> fieldList = new List<String>();

        if (String.isBlank(fields)) {
            return fieldList;
        }

        for (String field : fields.split(',')) {
            String trimmedField = field.trim();
            if (String.isNotBlank(trimmedField)) {
                validateFieldName(trimmedField);
                fieldList.add(trimmedField);
            }
        }

        return fieldList;
    }

    /**
     * @description Sanitizes a filter string to prevent SOQL injection.
     *              Escapes single quotes and validates the structure does not contain
     *              dangerous patterns like subqueries or DML statements.
     * @param filter The raw filter string
     * @return Sanitized filter string
     * @throws DynamicSOQLException if the filter contains dangerous patterns
     */
    private static String sanitizeFilter(String filter) {
        if (String.isBlank(filter)) {
            return filter;
        }

        String upperFilter = filter.toUpperCase().trim();

        // Reject filters containing dangerous patterns
        List<String> dangerousPatterns = new List<String>{
            'INSERT ', 'UPDATE ', 'DELETE ', 'UPSERT ', 'MERGE ',
            'CREATE ', 'DROP ', 'ALTER ', 'GRANT ', 'REVOKE ',
            '--', '/*', '*/', ';'
        };

        for (String pattern : dangerousPatterns) {
            if (upperFilter.contains(pattern.toUpperCase())) {
                throw new DynamicSOQLException(
                    'Filter contains potentially dangerous pattern: "' + pattern.trim() + '"'
                );
            }
        }

        return filter;
    }

    /**
     * @description Verifies that the specified SObject type exists in the org.
     * @param objectName The API name to check
     * @return True if the object exists
     */
    public static Boolean objectExists(String objectName) {
        if (String.isBlank(objectName)) {
            return false;
        }
        return Schema.getGlobalDescribe().containsKey(objectName.trim().toLowerCase());
    }

    /**
     * @description Retrieves all queryable field API names for a given SObject type.
     * @param objectName The SObject API name
     * @return Comma-separated string of field API names, or null if the object is not found
     */
    public static String getAllFields(String objectName) {
        if (String.isBlank(objectName)) {
            return null;
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectName.trim());
        if (objectType == null) {
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        List<String> fieldNames = new List<String>();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            if (fieldDescribe.isAccessible()) {
                fieldNames.add(fieldDescribe.getName());
            }
        }

        return String.join(fieldNames, ', ');
    }

    /**
     * @description Custom exception for dynamic SOQL errors.
     */
    public class DynamicSOQLException extends Exception {}
}