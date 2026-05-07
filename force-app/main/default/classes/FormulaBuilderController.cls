/**
 * @description Controller for Formula Builder LWC
 */
public with sharing class FormulaBuilderController {
    
    /**
     * Get all projects for dropdown
     */
    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjects() {
        return [SELECT Id, Name FROM Project__c ORDER BY Name LIMIT 1000];
    }
    
    /**
     * Get calculation templates for a project
     */
    @AuraEnabled(cacheable=true)
    public static List<Project_Calculation_Template__c> getTemplates(Id projectId) {
        return [
            SELECT Id, Template_Name__c, Description__c, Is_Active__c, 
                   Source_Object_API_Name__c, Target_Object_API_Name__c, 
                   Source_Lookup_Field__c, CreatedDate
            FROM Project_Calculation_Template__c
            WHERE Project__c = :projectId
            ORDER BY CreatedDate DESC
        ];
    }
    
    /**
     * Get template with all steps
     */
    @AuraEnabled(cacheable=true)
    public static Project_Calculation_Template__c getTemplateWithSteps(Id templateId) {
        return [
            SELECT Id, Template_Name__c, Description__c, Is_Active__c,
                   Project__c, Source_Object_API_Name__c, Target_Object_API_Name__c,
                   Source_Lookup_Field__c, Calculation_Detail_Field__c,
                   (SELECT Id, Step_Number__c, Step_Label__c, Variable_Name__c,
                           Formula_Expression__c, Store_In_Field__c, Is_Active__c, Description__c
                    FROM Calculation_Steps__r
                    ORDER BY Step_Number__c ASC)
            FROM Project_Calculation_Template__c
            WHERE Id = :templateId
        ];
    }
    
    /**
     * Get available fields from Unit and Booking objects
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAvailableFields() {
        Map<String, Object> result = new Map<String, Object>();
        
        // Get Unit fields
        List<Map<String, String>> unitFields = new List<Map<String, String>>();
        Map<String, Schema.SObjectField> unitFieldMap = Schema.SObjectType.Unit__c.fields.getMap();
        
        for(String fieldName : unitFieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = unitFieldMap.get(fieldName).getDescribe();
            if(dfr.getType() == Schema.DisplayType.CURRENCY || 
               dfr.getType() == Schema.DisplayType.DOUBLE ||
               dfr.getType() == Schema.DisplayType.PERCENT) {
                unitFields.add(new Map<String, String>{
                    'label' => dfr.getLabel(),
                    'value' => fieldName,
                    'type' => String.valueOf(dfr.getType())
                });
            }
        }
        
        // Get Booking fields for storage
        List<Map<String, String>> bookingFields = new List<Map<String, String>>();
        Map<String, Schema.SObjectField> bookingFieldMap = Schema.SObjectType.Booking__c.fields.getMap();
        
        for(String fieldName : bookingFieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = bookingFieldMap.get(fieldName).getDescribe();
            if((dfr.getType() == Schema.DisplayType.CURRENCY || 
                dfr.getType() == Schema.DisplayType.DOUBLE) && 
                dfr.isUpdateable()) {
                bookingFields.add(new Map<String, String>{
                    'label' => dfr.getLabel(),
                    'value' => fieldName,
                    'type' => String.valueOf(dfr.getType())
                });
            }
        }
        
        result.put('unitFields', unitFields);
        result.put('bookingFields', bookingFields);
        
        return result;
    }
    
    /**
 	* Get picklist values for a specific field
 	*/
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getPicklistValues(String objectAPI, String fieldAPI) {
        List<Map<String, String>> picklistValues = new List<Map<String, String>>();
        
        try {
            Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objectAPI).getDescribe();
            Schema.DescribeFieldResult fieldDescribe = objDescribe.fields.getMap().get(fieldAPI).getDescribe();
            
            List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();
            
            for(Schema.PicklistEntry entry : picklistEntries) {
                picklistValues.add(new Map<String, String>{
                    'label' => entry.getLabel(),
                        'value' => entry.getValue()
                        });
            }
        } catch(Exception e) {
            System.debug('Error getting picklist values: ' + e.getMessage());
        }
        
        return picklistValues;
    }
    
    /**
     * Get available objects for source/target selection
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAvailableObjects() {
        List<Map<String, String>> objects = new List<Map<String, String>>();
        
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        
        for(String objName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult objDescribe = globalDescribe.get(objName).getDescribe();
            
            // Only show custom objects and some standard objects
            if((objDescribe.isCustom() || objName == 'Opportunity' || objName == 'Product2') && 
               objDescribe.isCreateable() && objDescribe.isQueryable()) {
                objects.add(new Map<String, String>{
                    'label' => objDescribe.getLabel(),
                    'value' => objDescribe.getName()
                });
            }
        }
        
        return objects;
    }
    
    /**
     * Get lookup fields from target object that point to source object
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLookupFields(String targetObjectAPI, String sourceObjectAPI) {
        List<Map<String, String>> lookupFields = new List<Map<String, String>>();
        
        Schema.DescribeSObjectResult targetDescribe = Schema.getGlobalDescribe().get(targetObjectAPI).getDescribe();
        Map<String, Schema.SObjectField> fieldMap = targetDescribe.fields.getMap();
        
        for(String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            
            // Check if it's a lookup/master-detail to source object
            if(fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();
                for(Schema.SObjectType refType : references) {
                    if(refType.getDescribe().getName() == sourceObjectAPI) {
                        lookupFields.add(new Map<String, String>{
                            'label' => fieldDescribe.getLabel(),
                            'value' => fieldDescribe.getName()
                        });
                    }
                }
            }
        }
        
        return lookupFields;
    }
    
    /**
     * Get fields from specific object
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFieldsForObject(String objectAPI) {
        Map<String, Object> result = new Map<String, Object>();
        
        List<Map<String, String>> fields = new List<Map<String, String>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectAPI).getDescribe().fields.getMap();
        
        // Get object label for display
        String objectLabel = Schema.getGlobalDescribe().get(objectAPI).getDescribe().getLabel();
        
        for(String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            if(dfr.getType() == Schema.DisplayType.CURRENCY || 
               dfr.getType() == Schema.DisplayType.DOUBLE ||
               dfr.getType() == Schema.DisplayType.PERCENT ) { 
                   fields.add(new Map<String, String>{
                       'label' => dfr.getLabel() + ' (' + objectLabel + ')',
                           'value' => fieldName,
                           'type' => String.valueOf(dfr.getType()),
                           'objectLabel' => objectLabel
                           });
               }
        }
        
        result.put('fields', fields);
        
        return result;
    }
    
    /**
 	* Get combined fields from both Source and Target objects
 	* With clear labels showing which object they're from
 	*/
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getCombinedFieldsForStep(String sourceObjectAPI, String targetObjectAPI) {
        Map<String, Object> result = new Map<String, Object>();
        
        List<Map<String, String>> allFields = new List<Map<String, String>>();
        
        // Get Source Object fields
        Map<String, Schema.SObjectField> sourceFieldMap = Schema.getGlobalDescribe().get(sourceObjectAPI).getDescribe().fields.getMap();
        String sourceLabel = Schema.getGlobalDescribe().get(sourceObjectAPI).getDescribe().getLabel();
        
        for(String fieldName : sourceFieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = sourceFieldMap.get(fieldName).getDescribe();
            if(dfr.getType() == Schema.DisplayType.CURRENCY || 
               dfr.getType() == Schema.DisplayType.DOUBLE ||
               dfr.getType() == Schema.DisplayType.PERCENT ||
               dfr.getType() == Schema.DisplayType.INTEGER) {
                   allFields.add(new Map<String, String>{
                       'label' => '🔵 ' + dfr.getLabel() + ' [' + sourceLabel + ']',
                           'value' => fieldName,
                           'type' => String.valueOf(dfr.getType()),
                           'source' => 'source'
                           });
               }
        }
        
        // Get Target Object fields
        Map<String, Schema.SObjectField> targetFieldMap = Schema.getGlobalDescribe().get(targetObjectAPI).getDescribe().fields.getMap();
        String targetLabel = Schema.getGlobalDescribe().get(targetObjectAPI).getDescribe().getLabel();
        
        for(String fieldName : targetFieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = targetFieldMap.get(fieldName).getDescribe();
            if(dfr.getType() == Schema.DisplayType.CURRENCY || 
               dfr.getType() == Schema.DisplayType.DOUBLE ||
               dfr.getType() == Schema.DisplayType.PERCENT ||
               dfr.getType() == Schema.DisplayType.INTEGER ) {
                   allFields.add(new Map<String, String>{
                       'label' => '🟢 ' + dfr.getLabel() + ' [' + targetLabel + ']',
                           'value' => fieldName,
                           'type' => String.valueOf(dfr.getType()),
                           'source' => 'target'
                           });
               }
        }
        
        result.put('sourceFields', allFields);
        result.put('targetFields', allFields); // Same list, just different property names for compatibility
        
        return result;
    }
    
    /**
     * Save calculation template
     */
    @AuraEnabled
    public static Id saveTemplate(String templateData) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(templateData);
        
        Project_Calculation_Template__c template = new Project_Calculation_Template__c();
        
        if(data.containsKey('Id') && data.get('Id') != null) {
            template.Id = (Id) data.get('Id');
        }
        
        template.Template_Name__c = (String) data.get('templateName');
        template.Description__c = (String) data.get('description');
        template.Project__c = (Id) data.get('projectId');
        template.Is_Active__c = (Boolean) data.get('isActive');
        
        // Dynamic object fields
        template.Source_Object_API_Name__c = (String) data.get('sourceObject');
        template.Target_Object_API_Name__c = (String) data.get('targetObject');
        template.Source_Lookup_Field__c = (String) data.get('sourceLookupField');
        template.Calculation_Detail_Field__c = (String) data.get('calculationDetailField');

        upsert template;
        
        return template.Id;
    }
    
    /**
     * Save calculation steps
     */
    @AuraEnabled
    public static void saveSteps(Id templateId, String stepsData) {
        List<Object> stepsJson = (List<Object>) JSON.deserializeUntyped(stepsData);
        
        // Delete existing steps
        delete [SELECT Id FROM Calculation_Step__c WHERE Project_Calculation_Template__c = :templateId];
        
        // Insert new steps
        List<Calculation_Step__c> steps = new List<Calculation_Step__c>();
        
        for(Object stepObj : stepsJson) {
            Map<String, Object> stepData = (Map<String, Object>) stepObj;
            
            Calculation_Step__c step = new Calculation_Step__c();
            step.Project_Calculation_Template__c = templateId;
            step.Step_Number__c = (Decimal) stepData.get('stepNumber');
            step.Step_Label__c = (String) stepData.get('stepLabel');
            step.Variable_Name__c = (String) stepData.get('variableName');
            step.Formula_Expression__c = (String) stepData.get('formula');
            step.Store_In_Field__c = (String) stepData.get('storeInField');
            step.Is_Active__c = true;
            step.Description__c = (String) stepData.get('description');
            
            steps.add(step);
        }
        
        insert steps;
    }
    
    /**
     * Delete template
     */
    @AuraEnabled
    public static void deleteTemplate(Id templateId) {
        delete [SELECT Id FROM Project_Calculation_Template__c WHERE Id = :templateId];
    }
    
    /**
     * Activate/Deactivate template
     */
    @AuraEnabled
    public static void toggleTemplateStatus(Id templateId, Boolean isActive) {
        // Deactivate all templates for this project first if activating
        if(isActive) {
            Project_Calculation_Template__c template = [SELECT Project__c FROM Project_Calculation_Template__c WHERE Id = :templateId];
            List<Project_Calculation_Template__c> templates = [SELECT Id FROM Project_Calculation_Template__c WHERE Project__c = :template.Project__c];
            for(Project_Calculation_Template__c t : templates) {
                t.Is_Active__c = false;
            }
            update templates;
        }
        
        // Update the selected template
        Project_Calculation_Template__c template = new Project_Calculation_Template__c(Id = templateId, Is_Active__c = isActive);
        update template;
    }
    
    /**
     * Test calculation with a specific unit (for UI testing only)
     */
    @AuraEnabled
    public static Map<String, Object> testCalculation(Id templateId, Id unitId) {
        try {
            Project_Calculation_Template__c template = getTemplateWithSteps(templateId);

            // Get source record with all fields
            String sourceObjectAPI = template.Source_Object_API_Name__c;
            Map<Id, SObject> unitMap = getRecordsWithAllFieldsDynamic(new Set<Id>{unitId}, sourceObjectAPI);
            SObject unit = unitMap.get(unitId);

            if(unit == null) {
                return new Map<String, Object>{
                    'success' => false,
                    'error' => 'Unit not found'
                };
            }

            // Try to find an existing target record linked to this source record
            // so target field values are available for calculation
            String targetObjectAPI = template.Target_Object_API_Name__c;
            String lookupField = template.Source_Lookup_Field__c;
            SObject targetRecord = queryExistingTargetRecord(targetObjectAPI, lookupField, unitId);

            // If no existing target record, create an empty one
            if(targetRecord == null) {
                targetRecord = Schema.getGlobalDescribe().get(targetObjectAPI).newSObject();
                targetRecord.put(lookupField, unitId);
            }

            Map<String, Object> result = new Map<String, Object>();
            Map<String, Decimal> variableMap = new Map<String, Decimal>();
            List<Map<String, Object>> stepResults = new List<Map<String, Object>>();

            for(Calculation_Step__c step : template.Calculation_Steps__r) {
                if(!step.Is_Active__c) continue;

                String formula = step.Formula_Expression__c;

                // Replace fields with actual values from both target and source records
                formula = replaceFieldsForTest(formula, targetRecord, unit, targetObjectAPI, sourceObjectAPI);

                // Replace variables from previous steps
                formula = replaceVariablesForTest(formula, variableMap);

                Decimal stepResult = FormulaCalculationService.evaluateFormulaPublic(formula);

                if(String.isNotBlank(step.Variable_Name__c)) {
                    variableMap.put(step.Variable_Name__c, stepResult);
                }

                // Store result on in-memory target so subsequent steps can read it
                if(String.isNotBlank(step.Store_In_Field__c)) {
                    try {
                        targetRecord.put(step.Store_In_Field__c, stepResult);
                    } catch(Exception e) { /* field may not exist on target */ }
                }

                stepResults.add(new Map<String, Object>{
                    'stepLabel' => step.Step_Label__c,
                    'formula' => step.Formula_Expression__c,
                    'result' => stepResult
                });
            }

            result.put('stepResults', stepResults);
            result.put('finalResult', variableMap.isEmpty() ? 0 : variableMap.values()[variableMap.values().size() - 1]);
            result.put('success', true);

            return result;

        } catch(Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'error' => e.getMessage() + ' | ' + e.getStackTraceString()
            };
        }
    }

    /**
     * Query for an existing target record linked to the source record
     * Returns the record with all calculable fields, or null if none exists
     */
    private static SObject queryExistingTargetRecord(String targetObjectAPI, String lookupField, Id sourceId) {
        try {
            Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(targetObjectAPI).getDescribe().fields.getMap();
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

            String query = 'SELECT ' + String.join(fields, ', ') +
                ' FROM ' + targetObjectAPI +
                ' WHERE ' + lookupField + ' = :sourceId' +
                ' ORDER BY CreatedDate DESC LIMIT 1';
            List<SObject> records = Database.query(query);
            return records.isEmpty() ? null : records[0];
        } catch(Exception e) {
            return null;
        }
    }

    private static String replaceFieldsForTest(String formula, SObject targetRecord, SObject unit, String targetObjectAPI, String sourceObjectAPI) {
        Map<String, Schema.SObjectField> targetFields = Schema.getGlobalDescribe().get(targetObjectAPI).getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> sourceFields = Schema.getGlobalDescribe().get(sourceObjectAPI).getDescribe().fields.getMap();

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
                    value = unit.get(fieldName);
                    fieldType = sourceFields.get(fieldName).getDescribe().getType();
                } catch(Exception e) {}
            }

            // Convert value based on type (matches FormulaCalculationService logic)
            if(value != null) {
                if(fieldType == Schema.DisplayType.PICKLIST) {
                    String picklistValue = String.valueOf(value);
                    replacements.put(fieldName, '"' + picklistValue + '"');
                } else if(value instanceof Decimal || value instanceof Double || value instanceof Integer) {
                    replacements.put(fieldName, String.valueOf(value));
                } else if(value instanceof Boolean) {
                    replacements.put(fieldName, (Boolean)value ? '1' : '0');
                } else {
                    replacements.put(fieldName, '0');
                }
            } else {
                replacements.put(fieldName, '0');
            }
        }

        for(String fieldName : replacements.keySet()) {
            formula = formula.replaceAll('\\b' + fieldName + '\\b', replacements.get(fieldName));
        }

        return formula;
    }
    
    private static String replaceVariablesForTest(String formula, Map<String, Decimal> variableMap) {
        for(String varName : variableMap.keySet()) {
            if(formula.contains(varName)) {
                formula = formula.replaceAll('\\b' + varName + '\\b', String.valueOf(variableMap.get(varName)));
            }
        }
        return formula;
    }
    
    private static Map<Id, SObject> getRecordsWithAllFieldsDynamic(Set<Id> recordIds, String objectAPI) {
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
     * Get units for a project (for testing) - dynamic
     */
    @AuraEnabled(cacheable=true)
    public static List<SObject> getUnitsForProject(Id projectId, String objectAPI) {
        String query = 'SELECT Id, Name FROM ' + objectAPI + ' WHERE Project__c = :projectId ORDER BY Name LIMIT 1000';
        return Database.query(query);
    }
    
    /**
     * Get records for testing - dynamic
     */
    @AuraEnabled(cacheable=true)
    public static List<SObject> getRecordsForObject(String objectAPI, Id projectId) {
        String query = 'SELECT Id, Name FROM ' + objectAPI + ' WHERE Project__c = :projectId ORDER BY Name LIMIT 1000';
        return Database.query(query);
    }

    /**
     * Get rich text (HTML) fields for an object - for calculation detail storage
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getRichTextFields(String objectAPI) {
        List<Map<String, String>> richTextFields = new List<Map<String, String>>();

        if (String.isBlank(objectAPI)) return richTextFields;

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectAPI);
        if (objType == null) return richTextFields;

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            if (dfr.getType() == Schema.DisplayType.TEXTAREA && dfr.isHtmlFormatted() && dfr.isUpdateable()) {
                richTextFields.add(new Map<String, String>{
                    'label' => dfr.getLabel(),
                    'value' => dfr.getName()
                });
            }
        }

        return richTextFields;
    }
}