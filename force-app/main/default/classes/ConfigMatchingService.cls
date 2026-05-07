/**
 * @description Reusable service to evaluate matching criteria for admin configurations.
 * Supports object field conditions, user profile matching, and user role matching.
 * Used across Email Templates, Document Templates, Post Sales Config, Approval Config, etc.
 */
public with sharing class ConfigMatchingService {

    /**
     * @description Evaluate matching criteria JSON against a record and current user context.
     * @param matchingCriteriaJson JSON string containing matching criteria
     * @param recordId The record to evaluate field conditions against
     * @param objectApiName API name of the object
     * @return true if the criteria match (or if no criteria defined)
     */
    @AuraEnabled
    public static Boolean evaluateCriteria(String matchingCriteriaJson, Id recordId, String objectApiName) {
        if (String.isBlank(matchingCriteriaJson)) {
            return true;
        }

        Map<String, Object> criteria = (Map<String, Object>) JSON.deserializeUntyped(matchingCriteriaJson);
        List<Object> conditions = (List<Object>) criteria.get('conditions');
        String matchLogic = (String) criteria.get('matchLogic');

        if (conditions == null || conditions.isEmpty()) {
            return true;
        }

        // Get current user context
        User currentUser = [SELECT Id, Profile.Name, UserRole.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String profileName = currentUser.Profile.Name;
        String roleName = currentUser.UserRole != null ? currentUser.UserRole.Name : '';

        // Collect field paths we need to query
        Set<String> fieldPaths = new Set<String>();
        for (Object condObj : conditions) {
            Map<String, Object> cond = (Map<String, Object>) condObj;
            String condType = (String) cond.get('type');
            if (condType == 'field' && recordId != null) {
                String fieldPath = (String) cond.get('fieldPath');
                if (String.isNotBlank(fieldPath)) {
                    fieldPaths.add(fieldPath);
                }
            }
        }

        // Query record fields if needed
        Map<String, Object> fieldValues = new Map<String, Object>();
        if (!fieldPaths.isEmpty() && recordId != null && String.isNotBlank(objectApiName)) {
            fieldValues = queryFieldValues(recordId, objectApiName, fieldPaths);
        }

        // Evaluate each condition
        Boolean isAnd = (matchLogic == 'AND');
        Boolean result = isAnd ? true : false;

        for (Object condObj : conditions) {
            Map<String, Object> cond = (Map<String, Object>) condObj;
            Boolean condResult = evaluateSingleCondition(cond, fieldValues, profileName, roleName);

            if (isAnd) {
                result = result && condResult;
                if (!result) return false;
            } else {
                result = result || condResult;
                if (result) return true;
            }
        }

        return result;
    }

    /**
     * @description Filter a list of config records by matching criteria.
     * @param configsWithCriteria List of maps with 'id' and 'matchingCriteria' keys
     * @param recordId Record to match against
     * @param objectApiName Object API name
     * @return List of config IDs that match
     */
    @AuraEnabled
    public static List<String> filterMatchingConfigs(String configsJson, Id recordId, String objectApiName) {
        List<String> matchingIds = new List<String>();
        List<Object> configs = (List<Object>) JSON.deserializeUntyped(configsJson);

        for (Object configObj : configs) {
            Map<String, Object> config = (Map<String, Object>) configObj;
            String configId = (String) config.get('id');
            String criteria = (String) config.get('matchingCriteria');

            if (evaluateCriteria(criteria, recordId, objectApiName)) {
                matchingIds.add(configId);
            }
        }

        return matchingIds;
    }

    /**
     * @description Get all profiles for the matching criteria builder UI.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllProfiles() {
        List<Map<String, String>> profiles = new List<Map<String, String>>();
        for (Profile p : [SELECT Id, Name FROM Profile ORDER BY Name]) {
            profiles.add(new Map<String, String>{ 'label' => p.Name, 'value' => p.Name });
        }
        return profiles;
    }

    /**
     * @description Get all roles for the matching criteria builder UI.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAllRoles() {
        List<Map<String, String>> roles = new List<Map<String, String>>();
        for (UserRole r : [SELECT Id, Name FROM UserRole ORDER BY Name]) {
            roles.add(new Map<String, String>{ 'label' => r.Name, 'value' => r.Name });
        }
        return roles;
    }

    /**
     * @description Search users for the matching criteria builder UI.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> searchUsers(String searchTerm) {
        List<Map<String, String>> users = new List<Map<String, String>>();
        String searchKey = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        for (User u : [SELECT Id, Name, Email FROM User
                        WHERE (Name LIKE :searchKey OR Email LIKE :searchKey) AND IsActive = true
                        ORDER BY Name LIMIT 20]) {
            users.add(new Map<String, String>{
                'label' => u.Name + ' (' + u.Email + ')',
                'value' => u.Id
            });
        }
        return users;
    }

    /**
     * @description Get fields for an object (for the field condition builder).
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getFieldsForObject(String objectApiName) {
        List<Map<String, String>> fields = new List<Map<String, String>>();
        if (String.isBlank(objectApiName)) return fields;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return fields;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        List<String> sortedFieldNames = new List<String>(fieldMap.keySet());
        sortedFieldNames.sort();
        for (String fieldName : sortedFieldNames) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            if (dfr.isAccessible()) {
                String label = dfr.getLabel() + ' (' + dfr.getName() + ')';
                fields.add(new Map<String, String>{
                    'label' => label,
                    'value' => dfr.getName(),
                    'type' => dfr.getType().name()
                });
            }
        }
        return fields;
    }

    /**
     * @description Get picklist values for a specific field.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPicklistValues(String objectApiName, String fieldApiName) {
        List<Map<String, String>> values = new List<Map<String, String>>();
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) return values;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return values;

        Schema.SObjectField field = objType.getDescribe().fields.getMap().get(fieldApiName.toLowerCase());
        if (field == null) return values;

        Schema.DescribeFieldResult dfr = field.getDescribe();
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                values.add(new Map<String, String>{ 'label' => pe.getLabel(), 'value' => pe.getValue() });
            }
        }
        return values;
    }

    /**
     * @description Resolve the best matching email template for a given action and record.
     */
    @AuraEnabled
    public static String resolveEmailTemplateForAction(String actionName, Id recordId, String objectApiName) {
        List<Email_Template_Config__c> templates = [
            SELECT Id, Template_Name__c, Matching_Criteria__c
            FROM Email_Template_Config__c
            WHERE Is_Active__c = true
              AND Action_Binding__c INCLUDES (:actionName)
              AND Object_API_Name__c = :objectApiName
            ORDER BY Is_Default__c DESC
        ];

        for (Email_Template_Config__c tmpl : templates) {
            if (evaluateCriteria(tmpl.Matching_Criteria__c, recordId, objectApiName)) {
                return tmpl.Id;
            }
        }
        return null;
    }

    // ============ PRIVATE HELPERS ============

    private static Boolean evaluateSingleCondition(Map<String, Object> cond,
            Map<String, Object> fieldValues, String profileName, String roleName) {
        String condType = (String) cond.get('type');
        String operator = (String) cond.get('operator');

        if (condType == 'profile') {
            List<Object> values = (List<Object>) cond.get('values');
            return matchesListCondition(profileName, values, operator);
        } else if (condType == 'role') {
            List<Object> values = (List<Object>) cond.get('values');
            return matchesListCondition(roleName, values, operator);
        } else if (condType == 'field') {
            String fieldPath = (String) cond.get('fieldPath');
            Object expectedValue = cond.get('value');
            Object actualValue = fieldValues.get(fieldPath);
            return matchesFieldCondition(actualValue, expectedValue, operator);
        }
        return true;
    }

    private static Boolean matchesListCondition(String actualValue, List<Object> expectedValues, String operator) {
        if (expectedValues == null || expectedValues.isEmpty()) return true;

        Boolean found = false;
        for (Object val : expectedValues) {
            if (String.valueOf(val) == actualValue) {
                found = true;
                break;
            }
        }
        return (operator == 'notIn') ? !found : found;
    }

    private static Boolean matchesFieldCondition(Object actualValue, Object expectedValue, String operator) {
        String actual = actualValue != null ? String.valueOf(actualValue) : '';
        String expected = expectedValue != null ? String.valueOf(expectedValue) : '';

        if (operator == 'equals') return actual == expected;
        if (operator == 'notEquals') return actual != expected;
        if (operator == 'contains') return actual.containsIgnoreCase(expected);
        if (operator == 'startsWith') return actual.startsWithIgnoreCase(expected);
        if (operator == 'greaterThan') {
            try { return Decimal.valueOf(actual) > Decimal.valueOf(expected); } catch (Exception e) { return false; }
        }
        if (operator == 'lessThan') {
            try { return Decimal.valueOf(actual) < Decimal.valueOf(expected); } catch (Exception e) { return false; }
        }
        if (operator == 'isNull') return String.isBlank(actual);
        if (operator == 'isNotNull') return String.isNotBlank(actual);
        return true;
    }

    private static Map<String, Object> queryFieldValues(Id recordId, String objectApiName, Set<String> fieldPaths) {
        Map<String, Object> values = new Map<String, Object>();

        // Build dynamic SOQL
        String soql = 'SELECT ' + String.join(new List<String>(fieldPaths), ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE Id = :recordId LIMIT 1';

        try {
            SObject record = Database.query(soql);
            for (String fieldPath : fieldPaths) {
                values.put(fieldPath, getNestedFieldValue(record, fieldPath));
            }
        } catch (Exception e) {
            System.debug('ConfigMatchingService.queryFieldValues error: ' + e.getMessage());
        }
        return values;
    }

    private static Object getNestedFieldValue(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) return null;

        List<String> parts = fieldPath.split('\\.');
        SObject current = record;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            current = current.getSObject(parts[i]);
            if (current == null) return null;
        }
        return current.get(parts[parts.size() - 1]);
    }
}