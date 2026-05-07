/**
 * ════════════════════════════════════════════════════════════════════════════
 * RoundRobinAssignmentHandlerTest
 * ════════════════════════════════════════════════════════════════════════════
 * Comprehensive test coverage for the dynamic Round Robin Assignment Engine.
 *
 * Scenarios covered:
 *   1. Bulk assignment (200 leads)
 *   2. Highest priority score wins when multiple buckets match
 *   3. Tie-breaker via Total_Priority__c
 *   4. No match leaves OwnerId unchanged
 *   5. Fair rotation across batch
 *   6. Bucket with no active members is skipped
 *   7. Rotation tracking (Last_Assigned__c) committed correctly
 * ════════════════════════════════════════════════════════════════════════════
 */
@isTest
private class RoundRobinAssignmentHandlerTest {

    // ── Constants matching handler ──────────────────────────────────────
    private static final String ASSIGN_TYPE = 'Pre Sales';

    // ═══════════════════════════════════════════════════════════════════
    //  TEST DATA SETUP
    // ═══════════════════════════════════════════════════════════════════

    @TestSetup
    static void setupData() {

        // ── 3 Test Users ────────────────────────────────────────────
        Profile stdProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        List<User> testUsers = new List<User>();
        for (Integer i = 0; i < 3; i++) {
            testUsers.add(new User(
                FirstName     = 'RRTest',
                LastName      = 'User' + i,
                Email         = 'rrtest' + i + '@test.example.com',
                Username      = 'rrtest' + i + '@rr.test.' + DateTime.now().getTime(),
                Alias         = 'rrt' + i,
                TimeZoneSidKey    = 'America/New_York',
                LocaleSidKey      = 'en_US',
                EmailEncodingKey  = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId         = stdProfile.Id,
                Availability__c   = true,
                is_working__c     = true
            ));
        }
        insert testUsers;

        // ── Field Priorities ────────────────────────────────────────
        //    Last_Name__c  = weight 10
        //    First_Name__c = weight 5
        insert new List<Round_Robin_Field_Priority__c>{
            new Round_Robin_Field_Priority__c(
                Field_API_Name__c = 'Last_Name__c',
                Priority__c       = 10
            ),
            new Round_Robin_Field_Priority__c(
                Field_API_Name__c = 'First_Name__c',
                Priority__c       = 5
            )
        };

        // ── Round Robin Buckets ─────────────────────────────────────

        // RR1: "High Specificity" – matches Last_Name + First_Name (score = 15)
        Round_Robin__c rr1 = new Round_Robin__c(
            Name              = 'RR High Specificity',
            Is_Active__c      = true,
            Total_Priority__c = 20
        );

        // RR2: "Low Specificity" – matches Last_Name only (score = 10)
        Round_Robin__c rr2 = new Round_Robin__c(
            Name              = 'RR Low Specificity',
            Is_Active__c      = true,
            Total_Priority__c = 10
        );

        // RR3: "Tiebreaker HIGH" – matches First_Name=Gamma (score = 5), Total = 50
        Round_Robin__c rr3 = new Round_Robin__c(
            Name              = 'RR Tiebreaker High',
            Is_Active__c      = true,
            Total_Priority__c = 50
        );

        // RR4: "Tiebreaker LOW" – matches First_Name=Gamma (score = 5), Total = 30
        Round_Robin__c rr4 = new Round_Robin__c(
            Name              = 'RR Tiebreaker Low',
            Is_Active__c      = true,
            Total_Priority__c = 30
        );

        // RR5: "No Members" – matching filters but zero active members
        Round_Robin__c rr5 = new Round_Robin__c(
            Name              = 'RR No Members',
            Is_Active__c      = true,
            Total_Priority__c = 5
        );

        insert new List<Round_Robin__c>{ rr1, rr2, rr3, rr4, rr5 };

        // ── Filters ─────────────────────────────────────────────────

        insert new List<Round_Robin_Filter__c>{
            // RR1: Last_Name__c = 'Alpha' AND First_Name__c = 'Beta'
            new Round_Robin_Filter__c(
                Round_Robin__c     = rr1.Id,
                Field_API_Name__c  = 'Last_Name__c',
                Field_Value__c     = 'Alpha',
                Preference_Order__c = 1
            ),
            new Round_Robin_Filter__c(
                Round_Robin__c     = rr1.Id,
                Field_API_Name__c  = 'First_Name__c',
                Field_Value__c     = 'Beta',
                Preference_Order__c = 2
            ),

            // RR2: Last_Name__c = 'Alpha'
            new Round_Robin_Filter__c(
                Round_Robin__c     = rr2.Id,
                Field_API_Name__c  = 'Last_Name__c',
                Field_Value__c     = 'Alpha',
                Preference_Order__c = 1
            ),

            // RR3: First_Name__c = 'Gamma'
            new Round_Robin_Filter__c(
                Round_Robin__c     = rr3.Id,
                Field_API_Name__c  = 'First_Name__c',
                Field_Value__c     = 'Gamma',
                Preference_Order__c = 1
            ),

            // RR4: First_Name__c = 'Gamma'
            new Round_Robin_Filter__c(
                Round_Robin__c     = rr4.Id,
                Field_API_Name__c  = 'First_Name__c',
                Field_Value__c     = 'Gamma',
                Preference_Order__c = 1
            ),

            // RR5: Last_Name__c = 'Delta'
            new Round_Robin_Filter__c(
                Round_Robin__c     = rr5.Id,
                Field_API_Name__c  = 'Last_Name__c',
                Field_Value__c     = 'Delta',
                Preference_Order__c = 1
            )
        };

        // ── Members ─────────────────────────────────────────────────

        List<Round_Robin_Member__c> members = new List<Round_Robin_Member__c>();

        // RR1 members: u0, u1, u2 (3-person rotation)
        for (Integer i = 0; i < 3; i++) {
            members.add(new Round_Robin_Member__c(
                Round_Robin__c      = rr1.Id,
                User__c             = testUsers[i].Id,
                Assignment_Type__c  = ASSIGN_TYPE,
                Is_Active__c        = true,
                Order__c            = i + 1,
                Unique_Key__c       = rr1.Id + '-' + testUsers[i].Id + '-' + ASSIGN_TYPE
            ));
        }

        // RR2 members: u0 only
        members.add(new Round_Robin_Member__c(
            Round_Robin__c      = rr2.Id,
            User__c             = testUsers[0].Id,
            Assignment_Type__c  = ASSIGN_TYPE,
            Is_Active__c        = true,
            Order__c            = 1,
            Unique_Key__c       = rr2.Id + '-' + testUsers[0].Id + '-' + ASSIGN_TYPE
        ));

        // RR3 members: u1
        members.add(new Round_Robin_Member__c(
            Round_Robin__c      = rr3.Id,
            User__c             = testUsers[1].Id,
            Assignment_Type__c  = ASSIGN_TYPE,
            Is_Active__c        = true,
            Order__c            = 1,
            Unique_Key__c       = rr3.Id + '-' + testUsers[1].Id + '-' + ASSIGN_TYPE
        ));

        // RR4 members: u2
        members.add(new Round_Robin_Member__c(
            Round_Robin__c      = rr4.Id,
            User__c             = testUsers[2].Id,
            Assignment_Type__c  = ASSIGN_TYPE,
            Is_Active__c        = true,
            Order__c            = 1,
            Unique_Key__c       = rr4.Id + '-' + testUsers[2].Id + '-' + ASSIGN_TYPE
        ));

        // RR5: NO members inserted (testing empty pool skip)

        insert members;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HELPER: Retrieve test users in deterministic order
    // ═══════════════════════════════════════════════════════════════════

    private static List<User> getTestUsers() {
        return [SELECT Id, LastName FROM User
                WHERE FirstName = 'RRTest'
                ORDER BY LastName ASC];
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 1: Bulk 200 Leads – all assigned, fair rotation
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testBulkAssignment_200Leads() {
        List<User> users = getTestUsers();
        Set<Id> memberUserIds = new Set<Id>();
        for (User u : users) {
            memberUserIds.add(u.Id);
        }

        // Build 200 leads matching RR1 (Last_Name=Alpha, First_Name=Beta)
        List<Lead__c> leads = new List<Lead__c>();
        for (Integer i = 0; i < 200; i++) {
            leads.add(new Lead__c(
                Last_Name__c     = 'Alpha',
                First_Name__c   = 'Beta',
                Primary_Mobile__c = '900000' + String.valueOf(i).leftPad(4, '0')
            ));
        }

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(leads);
        RoundRobinAssignmentHandler.commitRotationUpdates();
        Test.stopTest();

        // Verify: every lead got assigned to one of the 3 RR1 members
        for (Lead__c ld : leads) {
            System.assert(
                memberUserIds.contains(ld.OwnerId),
                'Lead should be assigned to an RR1 member. Got: ' + ld.OwnerId
            );
        }

        // Verify fair rotation: each user gets 66 or 67 leads
        Map<Id, Integer> countMap = new Map<Id, Integer>();
        for (Lead__c ld : leads) {
            Integer c = countMap.containsKey(ld.OwnerId) ? countMap.get(ld.OwnerId) : 0;
            countMap.put(ld.OwnerId, c + 1);
        }
        for (Id uid : countMap.keySet()) {
            Integer count = countMap.get(uid);
            System.assert(
                count >= 66 && count <= 67,
                'Each member should get 66-67 leads. User ' + uid + ' got ' + count
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 2: Highest priority score wins
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testHighestPriorityScoreWins() {
        List<User> users = getTestUsers();
        // RR1 has score 15 (Last_Name=10 + First_Name=5), RR2 has score 10 (Last_Name only)
        // Lead matches both -> RR1 should win
        // RR1 members: u0, u1, u2; rotation starts at index 0 -> u0

        Lead__c ld = new Lead__c(
            Last_Name__c     = 'Alpha',
            First_Name__c   = 'Beta',
            Primary_Mobile__c = '8001110000'
        );

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>{ ld });
        RoundRobinAssignmentHandler.commitRotationUpdates();
        Test.stopTest();

        // Should be assigned to first RR1 member (u0)
        System.assertEquals(
            users[0].Id,
            ld.OwnerId,
            'Lead should be assigned to RR1 first member (highest score bucket)'
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 3: Tie-breaker uses Total_Priority__c
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testTiebreakerTotalPriority() {
        List<User> users = getTestUsers();
        // RR3 and RR4 both match First_Name=Gamma -> same score (5)
        // RR3 Total_Priority=50 > RR4 Total_Priority=30 -> RR3 wins
        // RR3 member: u1

        Lead__c ld = new Lead__c(
            Last_Name__c     = 'NoMatchHere',
            First_Name__c   = 'Gamma',
            Primary_Mobile__c = '8002220000'
        );

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>{ ld });
        RoundRobinAssignmentHandler.commitRotationUpdates();
        Test.stopTest();

        System.assertEquals(
            users[1].Id,
            ld.OwnerId,
            'Tiebreaker: RR3 (Total_Priority=50) should win over RR4 (Total_Priority=30)'
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 4: No match preserves original OwnerId
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testNoMatchPreservesOwner() {
        Lead__c ld = new Lead__c(
            Last_Name__c     = 'ZZZNoMatch',
            First_Name__c   = 'XXXNoMatch',
            Primary_Mobile__c = '8003330000'
        );
        // OwnerId defaults to current user on new records
        Id originalOwnerId = ld.OwnerId;

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>{ ld });
        Test.stopTest();

        System.assertEquals(
            originalOwnerId,
            ld.OwnerId,
            'No matching bucket -> OwnerId should remain unchanged'
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 5: Fair rotation across 3 leads with 3 members
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testFairRotation_3Leads3Members() {
        List<User> users = getTestUsers();

        List<Lead__c> leads = new List<Lead__c>();
        for (Integer i = 0; i < 3; i++) {
            leads.add(new Lead__c(
                Last_Name__c     = 'Alpha',
                First_Name__c   = 'Beta',
                Primary_Mobile__c = '800444' + String.valueOf(i).leftPad(4, '0')
            ));
        }

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(leads);
        RoundRobinAssignmentHandler.commitRotationUpdates();
        Test.stopTest();

        // Each of the 3 members should get exactly 1 lead
        Set<Id> assignedOwners = new Set<Id>();
        for (Lead__c ld : leads) {
            assignedOwners.add(ld.OwnerId);
        }
        System.assertEquals(
            3,
            assignedOwners.size(),
            'All 3 members should each get exactly 1 lead'
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 6: Bucket with no active members is skipped
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testNoActiveMembers_Skipped() {
        // Lead matches RR5 (Last_Name=Delta) but RR5 has no members
        Lead__c ld = new Lead__c(
            Last_Name__c     = 'Delta',
            First_Name__c   = 'Epsilon',
            Primary_Mobile__c = '8005550000'
        );
        Id originalOwnerId = ld.OwnerId;

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>{ ld });
        Test.stopTest();

        System.assertEquals(
            originalOwnerId,
            ld.OwnerId,
            'Bucket with no active members should be skipped'
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 7: Rotation tracking – Last_Assigned__c updates persisted
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testRotationTracking_LastAssignedUpdated() {
        List<Lead__c> leads = new List<Lead__c>();
        for (Integer i = 0; i < 3; i++) {
            leads.add(new Lead__c(
                Last_Name__c     = 'Alpha',
                First_Name__c   = 'Beta',
                Primary_Mobile__c = '800666' + String.valueOf(i).leftPad(4, '0')
            ));
        }

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(leads);
        RoundRobinAssignmentHandler.commitRotationUpdates();
        Test.stopTest();

        // Query the RR1 members – at least some should have Last_Assigned__c set
        Round_Robin__c rr1 = [SELECT Id FROM Round_Robin__c
                              WHERE Name = 'RR High Specificity' LIMIT 1];
        List<Round_Robin_Member__c> members = [
            SELECT Id, Last_Assigned__c
            FROM Round_Robin_Member__c
            WHERE Round_Robin__c = :rr1.Id
              AND Assignment_Type__c = :ASSIGN_TYPE
        ];

        Integer updatedCount = 0;
        for (Round_Robin_Member__c m : members) {
            if (m.Last_Assigned__c != null) {
                updatedCount++;
            }
        }
        System.assertEquals(
            3,
            updatedCount,
            'All 3 assigned members should have Last_Assigned__c stamped'
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 8: Rotation continues from last assigned position
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testRotationContinuesFromLastPosition() {
        List<User> users = getTestUsers();

        // Pre-stamp u0 as the last assigned member (most recent)
        Round_Robin__c rr1 = [SELECT Id FROM Round_Robin__c
                              WHERE Name = 'RR High Specificity' LIMIT 1];
        Round_Robin_Member__c firstMember = [
            SELECT Id FROM Round_Robin_Member__c
            WHERE Round_Robin__c = :rr1.Id
              AND User__c = :users[0].Id
              AND Assignment_Type__c = :ASSIGN_TYPE
            LIMIT 1
        ];
        firstMember.Last_Assigned__c = DateTime.now().addMinutes(-5);
        update firstMember;

        // Now assign 1 lead -> should go to u1 (index 1, since u0 was last)
        Lead__c ld = new Lead__c(
            Last_Name__c     = 'Alpha',
            First_Name__c   = 'Beta',
            Primary_Mobile__c = '8007770000'
        );

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>{ ld });
        RoundRobinAssignmentHandler.commitRotationUpdates();
        Test.stopTest();

        System.assertEquals(
            users[1].Id,
            ld.OwnerId,
            'Rotation should continue from u1 since u0 was last assigned'
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 9: Empty lead list handled gracefully
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testEmptyListHandledGracefully() {
        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>());
        RoundRobinAssignmentHandler.assignOwners(null);
        RoundRobinAssignmentHandler.commitRotationUpdates();
        Test.stopTest();
        // No exception = pass
        System.assert(true, 'Empty/null lists handled without exception');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 10: Manual creation by Sales/Pre-Sales user skips RR
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testManualCreation_SalesProfileSkipsRoundRobin() {
        // Simulate a Sales Executive profile by overriding the cached value
        RoundRobinAssignmentHandler.runningUserProfileName = 'Sales Executive';

        Lead__c ld = new Lead__c(
            Last_Name__c      = 'Alpha',
            First_Name__c    = 'Beta',
            Primary_Mobile__c = '8009990000'
        );
        Id originalOwnerId = ld.OwnerId;

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>{ ld });
        Test.stopTest();

        System.assertEquals(
            originalOwnerId,
            ld.OwnerId,
            'Sales user manual creation: OwnerId should NOT be changed by Round Robin'
        );
    }

    @isTest
    static void testManualCreation_PreSalesProfileSkipsRoundRobin() {
        RoundRobinAssignmentHandler.runningUserProfileName = 'Pre-Sales Executive';

        Lead__c ld = new Lead__c(
            Last_Name__c      = 'Alpha',
            First_Name__c    = 'Beta',
            Primary_Mobile__c = '8009990001'
        );
        Id originalOwnerId = ld.OwnerId;

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>{ ld });
        Test.stopTest();

        System.assertEquals(
            originalOwnerId,
            ld.OwnerId,
            'Pre-Sales user manual creation: OwnerId should NOT be changed by Round Robin'
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 11: System/integration user still gets Round Robin
    // ═══════════════════════════════════════════════════════════════════

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 12: Unavailable members still get assigned (fallback)
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testUnavailableMembers_FallbackAssignment() {
        List<User> users = getTestUsers();
        Set<Id> memberUserIds = new Set<Id>();
        for (User u : users) memberUserIds.add(u.Id);

        // Mark ALL test users as not working / not available
        List<User> toUpdate = new List<User>();
        for (User u : users) {
            toUpdate.add(new User(
                Id = u.Id,
                is_working__c = false,
                Availability__c = false
            ));
        }
        update toUpdate;

        // Lead matches RR1 (Last_Name=Alpha, First_Name=Beta)
        Lead__c ld = new Lead__c(
            Last_Name__c      = 'Alpha',
            First_Name__c    = 'Beta',
            Primary_Mobile__c = '8008880000'
        );

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>{ ld });
        RoundRobinAssignmentHandler.commitRotationUpdates();
        Test.stopTest();

        // Even though no members are available, lead should still be assigned
        // to a round robin member — NOT left with admin
        System.assert(
            memberUserIds.contains(ld.OwnerId),
            'Unavailable members fallback: Lead should still be assigned to an RR member, not admin. Got: ' + ld.OwnerId
        );
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEST 13: System/integration user still gets Round Robin
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testSystemCreation_NonSalesProfileRunsRoundRobin() {
        List<User> users = getTestUsers();
        Set<Id> memberUserIds = new Set<Id>();
        for (User u : users) memberUserIds.add(u.Id);

        // Running user has 'Standard User' profile — RR should run
        RoundRobinAssignmentHandler.runningUserProfileName = 'Standard User';

        Lead__c ld = new Lead__c(
            Last_Name__c      = 'Alpha',
            First_Name__c    = 'Beta',
            Primary_Mobile__c = '8009990002'
        );

        Test.startTest();
        RoundRobinAssignmentHandler.assignOwners(new List<Lead__c>{ ld });
        RoundRobinAssignmentHandler.commitRotationUpdates();
        Test.stopTest();

        System.assert(
            memberUserIds.contains(ld.OwnerId),
            'System/integration user: OwnerId should be set by Round Robin. Got: ' + ld.OwnerId
        );
    }
}