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