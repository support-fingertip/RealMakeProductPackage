/**
 * @description Service class for dynamic approval submission and processing
 */
public with sharing class DynamicApprovalService {
    
    private static final Integer MAX_STEPS = 6;
    
    /**
     * @description Preview approvers without submitting
     * @param recordId The record ID
     * @param configId The configuration ID
     * @return List of approver previews
     */
    public static List<DynamicApprovalController.ApproverPreview> previewApprovers(Id recordId, Id configId) {
        List<DynamicApprovalController.ApproverPreview> previews = new List<DynamicApprovalController.ApproverPreview>();
        
        // Get configuration
        Approval_Configuration__c config = getConfiguration(configId);
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        
        // Parse steps from JSON
        List<StepConfig> steps = parseStepsFromJson(config.Steps_JSON__c);
        
        if (steps.isEmpty()) {
            return previews;
        }
        
        // Build and execute query
        Set<String> fieldPaths = new Set<String>{'Id'};
        for (StepConfig step : steps) {
            if (String.isNotBlank(step.fieldPath)) {
                fieldPaths.add(convertToQueryField(step.fieldPath));
            }
        }
        
        String query = 'SELECT ' + String.join(new List<String>(fieldPaths), ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE Id = :recordId';
        
        SObject record = Database.query(query);
        
        // Collect all approver IDs first
        Set<Id> approverIds = new Set<Id>();
        Map<Integer, Id> stepToApproverId = new Map<Integer, Id>();
        
        for (StepConfig step : steps) {
            if (String.isNotBlank(step.fieldPath)) {
                Id approverId = resolveFieldPath(record, step.fieldPath);
                if (approverId != null) {
                    approverIds.add(approverId);
                    stepToApproverId.put(step.stepNumber, approverId);
                }
            }
        }
        
        // Bulk query user names
        Map<Id, User> usersMap = new Map<Id, User>();
        if (!approverIds.isEmpty()) {
            usersMap = new Map<Id, User>([
                SELECT Id, Name FROM User WHERE Id IN :approverIds
            ]);
        }
        
        // Build previews
        for (StepConfig step : steps) {
            DynamicApprovalController.ApproverPreview preview = 
                new DynamicApprovalController.ApproverPreview(
                    step.stepNumber, 
                    step.stepName, 
                    step.fieldPath,
                    step.fieldLabel
                );
            
            if (String.isNotBlank(step.fieldPath)) {
                Id approverId = stepToApproverId.get(step.stepNumber);
                
                if (approverId != null && usersMap.containsKey(approverId)) {
                    preview.approverId = approverId;
                    preview.isFound = true;
                    preview.approverName = usersMap.get(approverId).Name;
                    preview.message = 'Will be assigned';
                } else {
                    preview.message = 'No user found - Step will be skipped';
                }
            }
            
            previews.add(preview);
        }
        
        return previews;
    }
    
    /**
     * @description Submit a record for approval
     * @param recordId The record ID
     * @param configId The configuration ID
     * @param comments Submission comments
     * @return Approval result
     */
    public static DynamicApprovalController.ApprovalResult submitForApproval(
        Id recordId, 
        Id configId, 
        String comments
    ) {
        // Get configuration
        Approval_Configuration__c config = getConfiguration(configId);
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        
        // Validate object matches
        if (objectApiName != config.Object_API_Name__c) {
            throw new ApprovalException('Record object type does not match configuration');
        }
        
        // Parse steps from JSON
        List<StepConfig> steps = parseStepsFromJson(config.Steps_JSON__c);

        if (steps.isEmpty()) {
            throw new ApprovalException('No approval steps configured for this process');
        }

        // Build query to get all field values
        Set<String> fieldPaths = new Set<String>{'Id'};
        for (StepConfig step : steps) {
            if (String.isNotBlank(step.fieldPath)) {
                fieldPaths.add(convertToQueryField(step.fieldPath));
            }
        }
        
        // Add approver fields to query if they exist
        for (Integer i = 1; i <= MAX_STEPS; i++) {
            String approverField = 'Approver_' + i + '__c';
            if (hasField(objectApiName, approverField)) {
                fieldPaths.add(approverField);
            }
        }
        
        // Add status field if configured
        if (String.isNotBlank(config.Status_Field_API_Name__c)) {
            fieldPaths.add(config.Status_Field_API_Name__c);
        }
        
        String query = 'SELECT ' + String.join(new List<String>(fieldPaths), ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE Id = :recordId';
        
        SObject record = Database.query(query);
        
        // Resolve approvers and update record
        Map<String, Object> fieldsToUpdate = new Map<String, Object>();
        
        // First, clear all approver fields
        for (Integer i = 1; i <= MAX_STEPS; i++) {
            String approverField = 'Approver_' + i + '__c';
            if (hasField(objectApiName, approverField)) {
                fieldsToUpdate.put(approverField, null);
            }
        }
        
        // Then set approvers based on steps
        for (StepConfig step : steps) {
            String approverField = 'Approver_' + step.stepNumber + '__c';
            if (hasField(objectApiName, approverField) && String.isNotBlank(step.fieldPath)) {
                Id approverId = resolveFieldPath(record, step.fieldPath);
                fieldsToUpdate.put(approverField, approverId);
            }
        }
        
        // Set status to Pending if status field is configured
        if (String.isNotBlank(config.Status_Field_API_Name__c) && 
            String.isNotBlank(config.Pending_Status_Value__c)) {
            fieldsToUpdate.put(config.Status_Field_API_Name__c, config.Pending_Status_Value__c);
        }
        
        // Update record with approvers and status
        SObject recordToUpdate = recordId.getSObjectType().newSObject(recordId);
        for (String fieldName : fieldsToUpdate.keySet()) {
            recordToUpdate.put(fieldName, fieldsToUpdate.get(fieldName));
        }
        update recordToUpdate;
        
        // Submit for approval
        Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
        request.setObjectId(recordId);
        
        if (String.isNotBlank(config.Approval_Process_API_Name__c)) {
            request.setProcessDefinitionNameOrId(config.Approval_Process_API_Name__c);
        }
        
        if (String.isNotBlank(comments)) {
            request.setComments(comments);
        }
        
        request.setSkipEntryCriteria(false);
        
        Approval.ProcessResult result = Approval.process(request);
        
        return new DynamicApprovalController.ApprovalResult(
            result.isSuccess(),
            result.isSuccess() ? 'Successfully submitted for approval' : 'Failed to submit:  ' + getErrorMessages(result),
            result.isSuccess() ? result.getInstanceId() : null
        );
    }
    
    /**
     * @description Get error messages from process result
     */
    private static String getErrorMessages(Approval.ProcessResult result) {
        List<String> errors = new List<String>();
        for (Database.Error error : result.getErrors()) {
            errors.add(error.getMessage());
        }
        return String.join(errors, '; ');
    }
    
    /**
     * @description Get configuration record
     */
    private static Approval_Configuration__c getConfiguration(Id configId) {
        return [
            SELECT Id, Object_API_Name__c, Process_Type__c, Process_Label__c,
                   Status_Field_API_Name__c, Approved_Status_Value__c,
                   Rejected_Status_Value__c, Pending_Status_Value__c,
                   Steps_JSON__c, On_Approval_JSON__c, On_Rejection_JSON__c,
                   Approval_Process_API_Name__c
            FROM Approval_Configuration__c
            WHERE Id = :configId
            LIMIT 1
        ];
    }
    
    /**
     * @description Parse steps from JSON
     */
    private static List<StepConfig> parseStepsFromJson(String stepsJson) {
        List<StepConfig> steps = new List<StepConfig>();
        
        if (String.isBlank(stepsJson)) {
            return steps;
        }
        
        try {
            StepsWrapper wrapper = (StepsWrapper) JSON.deserialize(stepsJson, StepsWrapper.class);
            if (wrapper.steps != null) {
                steps = wrapper.steps;
            }
        } catch (Exception e) {
            throw new ApprovalException('Invalid approval steps configuration: ' + e.getMessage());
        }
        
        return steps;
    }
    
    /**
     * @description Convert field path to SOQL query format.
     * Salesforce SOQL natively supports dot-notation relationship paths
     * (e.g., Owner.ManagerId), so no conversion is needed.
     */
    private static String convertToQueryField(String fieldPath) {
        return fieldPath;
    }
    
    /**
     * @description Resolve a field path to get the User ID
     */
    private static Id resolveFieldPath(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) {
            return null;
        }
        
        List<String> pathParts = fieldPath.split('\\.');
        Object currentValue = record;
        
        for (Integer i = 0; i < pathParts.size(); i++) {
            String part = pathParts[i];
            
            if (currentValue == null) {
                return null;
            }
            
            if (currentValue instanceof SObject) {
                SObject currentRecord = (SObject) currentValue;
                
                if (i == pathParts.size() - 1) {
                    // Last part - get the field value
                    currentValue = currentRecord.get(part);
                } else {
                    // Intermediate part - get the related record
                    currentValue = currentRecord.getSObject(part);
                }
            } else {
                return null;
            }
        }
        
        if (currentValue instanceof Id) {
            return (Id) currentValue;
        }
        
        return null;
    }
    
    /**
     * @description Check if object has a specific field
     */
    private static Boolean hasField(String objectApiName, String fieldName) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            return false;
        }
        return objectType.getDescribe().fields.getMap().containsKey(fieldName.toLowerCase());
    }
    
    /**
     * @description Wrapper class for steps JSON
     */
    public class StepsWrapper {
        public Integer numberOfSteps;
        public List<StepConfig> steps;
    }
    
    /**
     * @description Inner class for step configuration
     */
    public class StepConfig {
        public Integer stepNumber;
        public String stepName;
        public String fieldPath;
        public String fieldLabel;
    }
    
    public class ApprovalException extends Exception {}
}