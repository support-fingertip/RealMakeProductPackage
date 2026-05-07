/**
 * @description Controller for Bulk Approval Manager Lightning Web Component
 * @author Salesforce
 * @date 2024
 */
public with sharing class BulkApprovalController {
    
    /**
     * @description Wrapper class for approval items
     */
    public class ApprovalItemWrapper {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String recordName { get; set; }
        @AuraEnabled public String recordType { get; set; }
        @AuraEnabled public String submittedBy { get; set; }
        @AuraEnabled public String submittedById { get; set; }
        @AuraEnabled public DateTime submittedDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String workItemId { get; set; }
        @AuraEnabled public String processInstanceId { get; set; }
    }
    
    /**
     * @description Wrapper class for approval response
     */
    public class ApprovalResponse {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Integer successCount { get; set; }
        @AuraEnabled public Integer failureCount { get; set; }
        @AuraEnabled public List<String> errors { get; set; }
        
        public ApprovalResponse() {
            this.success = true;
            this.successCount = 0;
            this.failureCount = 0;
            this.errors = new List<String>();
        }
    }
    
    /**
     * @description Wrapper class for user lookup
     */
    public class UserWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String title { get; set; }
    }
    
    /**
     * @description Wrapper class for approval history
     */
    public class ApprovalHistoryWrapper {
        @AuraEnabled public String stepName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String actorName { get; set; }
        @AuraEnabled public DateTime actionDate { get; set; }
        @AuraEnabled public String comments { get; set; }
    }
    
    /**
     * @description Get pending approval items for current user
     * @return List of ApprovalItemWrapper
     */
    @AuraEnabled(cacheable=true)
    public static List<ApprovalItemWrapper> getPendingApprovals() {
        List<ApprovalItemWrapper> approvalItems = new List<ApprovalItemWrapper>();
        
        try {
            // Query ProcessInstanceWorkitem for pending approvals assigned to current user
            List<ProcessInstanceWorkitem> workItems = [
                SELECT Id, ProcessInstance.TargetObjectId, ProcessInstance.Status,
                       ProcessInstance.CreatedById, ProcessInstance.CreatedBy.Name,
                       ProcessInstance.CreatedDate, ProcessInstance.TargetObject.Name,
                       ProcessInstance.TargetObject.Type
                FROM ProcessInstanceWorkitem
                WHERE ActorId = :UserInfo.getUserId()
                AND ProcessInstance.Status = 'Pending'
                ORDER BY ProcessInstance.CreatedDate DESC
                LIMIT 200
            ];
            
            for (ProcessInstanceWorkitem workItem : workItems) {
                ApprovalItemWrapper item = new ApprovalItemWrapper();
                item.workItemId = workItem.Id;
                item.processInstanceId = workItem.ProcessInstance.Id;
                item.recordId = workItem.ProcessInstance.TargetObjectId;
                item.recordName = workItem.ProcessInstance.TargetObject.Name;
                item.recordType = workItem.ProcessInstance.TargetObject.Type;
                item.submittedBy = workItem.ProcessInstance.CreatedBy.Name;
                item.submittedById = workItem.ProcessInstance.CreatedById;
                item.submittedDate = workItem.ProcessInstance.CreatedDate;
                item.status = workItem.ProcessInstance.Status;
                approvalItems.add(item);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving pending approvals: ' + e.getMessage());
        }
        
        return approvalItems;
    }
    
    /**
     * @description Process approval or rejection for selected records
     * @param recordIds List of work item IDs to process
     * @param action Action to perform (Approve or Reject)
     * @param comments Comments to add
     * @return ApprovalResponse with results
     */
    @AuraEnabled
    public static ApprovalResponse processApprovals(List<Id> recordIds, String action, String comments) {
        ApprovalResponse response = new ApprovalResponse();
        
        // Validate inputs
        if (recordIds == null || recordIds.isEmpty()) {
            response.success = false;
            response.message = 'No records selected';
            return response;
        }
        
        if (String.isBlank(action) || !(action == 'Approve' || action == 'Reject')) {
            response.success = false;
            response.message = 'Invalid action specified';
            return response;
        }
        
        // Limit to 200 records per transaction
        if (recordIds.size() > 200) {
            response.success = false;
            response.message = 'Cannot process more than 200 records at once';
            return response;
        }
        
        // Process each approval request
        List<Approval.ProcessWorkitemRequest> requests = new List<Approval.ProcessWorkitemRequest>();
        
        for (Id workItemId : recordIds) {
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workItemId);
            req.setAction(action);
            
            if (String.isNotBlank(comments)) {
                req.setComments(comments);
            }
            
            requests.add(req);
        }
        
        try {
            // Process all approval requests
            List<Approval.ProcessResult> results = Approval.process(requests, false);
            
            // Analyze results
            for (Approval.ProcessResult result : results) {
                if (result.isSuccess()) {
                    response.successCount++;
                } else {
                    response.failureCount++;
                    for (Database.Error error : result.getErrors()) {
                        response.errors.add(error.getMessage());
                    }
                }
            }
            
            // Set overall success and message
            if (response.failureCount > 0) {
                response.success = false;
                response.message = String.format('{0} records processed successfully, {1} failed', 
                    new List<String>{
                        String.valueOf(response.successCount),
                        String.valueOf(response.failureCount)
                    });
            } else {
                response.success = true;
                response.message = String.format('{0} record(s) {1} successfully', 
                    new List<String>{
                        String.valueOf(response.successCount),
                        action.toLowerCase() + 'd'
                    });
            }
            
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error processing approvals: ' + e.getMessage();
            response.errors.add(e.getMessage());
        }
        
        return response;
    }
    
    /**
     * @description Delegate approval requests to another user
     * @param recordIds List of work item IDs to delegate
     * @param delegateToUserId User ID to delegate to
     * @return ApprovalResponse with results
     */
    @AuraEnabled
    public static ApprovalResponse delegateApprovals(List<Id> recordIds, Id delegateToUserId) {
        ApprovalResponse response = new ApprovalResponse();
        
        // Validate inputs
        if (recordIds == null || recordIds.isEmpty()) {
            response.success = false;
            response.message = 'No records selected';
            return response;
        }
        
        if (delegateToUserId == null) {
            response.success = false;
            response.message = 'Please select a user to delegate to';
            return response;
        }
        
        // Limit to 200 records per transaction
        if (recordIds.size() > 200) {
            response.success = false;
            response.message = 'Cannot delegate more than 200 records at once';
            return response;
        }
        
        // Verify target user exists and is active
        try {
            User targetUser = [
                SELECT Id, IsActive 
                FROM User 
                WHERE Id = :delegateToUserId 
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            
            if (!targetUser.IsActive) {
                response.success = false;
                response.message = 'Cannot delegate to inactive user';
                return response;
            }
        } catch (Exception e) {
            response.success = false;
            response.message = 'Invalid user selected for delegation';
            return response;
        }
        
        // Process each delegation request
        List<Approval.ProcessWorkitemRequest> requests = new List<Approval.ProcessWorkitemRequest>();
        
        for (Id workItemId : recordIds) {
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workItemId);
            req.setAction('Reassign');
            req.setNextApproverIds(new List<Id>{delegateToUserId});
            
            requests.add(req);
        }
        
        try {
            // Process all delegation requests
            List<Approval.ProcessResult> results = Approval.process(requests, false);
            
            // Analyze results
            for (Approval.ProcessResult result : results) {
                if (result.isSuccess()) {
                    response.successCount++;
                } else {
                    response.failureCount++;
                    for (Database.Error error : result.getErrors()) {
                        response.errors.add(error.getMessage());
                    }
                }
            }
            
            // Set overall success and message
            if (response.failureCount > 0) {
                response.success = false;
                response.message = String.format('{0} records delegated successfully, {1} failed', 
                    new List<String>{
                        String.valueOf(response.successCount),
                        String.valueOf(response.failureCount)
                    });
            } else {
                response.success = true;
                response.message = String.format('{0} record(s) delegated successfully', 
                    new List<String>{String.valueOf(response.successCount)});
            }
            
        } catch (Exception e) {
            response.success = false;
            response.message = 'Error delegating approvals: ' + e.getMessage();
            response.errors.add(e.getMessage());
        }
        
        return response;
    }
    
    /**
     * @description Search for active users
     * @param searchTerm Search term for user lookup
     * @return List of UserWrapper
     */
    @AuraEnabled(cacheable=true)
    public static List<UserWrapper> searchUsers(String searchTerm) {
        List<UserWrapper> users = new List<UserWrapper>();
        
        if (String.isBlank(searchTerm)) {
            return users;
        }
        
        // Prevent SOQL injection
        String safeTerm = String.escapeSingleQuotes(searchTerm);
        String searchPattern = '%' + safeTerm + '%';
        
        try {
            List<User> userList = [
                SELECT Id, Name, Email, Title
                FROM User
                WHERE IsActive = true
                AND (Name LIKE :searchPattern OR Email LIKE :searchPattern)
                WITH SECURITY_ENFORCED
                ORDER BY Name
                LIMIT 10
            ];
            
            for (User u : userList) {
                UserWrapper wrapper = new UserWrapper();
                wrapper.id = u.Id;
                wrapper.name = u.Name;
                wrapper.email = u.Email;
                wrapper.title = u.Title;
                users.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error searching users: ' + e.getMessage());
        }
        
        return users;
    }
    
    /**
     * @description Get approval history for a record
     * @param recordId Record ID to get history for
     * @return List of ApprovalHistoryWrapper
     */
    @AuraEnabled(cacheable=true)
    public static List<ApprovalHistoryWrapper> getApprovalHistory(Id recordId) {
        List<ApprovalHistoryWrapper> history = new List<ApprovalHistoryWrapper>();
        
        if (recordId == null) {
            return history;
        }
        
        try {
            List<ProcessInstanceStep> steps = [
                SELECT StepStatus, Comments, Actor.Name, CreatedDate, 
                       ProcessInstance.ProcessDefinition.Name
                FROM ProcessInstanceStep
                WHERE ProcessInstance.TargetObjectId = :recordId
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
            
            for (ProcessInstanceStep step : steps) {
                ApprovalHistoryWrapper wrapper = new ApprovalHistoryWrapper();
                wrapper.stepName = step.ProcessInstance.ProcessDefinition.Name;
                wrapper.status = step.StepStatus;
                wrapper.actorName = step.Actor.Name;
                wrapper.actionDate = step.CreatedDate;
                wrapper.comments = step.Comments;
                history.add(wrapper);
            }
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving approval history: ' + e.getMessage());
        }
        
        return history;
    }
    
   /* @AuraEnabled(cacheable=true)
    public static List<ApprovalHistoryWrapper> getApprovalHistory(Id recordId) {
        
        List<ApprovalHistoryWrapper> history = new List<ApprovalHistoryWrapper>();
        
        if (recordId == null) {
            return history;
        }
        
        // Object level security check
        if (!Schema.sObjectType.ProcessInstanceStep.isAccessible()) {
            throw new AuraHandledException('No access to approval history.');
        }
        
        List<ProcessInstanceStep> steps = [
            SELECT Id, StepStatus, Comments, ActorId, CreatedDate,
            ProcessInstance.ProcessDefinition.Name
            FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId = :recordId
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
        
        // Collect Actor Ids
        Set<Id> actorIds = new Set<Id>();
        for(ProcessInstanceStep step : steps){
            if(step.ActorId != null){
                actorIds.add(step.ActorId);
            }
        }
        
        // Query Users separately (safe, non-polymorphic)
        Map<Id, User> userMap = new Map<Id, User>(
            [SELECT Id, Name FROM User WHERE Id IN :actorIds]
        );
        
        for (ProcessInstanceStep step : steps) {
            
            ApprovalHistoryWrapper wrapper = new ApprovalHistoryWrapper();
            wrapper.stepName = step.ProcessInstance.ProcessDefinition.Name;
            wrapper.status = step.StepStatus;
            wrapper.actionDate = step.CreatedDate;
            wrapper.comments = step.Comments;
            
            if(userMap.containsKey(step.ActorId)){
                wrapper.actorName = userMap.get(step.ActorId).Name;
            }
            
            history.add(wrapper);
        }
        
        return history;
    }*/

}