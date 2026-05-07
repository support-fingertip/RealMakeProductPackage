/**
 * @description Controller for Email Template Configuration CRUD operations
 * @author Your Name
 * @date 2024
 */
public with sharing class EmailTemplateConfigController {
    
    // ============ WRAPPER CLASS ============
    
    public class TemplateWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String objectApiName { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public Boolean isDefault { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String emailBody { get; set; }
        @AuraEnabled public String fromAddress { get; set; }
        @AuraEnabled public String replyTo { get; set; }
        @AuraEnabled public String recipientsConfig { get; set; }
        @AuraEnabled public String attachmentsConfig { get; set; }
        @AuraEnabled public Boolean allowAdditionalRecipients { get; set; }
        @AuraEnabled public Boolean allowFileUpload { get; set; }
        @AuraEnabled public String actionBinding { get; set; }
        @AuraEnabled public String matchingCriteria { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public DateTime lastModifiedDate { get; set; }
        @AuraEnabled public String createdByName { get; set; }
    }
    
    // ============ GET ALL TEMPLATES ============
    
    /**
     * @description Get all email templates
     * @return List of TemplateWrapper
     */
    @AuraEnabled(cacheable=true)
    public static List<TemplateWrapper> getAllTemplates() {
        List<TemplateWrapper> templates = new List<TemplateWrapper>();
        
        try {
            List<Email_Template_Config__c> configs = [
                SELECT Id, Template_Name__c, Object_API_Name__c, Description__c,
                       Is_Active__c, Is_Default__c, Subject__c, Email_Body__c,
                       From_Address__c, Reply_To__c, Recipients_Config__c,
                       Attachments_Config__c, Allow_Additional_Recipients__c,
                       Allow_File_Upload__c, Action_Binding__c, Matching_Criteria__c,
                       CreatedDate, LastModifiedDate,
                       CreatedBy.Name
                FROM Email_Template_Config__c
                ORDER BY Object_API_Name__c, Template_Name__c
            ];
            
            for (Email_Template_Config__c config : configs) {
                templates.add(mapToWrapper(config));
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching templates: ' + e.getMessage());
        }
        
        return templates;
    }
    
    // ============ GET TEMPLATES FOR OBJECT ============
    
    /**
     * @description Get active templates for a specific object
     * @param objectApiName Object API name
     * @return List of TemplateWrapper
     */
    @AuraEnabled(cacheable=true)
    public static List<TemplateWrapper> getTemplatesForObject(String objectApiName) {
        List<TemplateWrapper> templates = new List<TemplateWrapper>();
        
        try {
            if (String.isBlank(objectApiName)) {
                return templates;
            }
            
            List<Email_Template_Config__c> configs = [
                SELECT Id, Template_Name__c, Object_API_Name__c, Description__c,
                       Is_Active__c, Is_Default__c, Subject__c, Email_Body__c,
                       From_Address__c, Reply_To__c, Recipients_Config__c,
                       Attachments_Config__c, Allow_Additional_Recipients__c,
                       Allow_File_Upload__c, Action_Binding__c, Matching_Criteria__c,
                       CreatedDate, LastModifiedDate,
                       CreatedBy.Name
                FROM Email_Template_Config__c
                WHERE Object_API_Name__c = : objectApiName
                AND Is_Active__c = true
                ORDER BY Is_Default__c DESC, Template_Name__c ASC
            ];
            
            for (Email_Template_Config__c config : configs) {
                templates.add(mapToWrapper(config));
            }
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching templates:  ' + e.getMessage());
        }
        
        return templates;
    }
    
    // ============ GET SINGLE TEMPLATE ============
    
    /**
     * @description Get a single template by ID
     * @param templateId Template ID
     * @return TemplateWrapper
     */
    @AuraEnabled
    public static TemplateWrapper getTemplateById(String templateId) {
        try {
            if (String.isBlank(templateId)) {
                throw new AuraHandledException('Template ID is required');
            }
            
            List<Email_Template_Config__c> configs = [
                SELECT Id, Template_Name__c, Object_API_Name__c, Description__c,
                       Is_Active__c, Is_Default__c, Subject__c, Email_Body__c,
                       From_Address__c, Reply_To__c, Recipients_Config__c,
                       Attachments_Config__c, Allow_Additional_Recipients__c,
                       Allow_File_Upload__c, Action_Binding__c, Matching_Criteria__c,
                       CreatedDate, LastModifiedDate,
                       CreatedBy.Name
                FROM Email_Template_Config__c
                WHERE Id = :templateId
                LIMIT 1
            ];
            
            if (configs.isEmpty()) {
                throw new AuraHandledException('Template not found');
            }
            
            return mapToWrapper(configs[0]);
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching template: ' + e.getMessage());
        }
    }
    
    // ============ SAVE TEMPLATE ============
    
    /**
     * @description Save (create or update) a template
     * @param templateJson JSON string of template data
     * @return Template ID
     */
    @AuraEnabled
    public static String saveTemplate(String templateJson) {
        try {
            if (String.isBlank(templateJson)) {
                throw new AuraHandledException('Template data is required');
            }
            
            TemplateWrapper wrapper = (TemplateWrapper) JSON.deserialize(templateJson, TemplateWrapper.class);
            
            Email_Template_Config__c config;
            
            if (String.isNotBlank(wrapper.id)) {
                // Update existing
                config = [
                    SELECT Id FROM Email_Template_Config__c 
                    WHERE Id = :wrapper.id 
                    LIMIT 1
                ];
            } else {
                // Create new
                config = new Email_Template_Config__c();
            }
            
            // Set fields
            config.Template_Name__c = wrapper.name;
            config.Object_API_Name__c = wrapper.objectApiName;
            config.Description__c = wrapper.description;
            config.Is_Active__c = wrapper.isActive != null ? wrapper.isActive : true;
            config.Is_Default__c = wrapper.isDefault != null ? wrapper.isDefault : false;
            config.Subject__c = wrapper.subject;
            config.Email_Body__c = wrapper.emailBody;
            config.From_Address__c = wrapper.fromAddress;
            config.Reply_To__c = wrapper.replyTo;
            config.Recipients_Config__c = wrapper.recipientsConfig;
            config.Attachments_Config__c = wrapper.attachmentsConfig;
            config.Allow_Additional_Recipients__c = wrapper.allowAdditionalRecipients != null ?  wrapper.allowAdditionalRecipients :  true;
            config.Allow_File_Upload__c = wrapper.allowFileUpload != null ? wrapper.allowFileUpload : true;
            config.Action_Binding__c = wrapper.actionBinding;
            config.Matching_Criteria__c = wrapper.matchingCriteria;
            
            // If setting as default, unset other defaults for same object
            if (config.Is_Default__c) {
                unsetOtherDefaults(wrapper.objectApiName, config.Id);
            }
            
            upsert config;
            
            return config.Id;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving template:  ' + e.getMessage());
        }
    }
    
    /**
     * @description Unset default flag on other templates for same object
     */
    private static void unsetOtherDefaults(String objectApiName, Id excludeId) {
        List<Email_Template_Config__c> others = [
            SELECT Id, Is_Default__c
            FROM Email_Template_Config__c
            WHERE Object_API_Name__c = :objectApiName
            AND Is_Default__c = true
            AND Id != :excludeId
        ];
        
        for (Email_Template_Config__c config : others) {
            config.Is_Default__c = false;
        }
        
        if (! others.isEmpty()) {
            update others;
        }
    }
    
    // ============ DELETE TEMPLATE ============
    
    /**
     * @description Delete a template
     * @param templateId Template ID
     */
    @AuraEnabled
    public static void deleteTemplate(String templateId) {
        try {
            if (String.isBlank(templateId)) {
                throw new AuraHandledException('Template ID is required');
            }
            
            Email_Template_Config__c config = [
                SELECT Id FROM Email_Template_Config__c 
                WHERE Id = :templateId 
                LIMIT 1
            ];
            
            delete config;
            
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting template:  ' + e.getMessage());
        }
    }
    
    // ============ CLONE TEMPLATE ============
    
    /**
     * @description Clone a template
     * @param templateId Template ID to clone
     * @return New template ID
     */
    @AuraEnabled
    public static String cloneTemplate(String templateId) {
        try {
            TemplateWrapper original = getTemplateById(templateId);
            
            original.id = null;
            original.name = original.name + ' (Copy)';
            original.isDefault = false;
            
            return saveTemplate(JSON.serialize(original));
            
        } catch (Exception e) {
            throw new AuraHandledException('Error cloning template:  ' + e.getMessage());
        }
    }
    
    // ============ TOGGLE ACTIVE STATUS ============
    
    /**
     * @description Toggle template active status
     * @param templateId Template ID
     * @param isActive New active status
     */
    @AuraEnabled
    public static void toggleActiveStatus(String templateId, Boolean isActive) {
        try {
            Email_Template_Config__c config = [
                SELECT Id, Is_Active__c
                FROM Email_Template_Config__c
                WHERE Id = :templateId
                LIMIT 1
            ];
            
            config.Is_Active__c = isActive;
            update config;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error updating status: ' + e.getMessage());
        }
    }
    
    // ============ HELPER METHOD ============
    
    private static TemplateWrapper mapToWrapper(Email_Template_Config__c config) {
        TemplateWrapper wrapper = new TemplateWrapper();
        wrapper.id = config.Id;
        wrapper.name = config.Template_Name__c;
        wrapper.objectApiName = config.Object_API_Name__c;
        wrapper.description = config.Description__c;
        wrapper.isActive = config.Is_Active__c;
        wrapper.isDefault = config.Is_Default__c;
        wrapper.subject = config.Subject__c;
        wrapper.emailBody = config.Email_Body__c;
        wrapper.fromAddress = config.From_Address__c;
        wrapper.replyTo = config.Reply_To__c;
        wrapper.recipientsConfig = config.Recipients_Config__c;
        wrapper.attachmentsConfig = config.Attachments_Config__c;
        wrapper.allowAdditionalRecipients = config.Allow_Additional_Recipients__c;
        wrapper.allowFileUpload = config.Allow_File_Upload__c;
        wrapper.actionBinding = config.Action_Binding__c;
        wrapper.matchingCriteria = config.Matching_Criteria__c;
        wrapper.createdDate = config.CreatedDate;
        wrapper.lastModifiedDate = config.LastModifiedDate;
        wrapper.createdByName = config.CreatedBy?.Name;
        return wrapper;
    }
}