/**
 * @description Test class for NotificationDashboardController (100% coverage).
 * Each method is a thin try/catch wrapper — covers both the success pass-
 * through and the catch → AuraHandledException path.
 */
@isTest
private class NotificationDashboardControllerTest {

    @TestSetup
    static void setup() {
        Project__c p = TestDataFactory.createProject('NDC');
        TestDataFactory.createLead(p.Id, 'NDC', '9900001301');
    }

    @isTest
    static void getDashboardConfig_success() {
        Test.startTest();
        Map<String, Object> cfg = NotificationDashboardController.getDashboardConfig();
        Test.stopTest();
        System.assertNotEquals(null, cfg);
    }

    @isTest
    static void getTabData_success() {
        NotificationDashboardService.cachedTabConfigs = new List<Dashboard_Tab_Config__mdt>{
            new Dashboard_Tab_Config__mdt(
                Tab_Name__c = 'Today\'s Leads', Tab_Key__c = 'TODAY_LEADS',
                Sort_Order__c = 1, Icon_Name__c = 'standard:lead',
                SObject_Names__c = 'Lead__c', Allowed_Profiles__c = 'System Administrator',
                Empty_State_Text__c = '', Show_Badge_Count__c = true,
                Status_Actions_JSON__c = '[]', Is_Active__c = true
            )
        };
        NotificationDashboardService.cachedFieldConfigs = new List<Dashboard_Field_Config__mdt>{
            new Dashboard_Field_Config__mdt(
                SObject_Name__c = 'Lead__c', Field_API_Name__c = 'First_Name__c',
                Display_Label__c = 'First Name', Display_Order__c = 1, Context__c = 'CARD',
                Field_Type__c = 'TEXT', Is_Title_Field__c = true,
                Badge_Variant__c = '', CSS_Class__c = '', Is_Active__c = true
            )
        };
        Test.startTest();
        NotificationDashboardService.TabDataResult r =
            NotificationDashboardController.getTabData('TODAY_LEADS', 10, 0);
        Test.stopTest();
        System.assertNotEquals(null, r);
    }

    @isTest
    static void getTabData_invalidTab_throws() {
        Boolean thrown = false;
        try {
            NotificationDashboardController.getTabData(null, null, null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown);
    }

    @isTest
    static void updateRecordStatus_invalid_throws() {
        Boolean thrown = false;
        try {
            NotificationDashboardController.updateRecordStatus(
                null, null, null, null, null
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown);
    }

    @isTest
    static void moveLeadToFollowUp_success() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Test.startTest();
        NotificationDashboardController.moveLeadToFollowUp(
            lead.Id, 'Follow up', String.valueOf(DateTime.now().addDays(1)), 'notes'
        );
        Test.stopTest();
    }

    @isTest
    static void moveLeadToFollowUp_invalid_throws() {
        Boolean thrown = false;
        try {
            NotificationDashboardController.moveLeadToFollowUp(null, null, null, null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown);
    }
}