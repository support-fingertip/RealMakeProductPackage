/**
 * @description Controller to dynamically fetch objects and fields for email template builder
 * ENHANCED: Now supports related object relationships for VF page attachments
 * @author Your Name
 * @date 2024
 */
public with sharing class EmailFieldPickerController {
    
    // ============ WRAPPER CLASSES ============
    
    public class ObjectWrapper implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        
        public ObjectWrapper(String label, String value) {
            this.label = label;
            this.value = value;
        }
        
        public Integer compareTo(Object compareTo) {
            ObjectWrapper other = (ObjectWrapper) compareTo;
            if (this.label == null && other.label == null) return 0;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }
    
    public class FieldWrapper implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String objectName { get; set; }
        @AuraEnabled public String relationshipName { get; set; }
        @AuraEnabled public String referenceTo { get; set; }
        @AuraEnabled public Boolean isEmail { get; set; }
        @AuraEnabled public Boolean isReference { get; set; }
        
        public FieldWrapper() {
            this.isEmail = false;
            this.isReference = false;
        }
        
        public Integer compareTo(Object compareTo) {
            FieldWrapper other = (FieldWrapper) compareTo;
            if (this.label == null && other.label == null) return 0;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }
    
    public class RelationshipWrapper implements Comparable {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String relationshipType { get; set; }
        @AuraEnabled public String relationshipName { get; set; }
        @AuraEnabled public String relatedObjectApi { get; set; }
        
        public RelationshipWrapper(String label, String value, String relationshipType, 
                                   String relationshipName, String relatedObjectApi) {
            this.label = label;
            this.value = value;
            this.relationshipType = relationshipType;
            this.relationshipName = relationshipName;
            this.relatedObjectApi = relatedObjectApi;
        }
        
        public Integer compareTo(Object compareTo) {
            RelationshipWrapper other = (RelationshipWrapper) compareTo;
            if (this.relationshipType != other.relationshipType) {
                return this.relationshipType.compareTo(other.relationshipType);
            }
            if (this.label == null && other.label == null) return 0;
            if (this.label == null) return -1;
            if (other.label == null) return 1;
            return this.label.toLowerCase().compareTo(other.label.toLowerCase());
        }
    }
    
    // ============ GET ALL OBJECTS ============
    
    @AuraEnabled(cacheable=true)
    public static List<ObjectWrapper> getAllObjects() {
        List<ObjectWrapper> objects = new List<ObjectWrapper>();
        
        try {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            
            for (String objectName : globalDescribe.keySet()) {
                Schema.SObjectType sObjectType = globalDescribe.get(objectName);
                Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
                
                if (describeResult.isAccessible() && 
                    describeResult.isQueryable() && 
                    !describeResult.isDeprecatedAndHidden() &&
                    !isSystemObject(objectName)) {
                    
                    objects.add(new ObjectWrapper(
                        describeResult.getLabel(),
                        describeResult.getName()
                    ));
                }
            }
            
            objects.sort();
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching objects: ' + e.getMessage());
        }
        
        return objects;
    }
    
    private static Boolean isSystemObject(String objectName) {
        Set<String> excludedPrefixes = new Set<String>{
            'ApexTestResult', 'AsyncApexJob', 'CronTrigger', 'CronJobDetail',
            'LoginHistory', 'SetupAuditTrail', 'StaticResource', 'ApexClass',
            'ApexTrigger', 'ApexPage', 'ApexComponent', 'Profile', 'PermissionSet',
            'EntityDefinition', 'FieldDefinition', 'Publisher', 'PlatformEvent'
        };
        
        for (String prefix : excludedPrefixes) {
            if (objectName.startsWithIgnoreCase(prefix)) {
                return true;
            }
        }
        
        if (objectName.endsWith('Share') || 
            objectName.endsWith('History') || 
            objectName.endsWith('Feed') || 
            objectName.endsWith('Tag') ||
            objectName.endsWith('ChangeEvent')) {
            return true;
        }
        
        return false;
    }
    
    // ============ GET FIELDS FOR OBJECT ============
    
    /**
     * CRITICAL: Changed from cacheable=true to cacheable=false
     * This fixes the field dropdown not populating issue
     */
    @AuraEnabled(cacheable=false)
    public static List<FieldWrapper> getFieldsForObject(String objectApiName) {
        List<FieldWrapper> fields = new List<FieldWrapper>();
        
        try {
            if (String.isBlank(objectApiName)) {
                return fields;
            }
            
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }
            
            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
            
            for (String fieldName : fieldMap.keySet()) {
                Schema.SObjectField field = fieldMap.get(fieldName);
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
                
                if (fieldDescribe.isAccessible()) {
                    FieldWrapper fw = new FieldWrapper();
                    fw.label = fieldDescribe.getLabel();
                    fw.value = fieldDescribe.getName();
                    fw.type = String.valueOf(fieldDescribe.getType());
                    fw.objectName = objectApiName;
                    fw.isEmail = (fieldDescribe.getType() == Schema.DisplayType.EMAIL);
                    fw.isReference = (fieldDescribe.getType() == Schema.DisplayType.REFERENCE);
                    
                    if (fw.isReference) {
                        fw.relationshipName = fieldDescribe.getRelationshipName();
                        List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();
                        if (!referenceTo.isEmpty()) {
                            fw.referenceTo = referenceTo[0].getDescribe().getName();
                        }
                    }
                    
                    fields.add(fw);
                }
            }
            
            fields.sort();
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching fields: ' + e.getMessage());
        }
        
        return fields;
    }
    
    // ============ GET EMAIL FIELDS ONLY ============
    
    @AuraEnabled(cacheable=true)
    public static List<FieldWrapper> getEmailFieldsForObject(String objectApiName) {
        List<FieldWrapper> emailFields = new List<FieldWrapper>();
        
        try {
            List<FieldWrapper> allFields = getFieldsForObject(objectApiName);
            
            for (FieldWrapper field : allFields) {
                if (field.isEmail) {
                    emailFields.add(field);
                }
            }
            
            List<FieldWrapper> relatedEmailFields = getRelatedEmailFields(objectApiName, 3);
            emailFields.addAll(relatedEmailFields);
            
            emailFields.sort();
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching email fields: ' + e.getMessage());
        }
        
        return emailFields;
    }
    
    private static List<FieldWrapper> getRelatedEmailFields(String objectApiName, Integer maxLevels) {
        List<FieldWrapper> relatedFields = new List<FieldWrapper>();
        
        try {
            List<FieldWrapper> level1Fields = getFieldsForObject(objectApiName);
            
            for (FieldWrapper field : level1Fields) {
                if (field.isReference && String.isNotBlank(field.referenceTo) && String.isNotBlank(field.relationshipName)) {
                    List<FieldWrapper> relatedObjFields = getFieldsForObject(field.referenceTo);
                    
                    for (FieldWrapper relField : relatedObjFields) {
                        if (relField.isEmail) {
                            FieldWrapper fw = new FieldWrapper();
                            fw.label = field.label + ' → ' + relField.label;
                            fw.value = field.relationshipName + '.' + relField.value;
                            fw.type = 'EMAIL';
                            fw.objectName = objectApiName;
                            fw.isEmail = true;
                            relatedFields.add(fw);
                        }
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error getting related email fields: ' + e.getMessage());
        }
        
        return relatedFields;
    }
    
    // ============ GET MERGE FIELDS ============
    
    @AuraEnabled(cacheable=true)
    public static List<FieldWrapper> getMergeFieldsForObject(String objectApiName) {
        List<FieldWrapper> mergeFields = new List<FieldWrapper>();
        
        try {
            List<FieldWrapper> level1Fields = getFieldsForObject(objectApiName);
            for (FieldWrapper field : level1Fields) {
                if (!field.isReference) {
                    mergeFields.add(field);
                }
            }
            
            for (FieldWrapper field : level1Fields) {
                if (field.isReference && String.isNotBlank(field.referenceTo) && String.isNotBlank(field.relationshipName)) {
                    List<FieldWrapper> level2Fields = getFieldsForObject(field.referenceTo);
                    
                    for (FieldWrapper l2Field : level2Fields) {
                        if (!l2Field.isReference) {
                            FieldWrapper fw = new FieldWrapper();
                            fw.label = field.label + ' → ' + l2Field.label;
                            fw.value = field.relationshipName + '.' + l2Field.value;
                            fw.type = l2Field.type;
                            fw.objectName = objectApiName;
                            mergeFields.add(fw);
                        }
                    }
                }
            }
            
            mergeFields.sort();
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching merge fields: ' + e.getMessage());
        }
        return mergeFields;
    }
    
    // ============ GET ORG-WIDE EMAIL ADDRESSES ============
    
    @AuraEnabled(cacheable=true)
    public static List<ObjectWrapper> getOrgWideEmailAddresses() {
        List<ObjectWrapper> addresses = new List<ObjectWrapper>();
        
        try {
            List<OrgWideEmailAddress> oweas = [
                SELECT Id, DisplayName, Address 
                FROM OrgWideEmailAddress 
                WHERE IsAllowAllProfiles = true
                ORDER BY DisplayName
            ];
            
            for (OrgWideEmailAddress owea : oweas) {
                addresses.add(new ObjectWrapper(
                    owea.DisplayName + ' <' + owea.Address + '>',
                    owea.Id
                ));
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching org-wide emails: ' + e.getMessage());
        }
        
        return addresses;
    }
    
    // ============ GET VISUALFORCE PAGES ============
    
    @AuraEnabled(cacheable=true)
    public static List<ObjectWrapper> getVisualforcePages() {
        List<ObjectWrapper> pages = new List<ObjectWrapper>();
        
        try {
            List<ApexPage> vfPages = [
                SELECT Id, Name, NamespacePrefix, MasterLabel
                FROM ApexPage
                ORDER BY Name
            ];
            
            for (ApexPage page : vfPages) {
                String displayName = String.isNotBlank(page.MasterLabel) ? page.MasterLabel : page.Name;
                String apiName = String.isNotBlank(page.NamespacePrefix) 
                    ? page.NamespacePrefix + '__' + page.Name 
                    : page.Name;
                    
                pages.add(new ObjectWrapper(displayName, apiName));
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching VF pages: ' + e.getMessage());
        }
        
        return pages;
    }
    
    // ============ GET RELATED OBJECTS (PARENT & CHILD) ============
    
    @AuraEnabled(cacheable=true)
    public static List<RelationshipWrapper> getRelatedObjects(String objectApiName) {
        List<RelationshipWrapper> relationships = new List<RelationshipWrapper>();
        
        try {
            if (String.isBlank(objectApiName)) {
                return relationships;
            }
            
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            if (sObjectType == null) {
                throw new AuraHandledException('Object not found: ' + objectApiName);
            }
            
            Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
            
            // Get Parent Relationships
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
                
                if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE && 
                    fieldDescribe.isAccessible() &&
                    String.isNotBlank(fieldDescribe.getRelationshipName())) {
                    
                    List<Schema.SObjectType> referenceTo = fieldDescribe.getReferenceTo();
                    if (!referenceTo.isEmpty()) {
                        Schema.SObjectType parentType = referenceTo[0];
                        Schema.DescribeSObjectResult parentDescribe = parentType.getDescribe();
                        
                        if (!isSystemObject(parentDescribe.getName())) {
                            relationships.add(new RelationshipWrapper(
                                '⬆️ Parent: ' + fieldDescribe.getLabel() + ' (' + parentDescribe.getLabel() + ')',
                                'parent_' + fieldDescribe.getName(),
                                'Parent',
                                fieldDescribe.getName(),
                                parentDescribe.getName()
                            ));
                        }
                    }
                }
            }
            
            // Get Child Relationships
            List<Schema.ChildRelationship> childRelationships = describeResult.getChildRelationships();
            for (Schema.ChildRelationship childRel : childRelationships) {
                if (childRel.getRelationshipName() != null && 
                    childRel.getChildSObject() != null) {
                    
                    Schema.DescribeSObjectResult childDescribe = childRel.getChildSObject().getDescribe();
                    
                    if (childDescribe.isAccessible() && 
                        !isSystemObject(childDescribe.getName())) {
                        
                        relationships.add(new RelationshipWrapper(
                            '⬇️ Child: ' + childDescribe.getLabelPlural() + ' (' + childRel.getRelationshipName() + ')',
                            'child_' + childRel.getRelationshipName(),
                            'Child',
                            childRel.getField().getDescribe().getName(),
                            childDescribe.getName()
                        ));
                    }
                }
            }
            
            relationships.sort();
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching related objects: ' + e.getMessage());
        }
        
        return relationships;
    }
    
    // ============ SEARCH RECORDS ============
    
    @AuraEnabled
    public static List<ObjectWrapper> searchRecords(String objectApiName, String searchTerm) {
        List<ObjectWrapper> records = new List<ObjectWrapper>();
        
        try {
            if (String.isBlank(objectApiName)) {
                return records;
            }
            
            String nameField = getNameField(objectApiName);
            String query = 'SELECT Id, ' + String.escapeSingleQuotes(nameField) + 
                          ' FROM ' + String.escapeSingleQuotes(objectApiName);
            
            if (String.isNotBlank(searchTerm) && searchTerm.length() >= 2) {
                String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
                query += ' WHERE ' + nameField + ' LIKE :searchPattern';
            }
            
            query += ' ORDER BY ' + nameField + ' LIMIT 20';
            
            List<SObject> results = Database.query(query);
            
            for (SObject record : results) {
                records.add(new ObjectWrapper(
                    String.valueOf(record.get(nameField)),
                    record.Id
                ));
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error searching records: ' + e.getMessage());
        }
        
        return records;
    }
    
    private static String getNameField(String objectApiName) {
        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        Schema.DescribeSObjectResult describeResult = sObjectType.getDescribe();
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        
        if (fieldMap.containsKey('Name')) return 'Name';
        
        List<String> commonNameFields = new List<String>{'Subject', 'Title', 'CaseNumber', 'ContractNumber'};
        for (String fieldName : commonNameFields) {
            if (fieldMap.containsKey(fieldName.toLowerCase())) {
                return fieldName;
            }
        }
        
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            if (fieldDescribe.isAccessible() && 
                fieldDescribe.getType() == Schema.DisplayType.STRING) {
                return fieldDescribe.getName();
            }
        }
        
        return 'Id';
    }
}