/**
 * @description Test class for BulkLeadReassignmentController.
 * Targets 100% code coverage by exercising every validation branch
 * (AuraHandledException paths) and every delegation path through the
 * controller. Business-logic assertions live in
 * BulkLeadReassignmentServiceTest and UnitBlockingServiceTest; this class
 * focuses on the controller layer.
 */
@isTest
private class BulkLeadReassignmentControllerTest {

    // ═══════════════════════════════════════════════════════════════════
    //  TEST DATA SETUP
    // ═══════════════════════════════════════════════════════════════════

    @TestSetup
    static void setupData() {
        Project__c proj = TestDataFactory.createProject('Controller Test Project');
        Tower__c tower = TestDataFactory.createTower(proj.Id, 'CT-1');
        TestDataFactory.createUnit(proj.Id, tower.Id, 'C-101');
        TestDataFactory.createUnit(proj.Id, tower.Id, 'C-102');
        TestDataFactory.createUnit(proj.Id, tower.Id, 'C-103');

        TestDataFactory.createLead(proj.Id, 'Alice',   '9100000001');
        TestDataFactory.createLead(proj.Id, 'Bob',     '9100000002');
        TestDataFactory.createLead(proj.Id, 'Charlie', '9100000003');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HELPERS
    // ═══════════════════════════════════════════════════════════════════

    private static Project__c getProject() {
        return [SELECT Id, Name FROM Project__c LIMIT 1];
    }

    private static List<Lead__c> getLeads() {
        return [SELECT Id, Name, First_Name__c FROM Lead__c ORDER BY First_Name__c];
    }

    private static List<Unit__c> getUnits() {
        return [SELECT Id, Unit_Number__c, Status__c FROM Unit__c ORDER BY Unit_Number__c];
    }

    // ═══════════════════════════════════════════════════════════════════
    //  searchLeads
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void searchLeads_noFilters_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            BulkLeadReassignmentController.searchLeads(
                null, null, null, null, null, null, null, null
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Should throw when no filters supplied');
    }

    @isTest
    static void searchLeads_withFilter_returnsRows() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> rows =
            BulkLeadReassignmentController.searchLeads(
                UserInfo.getUserId(), null, null, null, null, null, null, null
            );
        Test.stopTest();
        System.assertNotEquals(null, rows, 'Should return a list');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  reassignLeads
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void reassignLeads_emptyLeads_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>(), UserInfo.getUserId(), 'Pre Sales', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Empty lead list should throw');
    }

    @isTest
    static void reassignLeads_nullLeads_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.reassignLeads(
                null, UserInfo.getUserId(), 'Pre Sales', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null lead list should throw');
    }

    @isTest
    static void reassignLeads_nullTargetUser_throws() {
        Lead__c lead = getLeads()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id }, null, 'Pre Sales', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null target user should throw');
    }

    @isTest
    static void reassignLeads_blankBucket_throws() {
        Lead__c lead = getLeads()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id }, UserInfo.getUserId(), '', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Blank bucket should throw');
    }

    @isTest
    static void reassignLeads_success_delegates() {
        Lead__c lead = getLeads()[0];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeads(
                new List<Id>{ lead.Id }, UserInfo.getUserId(), 'Pre Sales', true
            );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return a result object');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  reassignLeadsRoundRobin
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void reassignLeadsRoundRobin_emptyLeads_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>(), new List<Id>{ UserInfo.getUserId() }, 'Pre Sales', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Empty lead list should throw');
    }

    @isTest
    static void reassignLeadsRoundRobin_nullUsers_throws() {
        Lead__c lead = getLeads()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ lead.Id }, null, 'Pre Sales', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null users should throw');
    }

    @isTest
    static void reassignLeadsRoundRobin_emptyUsers_throws() {
        Lead__c lead = getLeads()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ lead.Id }, new List<Id>(), 'Pre Sales', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Empty users should throw');
    }

    @isTest
    static void reassignLeadsRoundRobin_blankBucket_throws() {
        Lead__c lead = getLeads()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ lead.Id }, new List<Id>{ UserInfo.getUserId() }, '', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Blank bucket should throw');
    }

    @isTest
    static void reassignLeadsRoundRobin_success_delegates() {
        Lead__c lead = getLeads()[0];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.reassignLeadsRoundRobin(
                new List<Id>{ lead.Id },
                new List<Id>{ UserInfo.getUserId() },
                'Pre Sales',
                true
            );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return a result object');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  searchActiveUsers
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void searchActiveUsers_blank_returnsEmpty() {
        List<User> users = BulkLeadReassignmentController.searchActiveUsers('');
        System.assertEquals(0, users.size(), 'Blank term returns empty');
    }

    @isTest
    static void searchActiveUsers_null_returnsEmpty() {
        List<User> users = BulkLeadReassignmentController.searchActiveUsers(null);
        System.assertEquals(0, users.size(), 'Null term returns empty');
    }

    @isTest
    static void searchActiveUsers_shortTerm_returnsEmpty() {
        List<User> users = BulkLeadReassignmentController.searchActiveUsers('a');
        System.assertEquals(0, users.size(), 'Single-char term returns empty');
    }

    @isTest
    static void searchActiveUsers_longTerm_delegates() {
        Test.startTest();
        List<User> users = BulkLeadReassignmentController.searchActiveUsers('Test');
        Test.stopTest();
        System.assertNotEquals(null, users, 'Should return a list');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  tempAssignLeads
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void tempAssignLeads_emptyLeads_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>(), UserInfo.getUserId(),
                Date.today(), Date.today().addDays(7),
                'Vacation', 'Edit', true, true
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Empty lead list should throw');
    }

    @isTest
    static void tempAssignLeads_nullOwner_throws() {
        Lead__c lead = getLeads()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>{ lead.Id }, null,
                Date.today(), Date.today().addDays(7),
                'Vacation', 'Edit', true, true
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null temp owner should throw');
    }

    @isTest
    static void tempAssignLeads_nullStartDate_throws() {
        Lead__c lead = getLeads()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>{ lead.Id }, UserInfo.getUserId(),
                null, Date.today().addDays(7),
                'Vacation', 'Edit', true, true
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null start date should throw');
    }

    @isTest
    static void tempAssignLeads_nullEndDate_throws() {
        Lead__c lead = getLeads()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>{ lead.Id }, UserInfo.getUserId(),
                Date.today(), null,
                'Vacation', 'Edit', true, true
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null end date should throw');
    }

    @isTest
    static void tempAssignLeads_success_delegates() {
        Lead__c lead = getLeads()[0];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>{ lead.Id }, UserInfo.getUserId(),
                Date.today(), Date.today().addDays(7),
                'Vacation', 'Read', true, true
            );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return a result');
    }

    @isTest
    static void tempAssignLeads_nullDefaults_delegates() {
        // Exercises the "!= null ? leadAccessLevel : 'Edit'" and
        // "shareFollowups == true" / "shareSiteVisits == true" branches
        Lead__c lead = getLeads()[0];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>{ lead.Id }, UserInfo.getUserId(),
                Date.today(), Date.today().addDays(7),
                'Sick Leave', null, null, null
            );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return a result');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  revokeTempAssignment
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void revokeTempAssignment_empty_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.revokeTempAssignment(new List<Id>());
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Empty list should throw');
    }

    @isTest
    static void revokeTempAssignment_null_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.revokeTempAssignment(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null list should throw');
    }

    @isTest
    static void revokeTempAssignment_success_delegates() {
        Lead__c lead = getLeads()[0];
        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.revokeTempAssignment(
                new List<Id>{ lead.Id }
            );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return a result');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  searchTempSharedRecords
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void searchTempSharedRecords_null_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.searchTempSharedRecords(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null temp owner should throw');
    }

    @isTest
    static void searchTempSharedRecords_success_delegates() {
        Test.startTest();
        List<BulkLeadReassignmentService.TempShareRow> rows =
            BulkLeadReassignmentController.searchTempSharedRecords(UserInfo.getUserId());
        Test.stopTest();
        System.assertNotEquals(null, rows, 'Should return a list (possibly empty)');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  searchUnits
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void searchUnits_noFilters_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.searchUnits(null, null, null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'No project and no unit number should throw');
    }

    @isTest
    static void searchUnits_blankUnitNumberNoProject_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.searchUnits(null, 'Available', '');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Blank unit number and null project should throw');
    }

    @isTest
    static void searchUnits_withProject_delegates() {
        Project__c proj = getProject();
        Test.startTest();
        List<UnitBlockingService.UnitRow> rows =
            BulkLeadReassignmentController.searchUnits(proj.Id, null, null);
        Test.stopTest();
        System.assertNotEquals(null, rows, 'Should return list');
    }

    @isTest
    static void searchUnits_withUnitNumber_delegates() {
        Test.startTest();
        List<UnitBlockingService.UnitRow> rows =
            BulkLeadReassignmentController.searchUnits(null, null, 'C-101');
        Test.stopTest();
        System.assertNotEquals(null, rows, 'Should return list');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  blockUnits
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void blockUnits_emptyUnits_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.blockUnits(
                new List<Id>(), 3, 'Reason', false, null, null
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Empty unit list should throw');
    }

    @isTest
    static void blockUnits_nullUnits_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.blockUnits(
                null, 3, 'Reason', false, null, null
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null unit list should throw');
    }

    @isTest
    static void blockUnits_blankReason_throws() {
        Unit__c unit = getUnits()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.blockUnits(
                new List<Id>{ unit.Id }, 3, '', false, null, null
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Blank reason should throw');
    }

    @isTest
    static void blockUnits_nullDaysNonManagement_throws() {
        Unit__c unit = getUnits()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.blockUnits(
                new List<Id>{ unit.Id }, null, 'Reason', false, null, null
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null days for non-management block should throw');
    }

    @isTest
    static void blockUnits_zeroDaysNonManagement_throws() {
        Unit__c unit = getUnits()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.blockUnits(
                new List<Id>{ unit.Id }, 0, 'Reason', false, null, null
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Zero days for non-management block should throw');
    }

    @isTest
    static void blockUnits_managementNullDays_delegates() {
        Unit__c unit = getUnits()[0];
        Test.startTest();
        UnitBlockingService.BlockResult result =
            BulkLeadReassignmentController.blockUnits(
                new List<Id>{ unit.Id }, null, 'Management hold', true, null, null
            );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Management block allows null days');
    }

    @isTest
    static void blockUnits_success_delegates() {
        Unit__c unit = getUnits()[0];
        Test.startTest();
        UnitBlockingService.BlockResult result =
            BulkLeadReassignmentController.blockUnits(
                new List<Id>{ unit.Id }, 3, 'Client interest', false, null, null
            );
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return result');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  unblockUnits
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void unblockUnits_empty_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.unblockUnits(new List<Id>());
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Empty list should throw');
    }

    @isTest
    static void unblockUnits_null_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.unblockUnits(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null list should throw');
    }

    @isTest
    static void unblockUnits_success_delegates() {
        Unit__c unit = getUnits()[0];
        Test.startTest();
        UnitBlockingService.BlockResult result =
            BulkLeadReassignmentController.unblockUnits(new List<Id>{ unit.Id });
        Test.stopTest();
        System.assertNotEquals(null, result, 'Should return result');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  getProjects
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void getProjects_returnsList() {
        Test.startTest();
        List<Project__c> projects = BulkLeadReassignmentController.getProjects();
        Test.stopTest();
        System.assert(projects.size() >= 1, 'Should find at least the setup project');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  searchBlockedUnits
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void searchBlockedUnits_delegates() {
        Test.startTest();
        List<UnitBlockingService.UnitRow> rows =
            BulkLeadReassignmentController.searchBlockedUnits(
                UserInfo.getUserId(), false, null
            );
        Test.stopTest();
        System.assertNotEquals(null, rows, 'Should return list');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  createBlockRequest
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void createBlockRequest_nullUnit_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.createBlockRequest(
                null, null, null, UserInfo.getUserId(), 3, 'Reason', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null unit should throw');
    }

    @isTest
    static void createBlockRequest_blankReason_throws() {
        Unit__c unit = getUnits()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.createBlockRequest(
                unit.Id, null, null, UserInfo.getUserId(), 3, '', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Blank reason should throw');
    }

    @isTest
    static void createBlockRequest_nullApprover_throws() {
        Unit__c unit = getUnits()[0];
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.createBlockRequest(
                unit.Id, null, null, null, 3, 'Reason', false
            );
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null approver should throw');
    }

    @isTest
    static void createBlockRequest_success_delegates() {
        Unit__c unit = getUnits()[0];
        Project__c proj = getProject();
        Test.startTest();
        Unit_Block_Request__c req =
            BulkLeadReassignmentController.createBlockRequest(
                unit.Id, proj.Id, null, UserInfo.getUserId(),
                3, 'Need approval', false
            );
        Test.stopTest();
        System.assertNotEquals(null, req, 'Should return a request');
        System.assertNotEquals(null, req.Id, 'Request should be persisted');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  approveBlockRequest / rejectBlockRequest
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void approveBlockRequest_null_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.approveBlockRequest(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null request id should throw');
    }

    @isTest
    static void approveBlockRequest_success_delegates() {
        Unit__c unit = getUnits()[0];
        Project__c proj = getProject();
        Unit_Block_Request__c req =
            BulkLeadReassignmentController.createBlockRequest(
                unit.Id, proj.Id, null, UserInfo.getUserId(),
                3, 'Approve me', false
            );
        Test.startTest();
        Unit_Block_Request__c approved =
            BulkLeadReassignmentController.approveBlockRequest(req.Id);
        Test.stopTest();
        System.assertNotEquals(null, approved, 'Should return approved request');
    }

    @isTest
    static void rejectBlockRequest_null_throws() {
        Boolean thrown = false;
        try {
            BulkLeadReassignmentController.rejectBlockRequest(null, 'n/a');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Null request id should throw');
    }

    @isTest
    static void rejectBlockRequest_success_delegates() {
        Unit__c unit = getUnits()[0];
        Project__c proj = getProject();
        Unit_Block_Request__c req =
            BulkLeadReassignmentController.createBlockRequest(
                unit.Id, proj.Id, null, UserInfo.getUserId(),
                3, 'Reject me', false
            );
        Test.startTest();
        Unit_Block_Request__c rejected =
            BulkLeadReassignmentController.rejectBlockRequest(req.Id, 'Not needed');
        Test.stopTest();
        System.assertNotEquals(null, rejected, 'Should return rejected request');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  getPendingBlockRequests / getMyBlockRequests
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void getPendingBlockRequests_delegates() {
        Test.startTest();
        List<UnitBlockingService.BlockRequestRow> rows =
            BulkLeadReassignmentController.getPendingBlockRequests();
        Test.stopTest();
        System.assertNotEquals(null, rows, 'Should return a list');
    }

    @isTest
    static void getMyBlockRequests_delegates() {
        Test.startTest();
        List<UnitBlockingService.BlockRequestRow> rows =
            BulkLeadReassignmentController.getMyBlockRequests();
        Test.stopTest();
        System.assertNotEquals(null, rows, 'Should return a list');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  getCurrentUserManager
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void getCurrentUserManager_returnsUserOrNull() {
        Test.startTest();
        // The running test user may or may not have a manager; both branches
        // of the if-check return valid results (User or null).
        User manager = BulkLeadReassignmentController.getCurrentUserManager();
        Test.stopTest();
        // No assertion on value — the method's single statement must run.
        System.assert(manager == null || manager.Id != null,
            'Should return null or a populated User');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  searchLeadsForLookup
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void searchLeadsForLookup_blank_returnsEmpty() {
        List<BulkLeadReassignmentService.LeadRow> rows =
            BulkLeadReassignmentController.searchLeadsForLookup('');
        System.assertEquals(0, rows.size(), 'Blank term returns empty');
    }

    @isTest
    static void searchLeadsForLookup_null_returnsEmpty() {
        List<BulkLeadReassignmentService.LeadRow> rows =
            BulkLeadReassignmentController.searchLeadsForLookup(null);
        System.assertEquals(0, rows.size(), 'Null term returns empty');
    }

    @isTest
    static void searchLeadsForLookup_shortTerm_returnsEmpty() {
        List<BulkLeadReassignmentService.LeadRow> rows =
            BulkLeadReassignmentController.searchLeadsForLookup('a');
        System.assertEquals(0, rows.size(), 'Single-char term returns empty');
    }

    @isTest
    static void searchLeadsForLookup_longTerm_returnsRows() {
        // Setup inserts a lead whose First_Name__c = 'Alice'
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> rows =
            BulkLeadReassignmentController.searchLeadsForLookup('Alice');
        Test.stopTest();
        System.assert(rows.size() >= 1, 'Should match Alice lead');
        BulkLeadReassignmentService.LeadRow row = rows[0];
        System.assertNotEquals(null, row.leadId, 'leadId should be populated');
        System.assertNotEquals(null, row.leadIdName, 'leadIdName should be populated');
        System.assert(row.leadName != null && row.leadName.length() > 0,
            'leadName should be populated');
    }
}