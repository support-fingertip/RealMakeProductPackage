/**
 * @description Controller for the Document Viewer LWC.
 * Fetches active templates for a given object/record, evaluates visibility
 * conditions (field values, profile, user), and generates PDF URLs.
 */
public with sharing class DocumentViewerController {

    // ============================== WRAPPERS ==============================

    public class ViewerTemplate {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String fileNamePattern { get; set; }
        @AuraEnabled public String pageSize { get; set; }
        @AuraEnabled public String pageOrientation { get; set; }
        @AuraEnabled public String pdfUrl { get; set; }
    }

    // ============================== MAIN METHOD ==============================

    /**
     * @description Get active templates visible for the given record.
     *              Evaluates visibility conditions stored in Template_JSON__c.
     * @param recordId The record to generate documents for
     * @param objectApiName The object API name (optional - derived from recordId if blank)
     * @return List of templates the current user can see for this record
     */
    @AuraEnabled
    public static List<ViewerTemplate> getTemplatesForRecord(String recordId, String objectApiName) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            // Derive object API name from record ID if not provided
            if (String.isBlank(objectApiName)) {
                objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
            }

            // Query active templates for this object (Document Viewer context only)
            List<Document_Template__c> templates = [
                SELECT Id, Name, Description__c, Template_JSON__c,
                       Template_Content_Document_Id__c,
                       File_Name_Pattern__c, Page_Size__c, Page_Orientation__c,
                       Matching_Criteria__c
                FROM Document_Template__c
                WHERE Object_API_Name__c = :objectApiName
                  AND Active__c = true
                  AND (Display_Context__c = 'Document Viewer' OR Display_Context__c = 'Both' OR Display_Context__c = null)
                ORDER BY Name ASC
            ];

            if (templates.isEmpty()) {
                return new List<ViewerTemplate>();
            }

            // Query the record for condition evaluation
            SObject record = queryRecordForConditions(recordId, objectApiName, templates);

            // Get current user info for profile/user conditions
            User currentUser = [
                SELECT Id, ProfileId, Profile.Name, UserRoleId, UserRole.Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            // Build VF page base URL
            String baseUrl = '/apex/DynamicDocumentPDF';

            List<ViewerTemplate> result = new List<ViewerTemplate>();
            for (Document_Template__c tmpl : templates) {
                // Evaluate visibility conditions from Template_JSON__c
                if (!isTemplateVisible(tmpl, record, currentUser)) {
                    continue;
                }

                // Evaluate matching criteria from Matching_Criteria__c field
                if (String.isNotBlank(tmpl.Matching_Criteria__c)) {
                    Boolean criteriaMatch = ConfigMatchingService.evaluateCriteria(
                        tmpl.Matching_Criteria__c, Id.valueOf(recordId), objectApiName
                    );
                    if (!criteriaMatch) {
                        continue;
                    }
                }

                ViewerTemplate vt = new ViewerTemplate();
                vt.id = tmpl.Id;
                vt.name = tmpl.Name;
                vt.description = tmpl.Description__c;
                vt.fileNamePattern = tmpl.File_Name_Pattern__c;
                vt.pageSize = tmpl.Page_Size__c;
                vt.pageOrientation = tmpl.Page_Orientation__c;
                vt.pdfUrl = baseUrl + '?templateId=' + tmpl.Id + '&id=' + recordId;
                result.add(vt);
            }

            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading templates: ' + e.getMessage());
        }
    }

    /**
     * Get templates filtered by Action Binding (e.g., 'Demand Raiser').
     * Only returns templates whose Action_Binding__c includes the specified action.
     */
    @AuraEnabled
    public static List<ViewerTemplate> getTemplatesForAction(String recordId, String objectApiName, String actionName) {
        try {
            if (String.isBlank(recordId)) {
                throw new AuraHandledException('Record ID is required');
            }

            if (String.isBlank(objectApiName)) {
                objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
            }

            List<Document_Template__c> templates = [
                SELECT Id, Name, Description__c, Template_JSON__c,
                       Template_Content_Document_Id__c,
                       File_Name_Pattern__c, Page_Size__c, Page_Orientation__c,
                       Matching_Criteria__c
                FROM Document_Template__c
                WHERE Object_API_Name__c = :objectApiName
                  AND Active__c = true
                  AND Action_Binding__c INCLUDES (:actionName)
                ORDER BY Name ASC
            ];

            if (templates.isEmpty()) {
                return new List<ViewerTemplate>();
            }

            String baseUrl = '/apex/DynamicDocumentPDF';
            List<ViewerTemplate> result = new List<ViewerTemplate>();

            for (Document_Template__c tmpl : templates) {
                // Evaluate matching criteria
                if (String.isNotBlank(tmpl.Matching_Criteria__c)) {
                    Boolean criteriaMatch = ConfigMatchingService.evaluateCriteria(
                        tmpl.Matching_Criteria__c, Id.valueOf(recordId), objectApiName
                    );
                    if (!criteriaMatch) continue;
                }

                ViewerTemplate vt = new ViewerTemplate();
                vt.id = tmpl.Id;
                vt.name = tmpl.Name;
                vt.description = tmpl.Description__c;
                vt.fileNamePattern = tmpl.File_Name_Pattern__c;
                vt.pageSize = tmpl.Page_Size__c;
                vt.pageOrientation = tmpl.Page_Orientation__c;
                vt.pdfUrl = baseUrl + '?templateId=' + tmpl.Id + '&id=' + recordId;
                result.add(vt);
            }

            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading action templates: ' + e.getMessage());
        }
    }

    // ============================== CONDITION EVALUATION ==============================

    /**
     * @description Check if a template should be visible based on its conditions.
     * Conditions are stored in Template_JSON__c under the "visibilityConditions" key.
     * Format:
     * {
     *   "visibilityConditions": {
     *     "logic": "AND" | "OR",
     *     "rules": [
     *       { "type": "field", "field": "Status__c", "operator": "equals", "value": "Active" },
     *       { "type": "profile", "operator": "equals", "value": "System Administrator" },
     *       { "type": "user", "field": "Id", "operator": "equals", "value": "005..." }
     *     ]
     *   }
     * }
     */
    private static Boolean isTemplateVisible(Document_Template__c tmpl, SObject record, User currentUser) {
        String jsonStr = TemplateJsonStorageService.loadTemplateJson(tmpl);
        if (String.isBlank(jsonStr)) return true;

        try {
            Map<String, Object> templateJson = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
            if (!templateJson.containsKey('visibilityConditions')) return true;

            Map<String, Object> conditions = (Map<String, Object>) templateJson.get('visibilityConditions');
            if (conditions == null) return true;

            List<Object> rules = (List<Object>) conditions.get('rules');
            if (rules == null || rules.isEmpty()) return true;

            String logic = (String) conditions.get('logic');
            if (String.isBlank(logic)) logic = 'AND';

            Boolean isAnd = logic.equalsIgnoreCase('AND');

            for (Object ruleObj : rules) {
                Map<String, Object> rule = (Map<String, Object>) ruleObj;
                Boolean ruleResult = evaluateRule(rule, record, currentUser);

                if (isAnd && !ruleResult) return false;  // AND: any false => false
                if (!isAnd && ruleResult) return true;    // OR: any true => true
            }

            return isAnd; // AND: all true => true, OR: all false => false
        } catch (Exception e) {
            // If conditions can't be parsed, show the template
            return true;
        }
    }

    private static Boolean evaluateRule(Map<String, Object> rule, SObject record, User currentUser) {
        String ruleType = (String) rule.get('type');
        String operator = (String) rule.get('operator');
        String expectedValue = (String) rule.get('value');

        if (String.isBlank(ruleType) || String.isBlank(operator)) return true;

        String actualValue = '';

        if (ruleType == 'field') {
            // Record field condition
            String fieldName = (String) rule.get('field');
            if (String.isBlank(fieldName) || record == null) return true;
            try {
                Object val = getFieldValue(record, fieldName);
                actualValue = val != null ? String.valueOf(val) : '';
            } catch (Exception e) {
                return true;
            }
        } else if (ruleType == 'profile') {
            // Profile condition
            actualValue = currentUser.Profile?.Name != null ? currentUser.Profile.Name : '';
        } else if (ruleType == 'userRole') {
            // Role condition
            actualValue = currentUser.UserRole?.Name != null ? currentUser.UserRole.Name : '';
        } else if (ruleType == 'user') {
            // User field condition
            String fieldName = (String) rule.get('field');
            if (fieldName == 'Id') {
                actualValue = currentUser.Id;
            } else {
                actualValue = currentUser.Id;
            }
        } else {
            return true;
        }

        return evaluateOperator(actualValue, operator, expectedValue);
    }

    private static Boolean evaluateOperator(String actualValue, String operator, String expectedValue) {
        if (actualValue == null) actualValue = '';
        if (expectedValue == null) expectedValue = '';

        if (operator == 'equals') {
            return actualValue.equalsIgnoreCase(expectedValue);
        } else if (operator == 'notEquals') {
            return !actualValue.equalsIgnoreCase(expectedValue);
        } else if (operator == 'contains') {
            return actualValue.containsIgnoreCase(expectedValue);
        } else if (operator == 'notContains') {
            return !actualValue.containsIgnoreCase(expectedValue);
        } else if (operator == 'startsWith') {
            return actualValue.startsWithIgnoreCase(expectedValue);
        } else if (operator == 'isBlank') {
            return String.isBlank(actualValue);
        } else if (operator == 'isNotBlank') {
            return String.isNotBlank(actualValue);
        } else if (operator == 'in') {
            // Comma-separated list check
            for (String v : expectedValue.split(',')) {
                if (actualValue.equalsIgnoreCase(v.trim())) return true;
            }
            return false;
        }

        return true;
    }

    // ============================== HELPERS ==============================

    private static SObject queryRecordForConditions(String recordId, String objectApiName,
                                                      List<Document_Template__c> templates) {
        // Collect all field names needed from conditions
        Set<String> fieldNames = new Set<String>{'Id'};

        for (Document_Template__c tmpl : templates) {
            String jsonStr = TemplateJsonStorageService.loadTemplateJson(tmpl);
            if (String.isNotBlank(jsonStr)) {
                try {
                    Map<String, Object> templateJson = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
                    if (templateJson.containsKey('visibilityConditions')) {
                        Map<String, Object> conditions = (Map<String, Object>) templateJson.get('visibilityConditions');
                        List<Object> rules = (List<Object>) conditions.get('rules');
                        if (rules != null) {
                            for (Object ruleObj : rules) {
                                Map<String, Object> rule = (Map<String, Object>) ruleObj;
                                if (rule.get('type') == 'field') {
                                    String fieldName = (String) rule.get('field');
                                    if (String.isNotBlank(fieldName)) {
                                        fieldNames.add(String.escapeSingleQuotes(fieldName));
                                    }
                                }
                            }
                        }
                    }
                } catch (Exception e) {
                    // Skip invalid JSON
                }
            }
        }

        // Validate fields exist
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) return null;
        Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();

        Set<String> validFields = new Set<String>();
        for (String f : fieldNames) {
            String fLower = f.toLowerCase();
            if (fieldMap.containsKey(fLower) && fieldMap.get(fLower).getDescribe().isAccessible()) {
                validFields.add(f);
            }
        }

        if (validFields.isEmpty()) {
            validFields.add('Id');
        }

        String query = 'SELECT ' + String.join(new List<String>(validFields), ', ') +
                        ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                        ' WHERE Id = :recordId LIMIT 1';

        try {
            List<SObject> records = Database.query(query);
            return records.isEmpty() ? null : records[0];
        } catch (Exception e) {
            return null;
        }
    }

    private static Object getFieldValue(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) return null;
        try {
            if (fieldPath.contains('.')) {
                String relName = fieldPath.substringBefore('.');
                String remaining = fieldPath.substringAfter('.');
                SObject parent = record.getSObject(relName);
                return parent != null ? getFieldValue(parent, remaining) : null;
            }
            return record.get(fieldPath);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Get picklist values for a field on the given object.
     *              Used by the visibility condition builder in the designer.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPicklistValues(String objectApiName, String fieldApiName) {
        List<Map<String, String>> result = new List<Map<String, String>>();
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) return result;

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) return result;

        Schema.SObjectField field = sType.getDescribe().fields.getMap().get(fieldApiName.toLowerCase());
        if (field == null) return result;

        Schema.DescribeFieldResult dfr = field.getDescribe();
        if (dfr.getType() != Schema.DisplayType.PICKLIST && dfr.getType() != Schema.DisplayType.MULTIPICKLIST) {
            return result;
        }

        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                result.add(new Map<String, String>{
                    'label' => pe.getLabel(),
                    'value' => pe.getValue()
                });
            }
        }
        return result;
    }
}