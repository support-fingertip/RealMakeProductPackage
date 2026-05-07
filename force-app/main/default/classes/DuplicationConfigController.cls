public with sharing class DuplicationConfigController {
    
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAllObjects() {
        List<ObjectOption> objectOptions = new List<ObjectOption>();
        
        for (Schema.SObjectType objType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            
            // Filter out system objects and include only relevant ones
            if (objDescribe.isCreateable() && objDescribe.isQueryable()) {
                objectOptions.add(new ObjectOption(
                    objDescribe.getLabel(),
                    objDescribe.getName()
                ));
            }
        }
        
        // Sort alphabetically
        objectOptions.sort();
        return objectOptions;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getObjectFields(String objectApiName) {
        List<FieldOption> fieldOptions = new List<FieldOption>();
        
        try {
            Schema.SObjectType objType = NamespaceUtil.describeObject(objectApiName);
            if (objType != null) {
                Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
                
                for (String fieldName : fieldMap.keySet()) {
                    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                    
                    // Include accessible fields
                    if (fieldDescribe.isAccessible()) {
                        fieldOptions.add(new FieldOption(
                            fieldDescribe.getLabel(),
                            fieldDescribe.getName(),
                            String.valueOf(fieldDescribe.getType())
                        ));
                    }
                }
                
                // Sort alphabetically
                fieldOptions.sort();
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching fields: ' + e.getMessage());
        }
        
        return fieldOptions;
    }
    
    @AuraEnabled
    public static List<FieldOption> getRelatedObjectFieldsImperative(String objectApiName) {
        return getObjectFields(objectApiName);
    }

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getRelatedObjects(String objectApiName) {
        List<ObjectOption> relatedObjects = new List<ObjectOption>();
        
        try {
            Schema.SObjectType objType = NamespaceUtil.describeObject(objectApiName);
            if (objType != null) {
                Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
                List<Schema.ChildRelationship> childRelationships = objDescribe.getChildRelationships();
                
                // Add child relationships
                for (Schema.ChildRelationship rel : childRelationships) {
                    if (rel.getRelationshipName() != null) {
                        Schema.DescribeSObjectResult childObjDescribe = rel.getChildSObject().getDescribe();
                        relatedObjects.add(new ObjectOption(
                            childObjDescribe.getLabel() + ' (' + rel.getRelationshipName() + ')',
                            childObjDescribe.getName()
                        ));
                    }
                }
                
                // Also include all objects for lookup relationships
                relatedObjects.addAll(getAllObjects());
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching related objects: ' + e.getMessage());
        }
        
        return relatedObjects;
    }
    
    @AuraEnabled
    public static String saveConfiguration(String configData) {
        try {
            // Parse the configuration data
            Map<String, Object> configMap = (Map<String, Object>) JSON.deserializeUntyped(configData);
            
            String primaryObject = (String) configMap.get('primaryObject');
            String primaryExpression = (String) configMap.get('primaryExpression');
            String relatedObject = (String) configMap.get('relatedObject');
            String relatedExpression = (String) configMap.get('relatedExpression');
            List<Object> fieldMappings = (List<Object>) configMap.get('fieldMappings');
            String configId = (String) configMap.get('configId');
            Boolean isEdit = String.isNotBlank(configId);

            Duplication_Configuration__c config;

            if (isEdit) {
                // Update existing configuration
                config = [SELECT Id, Name FROM Duplication_Configuration__c WHERE Id = :configId LIMIT 1];
            } else {
                // Create new Duplication Configuration record
                config = new Duplication_Configuration__c();
                config.Name = primaryObject + ' - Duplication Rule';
            }

            config.Primary_Object_API_Name__c = primaryObject;
            config.Primary_Expression__c = primaryExpression;
            config.Active__c = true;

            if (String.isNotBlank(relatedObject)) {
                config.Related_Object_API_Name__c = relatedObject;
                config.Related_Expression__c = relatedExpression;
            } else {
                config.Related_Object_API_Name__c = null;
                config.Related_Expression__c = null;
            }

            config.Description__c = 'Primary: ' + primaryExpression +
                (String.isNotBlank(relatedObject) ? '\nRelated (' + relatedObject + '): ' + relatedExpression : '');

            if (isEdit) {
                // Delete old field mappings before re-creating
                List<Field_Mapping__c> oldMappings = [
                    SELECT Id FROM Field_Mapping__c WHERE Duplication_Configuration__c = :configId
                ];
                if (!oldMappings.isEmpty()) {
                    delete oldMappings;
                }
                update config;
            } else {
                // Deactivate any existing active configurations for the same Primary Object
                List<Duplication_Configuration__c> existingActiveConfigs = [
                    SELECT Id, Active__c
                    FROM Duplication_Configuration__c
                    WHERE Primary_Object_API_Name__c = :primaryObject
                    AND Active__c = true
                ];
                if (!existingActiveConfigs.isEmpty()) {
                    for (Duplication_Configuration__c existing : existingActiveConfigs) {
                        existing.Active__c = false;
                    }
                    update existingActiveConfigs;
                }
                insert config;
            }
            
            // Create Field Mapping records if field mappings exist
            Integer mappingCount = 0;
            if (fieldMappings != null && !fieldMappings.isEmpty()) {
                List<Field_Mapping__c> mappingRecords = new List<Field_Mapping__c>();
                Integer sequence = 1;
                
                for (Object mappingObj : fieldMappings) {
                    Map<String, Object> mapping = (Map<String, Object>) mappingObj;
                    
                    Field_Mapping__c fieldMapping = new Field_Mapping__c();
                    fieldMapping.Duplication_Configuration__c = config.Id;
                    fieldMapping.Related_Object_Field__c = (String) mapping.get('relatedField');
                    fieldMapping.Mapping_Type__c = (String) mapping.get('mappingType');
                    fieldMapping.Primary_Object_Field_value__c = (String) mapping.get('sourceValue');
                    fieldMapping.Sequence__c = sequence++;
                    fieldMapping.Active__c = true;
                    
                    mappingRecords.add(fieldMapping);
                }
                
                if (!mappingRecords.isEmpty()) {
                    insert mappingRecords;
                    mappingCount = mappingRecords.size();
                }
            }
            
            String successMessage = 'Configuration saved successfully with ID: ' + config.Id;
            if (mappingCount > 0) {
                successMessage += '\n' + mappingCount + ' field mapping(s) created.';
            }
            
            return successMessage;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error saving configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Duplication_Configuration__c> getConfigurationsByObject(String objectApiName) {
        try {
            return [
                SELECT Id, Name, Primary_Object_API_Name__c, Primary_Expression__c, 
                       Related_Object_API_Name__c, Related_Expression__c, Active__c, Description__c
                FROM Duplication_Configuration__c
                WHERE Primary_Object_API_Name__c = :objectApiName
                AND Active__c = true
                ORDER BY CreatedDate DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching configurations: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> getConfigurationWithMappings(Id configId) {
        try {
            Duplication_Configuration__c config = [
                SELECT Id, Name, Primary_Object_API_Name__c, Primary_Expression__c,
                       Related_Object_API_Name__c, Related_Expression__c, Active__c, Description__c
                FROM Duplication_Configuration__c
                WHERE Id = :configId
                LIMIT 1
            ];

            List<Field_Mapping__c> mappings = [
                SELECT Id, Related_Object_Field__c, Mapping_Type__c,
                       Primary_Object_Field_value__c, Sequence__c, Active__c
                FROM Field_Mapping__c
                WHERE Duplication_Configuration__c = :configId
                ORDER BY Sequence__c ASC
            ];

            Map<String, Object> result = new Map<String, Object>();
            result.put('config', config);
            result.put('mappings', mappings);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading configuration: ' + e.getMessage());
        }
    }

    // Wrapper classes
    public class ObjectOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        
        public ObjectOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
        
        public Integer compareTo(Object compareTo) {
            ObjectOption compareToObj = (ObjectOption)compareTo;
            return this.label.compareTo(compareToObj.label);
        }
    }
    
    public class FieldOption implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String type { get; set; }
        
        public FieldOption(String label, String value, String type) {
            this.label = label;
            this.value = value;
            this.type = type;
        }
        
        public Integer compareTo(Object compareTo) {
            FieldOption compareToObj = (FieldOption)compareTo;
            return this.label.compareTo(compareToObj.label);
        }
    }
}