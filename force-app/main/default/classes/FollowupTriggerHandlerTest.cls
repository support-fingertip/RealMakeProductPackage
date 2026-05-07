/**
 * @description Test class for FollowupTriggerHandler.
 * Covers Cancelled_Date__c stamping on Status → 'Cancelled' transition,
 * the non-cancel branch, and no-re-stamp on subsequent updates.
 */
@isTest
private class FollowupTriggerHandlerTest {

    @TestSetup
    static void setup() {
        Project__c proj = TestDataFactory.createProject('FU Project');
        TestDataFactory.createLead(proj.Id, 'Alice', '9400000001');
    }

    @isTest
    static void cancelledDateStampedOnCancel() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Followup__c fu = TestDataFactory.createFollowup(lead.Id, UserInfo.getUserId());

        Test.startTest();
        fu.Status__c = 'Cancelled';
        fu.Cancelled_Reason__c = 'Test cancel';  // required by validation rule
        update fu;
        Test.stopTest();

        fu = [SELECT Cancelled_Date__c FROM Followup__c WHERE Id = :fu.Id];
        System.assertNotEquals(null, fu.Cancelled_Date__c,
            'Cancelled_Date__c should be stamped on cancel');
    }

    @isTest
    static void cancelledDateNotStampedOnOtherUpdate() {
        // Update something other than Status — the "not transitioning to Cancelled"
        // branch must leave Cancelled_Date__c null.
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Followup__c fu = TestDataFactory.createFollowup(lead.Id, UserInfo.getUserId());

        Test.startTest();
        fu.Subject__c = 'Renamed subject';
        update fu;
        Test.stopTest();

        fu = [SELECT Cancelled_Date__c FROM Followup__c WHERE Id = :fu.Id];
        System.assertEquals(null, fu.Cancelled_Date__c,
            'Cancelled_Date__c should stay null when not transitioning to Cancelled');
    }

    @isTest
    static void stayingCancelledDoesNotReStamp() {
        // Exercises the oldFu.Status__c != 'Cancelled' branch returning false.
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Followup__c fu = TestDataFactory.createFollowup(lead.Id, UserInfo.getUserId());
        fu.Status__c = 'Cancelled';
        fu.Cancelled_Reason__c = 'Test';
        update fu;

        fu = [SELECT Cancelled_Date__c FROM Followup__c WHERE Id = :fu.Id];
        Datetime firstStamp = fu.Cancelled_Date__c;

        Test.startTest();
        fu.Subject__c = 'Updated subject';
        update fu;
        Test.stopTest();

        fu = [SELECT Cancelled_Date__c FROM Followup__c WHERE Id = :fu.Id];
        System.assertEquals(firstStamp, fu.Cancelled_Date__c,
            'Cancelled_Date__c should not be re-stamped on subsequent updates');
    }
}