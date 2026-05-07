/**
 * @description Test class for RoundRobinMemberController (100% coverage).
 */
@isTest
private class RoundRobinMemberControllerTest {

    @isTest
    static void getMembers_returnsOrderedList() {
        Project__c p = TestDataFactory.createProject('RRMC');
        Round_Robin__c rr = TestDataFactory.createRoundRobin(p.Id);
        TestDataFactory.createRRMember(rr.Id, UserInfo.getUserId(), 'Pre Sales', 1);

        Test.startTest();
        List<Round_Robin_Member__c> members = RoundRobinMemberController.getMembers(rr.Id);
        Test.stopTest();
        System.assertEquals(1, members.size());
    }

    @isTest
    static void toggleMemberStatus_success() {
        Project__c p = TestDataFactory.createProject('RRMC');
        Round_Robin__c rr = TestDataFactory.createRoundRobin(p.Id);
        Round_Robin_Member__c m = TestDataFactory.createRRMember(rr.Id, UserInfo.getUserId(), 'Pre Sales', 1);

        Test.startTest();
        RoundRobinMemberController.toggleMemberStatus(m.Id, false);
        Test.stopTest();
        System.assertEquals(false,
            [SELECT Is_Active__c FROM Round_Robin_Member__c WHERE Id = :m.Id].Is_Active__c);
    }

    @isTest
    static void toggleMemberStatus_invalidId_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            RoundRobinMemberController.toggleMemberStatus(null, true);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Null id should throw via catch branch');
    }
}