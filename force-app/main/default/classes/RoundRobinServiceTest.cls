/**
 * @description Test class for RoundRobinService.
 * Exercises the 4-step pipeline (Query → Match → Filter → Rotate) across
 * both entry modes (single-lead getNextUser and bulk assignLeads +
 * commitPendingUpdates) plus guard-clause early returns.
 */
@isTest
private class RoundRobinServiceTest {

    @TestSetup
    static void setup() {
        Project__c proj = TestDataFactory.createProject('RRS Project');
        Round_Robin__c rr = TestDataFactory.createRoundRobin(proj.Id);
        TestDataFactory.createRRFilter(rr.Id, 'Project__c', String.valueOf(proj.Id), 10);
        TestDataFactory.createRRMember(rr.Id, UserInfo.getUserId(), 'Pre Sales', 1);
    }

    // ── single-lead entry (getNextUser) ─────────────────────────────

    @isTest
    static void getNextUser_nullInputs_returnsNull() {
        System.assertEquals(null, RoundRobinService.getNextUser((Lead__c) null, 'Pre Sales'));
        System.assertEquals(null, RoundRobinService.getNextUser(new Lead__c(), ''));
    }

    @isTest
    static void getNextUser_matchingBucket_returnsUser() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c ld = new Lead__c(Project__c = proj.Id);

        Test.startTest();
        Id userId = RoundRobinService.getNextUser(ld, 'Pre Sales');
        Test.stopTest();
        System.assertEquals(UserInfo.getUserId(), userId);
    }

    @isTest
    static void getNextUser_projectIdOverload() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        Id userId = RoundRobinService.getNextUser(proj.Id, 'Pre Sales');
        Test.stopTest();
        System.assertEquals(UserInfo.getUserId(), userId);
    }

    @isTest
    static void getNextUser_noBucketsReturnsNull() {
        // Deactivate the setup bucket
        Round_Robin__c rr = [SELECT Id FROM Round_Robin__c LIMIT 1];
        rr.Is_Active__c = false;
        update rr;

        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        Id userId = RoundRobinService.getNextUser(new Lead__c(Project__c = proj.Id), 'Pre Sales');
        Test.stopTest();
        System.assertEquals(null, userId);
    }

    @isTest
    static void getNextUser_noMatchingBucket() {
        Lead__c unmatched = new Lead__c(); // no Project__c → no filter match
        Test.startTest();
        Id userId = RoundRobinService.getNextUser(unmatched, 'Pre Sales');
        Test.stopTest();
        System.assertEquals(null, userId);
    }

    @isTest
    static void getNextUser_noMembersOfType_returnsNull() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        Id userId = RoundRobinService.getNextUser(
            new Lead__c(Project__c = proj.Id), 'No-Such-Type'
        );
        Test.stopTest();
        System.assertEquals(null, userId);
    }

    // ── bulk entry (assignLeads + commitPendingUpdates) ─────────────

    @isTest
    static void assignLeads_nullAndEmpty_noop() {
        RoundRobinService.assignLeads(null, 'Pre Sales');
        RoundRobinService.assignLeads(new List<Lead__c>(), 'Pre Sales');
        RoundRobinService.assignLeads(new List<Lead__c>{ new Lead__c() }, '');
    }

    @isTest
    static void assignLeads_assignsOwnerAndCommits() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c l1 = new Lead__c(Project__c = proj.Id);
        Lead__c l2 = new Lead__c(Project__c = proj.Id);

        Test.startTest();
        RoundRobinService.assignLeads(new List<Lead__c>{ l1, l2 }, 'Pre Sales');
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), l1.OwnerId);
        System.assertEquals(UserInfo.getUserId(), l2.OwnerId);
        System.assert(!RoundRobinService.pendingMemberUpdates.isEmpty(),
            'Deferred updates should be buffered');

        RoundRobinService.commitPendingUpdates();
        System.assert(RoundRobinService.pendingMemberUpdates.isEmpty(),
            'Buffer should be cleared after commit');
    }

    @isTest
    static void assignLeads_preassignedLeadIsSkipped() {
        // Create a second real user so ld.OwnerId != running user
        User cu = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        User other;
        System.runAs(cu) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            other = new User(
                Alias = 'rrs', Email = 'rrs@rrs.invalid',
                EmailEncodingKey = 'UTF-8', LastName = 'Rrs',
                LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
                ProfileId = p.Id, TimeZoneSidKey = 'America/Los_Angeles',
                Username = 'rrs' + DateTime.now().getTime() + '@rrs.invalid'
            );
            insert other;
        }
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c preassigned = new Lead__c(Project__c = proj.Id, OwnerId = other.Id);

        Test.startTest();
        RoundRobinService.assignLeads(new List<Lead__c>{ preassigned }, 'Pre Sales');
        Test.stopTest();
        System.assertEquals(other.Id, preassigned.OwnerId,
            'Pre-assigned owner must not be overwritten');
    }

    @isTest
    static void assignLeads_noBucketsEarlyReturn() {
        Round_Robin__c rr = [SELECT Id FROM Round_Robin__c LIMIT 1];
        rr.Is_Active__c = false;
        update rr;
        Lead__c ld = new Lead__c();
        Test.startTest();
        RoundRobinService.assignLeads(new List<Lead__c>{ ld }, 'Pre Sales');
        Test.stopTest();
    }

    @isTest
    static void commitPendingUpdates_emptyBufferEarlyReturn() {
        RoundRobinService.pendingMemberUpdates.clear();
        Test.startTest();
        RoundRobinService.commitPendingUpdates();
        Test.stopTest();
    }

    @isTest
    static void assignLeads_rotationWithHistory() {
        // Seed Last_Assigned__c so getNextRotationIndex takes the "latest
        // timestamp → next slot" branch rather than the zero-default branch.
        Round_Robin_Member__c m = [SELECT Id FROM Round_Robin_Member__c LIMIT 1];
        m.Last_Assigned__c = DateTime.now().addMinutes(-5);
        update m;

        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        RoundRobinService.assignLeads(
            new List<Lead__c>{ new Lead__c(Project__c = proj.Id) }, 'Pre Sales'
        );
        RoundRobinService.commitPendingUpdates();
        Test.stopTest();
    }
}