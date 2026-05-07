/**
 * ════════════════════════════════════════════════════════════════════════════
 * LeadScoringDesignerController
 * ════════════════════════════════════════════════════════════════════════════
 * Apex controller for the leadScoringDesigner LWC.
 *
 * Provides:
 *   - Dynamic Lead__c field describe (labels, API names, types)
 *   - Picklist value retrieval for any Lead__c field
 *   - CRUD operations for Lead_Score_Rule__c and Lead_Score_Tier__c
 *   - Related object discovery (objects with lookup to Lead__c)
 * ════════════════════════════════════════════════════════════════════════════
 */
public with sharing class LeadScoringDesignerController {

    // ════════════════════════════════════════════════════════════════════
    //  FIELD DESCRIBE
    // ════════════════════════════════════════════════════════════════════

    /**
     * Returns metadata for all fields on Lead__c.
     * Used by the left panel to display available fields.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getLeadFields() {
        List<FieldInfo> fields = new List<FieldInfo>();

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Lead__c.fields.getMap();

        for (String apiName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(apiName).getDescribe();

            // Skip system fields that aren't useful for scoring
            if (dfr.isAutoNumber() || !dfr.isAccessible()) continue;

            FieldInfo fi = new FieldInfo();
            fi.apiName = dfr.getName();
            fi.label = dfr.getLabel();
            fi.fieldType = dfr.getType().name();
            fi.isPicklist = (dfr.getType() == Schema.DisplayType.PICKLIST
                          || dfr.getType() == Schema.DisplayType.MULTIPICKLIST);
            fi.isLookup = (dfr.getType() == Schema.DisplayType.REFERENCE);

            fields.add(fi);
        }

        fields.sort();
        return fields;
    }

    /**
     * Returns picklist values for a given Lead__c field.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getPicklistValues(String fieldApiName) {
        List<PicklistOption> options = new List<PicklistOption>();
        if (String.isBlank(fieldApiName)) return options;

        Schema.SObjectField field = NamespaceUtil.describeField(Lead__c.SObjectType, fieldApiName);
        if (field == null) return options;

        Schema.DescribeFieldResult dfr = field.getDescribe();
        if (dfr.getType() != Schema.DisplayType.PICKLIST
            && dfr.getType() != Schema.DisplayType.MULTIPICKLIST) {
            return options;
        }

        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                PicklistOption po = new PicklistOption();
                po.label = pe.getLabel();
                po.value = pe.getValue();
                options.add(po);
            }
        }

        return options;
    }

    // ════════════════════════════════════════════════════════════════════
    //  RELATED OBJECTS (for Count rules)
    // ════════════════════════════════════════════════════════════════════

    /**
     * Returns objects that have a lookup/master-detail to Lead__c.
     * Used by Count-type rules to select which child object to count.
     */
    @AuraEnabled(cacheable=true)
    public static List<RelatedObjectInfo> getRelatedObjects() {
        List<RelatedObjectInfo> relatedObjects = new List<RelatedObjectInfo>();

        // Get child relationships of Lead__c
        List<Schema.ChildRelationship> children =
            Schema.SObjectType.Lead__c.getChildRelationships();

        Set<String> addedObjects = new Set<String>();

        for (Schema.ChildRelationship cr : children) {
            Schema.SObjectType childType = cr.getChildSObject();
            String objName = childType.getDescribe().getName();
            String fieldName = cr.getField().getDescribe().getName();

            // Skip duplicates and system objects
            if (addedObjects.contains(objName)) continue;
            if (!childType.getDescribe().isAccessible()) continue;
            if (!childType.getDescribe().isCustom()) continue;

            addedObjects.add(objName);

            RelatedObjectInfo roi = new RelatedObjectInfo();
            roi.objectApiName = objName;
            roi.objectLabel = childType.getDescribe().getLabel();
            roi.lookupField = fieldName;
            relatedObjects.add(roi);
        }

        return relatedObjects;
    }

    /**
     * Returns metadata for all fields on a given object (for Count rule field filter).
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldInfo> getRelatedObjectFields(String objectApiName) {
        List<FieldInfo> fields = new List<FieldInfo>();
        if (String.isBlank(objectApiName)) return fields;

        Schema.SObjectType objType = NamespaceUtil.describeObject(objectApiName);
        if (objType == null) return fields;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        for (String apiName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(apiName).getDescribe();
            if (dfr.isAutoNumber() || !dfr.isAccessible()) continue;

            FieldInfo fi = new FieldInfo();
            fi.apiName = dfr.getName();
            fi.label = dfr.getLabel();
            fi.fieldType = dfr.getType().name();
            fi.isPicklist = (dfr.getType() == Schema.DisplayType.PICKLIST
                          || dfr.getType() == Schema.DisplayType.MULTIPICKLIST);
            fi.isLookup = (dfr.getType() == Schema.DisplayType.REFERENCE);

            if (fi.isLookup && !dfr.getReferenceTo().isEmpty()) {
                fi.referenceTo = dfr.getReferenceTo()[0].getDescribe().getName();
            }

            fields.add(fi);
        }

        fields.sort();
        return fields;
    }

    /**
     * Returns picklist values for a field on any SObject (for Count rule filter fields).
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getRelatedObjectPicklistValues(String objectApiName, String fieldApiName) {
        List<PicklistOption> options = new List<PicklistOption>();
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) return options;

        Schema.SObjectType objType = NamespaceUtil.describeObject(objectApiName);
        if (objType == null) return options;

        Schema.SObjectField field = NamespaceUtil.describeField(objType, fieldApiName);
        if (field == null) return options;

        Schema.DescribeFieldResult dfr = field.getDescribe();
        if (dfr.getType() != Schema.DisplayType.PICKLIST
            && dfr.getType() != Schema.DisplayType.MULTIPICKLIST) {
            return options;
        }

        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                PicklistOption po = new PicklistOption();
                po.label = pe.getLabel();
                po.value = pe.getValue();
                options.add(po);
            }
        }

        return options;
    }

    /**
     * Returns records from a lookup target object (for Count rule filter lookup fields).
     * Returns up to 200 records with Id and Name.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getLookupRecords(String objectApiName) {
        List<PicklistOption> options = new List<PicklistOption>();
        if (String.isBlank(objectApiName)) return options;

        Schema.SObjectType objType = NamespaceUtil.describeObject(objectApiName);
        if (objType == null || !objType.getDescribe().isAccessible()) return options;

        // Check if object has a Name field
        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        String nameField = 'Name';
        if (!fieldMap.containsKey('name')) {
            // Fallback: use Id only
            nameField = 'Id';
        }

        String query = 'SELECT Id, ' + nameField + ' FROM ' + String.escapeSingleQuotes(objectApiName)
                      + ' ORDER BY ' + nameField + ' ASC LIMIT 200';
        List<SObject> records = Database.query(query);

        for (SObject rec : records) {
            PicklistOption po = new PicklistOption();
            po.value = (String) rec.get('Id');
            po.label = (nameField == 'Id') ? (String) rec.get('Id') : (String) rec.get(nameField);
            options.add(po);
        }

        return options;
    }

    // ════════════════════════════════════════════════════════════════════
    //  SCORING RULES CRUD
    // ════════════════════════════════════════════════════════════════════

    /**
     * Returns all Lead_Score_Rule__c records ordered by sequence.
     */
    @AuraEnabled(cacheable=true)
    public static List<Lead_Score_Rule__c> getRules() {
        return [
            SELECT Id, Name, Is_Active__c, Rule_Type__c, Field_API_Name__c,
                   Field_Label__c, Operator__c, Field_Value__c, Points__c,
                   Category__c, Sequence__c, Related_Object__c,
                   Lookup_Field__c, Count_Threshold__c,
                   Filter_Field__c, Filter_Value__c
            FROM Lead_Score_Rule__c
            ORDER BY Sequence__c ASC, CreatedDate ASC
        ];
    }

    /**
     * Upserts scoring rules from the designer.
     * Accepts JSON because LWC cannot pass SObject lists with null Ids.
     */
    @AuraEnabled
    public static List<Lead_Score_Rule__c> saveRules(String rulesJSON) {
        List<Lead_Score_Rule__c> rules =
            (List<Lead_Score_Rule__c>) JSON.deserialize(rulesJSON, List<Lead_Score_Rule__c>.class);

        // Set sequence based on list order
        for (Integer i = 0; i < rules.size(); i++) {
            rules[i].Sequence__c = i + 1;
        }

        upsert rules;
        return rules;
    }

    /**
     * Deletes a single scoring rule.
     */
    @AuraEnabled
    public static void deleteRule(Id ruleId) {
        if (ruleId == null) return;
        delete [SELECT Id FROM Lead_Score_Rule__c WHERE Id = :ruleId];
    }

    // ════════════════════════════════════════════════════════════════════
    //  TIER CONFIG CRUD
    // ════════════════════════════════════════════════════════════════════

    /**
     * Returns all Lead_Score_Tier__c records ordered by min score.
     */
    @AuraEnabled(cacheable=true)
    public static List<Lead_Score_Tier__c> getTiers() {
        return [
            SELECT Id, Name, Min_Score__c, Max_Score__c, Color__c, Sequence__c
            FROM Lead_Score_Tier__c
            ORDER BY Sequence__c ASC, Min_Score__c ASC
        ];
    }

    /**
     * Upserts tier records from the designer.
     */
    @AuraEnabled
    public static List<Lead_Score_Tier__c> saveTiers(String tiersJSON) {
        List<Lead_Score_Tier__c> tiers =
            (List<Lead_Score_Tier__c>) JSON.deserialize(tiersJSON, List<Lead_Score_Tier__c>.class);

        for (Integer i = 0; i < tiers.size(); i++) {
            tiers[i].Sequence__c = i + 1;
        }

        upsert tiers;
        return tiers;
    }

    /**
     * Deletes a single tier.
     */
    @AuraEnabled
    public static void deleteTier(Id tierId) {
        if (tierId == null) return;
        delete [SELECT Id FROM Lead_Score_Tier__c WHERE Id = :tierId];
    }

    // ════════════════════════════════════════════════════════════════════
    //  WRAPPER CLASSES
    // ════════════════════════════════════════════════════════════════════

    public class FieldInfo implements Comparable {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String fieldType;
        @AuraEnabled public Boolean isPicklist;
        @AuraEnabled public Boolean isLookup;
        @AuraEnabled public String referenceTo;

        public Integer compareTo(Object other) {
            FieldInfo o = (FieldInfo) other;
            return this.label.compareTo(o.label);
        }
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class RelatedObjectInfo {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String lookupField;
    }
}