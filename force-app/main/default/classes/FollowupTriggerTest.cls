/**
 * @description Test class for FollowupTrigger (100% coverage).
 */
@isTest
private class FollowupTriggerTest {
    @isTest
    static void update_cancelled() {
        Project__c p = TestDataFactory.createProject('FUT');
        Lead__c lead = TestDataFactory.createLead(p.Id, 'FUT', '9300000001');
        Followup__c fu = TestDataFactory.createFollowup(lead.Id, UserInfo.getUserId());

        Test.startTest();
        fu.Status__c = 'Cancelled';
        fu.Cancelled_Reason__c = 'Test';  // satisfies validation rule
        update fu;                         // before update
        Test.stopTest();
    }
}