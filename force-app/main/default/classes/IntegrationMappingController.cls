/**
 * @description Controller for the Integration Mapping Designer LWC.
 * Provides methods to manage Integration_Source_Config__c, Integration_Field_Rule__c,
 * and Integration_Lookup_Rule__c records via the UI.
 */
public with sharing class IntegrationMappingController {

    @AuraEnabled(cacheable=true)
    public static List<Integration_Source_Config__c> getSourceConfigs() {
        return [SELECT Id, Name, Source_Name__c, Target_Object__c, Is_Active__c, Version__c, Description__c, API_Schema_JSON__c, Validation_Rules_JSON__c, Endpoint_URL__c, 
                Enable_Duplicate_Check__c, Last_Modified_By_User__c, CreatedDate, LastModifiedDate FROM Integration_Source_Config__c ORDER BY Source_Name__c ASC];
    }

    @AuraEnabled
    public static Integration_Source_Config__c getSourceConfigWithRules(Id configId) {
        return [SELECT Id, Name, Source_Name__c, Target_Object__c, Is_Active__c, Version__c, Description__c, API_Schema_JSON__c, Validation_Rules_JSON__c, Endpoint_URL__c, Enable_Duplicate_Check__c,
                (SELECT Id, API_Field_Name__c, API_Field_Label__c, SF_Field_API_Name__c, Is_Required__c, Default_Value__c, Data_Type__c, Transform_Expression__c, Is_Active__c, Is_Static__c, Sequence__c,
                 (SELECT Id, Lookup_Object__c, Match_Field__c, Return_Field__c, Fail_On_No_Match__c, Additional_Filter__c FROM Integration_Lookup_Rules__r)
                 FROM Integration_Field_Rules__r ORDER BY Sequence__c ASC NULLS LAST)
                FROM Integration_Source_Config__c WHERE Id = :configId LIMIT 1];
    }

    @AuraEnabled
    public static Id saveSourceConfig(String configJSON) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(configJSON);

        Integration_Source_Config__c config = new Integration_Source_Config__c();

        if (data.containsKey('id') && data.get('id') != null && String.isNotBlank((String) data.get('id'))) {
            config.Id = (Id) data.get('id');
        }

        config.Name = (String) data.get('name');
        config.Source_Name__c = (String) data.get('sourceName');
        config.Target_Object__c = (String) data.get('targetObject');
        config.Is_Active__c = (Boolean) data.get('isActive');
        config.Description__c = (String) data.get('description');
        config.API_Schema_JSON__c = (String) data.get('apiSchemaJson');
        config.Validation_Rules_JSON__c = (String) data.get('validationRulesJson');
        config.Endpoint_URL__c = (String) data.get('endpointUrl');
        config.Enable_Duplicate_Check__c = data.get('enableDuplicateCheck') == true;
        config.Last_Modified_By_User__c = UserInfo.getName();

        if (data.containsKey('version') && data.get('version') != null) {
            config.Version__c = ((Decimal) data.get('version'));
        }

        upsert config;
        return config.Id;
    }

    @AuraEnabled
    public static void deleteSourceConfig(Id configId) {
        Integration_Source_Config__c config = [SELECT Id FROM Integration_Source_Config__c WHERE Id = :configId LIMIT 1];
        delete config; // cascade deletes children (master-detail)
    }

    // ════════════════════════════════════════════════════════════
    // FIELD RULES CRUD
    // ════════════════════════════════════════════════════════════

    @AuraEnabled
    public static void saveFieldRules(Id configId, String rulesJSON) {
        List<Object> rulesList = (List<Object>) JSON.deserializeUntyped(rulesJSON);

        Set<Id> incomingRuleIds = new Set<Id>();
        List<Integration_Field_Rule__c> toUpsert = new List<Integration_Field_Rule__c>();
        // Collect lookup rules to save after field rules are upserted
        Map<Integer, Map<String, Object>> lookupDataByIndex = new Map<Integer, Map<String, Object>>();

        Integer idx = 0;
        for (Object ruleObj : rulesList) {
            Map<String, Object> r = (Map<String, Object>) ruleObj;

            Integration_Field_Rule__c rule = new Integration_Field_Rule__c();

            String ruleId = (String) r.get('id');
            if (String.isNotBlank(ruleId)) {
                rule.Id = (Id) ruleId;
                incomingRuleIds.add(rule.Id);
            }

            rule.Integration_Source_Config__c = configId;
            rule.API_Field_Name__c = (String) r.get('apiFieldName');
            rule.API_Field_Label__c = (String) r.get('apiFieldLabel');
            rule.SF_Field_API_Name__c = (String) r.get('sfFieldApiName');
            rule.Is_Required__c = r.get('isRequired') == true;
            rule.Default_Value__c = (String) r.get('defaultValue');
            rule.Data_Type__c = (String) r.get('dataType');
            rule.Transform_Expression__c = (String) r.get('transformExpression');
            rule.Is_Active__c = r.get('isActive') != false; // default true
            rule.Is_Static__c = r.get('isStatic') == true;
            rule.Sequence__c = r.get('sequence') != null ? ((Decimal) r.get('sequence')).intValue() : idx + 1;

            toUpsert.add(rule);

            // Check for lookup rule data
            if (r.containsKey('lookupRule') && r.get('lookupRule') != null) {
                lookupDataByIndex.put(idx, (Map<String, Object>) r.get('lookupRule'));
            }

            idx++;
        }

        // Delete removed rules
        List<Integration_Field_Rule__c> existing = [
            SELECT Id FROM Integration_Field_Rule__c
            WHERE Integration_Source_Config__c = :configId
            AND Id NOT IN :incomingRuleIds
        ];
        if (!existing.isEmpty()) {
            delete existing; // cascade deletes child lookup rules
        }

        // Upsert field rules
        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }

        // Now save lookup rules
        List<Integration_Lookup_Rule__c> lookupToUpsert = new List<Integration_Lookup_Rule__c>();
        Set<Id> ruleIdsWithLookup = new Set<Id>();

        for (Integer i : lookupDataByIndex.keySet()) {
            Map<String, Object> lk = lookupDataByIndex.get(i);
            Integration_Field_Rule__c parentRule = toUpsert[i];

            Integration_Lookup_Rule__c lookupRule = new Integration_Lookup_Rule__c();

            String lookupId = (String) lk.get('id');
            if (String.isNotBlank(lookupId)) {
                lookupRule.Id = (Id) lookupId;
            }

            lookupRule.Integration_Field_Rule__c = parentRule.Id;
            lookupRule.Lookup_Object__c = (String) lk.get('lookupObject');
            lookupRule.Match_Field__c = (String) lk.get('matchField');
            lookupRule.Return_Field__c = String.isNotBlank((String) lk.get('returnField'))
                ? (String) lk.get('returnField') : 'Id';
            lookupRule.Fail_On_No_Match__c = lk.get('failOnNoMatch') == true;
            lookupRule.Additional_Filter__c = (String) lk.get('additionalFilter');

            lookupToUpsert.add(lookupRule);
            ruleIdsWithLookup.add(parentRule.Id);
        }

        // Delete lookup rules for field rules that no longer have them
        Set<Id> allRuleIds = new Set<Id>();
        for (Integration_Field_Rule__c fr : toUpsert) {
            if (fr.Id != null && !ruleIdsWithLookup.contains(fr.Id)) {
                allRuleIds.add(fr.Id);
            }
        }
        if (!allRuleIds.isEmpty()) {
            List<Integration_Lookup_Rule__c> orphanLookups = [
                SELECT Id FROM Integration_Lookup_Rule__c
                WHERE Integration_Field_Rule__c IN :allRuleIds
            ];
            if (!orphanLookups.isEmpty()) {
                delete orphanLookups;
            }
        }

        if (!lookupToUpsert.isEmpty()) {
            upsert lookupToUpsert;
        }
    }

    // ════════════════════════════════════════════════════════════
    // SCHEMA DESCRIBE HELPERS
    // ════════════════════════════════════════════════════════════

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getTargetObjectOptions() {
        List<ObjectOption> options = new List<ObjectOption>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (String objName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult objDescribe = globalDescribe.get(objName).getDescribe();
            if (objDescribe.isCreateable() && objDescribe.isCustom()) {
                options.add(new ObjectOption(objDescribe.getLabel(), objDescribe.getName()));
            }
        }

        options.sort();
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getObjectFields(String objectApiName) {
        List<FieldOption> fields = new List<FieldOption>();

        Schema.SObjectType objType = NamespaceUtil.describeObject(objectApiName);
        if (objType == null) {
            return fields;
        }

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();

            if (fd.isAccessible() && (fd.isCreateable() || fd.isUpdateable())) {
                String refTo = null;
                if (fd.getType() == Schema.DisplayType.REFERENCE && !fd.getReferenceTo().isEmpty()) {
                    refTo = fd.getReferenceTo()[0].getDescribe().getName();
                }

                fields.add(new FieldOption(
                    fd.getLabel(),
                    fd.getName(),
                    String.valueOf(fd.getType()),
                    fd.isNillable() == false, // isRequired
                    refTo
                ));
            }
        }

        fields.sort();
        return fields;
    }

    // ════════════════════════════════════════════════════════════
    // INNER CLASSES
    // ════════════════════════════════════════════════════════════

    public class ObjectOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }

        public ObjectOption(String label, String apiName) {
            this.label = label;
            this.apiName = apiName;
        }

        public Integer compareTo(Object other) {
            return this.label.compareTo(((ObjectOption) other).label);
        }
    }

    public class FieldOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public Boolean isRequired { get; set; }
        @AuraEnabled public String referenceTo { get; set; }

        public FieldOption(String label, String apiName, String fieldType, Boolean isRequired, String referenceTo) {
            this.label = label;
            this.apiName = apiName;
            this.fieldType = fieldType;
            this.isRequired = isRequired;
            this.referenceTo = referenceTo;
        }

        public Integer compareTo(Object other) {
            return this.label.compareTo(((FieldOption) other).label);
        }
    }
}