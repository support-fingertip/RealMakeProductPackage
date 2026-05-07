public with sharing class PostSalesConfigMasterController {

    public class MasterConfigWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String configName { get; set; }
        @AuraEnabled public Boolean isActive { get; set; }
        @AuraEnabled public String description { get; set; }
        // Demand Reminders
        @AuraEnabled public Decimal reminder1Days { get; set; }
        @AuraEnabled public String reminder1Object { get; set; }
        @AuraEnabled public Decimal reminder2Days { get; set; }
        @AuraEnabled public String reminder2Object { get; set; }
        @AuraEnabled public Decimal reminder3Days { get; set; }
        @AuraEnabled public String reminder3Object { get; set; }
        @AuraEnabled public Decimal reminder4Days { get; set; }
        @AuraEnabled public String reminder4Object { get; set; }
        // Document Templates for Reminders
        @AuraEnabled public Id reminder1Document { get; set; }
        @AuraEnabled public String reminder1DocumentName { get; set; }
        @AuraEnabled public Id reminder2Document { get; set; }
        @AuraEnabled public String reminder2DocumentName { get; set; }
        @AuraEnabled public Id reminder3Document { get; set; }
        @AuraEnabled public String reminder3DocumentName { get; set; }
        @AuraEnabled public Id reminder4Document { get; set; }
        @AuraEnabled public String reminder4DocumentName { get; set; }
        // Cancellation
        @AuraEnabled public Decimal cancellationMailDays { get; set; }
        @AuraEnabled public String cancellationObject { get; set; }
        @AuraEnabled public Boolean enableCancellation { get; set; }
        // Unit Unblocking
        @AuraEnabled public Decimal unitUnblockingDays { get; set; }
        @AuraEnabled public String unitUnblockingObject { get; set; }
        @AuraEnabled public Boolean enableUnitUnblocking { get; set; }
        // Payment Schedule
        @AuraEnabled public String paymentScheduleSource { get; set; }
        // General Settings
        @AuraEnabled public Decimal gracePeriodDays { get; set; }
        @AuraEnabled public Decimal dueDateOffsetDays { get; set; }
        @AuraEnabled public Boolean includeInterest { get; set; }
        @AuraEnabled public Boolean includePreviousDues { get; set; }
        @AuraEnabled public Boolean autoSendEmail { get; set; }
        @AuraEnabled public Boolean enableAutoDemand { get; set; }
        @AuraEnabled public Boolean enableReminders { get; set; }
        @AuraEnabled public Datetime createdDate { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<MasterConfigWrapper> getMasterConfigurations() {
        List<MasterConfigWrapper> wrappers = new List<MasterConfigWrapper>();
        List<Post_Sales_Config_Master__c> configs = [
            SELECT Id, Name, Config_Name__c, Is_Active__c, Description__c,
                   Reminder_1_Days__c, Reminder_1_Object__c, Reminder_1_Document__c, Reminder_1_Document__r.Name,
                   Reminder_2_Days__c, Reminder_2_Object__c, Reminder_2_Document__c, Reminder_2_Document__r.Name,
                   Reminder_3_Days__c, Reminder_3_Object__c, Reminder_3_Document__c, Reminder_3_Document__r.Name,
                   Reminder_4_Days__c, Reminder_4_Object__c, Reminder_4_Document__c, Reminder_4_Document__r.Name,
                   Cancellation_Mail_Days__c, Cancellation_Object__c, Enable_Cancellation__c,
                   Unit_Unblocking_Days__c, Unit_Unblocking_Object__c, Enable_Unit_Unblocking__c,
                   Payment_Schedule_Source__c,
                   Grace_Period_Days__c, Due_Date_Offset_Days__c,
                   Include_Interest__c, Include_Previous_Dues__c, Auto_Send_Email__c,
                   Enable_Auto_Demand__c, Enable_Reminders__c,
                   CreatedDate, LastModifiedDate
            FROM Post_Sales_Config_Master__c
            ORDER BY Is_Active__c DESC, LastModifiedDate DESC
        ];

        for (Post_Sales_Config_Master__c config : configs) {
            wrappers.add(mapToWrapper(config));
        }
        return wrappers;
    }

    @AuraEnabled
    public static Id saveMasterConfiguration(String configJson) {
        try {
            MasterConfigWrapper wrapper = (MasterConfigWrapper) JSON.deserialize(configJson, MasterConfigWrapper.class);
            Post_Sales_Config_Master__c config;

            if (wrapper.id != null) {
                config = [SELECT Id FROM Post_Sales_Config_Master__c WHERE Id = :wrapper.id LIMIT 1];
            } else {
                config = new Post_Sales_Config_Master__c();
            }

            config.Config_Name__c = wrapper.configName;
            config.Is_Active__c = wrapper.isActive == true;
            config.Description__c = wrapper.description;
            // Demand Reminders
            config.Reminder_1_Days__c = wrapper.reminder1Days;
            config.Reminder_1_Object__c = wrapper.reminder1Object;
            config.Reminder_1_Document__c = wrapper.reminder1Document;
            config.Reminder_2_Days__c = wrapper.reminder2Days;
            config.Reminder_2_Object__c = wrapper.reminder2Object;
            config.Reminder_2_Document__c = wrapper.reminder2Document;
            config.Reminder_3_Days__c = wrapper.reminder3Days;
            config.Reminder_3_Object__c = wrapper.reminder3Object;
            config.Reminder_3_Document__c = wrapper.reminder3Document;
            config.Reminder_4_Days__c = wrapper.reminder4Days;
            config.Reminder_4_Object__c = wrapper.reminder4Object;
            config.Reminder_4_Document__c = wrapper.reminder4Document;
            // Cancellation
            config.Cancellation_Mail_Days__c = wrapper.cancellationMailDays;
            config.Cancellation_Object__c = wrapper.cancellationObject;
            config.Enable_Cancellation__c = wrapper.enableCancellation == true;
            // Unit Unblocking
            config.Unit_Unblocking_Days__c = wrapper.unitUnblockingDays;
            config.Unit_Unblocking_Object__c = wrapper.unitUnblockingObject;
            config.Enable_Unit_Unblocking__c = wrapper.enableUnitUnblocking == true;
            // Payment Schedule
            config.Payment_Schedule_Source__c = wrapper.paymentScheduleSource;
            // General Settings
            config.Grace_Period_Days__c = wrapper.gracePeriodDays;
            config.Due_Date_Offset_Days__c = wrapper.dueDateOffsetDays;
            config.Include_Interest__c = wrapper.includeInterest == true;
            config.Include_Previous_Dues__c = wrapper.includePreviousDues == true;
            config.Auto_Send_Email__c = wrapper.autoSendEmail == true;
            config.Enable_Auto_Demand__c = wrapper.enableAutoDemand == true;
            config.Enable_Reminders__c = wrapper.enableReminders == true;

            // If activating this config, deactivate all others
            if (config.Is_Active__c) {
                deactivateOtherConfigs(wrapper.id);
            }

            upsert config;
            return config.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error saving configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteMasterConfiguration(Id configId) {
        try {
            delete [SELECT Id FROM Post_Sales_Config_Master__c WHERE Id = :configId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error deleting configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void activateMasterConfiguration(Id configId) {
        try {
            deactivateOtherConfigs(configId);
            Post_Sales_Config_Master__c config = [SELECT Id, Is_Active__c FROM Post_Sales_Config_Master__c WHERE Id = :configId LIMIT 1];
            config.Is_Active__c = true;
            update config;
        } catch (Exception e) {
            throw new AuraHandledException('Error activating configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void deactivateMasterConfiguration(Id configId) {
        try {
            Post_Sales_Config_Master__c config = [SELECT Id, Is_Active__c FROM Post_Sales_Config_Master__c WHERE Id = :configId LIMIT 1];
            config.Is_Active__c = false;
            update config;
        } catch (Exception e) {
            throw new AuraHandledException('Error deactivating configuration: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static MasterConfigWrapper cloneMasterConfiguration(Id configId) {
        try {
            Post_Sales_Config_Master__c original = [
                SELECT Config_Name__c, Description__c,
                       Reminder_1_Days__c, Reminder_1_Object__c, Reminder_1_Document__c,
                       Reminder_2_Days__c, Reminder_2_Object__c, Reminder_2_Document__c,
                       Reminder_3_Days__c, Reminder_3_Object__c, Reminder_3_Document__c,
                       Reminder_4_Days__c, Reminder_4_Object__c, Reminder_4_Document__c,
                       Cancellation_Mail_Days__c, Cancellation_Object__c, Enable_Cancellation__c,
                       Unit_Unblocking_Days__c, Unit_Unblocking_Object__c, Enable_Unit_Unblocking__c,
                       Payment_Schedule_Source__c,
                       Grace_Period_Days__c, Due_Date_Offset_Days__c,
                       Include_Interest__c, Include_Previous_Dues__c, Auto_Send_Email__c,
                       Enable_Auto_Demand__c, Enable_Reminders__c
                FROM Post_Sales_Config_Master__c
                WHERE Id = :configId LIMIT 1
            ];

            Post_Sales_Config_Master__c cloned = original.clone(false, true, false, false);
            cloned.Config_Name__c = original.Config_Name__c + ' (Copy)';
            cloned.Is_Active__c = false;
            insert cloned;

            Post_Sales_Config_Master__c result = [
                SELECT Id, Name, Config_Name__c, Is_Active__c, Description__c,
                       Reminder_1_Days__c, Reminder_1_Object__c, Reminder_1_Document__c, Reminder_1_Document__r.Name,
                       Reminder_2_Days__c, Reminder_2_Object__c, Reminder_2_Document__c, Reminder_2_Document__r.Name,
                       Reminder_3_Days__c, Reminder_3_Object__c, Reminder_3_Document__c, Reminder_3_Document__r.Name,
                       Reminder_4_Days__c, Reminder_4_Object__c, Reminder_4_Document__c, Reminder_4_Document__r.Name,
                       Cancellation_Mail_Days__c, Cancellation_Object__c, Enable_Cancellation__c,
                       Unit_Unblocking_Days__c, Unit_Unblocking_Object__c, Enable_Unit_Unblocking__c,
                       Payment_Schedule_Source__c,
                       Grace_Period_Days__c, Due_Date_Offset_Days__c,
                       Include_Interest__c, Include_Previous_Dues__c, Auto_Send_Email__c,
                       Enable_Auto_Demand__c, Enable_Reminders__c,
                       CreatedDate, LastModifiedDate
                FROM Post_Sales_Config_Master__c
                WHERE Id = :cloned.Id LIMIT 1
            ];
            return mapToWrapper(result);
        } catch (Exception e) {
            throw new AuraHandledException('Error cloning configuration: ' + e.getMessage());
        }
    }

    private static void deactivateOtherConfigs(Id excludeId) {
        List<Post_Sales_Config_Master__c> activeConfigs;
        if (excludeId != null) {
            activeConfigs = [SELECT Id, Is_Active__c FROM Post_Sales_Config_Master__c WHERE Is_Active__c = true AND Id != :excludeId];
        } else {
            activeConfigs = [SELECT Id, Is_Active__c FROM Post_Sales_Config_Master__c WHERE Is_Active__c = true];
        }
        for (Post_Sales_Config_Master__c c : activeConfigs) {
            c.Is_Active__c = false;
        }
        if (!activeConfigs.isEmpty()) {
            update activeConfigs;
        }
    }

    private static MasterConfigWrapper mapToWrapper(Post_Sales_Config_Master__c config) {
        MasterConfigWrapper w = new MasterConfigWrapper();
        w.id = config.Id;
        w.name = config.Name;
        w.configName = config.Config_Name__c;
        w.isActive = config.Is_Active__c;
        w.description = config.Description__c;
        w.reminder1Days = config.Reminder_1_Days__c;
        w.reminder1Object = config.Reminder_1_Object__c;
        w.reminder1Document = config.Reminder_1_Document__c;
        w.reminder1DocumentName = config.Reminder_1_Document__c != null ? config.Reminder_1_Document__r.Name : null;
        w.reminder2Days = config.Reminder_2_Days__c;
        w.reminder2Object = config.Reminder_2_Object__c;
        w.reminder2Document = config.Reminder_2_Document__c;
        w.reminder2DocumentName = config.Reminder_2_Document__c != null ? config.Reminder_2_Document__r.Name : null;
        w.reminder3Days = config.Reminder_3_Days__c;
        w.reminder3Object = config.Reminder_3_Object__c;
        w.reminder3Document = config.Reminder_3_Document__c;
        w.reminder3DocumentName = config.Reminder_3_Document__c != null ? config.Reminder_3_Document__r.Name : null;
        w.reminder4Days = config.Reminder_4_Days__c;
        w.reminder4Object = config.Reminder_4_Object__c;
        w.reminder4Document = config.Reminder_4_Document__c;
        w.reminder4DocumentName = config.Reminder_4_Document__c != null ? config.Reminder_4_Document__r.Name : null;
        w.cancellationMailDays = config.Cancellation_Mail_Days__c;
        w.cancellationObject = config.Cancellation_Object__c;
        w.enableCancellation = config.Enable_Cancellation__c;
        w.unitUnblockingDays = config.Unit_Unblocking_Days__c;
        w.unitUnblockingObject = config.Unit_Unblocking_Object__c;
        w.enableUnitUnblocking = config.Enable_Unit_Unblocking__c;
        w.paymentScheduleSource = config.Payment_Schedule_Source__c;
        w.gracePeriodDays = config.Grace_Period_Days__c;
        w.dueDateOffsetDays = config.Due_Date_Offset_Days__c;
        w.includeInterest = config.Include_Interest__c;
        w.includePreviousDues = config.Include_Previous_Dues__c;
        w.autoSendEmail = config.Auto_Send_Email__c;
        w.enableAutoDemand = config.Enable_Auto_Demand__c;
        w.enableReminders = config.Enable_Reminders__c;
        w.createdDate = config.CreatedDate;
        w.lastModifiedDate = config.LastModifiedDate;
        return w;
    }
}