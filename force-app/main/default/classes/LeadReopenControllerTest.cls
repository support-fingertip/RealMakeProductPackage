@isTest
private class LeadReopenControllerTest {

    @TestSetup
    static void setup() {
        TestDataFactory.createCPModuleConfig();
        Project__c proj = TestDataFactory.createProject('Reopen Ctrl Project');

        // Create RR bucket
        Round_Robin__c rr = new Round_Robin__c(Is_Active__c = true);
        insert rr;
        Round_Robin_Filter__c filter = new Round_Robin_Filter__c(
            Round_Robin__c = rr.Id,
            Field_API_Name__c = 'Project__c',
            Field_Value__c = proj.Id,
            Field_Priority__c = 1,
            Preference_Order__c = 1
        );
        insert filter;
        Round_Robin_Member__c member = new Round_Robin_Member__c(
            Round_Robin__c = rr.Id,
            User__c = UserInfo.getUserId(),
            Assignment_Type__c = 'Pre Sales',
            Is_Active__c = true,
            Order__c = 1
        );
        insert member;
    }

    @isTest
    static void testGetLeadInfo() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'InfoTest', '9400000001');

        Test.startTest();
        LeadReopenController.LeadInfo info =
            LeadReopenController.getLeadInfo(lead.Id);
        Test.stopTest();

        System.assertNotEquals(null, info);
        System.assertNotEquals(null, info.leadName);
        System.assertNotEquals(null, info.leadStatus);
        System.assertNotEquals(null, info.projectName);
    }

    @isTest
    static void testGetLeadInfoNullId() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            LeadReopenController.getLeadInfo(null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown);
    }

    @isTest
    static void testReopenLead() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Reopen', '9400000002');

        lead.Lead_Status__c = 'Unqualified';
        lead.Lost_Reason__c = 'Budget';
        update lead;

        Test.startTest();
        LeadReopenService.ReopenResult result =
            LeadReopenController.reopenLead(lead.Id, 'Manual', 'Test');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(lead.Id, result.leadId);
    }

    @isTest
    static void testReopenActiveLeadThrows() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'ActiveReopen', '9400000003');

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            LeadReopenController.reopenLead(lead.Id, 'Manual', null);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown);
    }
}