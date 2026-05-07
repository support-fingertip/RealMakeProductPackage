/**
 * @description Controller for the Document Designer LWC.
 * Provides CRUD for Document_Template__c and schema introspection
 * so the designer can offer merge-field and related-table insertion.
 */
public with sharing class DocumentDesignerController {

    private static final String DEFAULT_PAGE_SIZE = 'A4';
    private static final String DEFAULT_ORIENTATION = 'portrait';
    private static final String CLONE_SUFFIX = ' (Copy)';

    // ============================== WRAPPER CLASSES ==============================

    public class TemplateWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String templateJson { get; set; }
        @AuraEnabled public String logoUrl { get; set; }
        @AuraEnabled public String fileNamePattern { get; set; }
        @AuraEnabled public String pageSize { get; set; }
        @AuraEnabled public String pageOrientation { get; set; }
        @AuraEnabled public String displayContext { get; set; }
        @AuraEnabled public String actionBinding { get; set; }
        @AuraEnabled public String matchingCriteria { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public DateTime lastModifiedDate { get; set; }
        @AuraEnabled public String createdByName { get; set; }
    }

    public class FieldOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String value { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String referenceTo { get; set; }

        public FieldOption(String label, String value, String type, String referenceTo) {
            this.label = label;
            this.value = value;
            this.type = type;
            this.referenceTo = referenceTo;
        }
    }

    public class RelationshipOption {
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String childObjectName { get; set; }
        @AuraEnabled public String childObjectLabel { get; set; }
        @AuraEnabled public String relationshipName { get; set; }
        @AuraEnabled public String relationshipFieldName { get; set; }

        public RelationshipOption(String label, String childObjectName, String childObjectLabel,
                                   String relationshipName, String relationshipFieldName) {
            this.label = label;
            this.childObjectName = childObjectName;
            this.childObjectLabel = childObjectLabel;
            this.relationshipName = relationshipName;
            this.relationshipFieldName = relationshipFieldName;
        }
    }

    // ============================== TEMPLATE CRUD ==============================

    @AuraEnabled(cacheable=true)
    public static List<TemplateWrapper> getAllTemplates() {
        List<TemplateWrapper> result = new List<TemplateWrapper>();
        for (Document_Template__c t : [
            SELECT Id, Name, Object_API_Name__c, Description__c, Active__c,
                   Template_JSON__c, Template_Content_Document_Id__c,
                   Logo_URL__c, File_Name_Pattern__c,
                   Page_Size__c, Page_Orientation__c, Display_Context__c, Action_Binding__c, Matching_Criteria__c,
                   CreatedDate, LastModifiedDate, CreatedBy.Name
            FROM Document_Template__c
            ORDER BY LastModifiedDate DESC
        ]) {
            result.add(mapToWrapper(t));
        }
        return result;
    }

    @AuraEnabled
    public static TemplateWrapper getTemplateById(String templateId) {
        if (String.isBlank(templateId)) {
            throw new AuraHandledException('Template ID is required');
        }
        List<Document_Template__c> templates = [
            SELECT Id, Name, Object_API_Name__c, Description__c, Active__c,
                   Template_JSON__c, Template_Content_Document_Id__c,
                   Logo_URL__c, File_Name_Pattern__c,
                   Page_Size__c, Page_Orientation__c, Display_Context__c, Action_Binding__c, Matching_Criteria__c,
                   CreatedDate, LastModifiedDate, CreatedBy.Name
            FROM Document_Template__c
            WHERE Id = :templateId
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            throw new AuraHandledException('Template not found');
        }
        return mapToWrapper(templates[0]);
    }

    @AuraEnabled
    public static String saveTemplate(String templateJson) {
        try {
            if (String.isBlank(templateJson)) {
                throw new AuraHandledException('Template data is required');
            }
            TemplateWrapper w = (TemplateWrapper) JSON.deserialize(templateJson, TemplateWrapper.class);

            Document_Template__c t;
            if (String.isNotBlank(w.id)) {
                t = [SELECT Id, Template_Content_Document_Id__c FROM Document_Template__c WHERE Id = :w.id LIMIT 1];
            } else {
                t = new Document_Template__c();
            }

            t.Name = w.name;
            t.Object_API_Name__c = w.objectApiName;
            t.Description__c = w.description;
            t.Active__c = w.isActive != null ? w.isActive : true;
            t.Logo_URL__c = w.logoUrl;
            t.File_Name_Pattern__c = w.fileNamePattern;
            t.Page_Size__c = String.isNotBlank(w.pageSize) ? w.pageSize : DEFAULT_PAGE_SIZE;
            t.Page_Orientation__c = String.isNotBlank(w.pageOrientation) ? w.pageOrientation : DEFAULT_ORIENTATION;
            t.Display_Context__c = String.isNotBlank(w.displayContext) ? w.displayContext : 'Both';
            t.Action_Binding__c = w.actionBinding;
            t.Matching_Criteria__c = w.matchingCriteria;

            // Save record first (need Id for ContentVersion link)
            upsert t;

            // Save template JSON to ContentVersion (no size limit)
            if (String.isNotBlank(w.templateJson)) {
                TemplateJsonStorageService.saveTemplateJson(t.Id, w.templateJson);
            }

            return t.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving template: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteTemplate(String templateId) {
        try {
            if (String.isBlank(templateId)) {
                throw new AuraHandledException('Template ID is required');
            }
            delete [SELECT Id FROM Document_Template__c WHERE Id = :templateId LIMIT 1];
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting template: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String cloneTemplate(String templateId) {
        try {
            TemplateWrapper original = getTemplateById(templateId);
            original.id = null;
            original.name = original.name + CLONE_SUFFIX;
            original.isActive = false;
            return saveTemplate(JSON.serialize(original));
        } catch (Exception e) {
            throw new AuraHandledException('Error cloning template: ' + e.getMessage());
        }
    }

    // ============================== SCHEMA HELPERS ==============================

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getObjectList() {
        List<Map<String, String>> objects = new List<Map<String, String>>();
        List<String> sortedLabels = new List<String>();
        Map<String, Map<String, String>> labelMap = new Map<String, Map<String, String>>();

        for (Schema.SObjectType objType : Schema.getGlobalDescribe().values()) {
            Schema.DescribeSObjectResult d = objType.getDescribe();
            if (d.isAccessible() && (d.isCustom() || isCommonStandardObject(d.getName()))) {
                String lbl = d.getLabel() + ' (' + d.getName() + ')';
                Map<String, String> entry = new Map<String, String>{
                    'label' => lbl,
                    'value' => d.getName()
                };
                sortedLabels.add(lbl);
                labelMap.put(lbl, entry);
            }
        }
        sortedLabels.sort();
        for (String lbl : sortedLabels) {
            objects.add(labelMap.get(lbl));
        }
        return objects;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getObjectFields(String objectApiName) {
        List<FieldOption> fields = new List<FieldOption>();
        if (String.isBlank(objectApiName)) return fields;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return fields;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        // Collect and sort by label for consistent ordering
        List<String> sortedLabels = new List<String>();
        Map<String, FieldOption> labelToField = new Map<String, FieldOption>();
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            if (dfr.isAccessible()) {
                String refTo = null;
                if (dfr.getType() == Schema.DisplayType.REFERENCE && !dfr.getReferenceTo().isEmpty()) {
                    refTo = dfr.getReferenceTo()[0].getDescribe().getName();
                }
                String sortKey = dfr.getLabel() + '___' + dfr.getName();
                sortedLabels.add(sortKey);
                labelToField.put(sortKey, new FieldOption(dfr.getLabel(), dfr.getName(), String.valueOf(dfr.getType()), refTo));
            }
        }
        sortedLabels.sort();
        for (String key : sortedLabels) {
            fields.add(labelToField.get(key));
        }
        return fields;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getParentFields(String objectApiName, String lookupFieldName) {
        List<FieldOption> fields = new List<FieldOption>();
        if (String.isBlank(objectApiName) || String.isBlank(lookupFieldName)) return fields;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return fields;

        Schema.DescribeFieldResult lookupField = objType.getDescribe().fields.getMap()
            .get(lookupFieldName)?.getDescribe();
        if (lookupField == null || lookupField.getReferenceTo().isEmpty()) return fields;

        String parentObjectName = lookupField.getReferenceTo()[0].getDescribe().getName();
        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(parentObjectName);
        if (parentType == null) return fields;

        Map<String, Schema.SObjectField> parentFieldMap = parentType.getDescribe().fields.getMap();
        for (String fName : parentFieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = parentFieldMap.get(fName).getDescribe();
            if (dfr.isAccessible()) {
                fields.add(new FieldOption(dfr.getLabel(), dfr.getName(), String.valueOf(dfr.getType()), null));
            }
        }
        return fields;
    }

    @AuraEnabled(cacheable=true)
    public static List<RelationshipOption> getChildRelationships(String objectApiName) {
        List<RelationshipOption> result = new List<RelationshipOption>();
        if (String.isBlank(objectApiName)) return result;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);
        if (objType == null) return result;

        for (Schema.ChildRelationship rel : objType.getDescribe().getChildRelationships()) {
            Schema.DescribeSObjectResult childDesc = rel.getChildSObject().getDescribe();
            String relName = rel.getRelationshipName();
            if (String.isNotBlank(relName) && childDesc.isAccessible()) {
                result.add(new RelationshipOption(
                    childDesc.getLabel() + ' (' + childDesc.getName() + ')',
                    childDesc.getName(),
                    childDesc.getLabel(),
                    relName,
                    rel.getField().getDescribe().getName()
                ));
            }
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getChildObjectFields(String childObjectApiName) {
        return getObjectFields(childObjectApiName);
    }

    // ============================== LOGO UPLOAD ==============================

    @AuraEnabled
    public static String uploadLogo(String fileName, String base64Data) {
        try {
            if (String.isBlank(fileName) || String.isBlank(base64Data)) {
                throw new AuraHandledException('File name and data are required');
            }

            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName;
            cv.VersionData = EncodingUtil.base64Decode(base64Data);
            cv.Origin = 'C';
            insert cv;

            // Retrieve the ContentDocumentId
            cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

            // Create a public ContentDistribution for the file
            ContentDistribution cd = new ContentDistribution();
            cd.Name = fileName;
            cd.ContentVersionId = cv.Id;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesLinkLatestVersion = true;
            cd.PreferencesNotifyOnVisit = false;
            cd.PreferencesPasswordRequired = false;
            cd.PreferencesAllowOriginalDownload = true;
            insert cd;

            // Return JSON with internal Salesforce URL (reliable in LWC) and ContentVersionId (for PDF base64 embedding)
            Map<String, String> result = new Map<String, String>{
                'url' => '/sfc/servlet.shepherd/version/download/' + cv.Id,
                'contentVersionId' => cv.Id
            };
            return JSON.serialize(result);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error uploading logo: ' + e.getMessage());
        }
    }

    // ============================== PREVIEW ==============================

    @AuraEnabled
    public static String generatePreviewHtml(String templateId, String recordId) {
        try {
            TemplateWrapper template = getTemplateById(templateId);
            String jsonStr = template.templateJson;
            if (String.isBlank(jsonStr)) {
                return '<p>No template content configured.</p>';
            }
            return DynamicDocumentRenderer.renderDocument(jsonStr, recordId, template.objectApiName);
        } catch (Exception e) {
            throw new AuraHandledException('Error generating preview: ' + e.getMessage());
        }
    }

    // ============================== PRIVATE HELPERS ==============================

    private static TemplateWrapper mapToWrapper(Document_Template__c t) {
        TemplateWrapper w = new TemplateWrapper();
        w.id = t.Id;
        w.name = t.Name;
        w.objectApiName = t.Object_API_Name__c;
        w.description = t.Description__c;
        w.isActive = t.Active__c;
        // Load template JSON from ContentVersion (primary) or field (legacy fallback)
        w.templateJson = TemplateJsonStorageService.loadTemplateJson(t);
        w.logoUrl = t.Logo_URL__c;
        w.fileNamePattern = t.File_Name_Pattern__c;
        w.pageSize = t.Page_Size__c;
        w.pageOrientation = t.Page_Orientation__c;
        w.displayContext = t.Display_Context__c;
        w.actionBinding = t.Action_Binding__c;
        w.matchingCriteria = t.Matching_Criteria__c;
        w.createdDate = t.CreatedDate;
        w.lastModifiedDate = t.LastModifiedDate;
        w.createdByName = t.CreatedBy?.Name;
        return w;
    }

    private static final Set<String> COMMON_STANDARD_OBJECTS = new Set<String>{
        'Account', 'Contact', 'Opportunity', 'Lead', 'Case',
        'Contract', 'Order', 'Product2', 'Campaign', 'Asset'
    };

    private static Boolean isCommonStandardObject(String name) {
        return COMMON_STANDARD_OBJECTS.contains(name);
    }
}