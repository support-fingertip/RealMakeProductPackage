/**
 * @description Test class for BulkLeadReassignmentService and BulkLeadReassignmentController.
 * Covers: search with filters, mobile search (Lead + Enquiry), bucket transitions,
 * bulk reassignment with partial success, edge cases.
 */
@isTest
private class BulkLeadReassignmentServiceTest {

    // ═══════════════════════════════════════════════════════════════════
    //  TEST DATA SETUP
    // ═══════════════════════════════════════════════════════════════════

    @TestSetup
    static void setupData() {
        Project__c proj = TestDataFactory.createProject('Test Project Alpha');

        // Create Pre-Sales leads
        Lead__c lead1 = TestDataFactory.createLead(proj.Id, 'Alice', '9000000001');
        Lead__c lead2 = TestDataFactory.createLead(proj.Id, 'Bob', '9000000002');
        Lead__c lead3 = TestDataFactory.createLead(proj.Id, 'Charlie', '9000000003');

        // Create a Sales lead (change record type)
        Lead__c lead4 = TestDataFactory.createLead(proj.Id, 'Diana', '9000000004');
        Id salesRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
            .get('Sales').getRecordTypeId();
        lead4.RecordTypeId = salesRTId;
        lead4.Lead_Status__c = 'Site Visit Scheduled';
        update lead4;

        // Create Enquiry_Source__c with a different mobile pointing to lead1
        Enquiry_Source__c es = new Enquiry_Source__c();
        es.Lead__c = lead1.Id;
        es.Enquiry_Date__c = DateTime.now();
        es.Enquiry_Type__c = 'New';
        es.Source__c = 'Digital';
        es.Primary_Mobile__c = '9000099999';
        insert es;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SEARCH TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testSearchByProject() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                null, 'Test Project Alpha', null, null, null, null, null, null
            );
        Test.stopTest();

        System.assert(results.size() >= 4, 'Should find leads for project');
    }

    @isTest
    static void testSearchByOwner() {
        Id currentUser = UserInfo.getUserId();
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                currentUser, null, null, null, null, null, null, null
            );
        Test.stopTest();

        System.assert(results.size() >= 4, 'Should find leads owned by current user');
    }

    @isTest
    static void testSearchByLeadStatus() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                null, null, null, 'New Enquiry', null, null, null, null
            );
        Test.stopTest();

        System.assert(results.size() >= 3, 'Should find New Enquiry leads');
    }

    @isTest
    static void testSearchByBucket() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                null, null, null, null, null, null, null, 'Pre Sales'
            );
        Test.stopTest();

        System.assert(results.size() >= 3, 'Should find Pre Sales leads');
    }

    @isTest
    static void testSearchByLeadId() {
        Lead__c lead = [SELECT Id, Name FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                null, null, null, null, null, lead.Name, null, null
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should find exactly one lead by Name');
        System.assertEquals(lead.Id, results[0].leadId, 'Lead ID should match');
        System.assertEquals(lead.Name, results[0].leadIdName, 'Lead ID Name should match');
    }

    @isTest
    static void testSearchBySource() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                null, null, null, null, 'Digital', null, null, null
            );
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should find Digital source leads');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  MOBILE SEARCH TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testMobileSearchDirectMatch() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                null, null, null, null, null, null, '9000000001', null
            );
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should find lead by primary mobile');
    }

    @isTest
    static void testMobileSearchViaEnquiry() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                null, null, null, null, null, null, '9000099999', null
            );
        Test.stopTest();

        // Should find Alice's lead via the Enquiry_Source__c mobile match
        System.assert(results.size() >= 1, 'Should find lead via enquiry source mobile');
        System.assertEquals('Alice', results[0].leadName.split(' ')[0], 'Should be Alice');
    }

    @isTest
    static void testMobileSearchNoMatch() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                null, null, null, null, null, null, '0000000000', null
            );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should find no leads for unknown mobile');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  NO FILTER VALIDATION
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testSearchNoFilterThrowsError() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BulkLeadReassignmentController.searchLeads(
                null, null, null, null, null, null, null, null
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
           
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception when no filters applied');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  REASSIGNMENT TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testReassignPreSalesToPreSales() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id },
                currentUser,
                'Pre Sales',
                false
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should succeed');
        System.assertEquals(0, result.failureCount, 'No failures expected');
    }

    @isTest
    static void testReassignPreSalesToSales() {
        Lead__c lead = [SELECT Id, OwnerId FROM Lead__c WHERE First_Name__c = 'Bob' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id },
                currentUser,
                'Sales',
                false
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Pre Sales → Sales should succeed');

        // Verify record type changed
        Lead__c updated = [SELECT RecordType.DeveloperName, Pre_Sale_User__c FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Sales', updated.RecordType.DeveloperName, 'Record type should be Sales');
        System.assertNotEquals(null, updated.Pre_Sale_User__c, 'Pre_Sale_User__c should be set');
    }

    @isTest
    static void testReassignSalesToPreSalesAllowed() {
        Lead__c lead = [SELECT Id, OwnerId FROM Lead__c WHERE First_Name__c = 'Diana' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id },
                currentUser,
                'Pre Sales',
                false
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Sales → Pre Sales should succeed');
        System.assertEquals(0, result.failureCount, 'No failures expected');

        // Verify record type changed and fields reset
        Lead__c updated = [SELECT RecordType.DeveloperName, Pre_Sale_User__c, Transferred_On__c, Lead_Status__c
                           FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Pre_Sales', updated.RecordType.DeveloperName, 'Record type should be Pre_Sales');
        System.assertEquals(null, updated.Pre_Sale_User__c, 'Pre_Sale_User__c should be cleared');
        System.assertEquals(null, updated.Transferred_On__c, 'Transferred_On__c should be cleared');
        System.assertEquals('New Enquiry', updated.Lead_Status__c, 'Lead status should reset to New Enquiry');
    }

    @isTest
    static void testReassignSalesToSalesAllowed() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Diana' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id },
                currentUser,
                'Sales',
                false
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Sales → Sales should succeed');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BULK & MIXED BUCKET TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testBulkMixedBucketReassignment() {
        Lead__c preSalesLead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Lead__c salesLead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Diana' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ preSalesLead.Id, salesLead.Id },
                currentUser,
                'Sales',
                true
            );
        Test.stopTest();

        // Pre Sales → Sales: allowed; Sales → Sales: allowed
        System.assertEquals(2, result.successCount, 'Both should succeed to Sales');
        System.assertEquals(0, result.failureCount, 'No failures');
    }

    @isTest
    static void testBulkMixedBucketAllToPreSales() {
        Lead__c preSalesLead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Lead__c salesLead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Diana' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        // Target Pre Sales: Pre Sales → Pre Sales OK, Sales → Pre Sales OK
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ preSalesLead.Id, salesLead.Id },
                currentUser,
                'Pre Sales',
                false
            );
        Test.stopTest();

        System.assertEquals(2, result.successCount, 'Both should succeed to Pre Sales');
        System.assertEquals(0, result.failureCount, 'No failures');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testReassignNoLeadsSelected() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>(),
                UserInfo.getUserId(),
                'Pre Sales',
                false
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw when no leads selected');
    }

    @isTest
    static void testReassignNoTargetUser() {
        Boolean exceptionThrown = false;
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        try {
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id },
                null,
                'Pre Sales',
                false
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw when no target user');
    }

    @isTest
    static void testReassignNoBucket() {
        Boolean exceptionThrown = false;
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        try {
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id },
                UserInfo.getUserId(),
                '',
                false
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw when no bucket selected');
    }

    @isTest
    static void testReassignInvalidBucket() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id },
                UserInfo.getUserId(),
                'Invalid Bucket',
                false
            );
        Test.stopTest();

        System.assertEquals(1, result.failureCount, 'Should fail with invalid bucket');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ACTIVE USER SEARCH TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testSearchActiveUsers() {
        Test.startTest();
        List<User> users = BulkLeadReassignmentController.searchActiveUsers('Test');
        Test.stopTest();

        // At least the running user should be active
        System.assert(users != null, 'Should return a list');
    }

    @isTest
    static void testSearchActiveUsersTooShort() {
        Test.startTest();
        List<User> users = BulkLeadReassignmentController.searchActiveUsers('A');
        Test.stopTest();

        System.assertEquals(0, users.size(), 'Should return empty for short search');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TRANSITION VALIDATOR TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testTransitionValidatorAllowed() {
        System.assert(BulkLeadReassignmentService.isTransitionAllowed('Pre_Sales', 'Pre_Sales'), 'Pre_Sales → Pre_Sales allowed');
        System.assert(BulkLeadReassignmentService.isTransitionAllowed('Pre_Sales', 'Sales'), 'Pre_Sales → Sales allowed');
        System.assert(BulkLeadReassignmentService.isTransitionAllowed('Sales', 'Sales'), 'Sales → Sales allowed');
        System.assert(BulkLeadReassignmentService.isTransitionAllowed('Sales', 'Pre_Sales'), 'Sales → Pre_Sales allowed');
    }

    @isTest
    static void testTransitionValidatorChannelPartner() {
        System.assert(BulkLeadReassignmentService.isTransitionAllowed('Channel_Partner', 'Channel_Partner'),
            'Channel_Partner → Channel_Partner allowed (same-to-same)');
        System.assert(!BulkLeadReassignmentService.isTransitionAllowed('Channel_Partner', 'Sales'),
            'Channel_Partner → Sales blocked');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SUPPRESS NOTIFICATIONS TEST
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testReassignWithSuppressedNotifications() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Charlie' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id },
                currentUser,
                'Pre Sales',
                true
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should succeed with notifications suppressed');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ROUND ROBIN REASSIGNMENT TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testRoundRobinBasicDistribution() {
        // 3 Pre-Sales leads distributed across 2 users (current user used for both slots as test only has 1 user)
        Lead__c lead1 = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Lead__c lead2 = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Bob' LIMIT 1];
        Lead__c lead3 = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Charlie' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ lead1.Id, lead2.Id, lead3.Id },
                new List<Id>{ currentUser },
                'Pre Sales',
                false
            );
        Test.stopTest();

        System.assertEquals(3, result.successCount, 'All 3 leads should succeed');
        System.assertEquals(0, result.failureCount, 'No failures expected');

        // Verify all leads assigned to the only user
        for (Lead__c l : [SELECT OwnerId FROM Lead__c WHERE Id IN (:lead1.Id, :lead2.Id, :lead3.Id)]) {
            System.assertEquals(currentUser, l.OwnerId, 'All leads should be assigned to the user');
        }
    }

    @isTest
    static void testRoundRobinPreSalesToSalesTransition() {
        Lead__c lead1 = [SELECT Id, OwnerId FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Lead__c lead2 = [SELECT Id, OwnerId FROM Lead__c WHERE First_Name__c = 'Bob' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ lead1.Id, lead2.Id },
                new List<Id>{ currentUser },
                'Sales',
                false
            );
        Test.stopTest();

        System.assertEquals(2, result.successCount, 'Both Pre Sales → Sales should succeed');

        // Verify record type changed and Pre_Sale_User__c set
        for (Lead__c l : [SELECT RecordType.DeveloperName, Pre_Sale_User__c FROM Lead__c WHERE Id IN (:lead1.Id, :lead2.Id)]) {
            System.assertEquals('Sales', l.RecordType.DeveloperName, 'Record type should be Sales');
            System.assertNotEquals(null, l.Pre_Sale_User__c, 'Pre_Sale_User__c should be set');
        }
    }

    @isTest
    static void testRoundRobinSalesToPreSalesTransition() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Diana' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ lead.Id },
                new List<Id>{ currentUser },
                'Pre Sales',
                false
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Sales → Pre Sales should succeed');

        Lead__c updated = [SELECT RecordType.DeveloperName, Lead_Status__c, Pre_Sale_User__c
                           FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Pre_Sales', updated.RecordType.DeveloperName, 'Should be Pre_Sales');
        System.assertEquals('New Enquiry', updated.Lead_Status__c, 'Status should reset');
        System.assertEquals(null, updated.Pre_Sale_User__c, 'Pre_Sale_User__c should be cleared');
    }

    @isTest
    static void testRoundRobinNoUsersThrowsError() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ lead.Id },
                new List<Id>(),
                'Pre Sales',
                false
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw when no target users');
    }

    @isTest
    static void testRoundRobinNoLeadsThrowsError() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>(),
                new List<Id>{ UserInfo.getUserId() },
                'Pre Sales',
                false
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw when no leads selected');
    }

    @isTest
    static void testRoundRobinNoBucketThrowsError() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ lead.Id },
                new List<Id>{ UserInfo.getUserId() },
                '',
                false
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw when no bucket selected');
    }

    @isTest
    static void testRoundRobinMixedBuckets() {
        // Pre Sales lead + Sales lead → target Sales bucket
        Lead__c preSalesLead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Lead__c salesLead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Diana' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ preSalesLead.Id, salesLead.Id },
                new List<Id>{ currentUser },
                'Sales',
                true
            );
        Test.stopTest();

        System.assertEquals(2, result.successCount, 'Both should succeed');
        System.assertEquals(0, result.failureCount, 'No failures');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  COMBINED FILTERS TEST
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testSearchWithMultipleFilters() {
        Id currentUser = UserInfo.getUserId();
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                currentUser, 'Test Project Alpha', null, 'New Enquiry', 'Digital', null, null, 'Pre Sales'
            );
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should find leads matching all filters');
    }

    @isTest
    static void testMobileSearchWithAdditionalFilters() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentController.searchLeads(
                null, 'Test Project Alpha', null, null, null, null, '9000000001', 'Pre Sales'
            );
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should find lead with mobile + project + bucket filter');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HELPERS FOR ADDITIONAL COVERAGE
    // ═══════════════════════════════════════════════════════════════════

    private static User newActiveUser(String suffix) {
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        User u;
        System.runAs(currentUser) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            u = new User(
                Alias = 'tst' + suffix.left(2),
                Email = 'tst' + suffix + '@blrtest.invalid',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Tst' + suffix,
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = p.Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                Username = 'tst' + suffix + DateTime.now().getTime()
                    + Math.mod(Math.abs(Crypto.getRandomInteger()), 10000) + '@blrtest.invalid'
            );
            insert u;
        }
        return u;
    }

    private static Id deletedLeadId() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c temp = TestDataFactory.createLead(proj.Id, 'DelMe', '9100099100');
        Id tempId = temp.Id;
        delete temp;
        return tempId;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ADDITIONAL SEARCH COVERAGE
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testSearchByProjectId() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentService.searchLeads(
                null, null, proj.Id, null, null, null, null, null
            );
        Test.stopTest();
        System.assert(results.size() >= 3, 'Should find project leads via projectId');
    }

    @isTest
    static void testMobileSearchByProjectId() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentService.searchLeads(
                null, null, proj.Id, null, null, null, '9000000001', null
            );
        Test.stopTest();
        System.assert(results.size() >= 1, 'Should find lead via mobile + projectId');
    }

    @isTest
    static void testMobileSearchWithAllExtraFilters() {
        Id currentUser = UserInfo.getUserId();
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> results =
            BulkLeadReassignmentService.searchLeads(
                currentUser, 'Test Project Alpha', null, 'New Enquiry', 'Digital',
                null, '9000099999', 'Pre Sales'
            );
        Test.stopTest();
        // Enquiry mobile maps to Alice — filters should still match
        System.assert(results.size() >= 1, 'Enquiry mobile match should honor additional filters');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ADDITIONAL REASSIGN COVERAGE
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testReassignToInactiveUser() {
        User u = newActiveUser('Inact');
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.runAs(currentUser) {
            u.IsActive = false;
            update u;
        }
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.reassignLeads(
                new List<Id>{ lead.Id }, u.Id, 'Pre Sales', false
            );
        Test.stopTest();

        System.assertEquals(1, result.failureCount, 'Inactive user should fail');
        System.assertEquals(0, result.successCount, 'Nothing should succeed');
    }

    @isTest
    static void testReassignLeadNotFound() {
        Id missing = deletedLeadId();
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.reassignLeads(
                new List<Id>{ missing }, UserInfo.getUserId(), 'Pre Sales', false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount, 'Missing lead should fail');
    }

    @isTest
    static void testReassignChannelPartnerBlocked() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c cpLead = TestDataFactory.createLead(proj.Id, 'Eve', '9000000099');
        Id cpRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
            .get('Channel_Partner').getRecordTypeId();
        cpLead.RecordTypeId = cpRTId;
        update cpLead;

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.reassignLeads(
                new List<Id>{ cpLead.Id }, UserInfo.getUserId(), 'Sales', false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount,
            'Channel_Partner → Sales should be blocked');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ADDITIONAL ROUND ROBIN COVERAGE
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testRoundRobinAllInactiveUsers() {
        User u = newActiveUser('RRina');
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.runAs(currentUser) {
            u.IsActive = false;
            update u;
        }
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.reassignLeadsRoundRobin(
                new List<Id>{ lead.Id }, new List<Id>{ u.Id }, 'Pre Sales', false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount, 'All-inactive should fail entire batch');
    }

    @isTest
    static void testRoundRobinInvalidBucket() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.reassignLeadsRoundRobin(
                new List<Id>{ lead.Id },
                new List<Id>{ UserInfo.getUserId() },
                'Bogus Bucket',
                false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount, 'Invalid bucket should fail entire batch');
    }

    @isTest
    static void testRoundRobinLeadNotFound() {
        Id missing = deletedLeadId();
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.reassignLeadsRoundRobin(
                new List<Id>{ missing },
                new List<Id>{ UserInfo.getUserId() },
                'Pre Sales',
                false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount, 'Missing lead should fail');
    }

    @isTest
    static void testRoundRobinTransitionBlocked() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c cpLead = TestDataFactory.createLead(proj.Id, 'Frank', '9000000077');
        Id cpRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
            .get('Channel_Partner').getRecordTypeId();
        cpLead.RecordTypeId = cpRTId;
        update cpLead;

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.reassignLeadsRoundRobin(
                new List<Id>{ cpLead.Id },
                new List<Id>{ UserInfo.getUserId() },
                'Sales',
                false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount,
            'Channel_Partner → Sales should be blocked via round robin');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEMP ASSIGN TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testTempAssignSuccess() {
        User tempOwner = newActiveUser('TA1');
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id }, tempOwner.Id,
                Date.today(), Date.today().addDays(7),
                'Out of office', 'Edit', true, true
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Temp assignment should succeed');
        Lead__c updated = [SELECT Temp_Owner__c, Temp_Start__c, Temp_Expiry__c
                           FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals(tempOwner.Id, updated.Temp_Owner__c);
        System.assertEquals(Date.today(), updated.Temp_Start__c);
        System.assertEquals(Date.today().addDays(7), updated.Temp_Expiry__c);
    }

    @isTest
    static void testTempAssignBackwardCompatOverload() {
        User tempOwner = newActiveUser('TA2');
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Bob' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id }, tempOwner.Id,
                Date.today(), Date.today().addDays(3),
                'Short-form overload'
            );
        Test.stopTest();
        System.assertEquals(1, result.successCount, 'Backward-compat overload should succeed');
    }

    @isTest
    static void testTempAssignAccessLevelRead() {
        User tempOwner = newActiveUser('TA3');
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Charlie' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id }, tempOwner.Id,
                Date.today(), Date.today().addDays(5),
                'Read access', 'Read', false, false
            );
        Test.stopTest();
        System.assertEquals(1, result.successCount, 'Read access level should succeed');
    }

    @isTest
    static void testTempAssignInactiveOwner() {
        User tempOwner = newActiveUser('TA4');
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.runAs(currentUser) {
            tempOwner.IsActive = false;
            update tempOwner;
        }
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id }, tempOwner.Id,
                Date.today(), Date.today().addDays(1),
                'test', 'Edit', false, false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount,
            'Inactive temp owner should fail whole batch');
    }

    @isTest
    static void testTempAssignNullStartDate() {
        User tempOwner = newActiveUser('TA5');
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id }, tempOwner.Id,
                null, Date.today().addDays(1), 'x', 'Edit', false, false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount, 'Null start date should fail batch');
    }

    @isTest
    static void testTempAssignNullEndDate() {
        User tempOwner = newActiveUser('TA6');
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id }, tempOwner.Id,
                Date.today(), null, 'x', 'Edit', false, false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount, 'Null end date should fail batch');
    }

    @isTest
    static void testTempAssignEndBeforeStart() {
        User tempOwner = newActiveUser('TA7');
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id }, tempOwner.Id,
                Date.today(), Date.today().addDays(-1), 'x', 'Edit', false, false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount,
            'End-before-start should fail batch');
    }

    @isTest
    static void testTempAssignLeadNotFound() {
        User tempOwner = newActiveUser('TA8');
        Id missing = deletedLeadId();
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ missing }, tempOwner.Id,
                Date.today(), Date.today().addDays(1),
                'x', 'Edit', false, false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount, 'Missing lead should fail');
    }

    @isTest
    static void testTempAssignAlreadyHasTempOwner() {
        User tempOwner = newActiveUser('TA9');
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        // First assignment succeeds
        BulkLeadReassignmentService.tempAssignLeads(
            new List<Id>{ lead.Id }, tempOwner.Id,
            Date.today(), Date.today().addDays(2),
            'first', 'Edit', false, false
        );
        // Second attempt should fail
        User tempOwner2 = newActiveUser('TAA');
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id }, tempOwner2.Id,
                Date.today(), Date.today().addDays(3),
                'second', 'Edit', false, false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount,
            'Second temp assignment should be blocked');
    }

    @isTest
    static void testTempAssignSameOwnerBlocked() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id }, UserInfo.getUserId(),
                Date.today(), Date.today().addDays(1),
                'self', 'Edit', false, false
            );
        Test.stopTest();
        System.assertEquals(1, result.failureCount,
            'Temp owner == current owner should be blocked');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  REVOKE TEMP ASSIGN TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testRevokeSuccess() {
        User tempOwner = newActiveUser('RV1');
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        BulkLeadReassignmentService.tempAssignLeads(
            new List<Id>{ lead.Id }, tempOwner.Id,
            Date.today(), Date.today().addDays(3),
            'to-be-revoked', 'Edit', true, true
        );

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.revokeTempAssignment(new List<Id>{ lead.Id });
        Test.stopTest();
        System.assertEquals(1, result.successCount, 'Revoke should succeed');
        Lead__c updated = [SELECT Temp_Owner__c, Temp_Start__c, Temp_Expiry__c
                           FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals(null, updated.Temp_Owner__c, 'Temp_Owner cleared');
        System.assertEquals(null, updated.Temp_Start__c, 'Temp_Start cleared');
        System.assertEquals(null, updated.Temp_Expiry__c, 'Temp_Expiry cleared');
    }

    @isTest
    static void testRevokeLeadNotFound() {
        Id missing = deletedLeadId();
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.revokeTempAssignment(new List<Id>{ missing });
        Test.stopTest();
        System.assertEquals(1, result.failureCount, 'Missing lead should fail');
    }

    @isTest
    static void testRevokeLeadNoTempOwner() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.revokeTempAssignment(new List<Id>{ lead.Id });
        Test.stopTest();
        System.assertEquals(1, result.failureCount,
            'Revoking non-temp lead should fail');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SEARCH TEMP SHARED RECORDS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testSearchTempSharedRecordsEmpty() {
        Test.startTest();
        List<BulkLeadReassignmentService.TempShareRow> rows =
            BulkLeadReassignmentService.searchTempSharedRecords(UserInfo.getUserId());
        Test.stopTest();
        System.assertNotEquals(null, rows, 'Should return a list (possibly empty)');
    }

    @isTest
    static void testSearchTempSharedRecordsAfterAssign() {
        User tempOwner = newActiveUser('STS');
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        BulkLeadReassignmentService.tempAssignLeads(
            new List<Id>{ lead.Id }, tempOwner.Id,
            Date.today(), Date.today().addDays(4),
            'share-search', 'Read', true, false
        );

        Test.startTest();
        List<BulkLeadReassignmentService.TempShareRow> rows =
            BulkLeadReassignmentService.searchTempSharedRecords(tempOwner.Id);
        Test.stopTest();
        System.assert(rows.size() >= 1, 'Should find the temp assignment');
        BulkLeadReassignmentService.TempShareRow row = rows[0];
        System.assertEquals(lead.Id, row.leadId, 'Row should map to the lead');
        System.assertNotEquals(null, row.leadUrl, 'leadUrl should be populated');
        System.assertEquals('Active', row.status, 'Should be Active');
        System.assertEquals('Read', row.accessLevel, 'Access level should be Read');
    }
}