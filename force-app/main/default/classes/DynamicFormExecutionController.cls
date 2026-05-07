public with sharing class DynamicFormExecutionController {

    // Get available form configurations for a context object record
    @AuraEnabled
    public static List<FormConfigOption> getAvailableConfigurations(String contextObjectApiName, String recordId) {
        List<FormConfigOption> availableConfigs = new List<FormConfigOption>();

        User currentUser = [SELECT Id, ProfileId, UserRoleId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String currentProfileName = [SELECT Name FROM Profile WHERE Id = :currentUser.ProfileId LIMIT 1].Name;
        String currentRoleName = currentUser.UserRoleId != null ?
            [SELECT Name FROM UserRole WHERE Id = :currentUser.UserRoleId LIMIT 1].Name : '';

        List<Dynamic_Form_Configuration__c> configs = [
            SELECT Id, Name, Configuration_JSON__c, Description__c, Object_API_Name__c,
                   Context_Object__c, Button_Label__c
            FROM Dynamic_Form_Configuration__c
            WHERE Context_Object__c = :contextObjectApiName
            AND Active__c = true
        ];

        // Get record field values for condition evaluation
        Map<String, Object> recordFieldValues = new Map<String, Object>();
        if (String.isNotBlank(recordId) && !configs.isEmpty()) {
            recordFieldValues = getRecordFieldValues(contextObjectApiName, recordId, configs);
        }

        for (Dynamic_Form_Configuration__c config : configs) {
            if (String.isNotBlank(config.Configuration_JSON__c)) {
                Map<String, Object> jsonConfig = (Map<String, Object>) JSON.deserializeUntyped(config.Configuration_JSON__c);

                Boolean visibilityOk = checkVisibilityRules(jsonConfig, currentUser.Id, currentProfileName, currentRoleName);
                Boolean conditionsOk = checkFieldConditions(jsonConfig, recordFieldValues);

                if (visibilityOk && conditionsOk) {
                    availableConfigs.add(new FormConfigOption(
                        config.Id,
                        config.Name,
                        config.Description__c,
                        config.Configuration_JSON__c,
                        config.Object_API_Name__c,
                        config.Button_Label__c
                    ));
                }
            }
        }

        return availableConfigs;
    }

    // Get record field values needed for condition checks
    private static Map<String, Object> getRecordFieldValues(String objectApiName, String recordId,
                                                              List<Dynamic_Form_Configuration__c> configs) {
        Set<String> fieldsToQuery = new Set<String>{'Id'};

        for (Dynamic_Form_Configuration__c config : configs) {
            if (String.isNotBlank(config.Configuration_JSON__c)) {
                Map<String, Object> jsonConfig = (Map<String, Object>) JSON.deserializeUntyped(config.Configuration_JSON__c);
                List<Object> conditions = (List<Object>) jsonConfig.get('conditions');
                if (conditions != null) {
                    for (Object condObj : conditions) {
                        Map<String, Object> cond = (Map<String, Object>) condObj;
                        String fieldName = (String) cond.get('field');
                        if (String.isNotBlank(fieldName)) {
                            fieldsToQuery.add(fieldName);
                        }
                    }
                }
            }
        }

        if (fieldsToQuery.size() <= 1) {
            return new Map<String, Object>();
        }

        String query = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') +
                        ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                        ' WHERE Id = :recordId LIMIT 1';

        List<SObject> records = Database.query(query);
        if (records.isEmpty()) {
            return new Map<String, Object>();
        }

        Map<String, Object> fieldValues = new Map<String, Object>();
        SObject rec = records[0];
        for (String fieldName : fieldsToQuery) {
            if (fieldName != 'Id') {
                fieldValues.put(fieldName, rec.get(fieldName));
            }
        }

        return fieldValues;
    }

    // Check field-based conditions on the context record
    private static Boolean checkFieldConditions(Map<String, Object> jsonConfig, Map<String, Object> recordFieldValues) {
        List<Object> conditions = (List<Object>) jsonConfig.get('conditions');

        if (conditions == null || conditions.isEmpty()) {
            return true;
        }

        // AND logic - all conditions must match
        for (Object condObj : conditions) {
            Map<String, Object> cond = (Map<String, Object>) condObj;
            String fieldName = (String) cond.get('field');
            String operator = (String) cond.get('operator');
            String expectedValue = (String) cond.get('value');

            Object actualValue = recordFieldValues.get(fieldName);
            String actualStr = actualValue != null ? String.valueOf(actualValue) : '';

            if (!compareValues(actualStr, expectedValue, operator)) {
                return false;
            }
        }

        return true;
    }

    private static Boolean checkVisibilityRules(Map<String, Object> jsonConfig,
                                                 String userId, String profileName, String roleName) {
        List<Object> visibilityRules = (List<Object>) jsonConfig.get('visibilityRules');

        if (visibilityRules == null || visibilityRules.isEmpty()) {
            return true;
        }

        for (Object ruleObj : visibilityRules) {
            Map<String, Object> rule = (Map<String, Object>) ruleObj;
            String ruleType = (String) rule.get('ruleType');
            String operator = (String) rule.get('operator');
            String value = (String) rule.get('value');

            Boolean matches = false;

            if (ruleType == 'User') {
                matches = compareValues(userId, value, operator);
            } else if (ruleType == 'Profile') {
                matches = compareValues(profileName, value, operator);
            } else if (ruleType == 'Role') {
                matches = compareValues(roleName, value, operator);
            }

            if (matches) {
                return true;
            }
        }

        return false;
    }

    private static Boolean compareValues(String actualValue, String expectedValue, String operator) {
        if (String.isBlank(actualValue) && operator != 'equals' && operator != 'notEquals') {
            return false;
        }

        if (operator == 'equals') {
            if (String.isBlank(actualValue) && String.isBlank(expectedValue)) return true;
            if (String.isBlank(actualValue)) return false;
            return actualValue.equalsIgnoreCase(expectedValue);
        } else if (operator == 'notEquals') {
            if (String.isBlank(actualValue) && String.isBlank(expectedValue)) return false;
            if (String.isBlank(actualValue)) return true;
            return !actualValue.equalsIgnoreCase(expectedValue);
        } else if (operator == 'contains') {
            return actualValue.toLowerCase().contains(expectedValue.toLowerCase());
        } else if (operator == 'notContains') {
            return !actualValue.toLowerCase().contains(expectedValue.toLowerCase());
        }

        return false;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, FieldMetadata> getFieldsMetadata(String objectApiName, List<String> fieldApiNames) {
        Map<String, FieldMetadata> fieldsMetadata = new Map<String, FieldMetadata>();

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) {
            return fieldsMetadata;
        }

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        for (String fieldApiName : fieldApiNames) {
            if (fieldMap.containsKey(fieldApiName.toLowerCase())) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName.toLowerCase()).getDescribe();

                FieldMetadata metadata = new FieldMetadata();
                metadata.apiName = fieldDescribe.getName();
                metadata.label = fieldDescribe.getLabel();
                metadata.type = String.valueOf(fieldDescribe.getType());
                metadata.isRequired = !fieldDescribe.isNillable() && !fieldDescribe.isDefaultedOnCreate();
                metadata.length = fieldDescribe.getLength();
                metadata.scale = fieldDescribe.getScale();

                if (fieldDescribe.getType() == Schema.DisplayType.PICKLIST ||
                    fieldDescribe.getType() == Schema.DisplayType.MULTIPICKLIST) {
                    List<PicklistValue> picklistValues = new List<PicklistValue>();
                    for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                        if (entry.isActive()) {
                            picklistValues.add(new PicklistValue(entry.getLabel(), entry.getValue()));
                        }
                    }
                    metadata.picklistValues = picklistValues;
                }

                if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                    List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();
                    if (!references.isEmpty()) {
                        metadata.referenceObjectName = references[0].getDescribe().getName();
                    }
                }

                fieldsMetadata.put(fieldApiName, metadata);
            }
        }

        return fieldsMetadata;
    }

    // Save parent record and child records in a single transaction
    @AuraEnabled
    public static String saveFormWithChildren(String objectApiName, Map<String, Object> fieldValues,
                                               String childRecordsJson, String formName,
                                               String saveFormNameToField) {
        Savepoint sp = Database.setSavepoint();
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
            SObject parentRecord = objType.newSObject();

            Map<String, Schema.SObjectField> parentFieldMap = objType.getDescribe().fields.getMap();

            for (String fieldName : fieldValues.keySet()) {
                Object value = fieldValues.get(fieldName);
                if (value != null) {
                    parentRecord.put(fieldName, castFieldValue(parentFieldMap, fieldName, value));
                }
            }

            if (String.isNotBlank(saveFormNameToField)) {
                parentRecord.put(saveFormNameToField, formName);
            }

            insert parentRecord;
            Id parentId = parentRecord.Id;

            // Process child records
            if (String.isNotBlank(childRecordsJson)) {
                List<Object> childConfigs = (List<Object>) JSON.deserializeUntyped(childRecordsJson);

                List<SObject> allChildRecords = new List<SObject>();

                for (Object childConfigObj : childConfigs) {
                    Map<String, Object> childConfig = (Map<String, Object>) childConfigObj;
                    String childObjectName = (String) childConfig.get('childObject');
                    String relationshipField = (String) childConfig.get('relationshipField');
                    List<Object> rows = (List<Object>) childConfig.get('rows');

                    if (rows == null || rows.isEmpty()) continue;

                    Schema.SObjectType childObjType = Schema.getGlobalDescribe().get(childObjectName);
                    Map<String, Schema.SObjectField> childFieldMap = childObjType.getDescribe().fields.getMap();

                    for (Object rowObj : rows) {
                        Map<String, Object> row = (Map<String, Object>) rowObj;
                        SObject childRecord = childObjType.newSObject();

                        childRecord.put(relationshipField, parentId);

                        for (String fieldName : row.keySet()) {
                            Object value = row.get(fieldName);
                            if (value != null && fieldName != 'tempId') {
                                childRecord.put(fieldName, castFieldValue(childFieldMap, fieldName, value));
                            }
                        }

                        allChildRecords.add(childRecord);
                    }
                }

                if (!allChildRecords.isEmpty()) {
                    insert allChildRecords;
                }
            }

            return parentId;
        } catch (Exception e) {
            Database.rollback(sp);
            throw new AuraHandledException('Error saving record: ' + e.getMessage());
        }
    }

    // Cast field value to appropriate type based on schema
    private static Object castFieldValue(Map<String, Schema.SObjectField> fieldMap, String fieldName, Object value) {
        if (value == null) return null;

        Schema.SObjectField sField = fieldMap.get(fieldName.toLowerCase());
        if (sField == null) return value;

        Schema.DisplayType fieldType = sField.getDescribe().getType();
        String strValue = String.valueOf(value);

        if (fieldType == Schema.DisplayType.DOUBLE || fieldType == Schema.DisplayType.CURRENCY ||
            fieldType == Schema.DisplayType.PERCENT) {
            return Decimal.valueOf(strValue);
        } else if (fieldType == Schema.DisplayType.INTEGER) {
            return Integer.valueOf(strValue);
        } else if (fieldType == Schema.DisplayType.DATE) {
            return Date.valueOf(strValue);
        } else if (fieldType == Schema.DisplayType.DATETIME) {
            return Datetime.valueOf(strValue.replace('T', ' ').replace('Z', ''));
        } else if (fieldType == Schema.DisplayType.BOOLEAN) {
            return Boolean.valueOf(strValue);
        }

        return value;
    }

    // Keep backward compat
    @AuraEnabled
    public static String saveFormRecord(String objectApiName, Map<String, Object> fieldValues,
                                        String formName, String saveFormNameToField) {
        return saveFormWithChildren(objectApiName, fieldValues, null, formName, saveFormNameToField);
    }

    /**
     * @description Clone an existing record by copying all editable fields.
     * Unique/externalId text fields get ' (Copy)' appended automatically.
     * Auto-number and formula fields are excluded.
     * @param objectApiName API name of the SObject
     * @param recordId Id of the record to clone
     * @return Map of field API names to values (for pre-populating a form)
     */
    @AuraEnabled
    public static Map<String, Object> getRecordValuesForClone(String objectApiName, String recordId) {
        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
            if (objType == null) {
                throw new AuraHandledException('Invalid object: ' + objectApiName);
            }

            Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

            // Collect all creatable, non-auto fields
            List<String> queryFields = new List<String>();
            Set<String> uniqueTextFields = new Set<String>();
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
                // Skip auto-number, formula, calculated, and non-creatable fields
                if (!fd.isCreateable()) continue;
                if (fd.isAutoNumber()) continue;
                if (fd.isCalculated()) continue;

                queryFields.add(fd.getName());

                // Track unique text fields to append (Copy)
                if (fd.isUnique() && (fd.getType() == Schema.DisplayType.STRING || fd.getType() == Schema.DisplayType.TEXTAREA)) {
                    uniqueTextFields.add(fd.getName());
                }
            }

            if (queryFields.isEmpty()) {
                return new Map<String, Object>();
            }

            // Also add Name for reference
            String nameField = 'Name';
            String copySuffix = ' (Copy)';
            queryFields.add(nameField);

            String query = 'SELECT ' + String.join(queryFields, ', ') +
                           ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                           ' WHERE Id = \'' + String.escapeSingleQuotes(recordId) + '\' LIMIT 1';

            List<SObject> records = Database.query(query);
            if (records.isEmpty()) {
                throw new AuraHandledException('Record not found');
            }

            SObject sourceRecord = records[0];
            Map<String, Object> fieldValues = new Map<String, Object>();

            for (String fieldName : queryFields) {
                if (fieldName == nameField) continue; // Skip Name for output
                Object val = sourceRecord.get(fieldName);
                if (val != null) {
                    // Append copy suffix to unique text fields to avoid duplicate errors
                    if (uniqueTextFields.contains(fieldName)) {
                        String textVal = String.valueOf(val);
                        if (!textVal.endsWith(copySuffix)) {
                            textVal += copySuffix;
                        }
                        fieldValues.put(fieldName, textVal);
                    } else {
                        fieldValues.put(fieldName, val);
                    }
                }
            }

            return fieldValues;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Error preparing clone data: ' + e.getMessage());
        }
    }

    // Wrapper classes
    public class FormConfigOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
        @AuraEnabled public String configJson;
        @AuraEnabled public String targetObject;
        @AuraEnabled public String buttonLabel;

        public FormConfigOption(String id, String name, String description,
                                 String configJson, String targetObject, String buttonLabel) {
            this.id = id;
            this.name = name;
            this.description = description;
            this.configJson = configJson;
            this.targetObject = targetObject;
            this.buttonLabel = buttonLabel;
        }
    }

    public class FieldMetadata {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public Boolean isRequired;
        @AuraEnabled public Integer length;
        @AuraEnabled public Integer scale;
        @AuraEnabled public List<PicklistValue> picklistValues;
        @AuraEnabled public String referenceObjectName;
    }

    public class PicklistValue {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistValue(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /**
     * Search records for lookup fields in dynamic forms.
     */
    @AuraEnabled
    public static List<Map<String, String>> searchLookupRecords(String objectApiName, String searchTerm) {
        List<Map<String, String>> results = new List<Map<String, String>>();
        if (String.isBlank(objectApiName) || String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return results;
        }

        String searchKey = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        String query = 'SELECT Id, Name FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE Name LIKE :searchKey ORDER BY Name LIMIT 20';
        try {
            for (SObject rec : Database.query(query)) {
                results.add(new Map<String, String>{
                    'id' => rec.Id,
                    'name' => (String) rec.get('Name')
                });
            }
        } catch (Exception e) {
            System.debug('Lookup search error: ' + e.getMessage());
        }
        return results;
    }

    /**
     * Get a record's Name field by ID (for displaying lookup values).
     */
    @AuraEnabled(cacheable=true)
    public static String getRecordName(String recordId) {
        if (String.isBlank(recordId)) return '';
        try {
            Id recId = Id.valueOf(recordId);
            String objectApiName = recId.getSObjectType().getDescribe().getName();
            String query = 'SELECT Name FROM ' + objectApiName + ' WHERE Id = :recId LIMIT 1';
            List<SObject> records = Database.query(query);
            return records.isEmpty() ? '' : (String) records[0].get('Name');
        } catch (Exception e) {
            return '';
        }
    }
}