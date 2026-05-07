public with sharing class PostSalesAdminController {

    public class ConfigWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String configurationType { get; set; }
        @AuraEnabled public Id emailTemplateId { get; set; }
        @AuraEnabled public String emailTemplateName { get; set; }
        @AuraEnabled public String vfPageName { get; set; }
        @AuraEnabled public Id documentTemplateId { get; set; }
        @AuraEnabled public String documentTemplateName { get; set; }
        @AuraEnabled public Id approvalConfigurationId { get; set; }
        @AuraEnabled public String approvalConfigurationName { get; set; }
        @AuraEnabled public Decimal gracePeriodDays { get; set; }
        @AuraEnabled public Boolean includeInterest { get; set; }
        @AuraEnabled public Boolean includePreviousDues { get; set; }
        @AuraEnabled public Boolean autoSendEmail { get; set; }
        @AuraEnabled public Decimal dueDateOffsetDays { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String notes { get; set; }
        @AuraEnabled public String matchingCriteria { get; set; }
        @AuraEnabled public Boolean enableReminders { get; set; }
        @AuraEnabled public String reminderConfig { get; set; }
        @AuraEnabled public String scheduleMode { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<ConfigWrapper> getConfigurations() {
        List<ConfigWrapper> wrappers = new List<ConfigWrapper>();
        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Name, Configuration_Type__c,
                   Email_Template__c, Email_Template__r.Template_Name__c,
                   VF_Page_Name__c,
                   Document_Template__c, Document_Template__r.Name,
                   Approval_Configuration__c, Approval_Configuration__r.Name,
                   Grace_Period_Days__c, Include_Interest__c, Include_Previous_Dues__c,
                   Auto_Send_Email__c, Due_Date_Offset_Days__c, Is_Active__c, Notes__c,
                   Matching_Criteria__c, Enable_Reminders__c, Reminder_Config__c, Schedule_Mode__c
            FROM Post_Sales_Configuration__c
            ORDER BY Configuration_Type__c ASC
        ];

        for (Post_Sales_Configuration__c config : configs) {
            ConfigWrapper w = new ConfigWrapper();
            w.id = config.Id;
            w.name = config.Name;
            w.configurationType = config.Configuration_Type__c;
            w.emailTemplateId = config.Email_Template__c;
            w.emailTemplateName = config.Email_Template__c != null ? config.Email_Template__r.Template_Name__c : null;
            w.vfPageName = config.VF_Page_Name__c;
            w.documentTemplateId = config.Document_Template__c;
            w.documentTemplateName = config.Document_Template__c != null ? config.Document_Template__r.Name : null;
            w.approvalConfigurationId = config.Approval_Configuration__c;
            w.approvalConfigurationName = config.Approval_Configuration__c != null ? config.Approval_Configuration__r.Name : null;
            w.gracePeriodDays = config.Grace_Period_Days__c;
            w.includeInterest = config.Include_Interest__c;
            w.includePreviousDues = config.Include_Previous_Dues__c;
            w.autoSendEmail = config.Auto_Send_Email__c;
            w.dueDateOffsetDays = config.Due_Date_Offset_Days__c;
            w.isActive = config.Is_Active__c;
            w.notes = config.Notes__c;
            w.matchingCriteria = config.Matching_Criteria__c;
            w.enableReminders = config.Enable_Reminders__c;
            w.reminderConfig = config.Reminder_Config__c;
            w.scheduleMode = config.Schedule_Mode__c;
            wrappers.add(w);
        }

        return wrappers;
    }

    @AuraEnabled
    public static Id saveConfiguration(String configJson) {
        try {
            ConfigWrapper wrapper = (ConfigWrapper) JSON.deserialize(configJson, ConfigWrapper.class);
            Post_Sales_Configuration__c config;

            if (wrapper.id != null) {
                config = [SELECT Id FROM Post_Sales_Configuration__c WHERE Id = :wrapper.id LIMIT 1];
            } else {
                config = new Post_Sales_Configuration__c();
            }

            config.Configuration_Type__c = wrapper.configurationType;
            config.Email_Template__c = String.isNotBlank(wrapper.emailTemplateId) ? wrapper.emailTemplateId : null;
            config.VF_Page_Name__c = String.isNotBlank(wrapper.vfPageName) ? wrapper.vfPageName : null;
            config.Document_Template__c = String.isNotBlank(wrapper.documentTemplateId) ? wrapper.documentTemplateId : null;
            config.Approval_Configuration__c = String.isNotBlank(wrapper.approvalConfigurationId) ? wrapper.approvalConfigurationId : null;
            config.Grace_Period_Days__c = wrapper.gracePeriodDays;
            config.Include_Interest__c = wrapper.includeInterest == true;
            config.Include_Previous_Dues__c = wrapper.includePreviousDues == true;
            config.Auto_Send_Email__c = wrapper.autoSendEmail == true;
            config.Due_Date_Offset_Days__c = wrapper.dueDateOffsetDays;
            config.Is_Active__c = wrapper.isActive == true;
            config.Notes__c = wrapper.notes;
            config.Matching_Criteria__c = wrapper.matchingCriteria;
            config.Enable_Reminders__c = wrapper.enableReminders == true;
            config.Reminder_Config__c = wrapper.reminderConfig;
            config.Schedule_Mode__c = wrapper.scheduleMode;

            upsert config;
            return config.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteConfiguration(Id configId) {
        try {
            delete [SELECT Id FROM Post_Sales_Configuration__c WHERE Id = :configId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static ConfigWrapper getConfigurationByType(String configurationType) {
        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Name, Configuration_Type__c,
                   Email_Template__c, Email_Template__r.Template_Name__c,
                   VF_Page_Name__c,
                   Document_Template__c, Document_Template__r.Name,
                   Approval_Configuration__c, Approval_Configuration__r.Name,
                   Grace_Period_Days__c, Include_Interest__c, Include_Previous_Dues__c,
                   Auto_Send_Email__c, Due_Date_Offset_Days__c, Is_Active__c, Notes__c,
                   Matching_Criteria__c, Enable_Reminders__c, Reminder_Config__c, Schedule_Mode__c
            FROM Post_Sales_Configuration__c
            WHERE Configuration_Type__c = :configurationType
            AND Is_Active__c = true
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            return null;
        }

        return toWrapper(configs[0]);
    }

    /**
     * Resolve the best matching configuration for a specific record using matching criteria.
     * Evaluates all active configs of the given type against the record and returns the first match.
     * Falls back to a config without matching criteria if no criteria-based match is found.
     */
    @AuraEnabled
    public static ConfigWrapper resolveConfigurationForRecord(String configurationType, Id recordId, String objectApiName) {
        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Name, Configuration_Type__c,
                   Email_Template__c, Email_Template__r.Template_Name__c,
                   VF_Page_Name__c,
                   Document_Template__c, Document_Template__r.Name,
                   Approval_Configuration__c, Approval_Configuration__r.Name,
                   Grace_Period_Days__c, Include_Interest__c, Include_Previous_Dues__c,
                   Auto_Send_Email__c, Due_Date_Offset_Days__c, Is_Active__c, Notes__c,
                   Matching_Criteria__c, Enable_Reminders__c, Reminder_Config__c, Schedule_Mode__c
            FROM Post_Sales_Configuration__c
            WHERE Configuration_Type__c = :configurationType
            AND Is_Active__c = true
        ];

        if (configs.isEmpty()) return null;

        // Re-order in memory to evaluate configs with criteria first (Matching_Criteria__c
        // is a long-text-style field which is not sortable via SOQL).
        List<Post_Sales_Configuration__c> withCriteria = new List<Post_Sales_Configuration__c>();
        List<Post_Sales_Configuration__c> withoutCriteria = new List<Post_Sales_Configuration__c>();
        for (Post_Sales_Configuration__c c : configs) {
            if (String.isBlank(c.Matching_Criteria__c)) {
                withoutCriteria.add(c);
            } else {
                withCriteria.add(c);
            }
        }
        configs = new List<Post_Sales_Configuration__c>();
        configs.addAll(withCriteria);
        configs.addAll(withoutCriteria);

        // First pass: find config with matching criteria that matches the record
        Post_Sales_Configuration__c fallback = null;
        for (Post_Sales_Configuration__c config : configs) {
            if (String.isBlank(config.Matching_Criteria__c)) {
                // Config without criteria serves as fallback (applies to all records)
                if (fallback == null) fallback = config;
                continue;
            }
            // Evaluate matching criteria against the record
            if (recordId != null && String.isNotBlank(objectApiName)) {
                Boolean matches = ConfigMatchingService.evaluateCriteria(
                    config.Matching_Criteria__c, recordId, objectApiName
                );
                if (matches) {
                    return toWrapper(config);
                }
            }
        }

        // Fall back to config without criteria, or first config if none
        return toWrapper(fallback != null ? fallback : configs[0]);
    }

    private static ConfigWrapper toWrapper(Post_Sales_Configuration__c config) {
        ConfigWrapper w = new ConfigWrapper();
        w.id = config.Id;
        w.name = config.Name;
        w.configurationType = config.Configuration_Type__c;
        w.emailTemplateId = config.Email_Template__c;
        w.emailTemplateName = config.Email_Template__c != null ? config.Email_Template__r.Template_Name__c : null;
        w.vfPageName = config.VF_Page_Name__c;
        w.documentTemplateId = config.Document_Template__c;
        w.documentTemplateName = config.Document_Template__c != null ? config.Document_Template__r.Name : null;
        w.approvalConfigurationId = config.Approval_Configuration__c;
        w.approvalConfigurationName = config.Approval_Configuration__c != null ? config.Approval_Configuration__r.Name : null;
        w.gracePeriodDays = config.Grace_Period_Days__c;
        w.includeInterest = config.Include_Interest__c;
        w.includePreviousDues = config.Include_Previous_Dues__c;
        w.autoSendEmail = config.Auto_Send_Email__c;
        w.dueDateOffsetDays = config.Due_Date_Offset_Days__c;
        w.isActive = config.Is_Active__c;
        w.notes = config.Notes__c;
        w.matchingCriteria = config.Matching_Criteria__c;
        w.enableReminders = config.Enable_Reminders__c;
        w.reminderConfig = config.Reminder_Config__c;
        w.scheduleMode = config.Schedule_Mode__c;
        return w;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAvailableVFPages() {
        List<Map<String, String>> pages = new List<Map<String, String>>();
        for (ApexPage page : [SELECT Name, MasterLabel FROM ApexPage ORDER BY MasterLabel ASC]) {
            Map<String, String> pageMap = new Map<String, String>();
            pageMap.put('label', page.MasterLabel);
            pageMap.put('value', page.Name);
            pages.add(pageMap);
        }
        return pages;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getEmailTemplateOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        List<Email_Template_Config__c> templates = [
            SELECT Id, Template_Name__c, Object_API_Name__c
            FROM Email_Template_Config__c
            WHERE Is_Active__c = true
            ORDER BY Template_Name__c ASC
        ];
        for (Email_Template_Config__c tmpl : templates) {
            Map<String, String> opt = new Map<String, String>();
            opt.put('label', tmpl.Template_Name__c + ' (' + tmpl.Object_API_Name__c + ')');
            opt.put('value', tmpl.Id);
            options.add(opt);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getDocumentTemplateOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        List<Document_Template__c> templates = [
            SELECT Id, Name, Object_API_Name__c
            FROM Document_Template__c
            WHERE Active__c = true
              AND (Display_Context__c = 'Email' OR Display_Context__c = 'Both' OR Display_Context__c = null)
            ORDER BY Name ASC
        ];
        for (Document_Template__c tmpl : templates) {
            Map<String, String> opt = new Map<String, String>();
            opt.put('label', tmpl.Name + (tmpl.Object_API_Name__c != null ? ' (' + tmpl.Object_API_Name__c + ')' : ''));
            opt.put('value', tmpl.Id);
            options.add(opt);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getApprovalConfigOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        List<Approval_Configuration__c> configs = [
            SELECT Id, Name, Object_API_Name__c, Process_Type__c
            FROM Approval_Configuration__c
            WHERE Is_Active__c = true
            ORDER BY Name ASC
        ];
        for (Approval_Configuration__c config : configs) {
            Map<String, String> opt = new Map<String, String>();
            opt.put('label', config.Name + (config.Process_Type__c != null ? ' - ' + config.Process_Type__c : ''));
            opt.put('value', config.Id);
            options.add(opt);
        }
        return options;
    }
}