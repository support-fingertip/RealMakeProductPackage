public with sharing class DuplicationDetectionHelper {

    // ===============================================================
    // MAIN ENTRY
    // ===============================================================
    public static Map<Id, List<String>> checkForDuplicates(
        List<SObject> newRecords,
        String objectApiName
    ) {
        Map<Id, List<String>> duplicateMap = new Map<Id, List<String>>();

        Set<String> objectNameCandidates = new Set<String>{
            objectApiName, NamespaceUtil.strip(objectApiName), NamespaceUtil.qualify(objectApiName)
        };

        List<Duplication_Configuration__c> configs = [
            SELECT Id,
                   Primary_Object_API_Name__c,
                   Primary_Expression__c,
                   Related_Object_API_Name__c,
                   Related_Expression__c
            FROM Duplication_Configuration__c
            WHERE Primary_Object_API_Name__c IN :objectNameCandidates
            AND Active__c = true
            LIMIT 1
        ];

        if (configs.isEmpty()) return duplicateMap;

        Duplication_Configuration__c config = configs[0];

        for (SObject record : newRecords) {

            List<String> duplicateIds = new List<String>();

            String whereClause =
                buildWhereClauseFromExpression(
                    record,
                    config.Primary_Expression__c
                );

            if (String.isBlank(whereClause) || whereClause == '()') continue;

            String query =
                'SELECT Id FROM ' + objectApiName +
                ' WHERE ' + whereClause;

            if (record.Id != null) {
                query += ' AND Id != \'' + record.Id + '\'';
            }

            query += ' LIMIT 50';

            try {
                List<SObject> duplicates = Database.query(query);

                for (SObject dup : duplicates) {
                    duplicateIds.add(String.valueOf(dup.get('Id')));
                }

            } catch (Exception e) {
                System.debug('Duplicate Query Error: ' + e.getMessage());
                System.debug(query);
            }

            if (!duplicateIds.isEmpty()) {
                duplicateMap.put(record.Id, duplicateIds);
            }
        }

        return duplicateMap;
    }

    // ===============================================================
    // BUILD WHERE CLAUSE
    // ===============================================================
    public static String buildWhereClauseFromExpression(
        SObject record,
        String expression
    ) {
        if (String.isBlank(expression)) return '';

        String result =
            parseExpression(record, expression.trim(), expression);

        System.debug('Generated WHERE clause: ' + result);

        return result;
    }

    // ===============================================================
    // PARSE EXPRESSION
    // ===============================================================
    private static String parseExpression(
        SObject record,
        String expression,
        String fullExpression
    ) {
        if (String.isBlank(expression)) return '';

        expression = expression.trim();

        // Remove outer parentheses
        if (expression.startsWith('(') && expression.endsWith(')')) {
            if (isOuterParentheses(expression)) {
                return parseExpression(
                    record,
                    expression.substring(1, expression.length() - 1),
                    fullExpression
                );
            }
        }

        // OR logic
        List<String> orParts = splitTopLevel(expression, ' OR ');
        if (orParts.size() > 1) {

            List<String> conditions = new List<String>();

            for (String part : orParts) {
                String cond =
                    parseExpression(record, part, fullExpression);

                if (String.isNotBlank(cond)) {
                    conditions.add(cond);
                }
            }

            return conditions.isEmpty()
                ? ''
                : '(' + String.join(conditions, ' OR ') + ')';
        }

        // AND logic (+)
        List<String> andParts = splitTopLevel(expression, ' + ');
        if (andParts.size() > 1) {

            List<String> conditions = new List<String>();

            for (String part : andParts) {

                String cond =
                    parseExpression(record, part, fullExpression);

                // STRICT AND
                if (String.isBlank(cond)) {
                    return '';
                }

                conditions.add(cond);
            }

            return '(' + String.join(conditions, ' AND ') + ')';
        }

        // BASE CASE
        return buildConditionForField(
            record,
            expression,
            fullExpression
        );
    }

    // ===============================================================
    // BUILD FIELD CONDITION (Dynamic Cross-Mobile)
    // ===============================================================
    private static String buildConditionForField(
        SObject record,
        String fieldName,
        String fullExpression
    ) {
        Object value = record.get(fieldName);
        if (value == null) return '';

        if (value instanceof String) {

            String val = String.escapeSingleQuotes(String.valueOf(value));
            if (String.isBlank(val)) return '';

            // 🔥 Dynamic Cross Mobile
            if (fieldName.toLowerCase().contains('mobile')) {

                Set<String> mobileFields =
                    extractMobileFields(fullExpression);

                List<String> conditions = new List<String>();

                for (String mf : mobileFields) {
                    conditions.add(mf + ' = \'' + val + '\'');
                }

                return '(' + String.join(conditions, ' OR ') + ')';
            }

            return fieldName + ' = \'' + val + '\'';
        }

        if (value instanceof Id) {
            return fieldName + ' = \'' + value + '\'';
        }

        if (value instanceof Boolean ||
            value instanceof Integer ||
            value instanceof Decimal ||
            value instanceof Double ||
            value instanceof Long) {
            return fieldName + ' = ' + value;
        }

        if (value instanceof Date) {
            return fieldName + ' = ' + String.valueOf(value);
        }

        if (value instanceof Datetime) {
            return fieldName + ' = ' +
                ((Datetime)value).formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }

        return '';
    }

    // ===============================================================
    // Extract mobile fields from expression
    // ===============================================================
    private static Set<String> extractMobileFields(String expression) {

        Set<String> mobileFields = new Set<String>();

        if (String.isBlank(expression)) return mobileFields;

        String cleaned = expression
            .replace('(', '')
            .replace(')', '')
            .replace(' OR ', ',')
            .replace(' + ', ',');

        for (String part : cleaned.split(',')) {

            part = part.trim();

            if (part.toLowerCase().contains('mobile')) {
                mobileFields.add(part);
            }
        }

        return mobileFields;
    }

    // ===============================================================
    // Split helper
    // ===============================================================
    private static List<String> splitTopLevel(String expression, String operator) {

        List<String> result = new List<String>();
        Integer depth = 0;
        String current = '';

        for (Integer i = 0; i < expression.length(); i++) {

            String ch = expression.substring(i, i + 1);

            if (ch == '(') depth++;
            else if (ch == ')') depth--;

            if (depth == 0 && expression.substring(i).startsWith(operator)) {
                result.add(current.trim());
                current = '';
                i += operator.length() - 1;
            } else {
                current += ch;
            }
        }

        if (String.isNotBlank(current)) {
            result.add(current.trim());
        }

        return result;
    }

    private static Boolean isOuterParentheses(String expr) {

        Integer depth = 0;

        for (Integer i = 0; i < expr.length(); i++) {

            String ch = expr.substring(i, i + 1);

            if (ch == '(') depth++;
            if (ch == ')') depth--;

            if (depth == 0 && i < expr.length() - 1) {
                return false;
            }
        }

        return true;
    }

    // ===============================================================
    // PRE-INSERT DUPLICATE DETECTION (from payload / field values)
    // ===============================================================

    /**
     * @description Find duplicate records from a map of field values (before insert).
     *              Uses Duplication_Configuration__c to build the WHERE clause dynamically.
     * @param objectApiName  The SObject type to search (e.g., 'Channel_Partner__c')
     * @param fieldValues    Map of SF field API name => value to match against
     * @param fieldsToQuery  Comma-separated list of fields to return
     * @return List of matching SObject records
     */
    public static List<SObject> findDuplicatesFromPayload(
        String objectApiName,
        Map<String, Object> fieldValues,
        String fieldsToQuery
    ) {
        Set<String> objectNameCandidates = new Set<String>{
            objectApiName, NamespaceUtil.strip(objectApiName), NamespaceUtil.qualify(objectApiName)
        };
        List<Duplication_Configuration__c> configs = [
            SELECT Id, Primary_Object_API_Name__c, Primary_Expression__c
            FROM Duplication_Configuration__c
            WHERE Primary_Object_API_Name__c IN :objectNameCandidates
            AND Active__c = true
            LIMIT 1
        ];

        if (configs.isEmpty()) return new List<SObject>();

        // Build a temporary SObject to pass to buildWhereClauseFromExpression
        Schema.SObjectType sType = NamespaceUtil.describeObject(objectApiName);
        if (sType == null) return new List<SObject>();
        SObject tempRecord = sType.newSObject();
        for (String fieldName : fieldValues.keySet()) {
            Object val = fieldValues.get(fieldName);
            if (val != null) {
                Schema.SObjectField sfField = NamespaceUtil.describeField(sType, fieldName);
                if (sfField != null) {
                    tempRecord.put(sfField, val);
                }
            }
        }

        String whereClause = buildWhereClauseFromExpression(
            tempRecord, configs[0].Primary_Expression__c
        );

        if (String.isBlank(whereClause) || whereClause == '()') {
            return new List<SObject>();
        }

        String query = 'SELECT ' + String.escapeSingleQuotes(fieldsToQuery)
            + ' FROM ' + String.escapeSingleQuotes(objectApiName)
            + ' WHERE ' + whereClause
            + ' LIMIT 1';

        try {
            return Database.query(query);
        } catch (Exception e) {
            System.debug('Pre-insert duplicate query error: ' + e.getMessage());
            return new List<SObject>();
        }
    }

    // ===============================================================
    // INTRA-BATCH DUPLICATE DETECTION (in-memory, zero SOQL)
    // ===============================================================

    /**
     * @description Detect duplicates WITHIN a batch of records (in-memory, no SOQL).
     *              Two records are duplicates if their dedup key sets intersect.
     *              First occurrence is kept; subsequent duplicates are flagged.
     * @param newRecords  List of SObject records in the batch
     * @param expression  The Primary_Expression__c from Duplication_Configuration__c
     * @return Set of 0-based indices into newRecords that are intra-batch duplicates
     */
    public static Set<Integer> checkForIntraBatchDuplicates(List<SObject> newRecords, String expression){
        Set<Integer> duplicateIndices = new Set<Integer>();

        if (String.isBlank(expression) || newRecords == null || newRecords.size() <= 1) {
            return duplicateIndices;
        }

        // Map: dedup key -> index of the FIRST record that produced this key
        Map<String, Integer> keyToFirstIndex = new Map<String, Integer>();

        for (Integer i = 0; i < newRecords.size(); i++) {
            Set<String> keys = extractDedupKeys(newRecords[i], expression);

            Boolean isDuplicate = false;
            for (String key : keys) {
                if (keyToFirstIndex.containsKey(key)) {
                    isDuplicate = true;
                    break;
                }
            }

            if (isDuplicate) {
                duplicateIndices.add(i);
            } else {
                // Register all keys for this record
                for (String key : keys) {
                    keyToFirstIndex.put(key, i);
                }
            }
        }

        return duplicateIndices;
    }

    /**
     * @description Extract a set of dedup keys from a record based on the expression.
     *              Two records are intra-batch duplicates if their key sets intersect.
     * @param record      The SObject record
     * @param expression  The dedup expression (e.g., "Mobile__c OR Email__c")
     * @return Set of normalized string keys
     */
    public static Set<String> extractDedupKeys(SObject record, String expression) {
        if (String.isBlank(expression) || record == null) return new Set<String>();
        return parseExpressionToKeys(record, expression.trim(), expression);
    }

    /**
     * @description Recursive key parser mirroring parseExpression() structure.
     *              OR branches: union key sets. AND branches: Cartesian product.
     */
    private static Set<String> parseExpressionToKeys(SObject record, String expression, String fullExpression){
        Set<String> keys = new Set<String>();
        if (String.isBlank(expression)) return keys;

        expression = expression.trim();

        // Remove outer parentheses
        if (expression.startsWith('(') && expression.endsWith(')')) {
            if (isOuterParentheses(expression)) {
                return parseExpressionToKeys(record, expression.substring(1, expression.length() - 1), fullExpression);
            }
        }

        // OR logic: union key sets from each branch
        List<String> orParts = splitTopLevel(expression, ' OR ');
        if (orParts.size() > 1) {
            for (String part : orParts) {
                keys.addAll(parseExpressionToKeys(record, part, fullExpression));
            }
            return keys;
        }

        // AND logic (+): Cartesian product of key components
        List<String> andParts = splitTopLevel(expression, ' + ');
        if (andParts.size() > 1) {
            List<Set<String>> partKeySets = new List<Set<String>>();

            for (String part : andParts) {
                Set<String> partKeys = parseExpressionToKeys(record, part, fullExpression);
                if (partKeys.isEmpty()) {
                    return keys; // Strict AND: if any part yields nothing, no composite keys
                }
                partKeySets.add(partKeys);
            }

            // Build composite keys via Cartesian product
            Set<String> composites = new Set<String>{''};
            for (Set<String> partKeySet : partKeySets) {
                Set<String> newComposites = new Set<String>();
                for (String existing : composites) {
                    for (String partKey : partKeySet) {
                        String separator = String.isBlank(existing) ? '' : '|';
                        newComposites.add(existing + separator + partKey);
                    }
                }
                composites = newComposites;
            }

            keys.addAll(composites);
            return keys;
        }

        // BASE CASE: single field
        keys.addAll(buildFieldKey(record, expression, fullExpression));
        return keys;
    }

    /**
     * @description Build dedup key(s) for a single field value.
     *              Mobile fields generate cross-match keys for all mobile fields in the expression.
     */
    private static Set<String> buildFieldKey(
        SObject record, String fieldName, String fullExpression
    ) {
        Set<String> keyComponents = new Set<String>();
        Object value = record.get(fieldName);
        if (value == null) return keyComponents;

        String normalizedVal = String.valueOf(value).trim().toLowerCase();
        if (String.isBlank(normalizedVal)) return keyComponents;

        // Cross-mobile logic: same as buildConditionForField
        if (fieldName.toLowerCase().contains('mobile')) {
            Set<String> mobileFields = extractMobileFields(fullExpression);
            for (String mf : mobileFields) {
                keyComponents.add(mf.toLowerCase() + '=' + normalizedVal);
            }
        } else {
            keyComponents.add(fieldName.toLowerCase() + '=' + normalizedVal);
        }

        return keyComponents;
    }

    // ===============================================================
    // BULK-SAFE DB DUPLICATE CHECK (single SOQL, index-based result)
    // ===============================================================

    /**
     * @description Check for DB duplicates using a single bulk SOQL query.
     *              Returns results keyed by list index (works for BEFORE INSERT
     *              where record.Id is null). Fixes the SOQL-in-loop governor
     *              limit issue of the original checkForDuplicates().
     * @param newRecords     List of SObject records to check
     * @param objectApiName  API name of the SObject (e.g., 'Lead__c')
     * @param expression     The Primary_Expression__c from Duplication_Configuration__c
     * @return Map of batch index to list of matching DB record IDs
     */
    public static Map<Integer, List<String>> checkForDuplicatesByIndex(
        List<SObject> newRecords,
        String objectApiName,
        String expression
    ) {
        Map<Integer, List<String>> duplicateMap = new Map<Integer, List<String>>();

        if (newRecords == null || newRecords.isEmpty() || String.isBlank(expression)) {
            return duplicateMap;
        }

        // Step 1: Extract all field names from the expression
        Set<String> allFields = extractAllFields(expression);
        if (allFields.isEmpty()) return duplicateMap;

        Set<String> mobileFields = extractMobileFields(expression);

        // Step 2: Collect all values per field from all records
        Map<String, Set<String>> fieldToValues = new Map<String, Set<String>>();
        for (String fieldName : allFields) {
            fieldToValues.put(fieldName, new Set<String>());
        }

        for (SObject record : newRecords) {
            for (String fieldName : allFields) {
                Object val = record.get(fieldName);
                if (val != null) {
                    String strVal = String.valueOf(val);
                    if (String.isNotBlank(strVal)) {
                        fieldToValues.get(fieldName).add(strVal);
                        // Cross-mobile: add value to all mobile field sets
                        if (fieldName.toLowerCase().contains('mobile')) {
                            for (String mf : mobileFields) {
                                if (!fieldToValues.containsKey(mf)) {
                                    fieldToValues.put(mf, new Set<String>());
                                }
                                fieldToValues.get(mf).add(strVal);
                            }
                        }
                    }
                }
            }
        }

        // Remove empty sets
        Set<String> fieldsWithValues = new Set<String>();
        for (String fieldName : fieldToValues.keySet()) {
            if (!fieldToValues.get(fieldName).isEmpty()) {
                fieldsWithValues.add(fieldName);
            }
        }
        if (fieldsWithValues.isEmpty()) return duplicateMap;

        // Step 3: Build a single bulk SOQL query
        // SELECT Id, Field1, Field2, ... FROM Object WHERE (Field1 IN :vals1 OR Field2 IN :vals2 ...)
        String fieldsToSelect = 'Id';
        for (String fieldName : fieldsWithValues) {
            fieldsToSelect += ', ' + String.escapeSingleQuotes(fieldName);
        }

        // Build WHERE clause: combine all field IN conditions with OR
        // This is a broad filter — we post-filter in Apex for exact per-record matches
        List<String> inConditions = new List<String>();
        for (String fieldName : fieldsWithValues) {
            Set<String> vals = fieldToValues.get(fieldName);
            List<String> quotedVals = new List<String>();
            for (String v : vals) {
                quotedVals.add('\'' + String.escapeSingleQuotes(v) + '\'');
            }
            inConditions.add(String.escapeSingleQuotes(fieldName) + ' IN (' + String.join(quotedVals, ',') + ')');
        }

        String bulkWhere = '(' + String.join(inConditions, ' OR ') + ')';

        String query = 'SELECT ' + fieldsToSelect
            + ' FROM ' + String.escapeSingleQuotes(objectApiName)
            + ' WHERE ' + bulkWhere
            + ' LIMIT 500';

        List<SObject> dbResults;
        try {
            dbResults = Database.query(query);
        } catch (Exception e) {
            System.debug('Bulk duplicate query error: ' + e.getMessage());
            return duplicateMap;
        }

        if (dbResults.isEmpty()) return duplicateMap;

        // Step 4: Post-filter — for each batch record, check if any DB result
        // matches its specific dedup expression
        Set<String> dbKeySet = new Set<String>();
        Map<String, List<String>> dbKeyToIds = new Map<String, List<String>>();

        for (SObject dbRecord : dbResults) {
            Set<String> dbKeys = extractDedupKeys(dbRecord, expression);
            for (String key : dbKeys) {
                dbKeySet.add(key);
                if (!dbKeyToIds.containsKey(key)) {
                    dbKeyToIds.put(key, new List<String>());
                }
                dbKeyToIds.get(key).add(String.valueOf(dbRecord.get('Id')));
            }
        }

        for (Integer i = 0; i < newRecords.size(); i++) {
            SObject record = newRecords[i];
            Set<String> recordKeys = extractDedupKeys(record, expression);

            // Exclude self (for update triggers where record already has an Id)
            String selfId = (record.Id != null) ? String.valueOf(record.Id) : null;

            Set<String> matchedIds = new Set<String>();
            for (String key : recordKeys) {
                if (dbKeyToIds.containsKey(key)) {
                    for (String dbId : dbKeyToIds.get(key)) {
                        if (selfId == null || dbId != selfId) {
                            matchedIds.add(dbId);
                        }
                    }
                }
            }

            if (!matchedIds.isEmpty()) {
                duplicateMap.put(i, new List<String>(matchedIds));
            }
        }

        return duplicateMap;
    }

    /**
     * @description Extract all field names from a dedup expression.
     *              Strips operators and parentheses, returns clean field API names.
     */
    private static Set<String> extractAllFields(String expression) {
        Set<String> fields = new Set<String>();
        if (String.isBlank(expression)) return fields;

        String cleaned = expression
            .replace('(', '')
            .replace(')', '')
            .replace(' OR ', ',')
            .replace(' + ', ',');

        for (String part : cleaned.split(',')) {
            part = part.trim();
            if (String.isNotBlank(part)) {
                fields.add(part);
            }
        }

        return fields;
    }
}