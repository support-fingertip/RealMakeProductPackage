/**
 * @description Test class for RoundRobinSelector.
 * Exercises the single SOQL helper that returns all active buckets
 * with their filters and active members.
 */
@isTest
private class RoundRobinSelectorTest {

    @isTest
    static void returnsEmptyWhenNoBucketsExist() {
        Test.startTest();
        List<Round_Robin__c> rows = RoundRobinSelector.getActiveBucketsWithChildren();
        Test.stopTest();
        System.assertEquals(0, rows.size(), 'No buckets → empty list');
    }

    @isTest
    static void returnsActiveBucketWithChildren() {
        Project__c proj = TestDataFactory.createProject('RRS Project');
        Round_Robin__c rr = TestDataFactory.createRoundRobin(proj.Id);
        TestDataFactory.createRRFilter(rr.Id, 'Project__c', String.valueOf(proj.Id), 10);
        TestDataFactory.createRRMember(rr.Id, UserInfo.getUserId(), 'Pre Sales', 1);

        Test.startTest();
        List<Round_Robin__c> rows = RoundRobinSelector.getActiveBucketsWithChildren();
        Test.stopTest();

        System.assertEquals(1, rows.size(), 'Should return one active bucket');
        System.assertEquals(1, rows[0].Round_Robin_Filters__r.size(), 'One filter');
        System.assertEquals(1, rows[0].Round_Robin_Members__r.size(), 'One member');
    }

    @isTest
    static void inactiveBucketExcluded() {
        Project__c proj = TestDataFactory.createProject('RRS Inactive');
        Round_Robin__c rr = TestDataFactory.createRoundRobin(proj.Id);
        rr.Is_Active__c = false;
        update rr;

        Test.startTest();
        List<Round_Robin__c> rows = RoundRobinSelector.getActiveBucketsWithChildren();
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Inactive bucket must be excluded');
    }
}