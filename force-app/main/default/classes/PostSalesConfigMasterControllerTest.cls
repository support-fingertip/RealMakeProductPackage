@isTest
private class PostSalesConfigMasterControllerTest {

    @TestSetup
    static void setupData() {
        Post_Sales_Config_Master__c config = new Post_Sales_Config_Master__c();
        config.Config_Name__c = 'Test Config';
        config.Is_Active__c = true;
        config.Description__c = 'Test Description';
        config.Reminder_1_Days__c = 7;
        config.Reminder_2_Days__c = 14;
        config.Reminder_3_Days__c = 21;
        config.Reminder_4_Days__c = 28;
        config.Cancellation_Mail_Days__c = 30;
        config.Enable_Cancellation__c = true;
        config.Unit_Unblocking_Days__c = 5;
        config.Enable_Unit_Unblocking__c = false;
        config.Grace_Period_Days__c = 3;
        config.Due_Date_Offset_Days__c = 2;
        config.Include_Interest__c = true;
        config.Include_Previous_Dues__c = false;
        config.Auto_Send_Email__c = true;
        config.Enable_Auto_Demand__c = true;
        config.Enable_Reminders__c = true;
        insert config;
    }

    @isTest
    static void testGetMasterConfigurations() {
        Test.startTest();
        List<PostSalesConfigMasterController.MasterConfigWrapper> results =
            PostSalesConfigMasterController.getMasterConfigurations();
        Test.stopTest();
        System.assert(results.size() >= 1, 'Should return at least one config');
        System.assertEquals('Test Config', results[0].configName, 'Config name should match');
        System.assertEquals(true, results[0].isActive, 'Should be active');
        System.assertEquals(7, results[0].reminder1Days, 'Reminder 1 days should be 7');
    }

    @isTest
    static void testSaveMasterConfiguration_New() {
        PostSalesConfigMasterController.MasterConfigWrapper wrapper = new PostSalesConfigMasterController.MasterConfigWrapper();
        wrapper.configName = 'New Config';
        wrapper.isActive = false;
        wrapper.description = 'New Description';
        wrapper.gracePeriodDays = 5;

        Test.startTest();
        Id newId = PostSalesConfigMasterController.saveMasterConfiguration(JSON.serialize(wrapper));
        Test.stopTest();
        System.assertNotEquals(null, newId, 'Should return new Id');
    }

    @isTest
    static void testSaveMasterConfiguration_Update() {
        Post_Sales_Config_Master__c config = [SELECT Id FROM Post_Sales_Config_Master__c LIMIT 1];
        PostSalesConfigMasterController.MasterConfigWrapper wrapper = new PostSalesConfigMasterController.MasterConfigWrapper();
        wrapper.id = config.Id;
        wrapper.configName = 'Updated Config';
        wrapper.isActive = true;
        wrapper.description = 'Updated';

        Test.startTest();
        Id updatedId = PostSalesConfigMasterController.saveMasterConfiguration(JSON.serialize(wrapper));
        Test.stopTest();
        System.assertEquals(config.Id, updatedId, 'Should return same Id');
    }

    @isTest
    static void testDeleteMasterConfiguration() {
        Post_Sales_Config_Master__c config = [SELECT Id FROM Post_Sales_Config_Master__c LIMIT 1];
        Test.startTest();
        PostSalesConfigMasterController.deleteMasterConfiguration(config.Id);
        Test.stopTest();
        List<Post_Sales_Config_Master__c> remaining = [SELECT Id FROM Post_Sales_Config_Master__c WHERE Id = :config.Id];
        System.assertEquals(0, remaining.size(), 'Record should be deleted');
    }

    @isTest
    static void testActivateMasterConfiguration() {
        // Insert a second inactive config
        Post_Sales_Config_Master__c config2 = new Post_Sales_Config_Master__c();
        config2.Config_Name__c = 'Config 2';
        config2.Is_Active__c = false;
        insert config2;

        Test.startTest();
        PostSalesConfigMasterController.activateMasterConfiguration(config2.Id);
        Test.stopTest();

        Post_Sales_Config_Master__c activated = [SELECT Is_Active__c FROM Post_Sales_Config_Master__c WHERE Id = :config2.Id];
        System.assertEquals(true, activated.Is_Active__c, 'Should be activated');
    }

    @isTest
    static void testDeactivateMasterConfiguration() {
        Post_Sales_Config_Master__c config = [SELECT Id FROM Post_Sales_Config_Master__c LIMIT 1];
        Test.startTest();
        PostSalesConfigMasterController.deactivateMasterConfiguration(config.Id);
        Test.stopTest();

        Post_Sales_Config_Master__c deactivated = [SELECT Is_Active__c FROM Post_Sales_Config_Master__c WHERE Id = :config.Id];
        System.assertEquals(false, deactivated.Is_Active__c, 'Should be deactivated');
    }

    @isTest
    static void testCloneMasterConfiguration() {
        Post_Sales_Config_Master__c config = [SELECT Id FROM Post_Sales_Config_Master__c LIMIT 1];
        Test.startTest();
        PostSalesConfigMasterController.MasterConfigWrapper cloned =
            PostSalesConfigMasterController.cloneMasterConfiguration(config.Id);
        Test.stopTest();
        System.assertNotEquals(null, cloned, 'Cloned wrapper should not be null');
        System.assert(cloned.configName.contains('(Copy)'), 'Cloned name should contain (Copy)');
        System.assertEquals(false, cloned.isActive, 'Cloned config should be inactive');
    }

    @isTest
    static void testMasterConfigWrapper_Properties() {
        PostSalesConfigMasterController.MasterConfigWrapper w = new PostSalesConfigMasterController.MasterConfigWrapper();
        w.id = null;
        w.name = 'Name';
        w.configName = 'Config';
        w.isActive = true;
        w.description = 'Desc';
        w.reminder1Days = 1;
        w.reminder1Object = 'Obj';
        w.reminder1Document = null;
        w.reminder1DocumentName = 'Doc';
        w.reminder2Days = 2;
        w.reminder2Object = 'Obj2';
        w.reminder2Document = null;
        w.reminder2DocumentName = 'Doc2';
        w.reminder3Days = 3;
        w.reminder3Object = 'Obj3';
        w.reminder3Document = null;
        w.reminder3DocumentName = 'Doc3';
        w.reminder4Days = 4;
        w.reminder4Object = 'Obj4';
        w.reminder4Document = null;
        w.reminder4DocumentName = 'Doc4';
        w.cancellationMailDays = 30;
        w.cancellationObject = 'CO';
        w.enableCancellation = true;
        w.unitUnblockingDays = 5;
        w.unitUnblockingObject = 'UO';
        w.enableUnitUnblocking = false;
        w.paymentScheduleSource = 'Source';
        w.gracePeriodDays = 3;
        w.dueDateOffsetDays = 2;
        w.includeInterest = true;
        w.includePreviousDues = false;
        w.autoSendEmail = true;
        w.enableAutoDemand = true;
        w.enableReminders = true;
        w.createdDate = Datetime.now();
        w.lastModifiedDate = Datetime.now();
        System.assertEquals('Config', w.configName);
    }
}