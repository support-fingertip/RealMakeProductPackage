/**
 * @description Dynamic Formula Calculation Service
 * Works with ANY objects - fully dynamic
 * Supports Flow invocation
 */
public with sharing class FormulaCalculationService {

    // ==================== CONSTANTS ====================
    private static final String PROJECT_LOOKUP_FIELD = 'Project__c';
    
    /**
     * INVOCABLE METHOD - For Flow (SIMPLIFIED)
     * Only needs Target Record ID - everything else is automatic!
     */
    @InvocableMethod(label='Calculate Formula' description='Calculate based on formula template' category='Formula Calculator')
    public static List<FlowOutput> calculateFromFlow(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();
        
        for(FlowInput input : inputs) {
            FlowOutput output = new FlowOutput();
            
            try {
                Id targetRecordId = input.targetRecordId;
                
                // Step 1: Determine object type from record ID
                String targetObjectAPI = targetRecordId.getSObjectType().getDescribe().getName();
                
                // Step 2: Get target record with basic info
                SObject targetRecord = getRecordWithLookups(targetRecordId, targetObjectAPI);
                
                if(targetRecord == null) {
                    output.success = false;
                    output.errorMessage = 'Target record not found';
                    outputs.add(output);
                    continue;
                }
                
                // Step 3: Find active template for this target object
                Project_Calculation_Template__c template = findActiveTemplateForRecord(targetRecord, targetObjectAPI);
                
                if(template == null) {
                    output.success = false;
                    output.errorMessage = 'No active calculation template found for ' + targetObjectAPI;
                    outputs.add(output);
                    continue;
                }
                
                // Step 4: Get source record ID from target using configured lookup field
                Id sourceRecordId = (Id) targetRecord.get(template.Source_Lookup_Field__c);
                
                if(sourceRecordId == null) {
                    output.success = false;
                    output.errorMessage = 'Source record not linked';
                    outputs.add(output);
                    continue;
                }
                
                // Step 5: Get source record with all fields
                SObject sourceRecord = getRecordWithAllFields(sourceRecordId, template.Source_Object_API_Name__c);

                // Step 5b: Re-query target record with all calculable fields (numeric, picklist, boolean)
                // The initial query only fetched lookup fields for template discovery
                targetRecord = getRecordWithAllCalculableFields(targetRecordId, targetObjectAPI);

                // Step 6: Calculate
                calculateSingleRecord(targetRecord, sourceRecord, template);
                
                // Step 7: Update target record
                update targetRecord;
                
                output.success = true;
                output.targetRecordId = targetRecordId;
                output.message = 'Calculation completed successfully';
                
            } catch(Exception e) {
                output.success = false;
                output.errorMessage = e.getMessage();
            }
            
            outputs.add(output);
        }
        
        return outputs;
    }
    
    /**
     * Get record with all lookup fields to find source and project
     */
    private static SObject getRecordWithLookups(Id recordId, String objectAPI) {
        // Build query to get all lookup fields
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectAPI).getDescribe().fields.getMap();
        List<String> fields = new List<String>{'Id'};
        
        for(String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            // Get all reference fields
            if(dfr.getType() == Schema.DisplayType.REFERENCE) {
                fields.add(fieldName);
            }
        }
        
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM ' + objectAPI + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> records = Database.query(query);
        return records.isEmpty() ? null : records[0];
    }
    
    /**
     * Find active template for this record automatically
     * Looks for template matching target object and finds project from source
     */
    private static Project_Calculation_Template__c findActiveTemplateForRecord(SObject targetRecord, String targetObjectAPI) {
        // Find all possible templates for this target object
        List<Project_Calculation_Template__c> possibleTemplates = [
            SELECT Id, Source_Object_API_Name__c, Target_Object_API_Name__c,
                   Source_Lookup_Field__c, Project__c, Calculation_Detail_Field__c,
                   (SELECT Id, Step_Number__c, Step_Label__c, Variable_Name__c, Formula_Expression__c,
                           Store_In_Field__c, Is_Active__c
                    FROM Calculation_Steps__r
                    ORDER BY Step_Number__c ASC)
            FROM Project_Calculation_Template__c
            WHERE Target_Object_API_Name__c = :targetObjectAPI
            AND Is_Active__c = true
        ];
        
        // Try each template to find one that works
        for(Project_Calculation_Template__c template : possibleTemplates) {
            try {
                // Check if target has the lookup field
                Id sourceRecordId = (Id) targetRecord.get(template.Source_Lookup_Field__c);
                if(sourceRecordId == null) continue;
                
                // Get source record to find project
                String sourceQuery = 'SELECT Id, ' + PROJECT_LOOKUP_FIELD + ' FROM ' + template.Source_Object_API_Name__c +
                                   ' WHERE Id = :sourceRecordId LIMIT 1';
                List<SObject> sourceRecords = Database.query(sourceQuery);
                
                if(!sourceRecords.isEmpty()) {
                    Id projectId = (Id) sourceRecords[0].get(PROJECT_LOOKUP_FIELD);
                    // Check if this template belongs to the same project
                    if(projectId != null && projectId == template.Project__c) {
                        return template; // Found matching template!
                    }
                }
            } catch(Exception e) {
                // Skip this template if any error
                continue;
            }
        }
        
        return null; // No matching template found
    }
    
    /**
     * For Trigger - Bulk processing
     */
    public static void calculateRecords(List<SObject> targetRecords, String sourceObjectAPI, String targetObjectAPI, String sourceLookupField) {
        // Get all source record Ids
        Set<Id> sourceIds = new Set<Id>();
        for(SObject record : targetRecords) {
            Id sourceId = (Id) record.get(sourceLookupField);
            if(sourceId != null) {
                sourceIds.add(sourceId);
            }
        }
        
        if(sourceIds.isEmpty()) return;
        
        // Get source records with project info
        Map<Id, SObject> sourceMap = getSourceRecordsWithProject(sourceIds, sourceObjectAPI);
        
        // Get all Project Ids
        Set<Id> projectIds = new Set<Id>();
        for(SObject sourceRec : sourceMap.values()) {
            Id projectId = (Id) sourceRec.get(PROJECT_LOOKUP_FIELD);
            if(projectId != null) {
                projectIds.add(projectId);
            }
        }
        
        // Get active templates for projects
        Map<Id, Project_Calculation_Template__c> templatesByProject = getActiveTemplatesForProjects(projectIds, sourceObjectAPI, targetObjectAPI);
        
        // Get all source records with full data
        Map<Id, SObject> sourceDataMap = getRecordsWithAllFields(sourceIds, sourceObjectAPI);
        
        // Process each target record
        for(SObject targetRecord : targetRecords) {
            Id sourceId = (Id) targetRecord.get(sourceLookupField);
            if(sourceId == null) continue;
            
            SObject sourceRecord = sourceMap.get(sourceId);
            if(sourceRecord == null) continue;
            
            Id projectId = (Id) sourceRecord.get(PROJECT_LOOKUP_FIELD);
            Project_Calculation_Template__c template = templatesByProject.get(projectId);
            
            if(template == null || template.Calculation_Steps__r == null || template.Calculation_Steps__r.isEmpty()) {
                continue;
            }
            
            SObject sourceWithData = sourceDataMap.get(sourceId);
            
            try {
                calculateSingleRecord(targetRecord, sourceWithData, template);
            } catch(Exception e) {
                System.debug('Calculation error: ' + e.getMessage());
            }
        }
    }
    
    /**
     * Calculate a single record (works with in-memory record)
     */
    private static void calculateSingleRecord(
        SObject targetRecord,
        SObject sourceRecord,
        Project_Calculation_Template__c template
    ) {
        Map<String, Decimal> variableMap = new Map<String, Decimal>();
        String detailField = template.Calculation_Detail_Field__c;
        Boolean buildDetail = String.isNotBlank(detailField);
        String detailHtml = '';

        if (buildDetail) {
            detailHtml = '<div style="font-family:Arial,sans-serif;font-size:13px;color:#333;">';
            detailHtml += '<p style="margin:0 0 10px;color:#1a56db;font-weight:bold;font-size:14px;border-bottom:2px solid #1a56db;padding-bottom:6px;">Calculation Details</p>';
        }

        Integer stepIdx = 0;
        for (Calculation_Step__c step : template.Calculation_Steps__r) {
            if (!step.Is_Active__c) continue;
            stepIdx++;

            String originalFormula = step.Formula_Expression__c;

            // Build the resolved formula string (with actual values) before evaluation
            String resolvedFormula = originalFormula;
            resolvedFormula = replaceFieldsWithValues(resolvedFormula, targetRecord, sourceRecord, template.Target_Object_API_Name__c, template.Source_Object_API_Name__c);
            resolvedFormula = replaceVariables(resolvedFormula, variableMap);

            Decimal result = executeStep(step, targetRecord, sourceRecord, template.Target_Object_API_Name__c, template.Source_Object_API_Name__c, variableMap);

            // Store in variable map
            if (String.isNotBlank(step.Variable_Name__c)) {
                variableMap.put(step.Variable_Name__c, result);
            }

            // Store in target record field
            if (String.isNotBlank(step.Store_In_Field__c)) {
                targetRecord.put(step.Store_In_Field__c, result);
            }

            if (buildDetail) {
                String stepLabel = String.isNotBlank(step.Step_Label__c) ? step.Step_Label__c : 'Step ' + stepIdx;
                String storeField = String.isNotBlank(step.Store_In_Field__c) ? step.Store_In_Field__c : '';
                String resultStr = result != null ? formatNumber(result) : '0';

                detailHtml += '<div style="margin-bottom:10px;padding:8px 10px;background:#f8fafc;border-left:3px solid #1a56db;border-radius:0 4px 4px 0;">';
                detailHtml += '<b style="color:#1a56db;">Step ' + stepIdx + ' - ' + String.valueOf(stepLabel).escapeHtml4() + '</b><br/>';
                detailHtml += 'Formula: ' + String.valueOf(originalFormula).escapeHtml4() + '<br/>';
                detailHtml += 'Values: <span style="color:#059669;">' + String.valueOf(resolvedFormula).escapeHtml4() + '</span><br/>';
                detailHtml += 'Result = <b style="color:#1a56db;">' + resultStr + '</b>';
                if (String.isNotBlank(storeField)) {
                    detailHtml += ' &rarr; saved in <i>' + String.valueOf(storeField).escapeHtml4() + '</i>';
                }
                detailHtml += '</div>';
            }
        }

        if (buildDetail) {
            Decimal finalResult = variableMap.isEmpty() ? 0 : variableMap.values()[variableMap.values().size() - 1];
            detailHtml += '<div style="margin-top:6px;padding:8px 10px;background:#1a56db;color:white;border-radius:4px;font-size:14px;">';
            detailHtml += '<b>Final Result = ' + formatNumber(finalResult) + '</b>';
            detailHtml += '</div>';
            detailHtml += '<p style="font-size:10px;color:#999;margin:6px 0 0;">Generated: ' + Datetime.now().format('dd-MMM-yyyy HH:mm') + '</p>';
            detailHtml += '</div>';

            try {
                targetRecord.put(detailField, detailHtml);
            } catch (Exception e) {
                System.debug('Could not store calculation detail: ' + e.getMessage());
            }
        }
    }

    private static String formatNumber(Decimal value) {
        if (value == null) return '0';
        return value.setScale(2).format();
    }
    
    /**
     * Execute a single calculation step
     */
    private static Decimal executeStep(
        Calculation_Step__c step, 
        SObject targetRecord, 
        SObject sourceRecord,
        String targetObjectAPI,
        String sourceObjectAPI,
        Map<String, Decimal> variableMap
    ) {
        String formula = step.Formula_Expression__c;
        
        // Replace field names with actual values
        formula = replaceFieldsWithValues(formula, targetRecord, sourceRecord, targetObjectAPI, sourceObjectAPI);
        
        // Replace variables from previous steps
        formula = replaceVariables(formula, variableMap);
        
        // Evaluate formula
        return evaluateFormula(formula);
    }
    
    /**
     * Replace field names in formula with actual values
     * Priority: Target first, then Source
     */
    private static String replaceFieldsWithValues(
        String formula, 
        SObject targetRecord, 
        SObject sourceRecord,
        String targetObjectAPI,
        String sourceObjectAPI
    ) {
        Map<String, Schema.SObjectField> targetFields = Schema.getGlobalDescribe().get(targetObjectAPI).getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> sourceFields = Schema.getGlobalDescribe().get(sourceObjectAPI).getDescribe().fields.getMap();
        
        // Pattern to match field API names
        Pattern fieldPattern = Pattern.compile('\\b([A-Za-z][A-Za-z0-9_]*)__c\\b');
        Matcher matcher = fieldPattern.matcher(formula);
        
        Map<String, String> replacements = new Map<String, String>();
        
        while(matcher.find()) {
            String fieldName = matcher.group(1) + '__c';
            Object value = null;
            Schema.DisplayType fieldType = null;
            
            // Check Target first
            if(targetFields.containsKey(fieldName)) {
                try {
                    value = targetRecord.get(fieldName);
                    fieldType = targetFields.get(fieldName).getDescribe().getType();
                } catch(Exception e) {}
            }
            
            // If null, check Source
            if(value == null && sourceFields.containsKey(fieldName)) {
                try {
                    value = sourceRecord.get(fieldName);
                    fieldType = sourceFields.get(fieldName).getDescribe().getType();
                } catch(Exception e) {}
            }
            
            // Convert value based on type
            if(value != null) {
                if(fieldType == Schema.DisplayType.PICKLIST) {
                    // For picklist, keep as quoted string for text comparison
                    String picklistValue = String.valueOf(value);
                    replacements.put(fieldName, '"' + picklistValue + '"');
                } else if(value instanceof Decimal || value instanceof Double || value instanceof Integer) {
                    replacements.put(fieldName, String.valueOf(value));
                } else if(value instanceof Boolean) {
                    // Convert boolean to 1 or 0
                    replacements.put(fieldName, (Boolean)value ? '1' : '0');
                } else {
                    replacements.put(fieldName, '0');
                }
            } else {
                replacements.put(fieldName, '0');
            }
        }
        
        // Replace all field names
        for(String fieldName : replacements.keySet()) {
            formula = formula.replaceAll('\\b' + fieldName + '\\b', replacements.get(fieldName));
        }
        
        return formula;
    }
    
    /**
     * Replace variable names with their calculated values
     */
    private static String replaceVariables(String formula, Map<String, Decimal> variableMap) {
        for(String varName : variableMap.keySet()) {
            if(formula.contains(varName)) {
                formula = formula.replaceAll('\\b' + varName + '\\b', String.valueOf(variableMap.get(varName)));
            }
        }
        return formula;
    }
    
    /**
     * Evaluate mathematical formula
     */
    private static Decimal evaluateFormula(String formula) {
        formula = formula.trim();
        
        if(formula.startsWithIgnoreCase('IF(')) {
            return evaluateIfCondition(formula);
        }
        
        return evaluateExpression(formula);
    }
    
    private static Decimal evaluateIfCondition(String formula) {
        String condition = formula.substring(3, formula.length() - 1);
        List<String> parts = splitIfParts(condition);
        
        if(parts.size() != 3) {
            throw new FormulaException('Invalid IF syntax');
        }
        
        Boolean conditionResult = evaluateCondition(parts[0].trim());
        
        if(conditionResult) {
            return evaluateExpression(parts[1].trim());
        } else {
            return evaluateExpression(parts[2].trim());
        }
    }
    
    /**
 	* Evaluate condition - NOW SUPPORTS STRING COMPARISON
 	*/
    private static Boolean evaluateCondition(String condition) {
        // Handle string comparisons (for picklists)
        if(condition.contains('"')) {
            return evaluateStringCondition(condition);
        }
        
        // Original numeric comparisons
        if(condition.contains('>=')) {
            List<String> parts = condition.split('>=');
            return evaluateExpression(parts[0].trim()) >= evaluateExpression(parts[1].trim());
        } else if(condition.contains('<=')) {
            List<String> parts = condition.split('<=');
            return evaluateExpression(parts[0].trim()) <= evaluateExpression(parts[1].trim());
        } else if(condition.contains('==')) {
            List<String> parts = condition.split('==');
            return evaluateExpression(parts[0].trim()) == evaluateExpression(parts[1].trim());
        } else if(condition.contains('!=')) {
            List<String> parts = condition.split('!=');
            return evaluateExpression(parts[0].trim()) != evaluateExpression(parts[1].trim());
        } else if(condition.contains('>')) {
            List<String> parts = condition.split('>');
            return evaluateExpression(parts[0].trim()) > evaluateExpression(parts[1].trim());
        } else if(condition.contains('<')) {
            List<String> parts = condition.split('<');
            return evaluateExpression(parts[0].trim()) < evaluateExpression(parts[1].trim());
        }
        return false;
    }
    
    /**
	 * NEW METHOD: Evaluate string comparison for picklists
	 */
    private static Boolean evaluateStringCondition(String condition) {
        if(condition.contains('==')) {
            List<String> parts = condition.split('==');
            String left = parts[0].trim().replace('"', '');
            String right = parts[1].trim().replace('"', '');
            return left.equals(right);
        } else if(condition.contains('!=')) {
            List<String> parts = condition.split('!=');
            String left = parts[0].trim().replace('"', '');
            String right = parts[1].trim().replace('"', '');
            return !left.equals(right);
        }
        return false;
    }
    
    private static List<String> splitIfParts(String str) {
        List<String> parts = new List<String>();
        Integer depth = 0;
        Integer lastSplit = 0;
        
        for(Integer i = 0; i < str.length(); i++) {
            String c = str.substring(i, i+1);
            if(c == '(') depth++;
            if(c == ')') depth--;
            
            if(c == ',' && depth == 0) {
                parts.add(str.substring(lastSplit, i));
                lastSplit = i + 1;
            }
        }
        parts.add(str.substring(lastSplit));
        
        return parts;
    }
    
    private static Decimal evaluateExpression(String expr) {
        expr = expr.trim().replaceAll('\\s+', '');
        
        if(expr.startsWith('-') && expr.length() > 1) {
            return -1 * evaluateExpression(expr.substring(1));
        }
        
        if(expr.contains('(')) {
            return evaluateWithParentheses(expr);
        }
        
        for(Integer i = expr.length() - 1; i >= 0; i--) {
            String c = expr.substring(i, i+1);
            if(c == '+') {
                return evaluateExpression(expr.substring(0, i)) + evaluateExpression(expr.substring(i+1));
            } else if(c == '-' && i > 0 && !isOperator(expr.substring(i-1, i))) {
                return evaluateExpression(expr.substring(0, i)) - evaluateExpression(expr.substring(i+1));
            }
        }
        
        for(Integer i = expr.length() - 1; i >= 0; i--) {
            String c = expr.substring(i, i+1);
            if(c == '*') {
                return evaluateExpression(expr.substring(0, i)) * evaluateExpression(expr.substring(i+1));
            } else if(c == '/') {
                Decimal divisor = evaluateExpression(expr.substring(i+1));
                if(divisor == 0) {
                    throw new FormulaException('Division by zero');
                }
                return evaluateExpression(expr.substring(0, i)) / divisor;
            } else if(c == '%') {
                return Math.mod(evaluateExpression(expr.substring(0, i)).intValue(), 
                               evaluateExpression(expr.substring(i+1)).intValue());
            }
        }
        
        try {
            return Decimal.valueOf(expr);
        } catch(Exception e) {
            throw new FormulaException('Invalid number: ' + expr);
        }
    }
    
    private static Boolean isOperator(String c) {
        return c == '+' || c == '-' || c == '*' || c == '/' || c == '%';
    }
    
    private static Decimal evaluateWithParentheses(String expr) {
        while(expr.contains('(')) {
            Integer start = expr.lastIndexOf('(');
            Integer ends = expr.indexOf(')', start);
            
            if(ends == -1) {
                throw new FormulaException('Mismatched parentheses');
            }
            
            String innerExpr = expr.substring(start + 1, ends);
            Decimal innerResult = evaluateExpression(innerExpr);
            
            expr = expr.substring(0, start) + String.valueOf(innerResult) + expr.substring(ends + 1);
        }
        
        return evaluateExpression(expr);
    }
    
    /**
     * HELPER METHODS - Dynamic queries
     */
    
    private static Project_Calculation_Template__c getTemplateById(Id templateId) {
        return [
            SELECT Id, Source_Object_API_Name__c, Target_Object_API_Name__c, Source_Lookup_Field__c,
                   Calculation_Detail_Field__c,
                   (SELECT Id, Step_Number__c, Step_Label__c, Variable_Name__c, Formula_Expression__c,
                           Store_In_Field__c, Is_Active__c
                    FROM Calculation_Steps__r
                    ORDER BY Step_Number__c ASC)
            FROM Project_Calculation_Template__c
            WHERE Id = :templateId
            LIMIT 1
        ];
    }
    
    private static SObject getRecordById(Id recordId, String objectAPI) {
        String query = 'SELECT Id FROM ' + objectAPI + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> records = Database.query(query);
        return records.isEmpty() ? null : records[0];
    }
    
    private static Map<Id, SObject> getSourceRecordsWithProject(Set<Id> sourceIds, String sourceObjectAPI) {
        String query = 'SELECT Id, ' + PROJECT_LOOKUP_FIELD + ' FROM ' + sourceObjectAPI + ' WHERE Id IN :sourceIds';
        List<SObject> records = Database.query(query);
        
        Map<Id, SObject> recordMap = new Map<Id, SObject>();
        for(SObject rec : records) {
            recordMap.put(rec.Id, rec);
        }
        return recordMap;
    }
    
    private static Map<Id, Project_Calculation_Template__c> getActiveTemplatesForProjects(
        Set<Id> projectIds,
        String sourceObjectAPI,
        String targetObjectAPI
    ) {
        Map<Id, Project_Calculation_Template__c> templatesByProject = new Map<Id, Project_Calculation_Template__c>();
        
        List<Project_Calculation_Template__c> templates = [
            SELECT Id, Project__c, Source_Lookup_Field__c, Calculation_Detail_Field__c,
                   (SELECT Id, Step_Number__c, Step_Label__c, Variable_Name__c, Formula_Expression__c,
                           Store_In_Field__c, Is_Active__c
                    FROM Calculation_Steps__r
                    ORDER BY Step_Number__c ASC)
            FROM Project_Calculation_Template__c
            WHERE Project__c IN :projectIds
            AND Source_Object_API_Name__c = :sourceObjectAPI
            AND Target_Object_API_Name__c = :targetObjectAPI
            AND Is_Active__c = true
        ];
        
        for(Project_Calculation_Template__c template : templates) {
            templatesByProject.put(template.Project__c, template);
        }
        
        return templatesByProject;
    }
    
    private static SObject getRecordWithAllFields(Id recordId, String objectAPI) {
        Map<Id, SObject> recordMap = getRecordsWithAllFields(new Set<Id>{recordId}, objectAPI);
        return recordMap.get(recordId);
    }
    
    private static Map<Id, SObject> getRecordsWithAllFields(Set<Id> recordIds, String objectAPI) {
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectAPI).getDescribe().fields.getMap();
        List<String> fields = new List<String>{'Id'};

        for(String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            Schema.DisplayType fieldType = dfr.getType();
            if(fieldType == Schema.DisplayType.CURRENCY ||
               fieldType == Schema.DisplayType.DOUBLE ||
               fieldType == Schema.DisplayType.PERCENT ||
               fieldType == Schema.DisplayType.INTEGER ||
               fieldType == Schema.DisplayType.PICKLIST ||
               fieldType == Schema.DisplayType.BOOLEAN) {
                fields.add(fieldName);
            }
        }
        
        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM ' + objectAPI + ' WHERE Id IN :recordIds';
        List<SObject> records = Database.query(query);
        
        Map<Id, SObject> recordMap = new Map<Id, SObject>();
        for(SObject rec : records) {
            recordMap.put(rec.Id, rec);
        }
        
        return recordMap;
    }
    
    /**
     * Get record with all fields needed for formula calculation
     * Includes numeric, picklist, boolean, and reference fields
     */
    private static SObject getRecordWithAllCalculableFields(Id recordId, String objectAPI) {
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectAPI).getDescribe().fields.getMap();
        List<String> fields = new List<String>{'Id'};

        for(String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            Schema.DisplayType fieldType = dfr.getType();
            if(fieldType == Schema.DisplayType.CURRENCY ||
               fieldType == Schema.DisplayType.DOUBLE ||
               fieldType == Schema.DisplayType.PERCENT ||
               fieldType == Schema.DisplayType.INTEGER ||
               fieldType == Schema.DisplayType.PICKLIST ||
               fieldType == Schema.DisplayType.BOOLEAN ||
               fieldType == Schema.DisplayType.REFERENCE) {
                fields.add(fieldName);
            }
        }

        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM ' + objectAPI + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> records = Database.query(query);
        return records.isEmpty() ? null : records[0];
    }

    /**
     * PUBLIC wrapper for testing
     */
    public static Decimal evaluateFormulaPublic(String formula) {
        return evaluateFormula(formula);
    }
    
    /**
     * Inner Classes
     */
    public class FlowInput {
        @InvocableVariable(label='Target Record ID' description='ID of the record to calculate (e.g., Booking ID)' required=true)
        public Id targetRecordId;
    }
    
    public class FlowOutput {
        @InvocableVariable(label='Success')
        public Boolean success;
        
        @InvocableVariable(label='Target Record ID')
        public Id targetRecordId;
        
        @InvocableVariable(label='Message')
        public String message;
        
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }
    
    public class FormulaException extends Exception {}
}