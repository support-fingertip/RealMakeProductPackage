@isTest
private class SiteVisitCreationServiceTest {

    @TestSetup
    static void setup() {
        Project__c projA = TestDataFactory.createProject('Project Alpha');
        Project__c projB = TestDataFactory.createProject('Project Beta');

        // Create Round Robin bucket for Project Beta with Sales member
        Round_Robin__c rr = new Round_Robin__c(Is_Active__c = true);
        insert rr;

        Round_Robin_Filter__c filter = new Round_Robin_Filter__c(
            Round_Robin__c = rr.Id,
            Field_API_Name__c = 'Project__c',
            Field_Value__c = projB.Id,
            Field_Priority__c = 1,
            Preference_Order__c = 1
        );
        insert filter;

        Round_Robin_Member__c member = new Round_Robin_Member__c(
            Round_Robin__c = rr.Id,
            User__c = UserInfo.getUserId(),
            Assignment_Type__c = 'Sales',
            Is_Active__c = true,
            Order__c = 1
        );
        insert member;
    }

    @isTest
    static void testSameProjectSiteVisit() {
        Project__c proj = [SELECT Id FROM Project__c WHERE Name = 'Project Alpha' LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'SameProj', '9100000001');

        Test.startTest();
        SiteVisitCreationService.SiteVisitResult result =
            SiteVisitCreationService.createSiteVisit(
                lead.Id, proj.Id, DateTime.now().addDays(1),
                'On Site', 'Digital (Own)', false
            );
        Test.stopTest();

        System.assertNotEquals(null, result.siteVisitId, 'Site Visit should be created');
        System.assertEquals(false, result.isCrossProject, 'Should not be cross-project');
        System.assertEquals(false, result.wasRoundRobinUsed, 'RR should not be used');

        Site_Visit__c sv = [SELECT Lead__c, Project__c, Status__c, Is_Cross_Project__c
                            FROM Site_Visit__c WHERE Id = :result.siteVisitId];
        System.assertEquals(lead.Id, sv.Lead__c);
        System.assertEquals(proj.Id, sv.Project__c);
        System.assertEquals('Scheduled', sv.Status__c);
        System.assertEquals(false, sv.Is_Cross_Project__c);
    }

    @isTest
    static void testCrossProjectSiteVisit_OwnerInPool() {
        Project__c projA = [SELECT Id FROM Project__c WHERE Name = 'Project Alpha' LIMIT 1];
        Project__c projB = [SELECT Id FROM Project__c WHERE Name = 'Project Beta' LIMIT 1];

        // Lead on Project Alpha, owner is running user who IS in Project Beta's RR pool
        Lead__c lead = TestDataFactory.createLead(projA.Id, 'CrossInPool', '9100000002');

        Test.startTest();
        SiteVisitCreationService.SiteVisitResult result =
            SiteVisitCreationService.createSiteVisit(
                lead.Id, projB.Id, DateTime.now().addDays(1),
                'On Site', 'Digital (Own)', false
            );
        Test.stopTest();

        System.assertNotEquals(null, result.siteVisitId);
        System.assertEquals(true, result.isCrossProject);
        // Owner is in pool, so RR should NOT be used
        System.assertEquals(false, result.wasRoundRobinUsed);
        System.assertEquals(UserInfo.getUserId(), result.assignedToUserId);
    }

    @isTest
    static void testCrossProjectSiteVisit_OwnerNotInPool() {
        Project__c projA = [SELECT Id FROM Project__c WHERE Name = 'Project Alpha' LIMIT 1];

        // Create a third project with no RR pool for the lead owner
        Project__c projC = TestDataFactory.createProject('Project Charlie');

        Lead__c lead = TestDataFactory.createLead(projA.Id, 'CrossNoPool', '9100000003');

        Test.startTest();
        SiteVisitCreationService.SiteVisitResult result =
            SiteVisitCreationService.createSiteVisit(
                lead.Id, projC.Id, DateTime.now().addDays(1),
                'Virtual', 'Channel Partner', false
            );
        Test.stopTest();

        // No RR pool for Project Charlie, so RR returns null and falls back to lead owner
        System.assertNotEquals(null, result.siteVisitId);
        System.assertEquals(true, result.isCrossProject);

        Site_Visit__c sv = [SELECT Is_Cross_Project__c, Mode_Of_Visit__c, Source_Type__c
                            FROM Site_Visit__c WHERE Id = :result.siteVisitId];
        System.assertEquals(true, sv.Is_Cross_Project__c);
        System.assertEquals('Virtual', sv.Mode_Of_Visit__c);
        System.assertEquals('Channel Partner', sv.Source_Type__c);
    }

    @isTest
    static void testIsUserInProjectRRPool() {
        Project__c projB = [SELECT Id FROM Project__c WHERE Name = 'Project Beta' LIMIT 1];
        Project__c projA = [SELECT Id FROM Project__c WHERE Name = 'Project Alpha' LIMIT 1];

        Test.startTest();
        Boolean inPool = SiteVisitCreationService.isUserInProjectRRPool(
            UserInfo.getUserId(), projB.Id
        );
        Boolean notInPool = SiteVisitCreationService.isUserInProjectRRPool(
            UserInfo.getUserId(), projA.Id
        );
        Test.stopTest();

        System.assertEquals(true, inPool, 'User should be in Project Beta RR pool');
        System.assertEquals(false, notInPool, 'User should NOT be in Project Alpha RR pool');
    }

    @isTest
    static void testCreateSiteVisitValidation() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            SiteVisitCreationService.createSiteVisit(null, null, null, null, null, false);
        } catch (SiteVisitCreationService.SiteVisitCreationException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw exception for null params');
    }
}