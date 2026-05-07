/**
 * @description Handles final approval/rejection actions based on configuration
 * Auto-detects which approval status changed and sends notifications
 */
public with sharing class ApprovalActionHandler {

    // ==================== CONSTANTS ====================
    private static final String SPECIAL_VALUE_TODAY = '$TODAY';
    private static final String SPECIAL_VALUE_NOW = '$NOW';
    private static final String SPECIAL_VALUE_USER_ID = '$USER_ID';
    private static final String CHATTER_FEED_ITEM_OBJECT = 'FeedItem';
    private static final String CHATTER_PARENT_ID_FIELD = 'ParentId';
    private static final String CHATTER_BODY_FIELD = 'Body';
    private static final String USER_KEY_PREFIX = '005';

    // ==================== INVOCABLE METHOD (Called from Flow) ====================
    
    /**
     * @description Auto-detects which approval status changed and processes notifications
     * @param requests List of requests from Flow
     * @return List of results
     */
    @InvocableMethod(label='Process Approval Notifications' description='Auto-detects which approval completed and sends notifications')
    public static List<NotificationResult> processApprovalNotifications(List<NotificationRequest> requests) {
        List<NotificationResult> results = new List<NotificationResult>();
        
        for (NotificationRequest request : requests) {
            NotificationResult result = detectAndProcess(request);
            results.add(result);
        }
        
        return results;
    }
    
    /**
     * @description Detect which status changed and process appropriate actions
     */
    private static NotificationResult detectAndProcess(NotificationRequest request) {
        NotificationResult result = new NotificationResult();
        result.success = false;
        result.message = 'No action taken';
        
        if (request.recordId == null) {
            result.message = 'Record ID is required';
            return result;
        }
        
        try {
            // Get object API name
            String objectApiName = request.recordId.getSObjectType().getDescribe().getName();
            
            // Get all active configurations for this object
            List<Approval_Configuration__c> configs = [
                SELECT Id, Process_Type__c, Process_Label__c,
                       Status_Field_API_Name__c,
                       Approved_Status_Value__c, 
                       Rejected_Status_Value__c,
                       On_Approval_JSON__c,
                       On_Rejection_JSON__c
                FROM Approval_Configuration__c
                WHERE Object_API_Name__c = : objectApiName
                AND Is_Active__c = true
                AND Status_Field_API_Name__c != null
            ];
            
            if (configs.isEmpty()) {
                result.message = 'No active approval configurations found';
                return result;
            }
            
            // Build query with all status fields
            Set<String> fieldsToQuery = new Set<String>{'Id'};
            for (Approval_Configuration__c config : configs) {
                fieldsToQuery.add(config.Status_Field_API_Name__c);
            }
            
            // Query current record
            Id recordId = request.recordId;
            String query = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') +
                           ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                           ' WHERE Id = :recordId';
            
            SObject currentRecord = Database.query(query);
            
            // Parse prior values if provided
            Map<String, String> priorValues = parsePriorValues(request.priorValuesJson);
            
            // Check each configuration
            List<String> processedList = new List<String>();
            
            for (Approval_Configuration__c config : configs) {
                String statusField = config.Status_Field_API_Name__c;
                String currentValue = getFieldValueAsString(currentRecord, statusField);
                String priorValue = priorValues.get(statusField);
                
                if (String.isBlank(currentValue)) {
                    continue;
                }
                
                // Skip if value hasn't changed (when prior value is available)
                if (String.isNotBlank(priorValue) && currentValue.equalsIgnoreCase(priorValue)) {
                    continue;
                }
                
                String actionType = determineActionType(config, currentValue, priorValue);
                
                // Process if action type determined
                if (actionType != null) {
                    executeApprovalActions(request.recordId, objectApiName, config, actionType);
                    processedList.add(config.Process_Label__c + ' (' + actionType + ')');
                }
            }
            
            if (! processedList.isEmpty()) {
                result.success = true;
                result.message = 'Processed:  ' + String.join(processedList, ', ');
            } else {
                result.message = 'No final approval/rejection detected';
            }
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error:  ' + e.getMessage();
            System.debug('ApprovalActionHandler Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Parse prior values JSON
     */
    private static Map<String, String> parsePriorValues(String priorValuesJson) {
        Map<String, String> priorValues = new Map<String, String>();
        
        if (String.isNotBlank(priorValuesJson)) {
            try {
                priorValues = (Map<String, String>) JSON.deserialize(
                    priorValuesJson, 
                    Map<String, String>.class
                );
            } catch (Exception e) {
                System.debug('Error parsing prior values JSON: ' + e.getMessage());
            }
        }
        
        return priorValues;
    }
    
    /**
     * @description Determine action type based on current and prior values
     */
    private static String determineActionType(Approval_Configuration__c config, String currentValue, String priorValue) {
        // Check if Approved
        if (String.isNotBlank(config.Approved_Status_Value__c) && 
            currentValue.equalsIgnoreCase(config.Approved_Status_Value__c)) {
            
            // Skip if was already Approved
            if (String.isNotBlank(priorValue) && 
                priorValue.equalsIgnoreCase(config.Approved_Status_Value__c)) {
                return null;
            }
            return 'APPROVAL';
        }
        
        // Check if Rejected
        if (String.isNotBlank(config.Rejected_Status_Value__c) && 
            currentValue.equalsIgnoreCase(config.Rejected_Status_Value__c)) {
            
            // Skip if was already Rejected
            if (String.isNotBlank(priorValue) && 
                priorValue.equalsIgnoreCase(config.Rejected_Status_Value__c)) {
                return null;
            }
            return 'REJECTION';
        }
        
        return null;
    }
    
    /**
     * @description Get field value as string safely
     */
    private static String getFieldValueAsString(SObject record, String fieldName) {
        try {
            Object value = record.get(fieldName);
            return value != null ? String.valueOf(value) : null;
        } catch (Exception e) {
            return null;
        }
    }
    
    // ==================== ACTION EXECUTION ====================
    
    /**
     * @description Execute approval/rejection actions for a config
     */
    private static void executeApprovalActions(Id recordId, String objectApiName, Approval_Configuration__c config, String actionType) {
        String actionsJson = actionType == 'APPROVAL' 
            ? config.On_Approval_JSON__c 
            : config.On_Rejection_JSON__c;
        
        if (String.isBlank(actionsJson)) {
            System.debug('No actions configured for ' + actionType + ' in ' + config.Process_Label__c);
            return;
        }
        
        try {
            ActionConfig actionConfig = (ActionConfig) JSON.deserialize(actionsJson, ActionConfig.class);
            
            if (actionConfig.actions != null) {
                for (ActionItem action : actionConfig.actions) {
                    executeAction(recordId, objectApiName, action);
                }
            }
        } catch (Exception e) {
            System.debug('Error processing actions: ' + e.getMessage());
        }
    }
    
    /**
     * @description Execute a single action
     */
    private static void executeAction(Id recordId, String objectApiName, ActionItem action) {
        switch on action.actionType {
            when 'EMAIL_NOTIFICATION' {
                sendEmailNotification(recordId, objectApiName, action);
            }
            when 'BELL_NOTIFICATION' {
                sendBellNotification(recordId, objectApiName, action);
            }
            when 'FIELD_UPDATE' {
                performFieldUpdate(recordId, objectApiName, action);
            }
            when 'CHATTER_POST' {
                postToChatter(recordId, action);
            }
        }
    }
    
    // ==================== EMAIL NOTIFICATION ====================
    
    private static void sendEmailNotification(Id recordId, String objectApiName, ActionItem action) {
        if (action.emailConfig == null) {
            return;
        }
        
        Set<String> recipientEmails = new Set<String>();
        Set<Id> recipientUserIds = new Set<Id>();
        
        // Get recipients from field paths
        if (action.emailConfig.recipientFieldPaths != null && ! action.emailConfig.recipientFieldPaths.isEmpty()) {
            recipientUserIds.addAll(getUserIdsFromFieldPaths(recordId, objectApiName, action.emailConfig.recipientFieldPaths));
        }
        
        // Add additional emails
        if (action.emailConfig.additionalEmails != null) {
            recipientEmails.addAll(action.emailConfig.additionalEmails);
        }
        
        // Get emails from user IDs
        if (! recipientUserIds.isEmpty()) {
            for (User u : [SELECT Email FROM User WHERE Id IN :recipientUserIds AND Email != null]) {
                recipientEmails.add(u.Email);
            }
        }
        
        if (recipientEmails.isEmpty()) {
            System.debug('No recipients found for email notification');
            return;
        }
        
        // Send email
        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>(recipientEmails));
            email.setSaveAsActivity(false);
            
            if (String.isNotBlank(action.emailConfig.templateDeveloperName)) {
                List<EmailTemplate> templates = [
                    SELECT Id FROM EmailTemplate 
                    WHERE DeveloperName = :action.emailConfig.templateDeveloperName 
                    LIMIT 1
                ];
                if (!templates.isEmpty()) {
                    email.setTemplateId(templates[0].Id);
                    email.setTargetObjectId(UserInfo.getUserId());
                    email.setWhatId(recordId);
                    email.setTreatTargetObjectAsRecipient(false);
                } else {
                    setDefaultEmailContent(email, recordId);
                }
            } else {
                setDefaultEmailContent(email, recordId);
            }
            
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{email});
            System.debug('Email sent successfully to:  ' + recipientEmails);
        } catch (Exception e) {
            System.debug('Error sending email: ' + e.getMessage());
        }
    }
    
    private static void setDefaultEmailContent(Messaging.SingleEmailMessage email, Id recordId) {
        email.setSubject('Approval Status Update');
        email.setPlainTextBody('The approval status has been updated for record: ' + recordId);
    }
    
    // ==================== BELL NOTIFICATION ====================
    
    /**
 	* @description Send bell notification (Custom Notification)
	*/
    private static void sendBellNotification(Id recordId, String objectApiName, ActionItem action) {
        if (action.bellConfig == null) {
            return;
        }
        
        String title = action.bellConfig.title;
        String body = action.bellConfig.body;
        
        if (String.isBlank(title) || String.isBlank(body)) {
            System.debug('Bell notification title or body is empty');
            return;
        }
        
        // NEW: Replace merge fields with actual values
        title = replaceMergeFields(title, recordId, objectApiName);
        body = replaceMergeFields(body, recordId, objectApiName);
        
        // Get recipient user IDs as Set<String>
        Set<String> recipientUserIds = new Set<String>();
        
        if (action.bellConfig.recipientFieldPaths != null && ! action.bellConfig.recipientFieldPaths.isEmpty()) {
            Set<Id> userIds = getUserIdsFromFieldPaths(recordId, objectApiName, action.bellConfig.recipientFieldPaths);
            for (Id userId : userIds) {
                recipientUserIds.add(String.valueOf(userId));
            }
        }
        
        if (recipientUserIds.isEmpty()) {
            System.debug('No recipients found for bell notification');
            return;
        }
        
        try {
            List<CustomNotificationType> notifTypes = [
                SELECT Id 
                FROM CustomNotificationType 
                WHERE DeveloperName = :System.Label.Approval_Notification_Type
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                System.debug('Custom notification type "Approval_Notification" not found');
                return;
            }
            
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(notifTypes[0].Id);
            notification.setTargetId(recordId);
            notification.send(recipientUserIds);
            
            System.debug('Bell notification sent to: ' + recipientUserIds);
        } catch (Exception e) {
            System.debug('Error sending bell notification: ' + e.getMessage());
        }
    }
    
    /**
	* @description Replace merge fields {FieldName} with actual values from record
	*/
    private static String replaceMergeFields(String template, Id recordId, String objectApiName) {
        if (String.isBlank(template) || ! template.contains('{')) {
            return template;
        }
        
        // Find all merge fields in the template
        Set<String> mergeFields = new Set<String>();
        Pattern p = Pattern.compile('\\{([^}]+)\\}');
        Matcher m = p.matcher(template);
        
        while (m.find()) {
            mergeFields.add(m.group(1));
        }
        
        if (mergeFields.isEmpty()) {
            return template;
        }
        
        // Query the record with all merge fields
        Set<String> fieldsToQuery = new Set<String>{'Id'};
            fieldsToQuery.addAll(mergeFields);
        
        // Remove any invalid field names
        Set<String> validFields = new Set<String>();
        try {
            Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
            Map<String, Schema.SObjectField> fieldsMap = sObjectType.getDescribe().fields.getMap();
            
            for (String fieldName : fieldsToQuery) {
                if (fieldsMap.containsKey(fieldName.toLowerCase())) {
                    validFields.add(fieldName);
                }
            }
        } catch (Exception e) {
            System.debug('Error validating fields: ' + e.getMessage());
            return template;
        }
        
        if (validFields.isEmpty()) {
            return template;
        }
        
        // Query the record
        String query = 'SELECT ' + String.join(new List<String>(validFields), ', ') +
            ' FROM ' + String.escapeSingleQuotes(objectApiName) +
            ' WHERE Id = : recordId';
        
        SObject record = Database.query(query);
        
        // Replace merge fields with values
        String result = template;
        
        for (String fieldName : mergeFields) {
            String placeholder = '{' + fieldName + '}';
            String value = '';
            
            try {
                Object fieldValue = record.get(fieldName);
                if (fieldValue != null) {
                    value = String.valueOf(fieldValue);
                }
            } catch (Exception e) {
                System.debug('Error getting field value for ' + fieldName + ': ' + e.getMessage());
            }
            
            result = result.replace(placeholder, value);
        }
        
        return result;
    }
    
    // ==================== FIELD UPDATE ====================
    
    private static void performFieldUpdate(Id recordId, String objectApiName, ActionItem action) {
        if (action.fieldUpdates == null || action.fieldUpdates.isEmpty()) {
            return;
        }
        
        SObject record = recordId.getSObjectType().newSObject(recordId);
        
        for (FieldUpdate fu : action.fieldUpdates) {
            Object value = fu.value;
            
            // Handle special values
            if (value instanceof String) {
                String strValue = (String) value;
                if (strValue == SPECIAL_VALUE_TODAY) {
                    value = Date.today();
                } else if (strValue == SPECIAL_VALUE_NOW) {
                    value = DateTime.now();
                } else if (strValue == SPECIAL_VALUE_USER_ID) {
                    value = UserInfo.getUserId();
                }
            }
            
            try {
                record.put(fu.fieldName, value);
            } catch (Exception e) {
                System.debug('Error setting field ' + fu.fieldName + ': ' + e.getMessage());
            }
        }
        
        update record;
        System.debug('Field updates completed successfully');
    }
    
    // ==================== CHATTER POST ====================
    
    private static void postToChatter(Id recordId, ActionItem action) {
        if (String.isBlank(action.chatterMessage)) {
            return;
        }
        
        try {
            Schema.SObjectType feedItemType = Schema.getGlobalDescribe().get(CHATTER_FEED_ITEM_OBJECT);

            if (feedItemType == null) {
                System.debug('Chatter is not enabled');
                return;
            }

            SObject feedItem = feedItemType.newSObject();
            feedItem.put(CHATTER_PARENT_ID_FIELD, recordId);
            feedItem.put(CHATTER_BODY_FIELD, action.chatterMessage);
            
            insert feedItem;
            System.debug('Chatter post created successfully');
        } catch (Exception e) {
            System.debug('Error posting to Chatter: ' + e.getMessage());
        }
    }
    
    // ==================== HELPER METHODS ====================
    
    /**
     * @description Get User IDs from field paths on a record
     */
    private static Set<Id> getUserIdsFromFieldPaths(Id recordId, String objectApiName, List<String> fieldPaths) {
        Set<Id> userIds = new Set<Id>();
        
        if (fieldPaths == null || fieldPaths.isEmpty()) {
            return userIds;
        }
        
        Set<String> fieldsToQuery = new Set<String>{'Id'};
        fieldsToQuery.addAll(fieldPaths);
        
        String query = 'SELECT ' + String.join(new List<String>(fieldsToQuery), ', ') +
                       ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                       ' WHERE Id = :recordId';
        
        SObject record = Database.query(query);
        
        for (String fieldPath : fieldPaths) {
            try {
                Object fieldValue = record.get(fieldPath);
                if (fieldValue != null && fieldValue instanceof Id) {
                    Id potentialUserId = (Id) fieldValue;
                    // Check if it's a User ID (starts with 005)
                    if (String.valueOf(potentialUserId).startsWith(USER_KEY_PREFIX)) {
                        userIds.add(potentialUserId);
                    }
                }
            } catch (Exception e) {
                System.debug('Error resolving field path:  ' + fieldPath);
            }
        }
        
        return userIds;
    }
    
    // ==================== INVOCABLE REQUEST/RESULT CLASSES ====================
    
    public class NotificationRequest {
        @InvocableVariable(required=true label='Record ID' description='The ID of the record')
        public Id recordId;
        
        @InvocableVariable(required=false label='Prior Values JSON' description='JSON map of prior field values (optional)')
        public String priorValuesJson;
    }
    
    public class NotificationResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        
        @InvocableVariable(label='Message')
        public String message;
    }
    
    // ==================== JSON WRAPPER CLASSES ====================
    
    public class ActionConfig {
        public List<ActionItem> actions;
    }
    
    public class ActionItem {
        public String actionType;
        public EmailConfig emailConfig;
        public BellConfig bellConfig;
        public List<FieldUpdate> fieldUpdates;
        public String chatterMessage;
    }
    
    public class EmailConfig {
        public List<String> recipientFieldPaths;
        public List<String> additionalEmails;
        public String templateDeveloperName;
    }
    
    public class BellConfig {
        public String title;
        public String body;
        public List<String> recipientFieldPaths;
    }
    
    public class FieldUpdate {
        public String fieldName;
        public Object value;
    }
}