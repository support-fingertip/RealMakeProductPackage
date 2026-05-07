public with sharing class FieldMapperController {
    
    @AuraEnabled(cacheable=true)
    public static List<ObjectInfo> getObjectList() {
        List<ObjectInfo> objectList = new List<ObjectInfo>();
        
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        
        for (String objName : globalDescribe.keySet()) {
            Schema.SObjectType objType = globalDescribe.get(objName);
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            
            if (objDescribe.isCreateable() && objDescribe.isUpdateable() && 
                (objDescribe.isCustom() || isCommonStandardObject(objName))) {
                objectList.add(new ObjectInfo(objDescribe.getLabel(), objDescribe.getName()));
            }
        }
        
        objectList.sort();
        return objectList;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getFieldList(String objectApiName) {
        List<FieldInfo> fieldList = new List<FieldInfo>();
        
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) {
            return fieldList;
        }
        
        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            
            if (fieldDescribe.isAccessible()) {
                String fieldType = String.valueOf(fieldDescribe.getType());
                String referenceTo = null;
                
                if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE && 
                    !fieldDescribe.getReferenceTo().isEmpty()) {
                    referenceTo = fieldDescribe.getReferenceTo()[0].getDescribe().getName();
                }
                
                fieldList.add(new FieldInfo(
                    fieldDescribe.getLabel(),
                    fieldDescribe.getName(),
                    fieldType,
                    referenceTo
                ));
            }
        }
        
        fieldList.sort();
        return fieldList;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getCompatibleFields(String objectApiName, String fieldType) {
        List<FieldInfo> compatibleFields = new List<FieldInfo>();
        
        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) {
            return compatibleFields;
        }
        
        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        Set<String> compatibleTypes = getCompatibleFieldTypes(fieldType);
        
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            String targetFieldType = String.valueOf(fieldDescribe.getType());
            
            if ((fieldDescribe.isUpdateable() || fieldDescribe.isCreateable()) && 
                compatibleTypes.contains(targetFieldType)) {
                compatibleFields.add(new FieldInfo(
                    fieldDescribe.getLabel(),
                    fieldDescribe.getName(),
                    targetFieldType,
                    null
                ));
            }
        }
        
        compatibleFields.sort();
        return compatibleFields;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<MappingConfigWrapper> getAllMappingConfigurations() {
        List<MappingConfigWrapper> result = new List<MappingConfigWrapper>();
        for (Field_Mapping_Configuration__c cfg : [
            SELECT Id, Name, From_Object__c, To_Object__c, Is_Active__c, Mapping_Trigger__c,
                   CreatedDate, LastModifiedDate,
                   (SELECT Id FROM Field_Mapping_Details__r)
            FROM Field_Mapping_Configuration__c
            ORDER BY LastModifiedDate DESC
        ]) {
            MappingConfigWrapper w = new MappingConfigWrapper();
            w.id = cfg.Id;
            w.name = cfg.Name;
            w.fromObject = cfg.From_Object__c;
            w.toObject = cfg.To_Object__c;
            w.isActive = cfg.Is_Active__c;
            w.mappingTrigger = cfg.Mapping_Trigger__c;
            w.fieldCount = cfg.Field_Mapping_Details__r.size();
            result.add(w);
        }
        return result;
    }

    @AuraEnabled
    public static void deleteMappingConfiguration(String configId) {
        if (String.isBlank(configId)) {
            throw new AuraHandledException('Configuration ID is required');
        }
        delete [SELECT Id FROM Field_Mapping_Configuration__c WHERE Id = :configId LIMIT 1];
    }

    @AuraEnabled
    public static void saveMappingConfiguration(String configData) {
        Map<String, Object> config = (Map<String, Object>) JSON.deserializeUntyped(configData);
        
        String mappingName = (String) config.get('mappingName');
        String fromObject = (String) config.get('fromObject');
        String toObject = (String) config.get('toObject');
        String lookupField = (String) config.get('lookupField');
        Boolean isActive = (Boolean) config.get('isActive');
        String mappingTrigger = (String) config.get('mappingTrigger');
        String mappingDetailsJson = (String) config.get('mappingDetails');
        
        if (isActive) {
            List<Field_Mapping_Configuration__c> existingActive = [
                SELECT Id 
                FROM Field_Mapping_Configuration__c 
                WHERE From_Object__c = :fromObject 
                AND To_Object__c = :toObject 
                AND Is_Active__c = true
                LIMIT 1
            ];
            
            if (!existingActive.isEmpty()) {
                throw new AuraHandledException('An active mapping already exists for this From-To object combination. Please deactivate the existing mapping first.');
            }
        }
        
        Field_Mapping_Configuration__c configRecord = new Field_Mapping_Configuration__c(
            Name = mappingName,
            From_Object__c = fromObject,
            To_Object__c = toObject,
            Is_Active__c = isActive,
            Mapping_Trigger__c = mappingTrigger
        );
        
        insert configRecord;
        
        List<Object> mappingDetails = (List<Object>) JSON.deserializeUntyped(mappingDetailsJson);
        List<Field_Mapping_Detail__c> detailRecords = new List<Field_Mapping_Detail__c>();
        
        for (Object detail : mappingDetails) {
            Map<String, Object> detailMap = (Map<String, Object>) detail;
            
            Field_Mapping_Detail__c detailRecord = new Field_Mapping_Detail__c(
                Field_Mapping_Configuration__c = configRecord.Id,
                From_Field_API_Name__c = (String) detailMap.get('fromField'),
                To_Field_API_Name__c = (String) detailMap.get('toField'),
                From_Field_Type__c = (String) detailMap.get('fromFieldType'),
                To_Field_Type__c = (String) detailMap.get('toFieldType'),
                Sequence__c = (Integer) detailMap.get('sequence')
            );
            
            detailRecords.add(detailRecord);
        }
        
        if (!detailRecords.isEmpty()) {
            insert detailRecords;
        }
    }
    
    private static final Set<String> COMMON_STANDARD_OBJECTS = new Set<String>{
        'account', 'contact', 'opportunity', 'lead', 'case',
        'task', 'event', 'campaign', 'product2', 'pricebook2',
        'order', 'quote', 'contract', 'asset'
    };

    private static Boolean isCommonStandardObject(String objName) {
        return COMMON_STANDARD_OBJECTS.contains(objName.toLowerCase());
    }
    
    private static Set<String> getCompatibleFieldTypes(String sourceType) {
        Map<String, Set<String>> compatibilityMap = new Map<String, Set<String>>{
            'STRING' => new Set<String>{'STRING', 'TEXTAREA', 'PICKLIST', 'EMAIL', 'PHONE', 'URL'},
            'TEXTAREA' => new Set<String>{'STRING', 'TEXTAREA'},
            'PICKLIST' => new Set<String>{'STRING', 'PICKLIST', 'TEXTAREA'},
            'MULTIPICKLIST' => new Set<String>{'STRING', 'MULTIPICKLIST', 'TEXTAREA'},
            'BOOLEAN' => new Set<String>{'BOOLEAN'},
            'INTEGER' => new Set<String>{'INTEGER', 'DOUBLE', 'CURRENCY', 'PERCENT'},
            'DOUBLE' => new Set<String>{'DOUBLE', 'CURRENCY', 'PERCENT', 'INTEGER'},
            'CURRENCY' => new Set<String>{'CURRENCY', 'DOUBLE', 'PERCENT', 'INTEGER'},
            'PERCENT' => new Set<String>{'PERCENT', 'DOUBLE', 'CURRENCY', 'INTEGER'},
            'DATE' => new Set<String>{'DATE', 'DATETIME'},
            'DATETIME' => new Set<String>{'DATETIME', 'DATE'},
            'TIME' => new Set<String>{'TIME'},
            'EMAIL' => new Set<String>{'EMAIL', 'STRING', 'TEXTAREA'},
            'PHONE' => new Set<String>{'PHONE', 'STRING', 'TEXTAREA'},
            'URL' => new Set<String>{'URL', 'STRING', 'TEXTAREA'},
            'REFERENCE' => new Set<String>{'REFERENCE'},
            'ID' => new Set<String>{'ID', 'STRING', 'TEXTAREA'}
        };
        
        return compatibilityMap.containsKey(sourceType) ? 
               compatibilityMap.get(sourceType) : 
               new Set<String>{sourceType};
    }
    
    public class ObjectInfo implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }
        
        public ObjectInfo(String label, String apiName) {
            this.label = label;
            this.apiName = apiName;
        }
        
        public Integer compareTo(Object other) {
            ObjectInfo otherObj = (ObjectInfo) other;
            return this.label.compareTo(otherObj.label);
        }
    }
    
    public class MappingConfigWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String fromObject { get; set; }
        @AuraEnabled public String toObject { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String mappingTrigger { get; set; }
        @AuraEnabled public Integer fieldCount { get; set; }
    }

    public class FieldInfo implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String apiName { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String referenceTo { get; set; }
        
        public FieldInfo(String label, String apiName, String type, String referenceTo) {
            this.label = label;
            this.apiName = apiName;
            this.type = type;
            this.referenceTo = referenceTo;
        }
        
        public Integer compareTo(Object other) {
            FieldInfo otherField = (FieldInfo) other;
            return this.label.compareTo(otherField.label);
        }
    }
}