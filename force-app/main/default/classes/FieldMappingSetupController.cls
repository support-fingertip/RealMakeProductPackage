public with sharing class FieldMappingSetupController {

    @AuraEnabled(cacheable=true)
    public static List<General_Setup__c> getGeneralSetups() {
        return [
            SELECT Id, Name, Push_To_Sales_Type__c, Lead_Duplication_Type__c, Is_Active__c, Description__c,
                   CreatedDate, LastModifiedDate
            FROM General_Setup__c
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static General_Setup__c getGeneralSetupWithMappings(Id setupId) {
        return [
            SELECT Id, Name, Push_To_Sales_Type__c, Lead_Duplication_Type__c, Is_Active__c, Description__c,
                   (SELECT Id, Primary_Object_Field_value__c, Related_object_field__c,
                           Mapping_Type__c, Sequence__c, Active__c
                    FROM Field_Mappings__r
                    ORDER BY Sequence__c ASC)
            FROM General_Setup__c
            WHERE Id = :setupId
            LIMIT 1
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getLeadFields() {
        List<FieldOption> fieldOptions = new List<FieldOption>();

        Schema.SObjectType leadType = NamespaceUtil.describeObject('Lead__c');
        if (leadType == null) {
            return fieldOptions;
        }

        Map<String, Schema.SObjectField> fieldMap = leadType.getDescribe().fields.getMap();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();

            if (fieldDescribe.isAccessible() && !fieldDescribe.isCalculated()) {
                fieldOptions.add(new FieldOption(
                    fieldDescribe.getLabel(),
                    fieldDescribe.getName(),
                    String.valueOf(fieldDescribe.getType()),
                    fieldDescribe.isUpdateable()
                ));
            }
        }

        fieldOptions.sort();
        return fieldOptions;
    }

    @AuraEnabled
    public static Id saveGeneralSetup(String setupData) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(setupData);

        General_Setup__c setup = new General_Setup__c();

        if (data.containsKey('id') && data.get('id') != null) {
            setup.Id = (Id) data.get('id');
        }

        setup.Push_To_Sales_Type__c = (String) data.get('pushToSalesType');
        setup.Lead_Duplication_Type__c = (String) data.get('leadDuplicationType');
        setup.Is_Active__c = (Boolean) data.get('isActive');
        setup.Description__c = (String) data.get('description');

        upsert setup;
        return setup.Id;
    }

    @AuraEnabled
    public static void saveFieldMappings(Id generalSetupId, String mappingsJson) {
        List<Object> mappings = (List<Object>) JSON.deserializeUntyped(mappingsJson);

        // Collect existing mapping IDs to determine which to delete
        Set<Id> incomingIds = new Set<Id>();
        List<Field_Mapping__c> toUpsert = new List<Field_Mapping__c>();

        for (Object mappingObj : mappings) {
            Map<String, Object> m = (Map<String, Object>) mappingObj;

            Field_Mapping__c fm = new Field_Mapping__c();

            if (m.containsKey('id') && m.get('id') != null && String.isNotBlank((String) m.get('id'))) {
                fm.Id = (Id) m.get('id');
                incomingIds.add(fm.Id);
            }

            fm.General_Setup__c = generalSetupId;
            fm.Primary_Object_Field_value__c = (String) m.get('sourceField');
            fm.Related_object_field__c = (String) m.get('targetField');
            fm.GS_Source_Field_API_Name__c = 'Lead__c';
            fm.GS_Target_Field_API_Name__c = 'Lead__c';
            fm.Mapping_Type__c = (String) m.get('mappingType');
            fm.Sequence__c = (Decimal) m.get('sequence');
            fm.Active__c = (Boolean) m.get('isActive');

            toUpsert.add(fm);
        }

        // Delete mappings that were removed from the UI
        List<Field_Mapping__c> existingMappings = [
            SELECT Id FROM Field_Mapping__c
            WHERE General_Setup__c = :generalSetupId
            AND Id NOT IN :incomingIds
        ];

        if (!existingMappings.isEmpty()) {
            delete existingMappings;
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
    }

    @AuraEnabled
    public static void deleteFieldMapping(Id mappingId) {
        Field_Mapping__c fm = [SELECT Id FROM Field_Mapping__c WHERE Id = :mappingId LIMIT 1];
        delete fm;
    }

    @AuraEnabled
    public static void deleteGeneralSetup(Id setupId) {
        // Delete child mappings first
        List<Field_Mapping__c> childMappings = [
            SELECT Id FROM Field_Mapping__c WHERE General_Setup__c = :setupId
        ];
        if (!childMappings.isEmpty()) {
            delete childMappings;
        }

        General_Setup__c setup = [SELECT Id FROM General_Setup__c WHERE Id = :setupId LIMIT 1];
        delete setup;
    }

    public class FieldOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public Boolean isUpdateable { get; set; }

        public FieldOption(String label, String apiName, String fieldType, Boolean isUpdateable) {
            this.label = label;
            this.apiName = apiName;
            this.fieldType = fieldType;
            this.isUpdateable = isUpdateable;
        }

        public Integer compareTo(Object other) {
            FieldOption otherField = (FieldOption) other;
            return this.label.compareTo(otherField.label);
        }
    }
}