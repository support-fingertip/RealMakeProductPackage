/**
 * @description Controller for Dynamic Approval LWC components
 * Handles configuration management and approval submission
 */
public with sharing class DynamicApprovalController {

    // Standard objects to include in approval config (extend as needed)
    private static final Set<String> STANDARD_OBJECTS_FOR_APPROVAL = new Set<String>{
        'Account', 'Contact', 'Opportunity', 'Case', 'Lead', 'Order', 'Contract'
    };

    // Step category constants
    private static final String CATEGORY_COMPLETED = 'COMPLETED';
    private static final String CATEGORY_REJECTED = 'REJECTED';
    private static final String CATEGORY_IN_PROGRESS = 'IN_PROGRESS';
    private static final String CATEGORY_AVAILABLE = 'AVAILABLE';
    private static final String CATEGORY_LOCKED = 'LOCKED';

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAvailableObjects() {
        List<ObjectOption> options = new List<ObjectOption>();

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (String objName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult describeResult = globalDescribe.get(objName).getDescribe();

            if (describeResult.isCustom() || STANDARD_OBJECTS_FOR_APPROVAL.contains(describeResult.getName())) {
                if (describeResult.isAccessible() && describeResult.isUpdateable()) {
                    options.add(new ObjectOption(
                        describeResult.getLabel(),
                        describeResult.getName()
                    ));
                }
            }
        }
        
        options.sort();
        return options;
    }
    
    /**
     * @description Get object API name from a record ID
     * @param recordId The record ID
     * @return Object API name
     */
    @AuraEnabled(cacheable=true)
    public static String getObjectApiNameFromRecordId(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record ID cannot be null');
        }
        
        try {
            return recordId.getSObjectType().getDescribe().getName();
        } catch (Exception e) {
            throw new AuraHandledException('Error getting object API name: ' + e.getMessage());
        }
    }
    
    /**
     * @description Discover all User lookup fields for an object (2 levels deep)
     * @param objectApiName API name of the object
     * @return List of field paths that resolve to User
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldPathOption> discoverUserLookupFields(String objectApiName) {
        return FieldDiscoveryService.discoverUserLookups(objectApiName);
    }
    
    /**
     * @description Discover all picklist fields for an object (for status field selection)
     * @param objectApiName API name of the object
     * @return List of picklist field options
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> discoverPicklistFields(String objectApiName) {
        List<FieldOption> options = new List<FieldOption>();
        
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            return options;
        }
        
        Map<String, Schema.SObjectField> fieldsMap = objectType.getDescribe().fields.getMap();
        
        for (String fieldName : fieldsMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
            
            if (fieldDescribe.isAccessible() && 
                fieldDescribe.getType() == Schema.DisplayType.PICKLIST) {
                options.add(new FieldOption(
                    fieldDescribe.getLabel(),
                    fieldDescribe.getName()
                ));
            }
        }
        
        return options;
    }
    
    /**
     * @description Get picklist values for a specific field
     * @param objectApiName API name of the object
     * @param fieldApiName API name of the field
     * @return List of picklist values
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistValueOption> getPicklistValues(String objectApiName, String fieldApiName) {
        List<PicklistValueOption> options = new List<PicklistValueOption>();
        
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            return options;
        }
        
        Schema.SObjectField field = objectType.getDescribe().fields.getMap().get(fieldApiName);
        if (field == null) {
            return options;
        }
        
        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
        List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistEntries) {
            if (entry.isActive()) {
                options.add(new PicklistValueOption(entry.getLabel(), entry.getValue()));
            }
        }
        
        return options;
    }
    
    /**
     * @description Discover all fields for an object (for field updates)
     * @param objectApiName API name of the object
     * @return List of field options
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> discoverAllFields(String objectApiName) {
        List<FieldOption> options = new List<FieldOption>();
        
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            return options;
        }
        
        Map<String, Schema.SObjectField> fieldsMap = objectType.getDescribe().fields.getMap();
        
        for (String fieldName : fieldsMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
            
            if (fieldDescribe.isAccessible() && fieldDescribe.isUpdateable()) {
                options.add(new FieldOption(
                    fieldDescribe.getLabel(),
                    fieldDescribe.getName()
                ));
            }
        }
        
        return options;
    }
    
    /**
     * @description Get all fields for an object (for merge field picker)
     * @param objectApiName The API name of the object
     * @return List of field options
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getObjectFields(String objectApiName) {
        List<FieldOption> fieldOptions = new List<FieldOption>();
        
        try {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            
            if (sObjectType == null) {
                return fieldOptions;
            }
            
            Map<String, Schema.SObjectField> fieldsMap = sObjectType.getDescribe().fields.getMap();
            
            for (String fieldName : fieldsMap.keySet()) {
                Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
                
                // Skip non-accessible fields
                if (!fieldDescribe.isAccessible()) {
                    continue;
                }
                
                // Include text, number, date, datetime, picklist, email, phone, url fields
                Schema.DisplayType fieldType = fieldDescribe.getType();
                
                if (fieldType == Schema.DisplayType.STRING ||
                    fieldType == Schema.DisplayType.TEXTAREA ||
                    fieldType == Schema.DisplayType.EMAIL ||
                    fieldType == Schema.DisplayType.PHONE ||
                    fieldType == Schema.DisplayType.URL ||
                    fieldType == Schema.DisplayType.INTEGER ||
                    fieldType == Schema.DisplayType.DOUBLE ||
                    fieldType == Schema.DisplayType.CURRENCY ||
                    fieldType == Schema.DisplayType.PERCENT ||
                    fieldType == Schema.DisplayType.DATE ||
                    fieldType == Schema.DisplayType.DATETIME ||
                    fieldType == Schema.DisplayType.PICKLIST ||
                    fieldType == Schema.DisplayType.BOOLEAN ||
                    fieldType == Schema.DisplayType.ID ||
                    fieldType == Schema.DisplayType.REFERENCE) {
                        
                        fieldOptions.add(new FieldOption(
                            fieldDescribe.getLabel(),
                            fieldDescribe.getName()
                        ));
                    }
            }
            
            // Sort by label using a custom comparator
            fieldOptions.sort();
            
        } catch (Exception e) {
            System.debug('Error getting object fields: ' + e.getMessage());
            throw new AuraHandledException('Error getting object fields: ' + e.getMessage());
        }
        
        return fieldOptions;
    }
    
    /**
     * @description Get all configurations for an object
     * @param objectApiName API name of the object
     * @return List of approval configurations
     */
    @AuraEnabled(cacheable=true)
    public static List<Approval_Configuration__c> getConfigurationsForObject(String objectApiName) {
        return [
            SELECT Id, Name, Object_API_Name__c, Process_Type__c, Process_Label__c,
                   Is_Active__c, Sequence_Order__c,
                   Status_Field_API_Name__c, Approved_Status_Value__c,
                   Rejected_Status_Value__c, Pending_Status_Value__c,
                   Prerequisite_Process_Type__c, Prerequisite_Status_Value__c,
                   Steps_JSON__c, On_Approval_JSON__c, On_Rejection_JSON__c,
                   Approval_Process_API_Name__c, Required_Fields_JSON__c, Matching_Criteria__c,
                   CreatedDate, LastModifiedDate
            FROM Approval_Configuration__c
            WHERE Object_API_Name__c = :objectApiName
            ORDER BY Sequence_Order__c NULLS LAST, Process_Label__c
        ];
    }
    
    /**
     * @description Get all configurations (for configuration tab)
     * @return List of all approval configurations
     */
    @AuraEnabled(cacheable=true)
    public static List<Approval_Configuration__c> getAllConfigurations() {
        return [
            SELECT Id, Name, Object_API_Name__c, Process_Type__c, Process_Label__c,
                   Is_Active__c, Sequence_Order__c,
                   Status_Field_API_Name__c, Approved_Status_Value__c,
                   Rejected_Status_Value__c, Pending_Status_Value__c,
                   Prerequisite_Process_Type__c, Prerequisite_Status_Value__c,
                   Steps_JSON__c, On_Approval_JSON__c, On_Rejection_JSON__c,
                   Approval_Process_API_Name__c, Required_Fields_JSON__c, Matching_Criteria__c,
                   CreatedDate, LastModifiedDate
            FROM Approval_Configuration__c
            ORDER BY Object_API_Name__c, Sequence_Order__c NULLS LAST, Process_Label__c
        ];
    }
    
    /**
     * @description Get approval processes with their current status for a specific record
     * @param recordId The record ID
     * @return Wrapper containing categorized approval processes
     */
    @AuraEnabled
    public static ApprovalStatusWrapper getApprovalStatusForRecord(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record ID cannot be null');
        }
        
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        
        // Get all active configurations for this object
        List<Approval_Configuration__c> configs = [
            SELECT Id, Name, Object_API_Name__c, Process_Type__c, Process_Label__c,
                   Sequence_Order__c,
                   Status_Field_API_Name__c, Approved_Status_Value__c, 
                   Rejected_Status_Value__c, Pending_Status_Value__c,
                   Prerequisite_Process_Type__c, Prerequisite_Status_Value__c,
                   Steps_JSON__c, Approval_Process_API_Name__c
            FROM Approval_Configuration__c
            WHERE Object_API_Name__c = :objectApiName
            AND Is_Active__c = true
            ORDER BY Sequence_Order__c NULLS LAST, Process_Label__c
        ];
        
        if (configs.isEmpty()) {
            return new ApprovalStatusWrapper();
        }
        
        // Build dynamic query to get all status fields
        Set<String> statusFields = new Set<String>{'Id'};
        for (Approval_Configuration__c config : configs) {
            if (String.isNotBlank(config.Status_Field_API_Name__c)) {
                statusFields.add(config.Status_Field_API_Name__c);
            }
        }
        
        String query = 'SELECT ' + String.join(new List<String>(statusFields), ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE Id = :recordId LIMIT 1';
        
        List<SObject> records = Database.query(query);
        if (records.isEmpty()) {
            throw new AuraHandledException('Record not found');
        }
        
        SObject record = records[0];
        
        // Build a map of process type to status value
        Map<String, String> processTypeToStatus = new Map<String, String>();
        for (Approval_Configuration__c config : configs) {
            if (String.isNotBlank(config.Status_Field_API_Name__c)) {
                Object statusValue = record.get(config.Status_Field_API_Name__c);
                processTypeToStatus.put(
                    config.Process_Type__c, 
                    statusValue != null ? String.valueOf(statusValue) : null
                );
            }
        }
        
        // Categorize each configuration
        ApprovalStatusWrapper wrapper = new ApprovalStatusWrapper();
        
        for (Approval_Configuration__c config : configs) {
            ApprovalProcessStatus processStatus = new ApprovalProcessStatus(config);
            
            String currentStatus = processTypeToStatus.get(config.Process_Type__c);
            processStatus.currentStatusValue = currentStatus;
            
            // Determine category
            if (String.isNotBlank(currentStatus)) {
                if (currentStatus == config.Approved_Status_Value__c) {
                    processStatus.category = CATEGORY_COMPLETED;
                    processStatus.categoryLabel = PostSalesConstants.SCHEDULE_STATUS_COMPLETED;
                    processStatus.statusMessage = PostSalesConstants.APPROVAL_STATUS_APPROVED;
                    wrapper.completed.add(processStatus);
                } else if (currentStatus == config.Rejected_Status_Value__c) {
                    processStatus.category = CATEGORY_REJECTED;
                    processStatus.categoryLabel = PostSalesConstants.APPROVAL_STATUS_REJECTED;
                    processStatus.statusMessage = PostSalesConstants.APPROVAL_STATUS_REJECTED + ' - Can resubmit';
                    processStatus.canResubmit = true;
                    wrapper.available.add(processStatus);
                } else if (currentStatus == config.Pending_Status_Value__c) {
                    processStatus.category = CATEGORY_IN_PROGRESS;
                    processStatus.categoryLabel = 'In Progress';
                    processStatus.statusMessage = 'Pending approval';
                    wrapper.inProgress.add(processStatus);
                } else {
                    processStatus.category = CATEGORY_AVAILABLE;
                    processStatus.categoryLabel = PostSalesConstants.UNIT_STATUS_AVAILABLE;
                    wrapper.available.add(processStatus);
                }
            } else {
                // No status set - check prerequisites
                if (String.isNotBlank(config.Prerequisite_Process_Type__c)) {
                    String prerequisiteStatus = processTypeToStatus.get(config.Prerequisite_Process_Type__c);

                    if (prerequisiteStatus == config.Prerequisite_Status_Value__c) {
                        processStatus.category = CATEGORY_AVAILABLE;
                        processStatus.categoryLabel = PostSalesConstants.UNIT_STATUS_AVAILABLE;
                        processStatus.prerequisiteMet = true;
                        processStatus.statusMessage = 'Prerequisite completed';
                        wrapper.available.add(processStatus);
                    } else {
                        processStatus.category = CATEGORY_LOCKED;
                        processStatus.categoryLabel = 'Locked';
                        processStatus.prerequisiteMet = false;
                        processStatus.statusMessage = 'Requires: ' + config.Prerequisite_Process_Type__c;
                        wrapper.locked.add(processStatus);
                    }
                } else {
                    processStatus.category = CATEGORY_AVAILABLE;
                    processStatus.categoryLabel = PostSalesConstants.UNIT_STATUS_AVAILABLE;
                    processStatus.statusMessage = 'Ready to submit';
                    wrapper.available.add(processStatus);
                }
            }
        }
        
        return wrapper;
    }
    
    /**
     * @description Save an approval configuration
     * @param configJson The configuration as JSON string
     * @return Saved configuration record
     */
    @AuraEnabled
    public static Approval_Configuration__c saveConfiguration(String configJson) {
        try {
            Approval_Configuration__c config = (Approval_Configuration__c) JSON.deserialize(
                configJson, 
                Approval_Configuration__c.class
            );
            upsert config;
            return config;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving configuration: ' + e.getMessage());
        }
    }
    
    /**
     * @description Delete an approval configuration
     * @param configId The configuration ID to delete
     */
    @AuraEnabled
    public static void deleteConfiguration(Id configId) {
        try {
            delete [SELECT Id FROM Approval_Configuration__c WHERE Id = :configId];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting configuration: ' + e.getMessage());
        }
    }
    
    /**
     * @description Preview approvers for a record before submission
     * @param recordId The record ID
     * @param configId The configuration ID
     * @return List of approver previews
     */
    @AuraEnabled
    public static List<ApproverPreview> previewApprovers(Id recordId, Id configId) {
        if (recordId == null) {
            throw new AuraHandledException('Record ID cannot be null');
        }
        if (configId == null) {
            throw new AuraHandledException('Configuration ID cannot be null');
        }
        
        try {
            return DynamicApprovalService.previewApprovers(recordId, configId);
        } catch (Exception e) {
            throw new AuraHandledException('Error previewing approvers: ' + e.getMessage());
        }
    }
    
    /**
     * @description Submit a record for approval
     * @param recordId The record ID to submit
     * @param configId The configuration ID to use
     * @param comments Optional submission comments
     * @return Approval result
     */
    @AuraEnabled
    public static ApprovalResult submitForApproval(Id recordId, Id configId, String comments) {
        if (recordId == null) {
            throw new AuraHandledException('Record ID cannot be null');
        }
        if (configId == null) {
            throw new AuraHandledException('Configuration ID cannot be null');
        }
        
        try {
            // Validate required fields before submitting
            List<RequiredFieldStatus> fieldStatuses = validateRequiredFieldsInternal(recordId, configId);
            for (RequiredFieldStatus fs : fieldStatuses) {
                if (!fs.isFilled) {
                    throw new AuraHandledException('Required field "' + fs.fieldLabel + '" must be filled before submitting for approval.');
                }
            }
            return DynamicApprovalService.submitForApproval(recordId, configId, comments);
        } catch (AuraHandledException ae) {
            throw ae;
        } catch (Exception e) {
            System.debug('Error in submitForApproval: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error submitting for approval: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<RequiredFieldStatus> getRequiredFieldsStatus(Id recordId, Id configId) {
        return validateRequiredFieldsInternal(recordId, configId);
    }

    private static List<RequiredFieldStatus> validateRequiredFieldsInternal(Id recordId, Id configId) {
        List<RequiredFieldStatus> result = new List<RequiredFieldStatus>();

        Approval_Configuration__c config = [
            SELECT Required_Fields_JSON__c, Object_API_Name__c
            FROM Approval_Configuration__c WHERE Id = :configId LIMIT 1
        ];

        if (String.isBlank(config.Required_Fields_JSON__c)) {
            return result;
        }

        List<Object> fieldList = (List<Object>) JSON.deserializeUntyped(config.Required_Fields_JSON__c);
        if (fieldList.isEmpty()) return result;

        // Build field API names list and a map for labels
        Set<String> fieldApiNames = new Set<String>();
        Map<String, String> labelMap = new Map<String, String>();
        for (Object item : fieldList) {
            Map<String, Object> fieldDef = (Map<String, Object>) item;
            String apiName = (String) fieldDef.get('apiName');
            String label = (String) fieldDef.get('label');
            fieldApiNames.add(apiName);
            labelMap.put(apiName, label);
        }

        // Get field describe info for types
        Schema.SObjectType sType = Schema.getGlobalDescribe().get(config.Object_API_Name__c);
        Map<String, Schema.SObjectField> fieldMap = sType != null ? sType.getDescribe().fields.getMap() : new Map<String, Schema.SObjectField>();

        // Query the record for these fields
        String soql = 'SELECT ' + String.join(new List<String>(fieldApiNames), ', ')
            + ' FROM ' + config.Object_API_Name__c
            + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> records = Database.query(soql);

        if (records.isEmpty()) return result;

        SObject record = records[0];
        for (String apiName : fieldApiNames) {
            RequiredFieldStatus fs = new RequiredFieldStatus();
            fs.fieldApiName = apiName;
            fs.fieldLabel = labelMap.get(apiName);
            Object val = record.get(apiName);
            fs.isFilled = val != null && String.valueOf(val).trim().length() > 0;
            fs.currentValue = val != null ? String.valueOf(val) : '';

            // Add field type info for inline editing
            Schema.SObjectField sField = fieldMap.get(apiName.toLowerCase());
            if (sField != null) {
                Schema.DescribeFieldResult dfr = sField.getDescribe();
                Schema.DisplayType dt = dfr.getType();
                if (dt == Schema.DisplayType.DATE) fs.fieldType = 'date';
                else if (dt == Schema.DisplayType.DATETIME) fs.fieldType = 'datetime';
                else if (dt == Schema.DisplayType.CURRENCY) fs.fieldType = 'currency';
                else if (dt == Schema.DisplayType.DOUBLE || dt == Schema.DisplayType.INTEGER || dt == Schema.DisplayType.PERCENT) fs.fieldType = 'number';
                else if (dt == Schema.DisplayType.BOOLEAN) fs.fieldType = 'checkbox';
                else if (dt == Schema.DisplayType.EMAIL) fs.fieldType = 'email';
                else if (dt == Schema.DisplayType.PHONE) fs.fieldType = 'phone';
                else if (dt == Schema.DisplayType.URL) fs.fieldType = 'url';
                else if (dt == Schema.DisplayType.PICKLIST) {
                    fs.fieldType = 'picklist';
                    fs.picklistValues = new List<Map<String, String>>();
                    fs.picklistValues.add(new Map<String, String>{ 'label' => '-- Select --', 'value' => '' });
                    for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                        if (pe.isActive()) {
                            fs.picklistValues.add(new Map<String, String>{ 'label' => pe.getLabel(), 'value' => pe.getValue() });
                        }
                    }
                }
                else fs.fieldType = 'text';
            } else {
                fs.fieldType = 'text';
            }

            result.add(fs);
        }

        return result;
    }
    
    /**
     * @description Get all email templates for notification configuration
     * @return List of email template options
     */
    @AuraEnabled(cacheable=true)
    public static List<EmailTemplateOption> getEmailTemplates() {
        List<EmailTemplateOption> options = new List<EmailTemplateOption>();
        
        for (EmailTemplate template : [
            SELECT Id, Name, DeveloperName, FolderId, Folder.Name
            FROM EmailTemplate
            WHERE IsActive = true
            ORDER BY Name
            LIMIT 200
        ]) {
            options.add(new EmailTemplateOption(
                template.Name + ' (' + template.Folder.Name + ')',
                template.DeveloperName
            ));
        }
        
        return options;
    }
    
    /**
     * @description Get custom Email Template Config records for selection in approval actions
     * @return List of email config template options with Id and Name
     */
    @AuraEnabled(cacheable=true)
    public static List<EmailTemplateOption> getEmailConfigTemplates() {
        List<EmailTemplateOption> options = new List<EmailTemplateOption>();

        for (Email_Template_Config__c config : [
            SELECT Id, Template_Name__c, Object_API_Name__c
            FROM Email_Template_Config__c
            WHERE Is_Active__c = true
            ORDER BY Template_Name__c ASC
            LIMIT 200
        ]) {
            String label = config.Template_Name__c;
            if (config.Object_API_Name__c != null) {
                label += ' (' + config.Object_API_Name__c + ')';
            }
            options.add(new EmailTemplateOption(label, config.Id));
        }

        return options;
    }

    /**
     * @description Get other approval configurations for prerequisite selection
     * @param objectApiName API name of the object
     * @param currentConfigId Current config ID to exclude
     * @return List of available prerequisite options
     */
    @AuraEnabled(cacheable=true)
    public static List<PrerequisiteOption> getPrerequisiteOptions(String objectApiName, Id currentConfigId) {
        List<PrerequisiteOption> options = new List<PrerequisiteOption>();
        
        // Add empty option
        options.add(new PrerequisiteOption('-- None --', ''));
        
        String query = 'SELECT Id, Process_Type__c, Process_Label__c FROM Approval_Configuration__c ' +
                       'WHERE Object_API_Name__c = :objectApiName';
        
        if (currentConfigId != null) {
            query += ' AND Id != :currentConfigId';
        }
        
        query += ' ORDER BY Sequence_Order__c NULLS LAST, Process_Label__c';
        
        for (Approval_Configuration__c config : Database.query(query)) {
            options.add(new PrerequisiteOption(
                config.Process_Label__c,
                config.Process_Type__c
            ));
        }
        
        return options;
    }
    
    // ============ Wrapper Classes ============
    
    public class ObjectOption implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public ObjectOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
        
        public Integer compareTo(Object compareTo) {
            ObjectOption other = (ObjectOption) compareTo;
            return this.label.compareTo(other.label);
        }
    }
    
    public class FieldOption implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public FieldOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
        
        public Integer compareTo(Object compareTo) {
            FieldOption other = (FieldOption) compareTo;
            return this.label.compareTo(other.label);
        }
    }
    
    public class FieldPathOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Integer level;
        @AuraEnabled public String targetObject;
        
        public FieldPathOption(String label, String value, Integer level, String targetObject) {
            this.label = label;
            this.value = value;
            this.level = level;
            this.targetObject = targetObject;
        }
    }
    
    public class PicklistValueOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public PicklistValueOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    public class EmailTemplateOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public EmailTemplateOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    public class PrerequisiteOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public PrerequisiteOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
    
    public class ApproverPreview {
        @AuraEnabled public Integer stepNumber;
        @AuraEnabled public String stepName;
        @AuraEnabled public String fieldPath;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public Id approverId;
        @AuraEnabled public String approverName;
        @AuraEnabled public Boolean isFound;
        @AuraEnabled public String message;
        
        public ApproverPreview(Integer stepNumber, String stepName, String fieldPath, String fieldLabel) {
            this.stepNumber = stepNumber;
            this.stepName = stepName;
            this.fieldPath = fieldPath;
            this.fieldLabel = fieldLabel;
            this.isFound = false;
            this.message = 'Not configured';
        }
    }
    
    public class ApprovalResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Id processInstanceId;
        
        public ApprovalResult(Boolean success, String message, Id processInstanceId) {
            this.success = success;
            this.message = message;
            this.processInstanceId = processInstanceId;
        }
    }
    
    public class ApprovalStatusWrapper {
        @AuraEnabled public List<ApprovalProcessStatus> available;
        @AuraEnabled public List<ApprovalProcessStatus> completed;
        @AuraEnabled public List<ApprovalProcessStatus> inProgress;
        @AuraEnabled public List<ApprovalProcessStatus> locked;
        
        public ApprovalStatusWrapper() {
            this.available = new List<ApprovalProcessStatus>();
            this.completed = new List<ApprovalProcessStatus>();
            this.inProgress = new List<ApprovalProcessStatus>();
            this.locked = new List<ApprovalProcessStatus>();
        }
    }
    
    public class ApprovalProcessStatus {
        @AuraEnabled public Id configId;
        @AuraEnabled public String processType;
        @AuraEnabled public String processLabel;
        @AuraEnabled public Integer numberOfSteps;
        @AuraEnabled public String category;
        @AuraEnabled public String categoryLabel;
        @AuraEnabled public String currentStatusValue;
        @AuraEnabled public String statusMessage;
        @AuraEnabled public Boolean prerequisiteMet;
        @AuraEnabled public String prerequisiteProcessType;
        @AuraEnabled public Boolean canResubmit;
        @AuraEnabled public List<StepInfo> steps;
        
        public ApprovalProcessStatus(Approval_Configuration__c config) {
            this.configId = config.Id;
            this.processType = config.Process_Type__c;
            this.processLabel = config.Process_Label__c;
            this.prerequisiteProcessType = config.Prerequisite_Process_Type__c;
            this.canResubmit = false;
            this.steps = new List<StepInfo>();
            
            // Parse steps from JSON
            if (String.isNotBlank(config.Steps_JSON__c)) {
                try {
                    StepsWrapper stepsWrapper = (StepsWrapper) JSON.deserialize(
                        config.Steps_JSON__c, 
                        StepsWrapper.class
                    );
                    this.numberOfSteps = stepsWrapper.numberOfSteps != null ? stepsWrapper.numberOfSteps : 0;
                    if (stepsWrapper.steps != null) {
                        for (StepConfig step : stepsWrapper.steps) {
                            this.steps.add(new StepInfo(step.stepNumber, step.stepName));
                        }
                    }
                } catch (Exception e) {
                    System.debug('Error parsing Steps_JSON__c: ' + e.getMessage());
                    this.numberOfSteps = 0;
                }
            } else {
                this.numberOfSteps = 0;
            }
        }
    }
    
    public class StepInfo {
        @AuraEnabled public Integer stepNumber;
        @AuraEnabled public String stepName;
        
        public StepInfo(Integer stepNumber, String stepName) {
            this.stepNumber = stepNumber;
            this.stepName = stepName != null ? stepName : '';
        }
    }
    
    public class StepsWrapper {
        public Integer numberOfSteps;
        public List<StepConfig> steps;
    }
    
    public class StepConfig {
        public Integer stepNumber;
        public String stepName;
        public String fieldPath;
        public String fieldLabel;
    }

    public class RequiredFieldStatus {
        @AuraEnabled public String fieldApiName { get; set; }
        @AuraEnabled public String fieldLabel { get; set; }
        @AuraEnabled public Boolean isFilled { get; set; }
        @AuraEnabled public String currentValue { get; set; }
        @AuraEnabled public String fieldType { get; set; }
        @AuraEnabled public List<Map<String, String>> picklistValues { get; set; }
    }

    /**
     * Save required field values to the record before approval submission.
     */
    @AuraEnabled
    public static void saveRequiredFieldValues(Id recordId, Id configId, String fieldValuesJson) {
        if (recordId == null || String.isBlank(fieldValuesJson)) return;

        Approval_Configuration__c config = [
            SELECT Object_API_Name__c FROM Approval_Configuration__c WHERE Id = :configId LIMIT 1
        ];

        Map<String, Object> fieldValues = (Map<String, Object>) JSON.deserializeUntyped(fieldValuesJson);
        if (fieldValues.isEmpty()) return;

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(config.Object_API_Name__c);
        Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();

        SObject record = sType.newSObject(recordId);
        for (String fieldName : fieldValues.keySet()) {
            Object val = fieldValues.get(fieldName);
            Schema.SObjectField sField = fieldMap.get(fieldName.toLowerCase());
            if (sField == null || !sField.getDescribe().isUpdateable()) continue;

            Schema.DisplayType dt = sField.getDescribe().getType();
            if (val == null || (val instanceof String && String.isBlank((String) val))) {
                record.put(fieldName, null);
            } else if (dt == Schema.DisplayType.DATE) {
                record.put(fieldName, Date.valueOf(String.valueOf(val)));
            } else if (dt == Schema.DisplayType.DATETIME) {
                record.put(fieldName, DateTime.valueOf(String.valueOf(val).replace('T', ' ')));
            } else if (dt == Schema.DisplayType.CURRENCY || dt == Schema.DisplayType.DOUBLE || dt == Schema.DisplayType.PERCENT) {
                record.put(fieldName, Decimal.valueOf(String.valueOf(val)));
            } else if (dt == Schema.DisplayType.INTEGER) {
                record.put(fieldName, Integer.valueOf(String.valueOf(val)));
            } else if (dt == Schema.DisplayType.BOOLEAN) {
                record.put(fieldName, Boolean.valueOf(String.valueOf(val)));
            } else {
                record.put(fieldName, String.valueOf(val));
            }
        }

        update record;
    }

    @AuraEnabled
    public static List<User> searchApproverUsers(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<User>();
        }
        String likeKey = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        return [SELECT Id, Name, Email FROM User
                WHERE IsActive = true AND (Name LIKE :likeKey OR Email LIKE :likeKey)
                ORDER BY Name LIMIT 10];
    }
}