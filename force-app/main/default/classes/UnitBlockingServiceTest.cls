/**
 * @description Test class for UnitBlockingService (100% coverage).
 * Covers: searchUnits, blockUnits (3-arg and 6-arg overloads), unblockUnits,
 * searchBlockedUnits, createBlockRequest, approveBlockRequest, rejectBlockRequest,
 * getPendingRequests, getMyRequests, and all inner wrapper classes.
 */
@isTest
private class UnitBlockingServiceTest {

    @TestSetup
    static void setupData() {
        Project__c proj = TestDataFactory.createProject('Test Project');
        Tower__c t = TestDataFactory.createTower(proj.Id, 'T1');
        TestDataFactory.createUnit(proj.Id, t.Id, 'A-101');
        TestDataFactory.createUnit(proj.Id, t.Id, 'A-102');
        TestDataFactory.createUnit(proj.Id, t.Id, 'A-103');
    }

    // ── searchUnits ───────────────────────────────────────────────────

    @isTest
    static void testSearchUnits_byProject_returnsAll() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        List<UnitBlockingService.UnitRow> results =
            UnitBlockingService.searchUnits(proj.Id, null, null);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'Should find 3 units');
    }

    @isTest
    static void testSearchUnits_byStatus_returnsAvailable() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        List<UnitBlockingService.UnitRow> results =
            UnitBlockingService.searchUnits(proj.Id, 'Available', null);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'All 3 units should be Available');
    }

    @isTest
    static void testSearchUnits_byUnitNumber_returnsOne() {
        Test.startTest();
        List<UnitBlockingService.UnitRow> results =
            UnitBlockingService.searchUnits(null, null, 'A-101');
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should find unit A-101');
    }

    @isTest
    static void testSearchUnits_noFilter_returnsAllUnits() {
        // UnitBlockingService does NOT throw for null filters (unlike BulkLeadReassignmentController)
        Test.startTest();
        List<UnitBlockingService.UnitRow> results =
            UnitBlockingService.searchUnits(null, null, null);
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results.size() >= 3, 'Should return all units when no filters');
    }

    // ── blockUnits ────────────────────────────────────────────────────

    @isTest
    static void testBlockUnits_threeArgOverload_success() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(new List<Id>{ unit.Id }, 5, 'Client interest');
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should block 1 unit via 3-arg overload');
        System.assertEquals(0, result.failureCount, 'No failures');
    }

    @isTest
    static void testBlockUnits_success() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(
                new List<Id>{ unit.Id }, 5, 'Client interest', false, null, null
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should block 1 unit');
        System.assertEquals(0, result.failureCount, 'No failures');

        Unit__c updated = [SELECT Status__c, Block_Expiry__c, Blocked_By_User__c,
                                  Block_Reason__c, Block_Duration_Days__c, Is_Management_Block__c
                           FROM Unit__c WHERE Id = :unit.Id];
        System.assertEquals('Blocked', updated.Status__c, 'Status should be Blocked');
        System.assertEquals(Date.today().addDays(5), updated.Block_Expiry__c, 'Expiry should be today+5');
        System.assertEquals(UserInfo.getUserId(), updated.Blocked_By_User__c, 'Blocked by user should be set');
        System.assertEquals('Client interest', updated.Block_Reason__c, 'Reason should be set');
        System.assertEquals(5, updated.Block_Duration_Days__c.intValue(), 'Duration should be 5');
        System.assertEquals(false, updated.Is_Management_Block__c, 'Should not be management block');
    }

    @isTest
    static void testBlockUnits_alreadyBlocked_fails() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-102' LIMIT 1];
        unit.Status__c = 'Blocked';
        unit.Block_Expiry__c = Date.today().addDays(3);
        update unit;

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(
                new List<Id>{ unit.Id }, 5, 'Test', false, null, null
            );
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Should not succeed');
        System.assertEquals(1, result.failureCount, 'Should fail: already blocked');
    }

    @isTest
    static void testBlockUnits_exceedsMaxDays_fails() {
        Unit__c unit = [SELECT Id, Project__c FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];
        // Set max block days on project so validation kicks in
        Project__c proj = [SELECT Id FROM Project__c WHERE Id = :unit.Project__c LIMIT 1];
        proj.Max_Block_Days__c = 7;
        update proj;

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(
                new List<Id>{ unit.Id }, 30, 'Test', false, null, null
            );
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Should not succeed');
        System.assertEquals(1, result.failureCount, 'Should fail: exceeds max days');
    }

    @isTest
    static void testBlockUnits_managementBypassesMaxDays() {
        Unit__c unit = [SELECT Id, Project__c FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c WHERE Id = :unit.Project__c LIMIT 1];
        proj.Max_Block_Days__c = 7;
        update proj;

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(
                new List<Id>{ unit.Id }, 30, 'Management reservation', true, null, null
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Management block should bypass max days');
        Unit__c updated = [SELECT Is_Management_Block__c FROM Unit__c WHERE Id = :unit.Id];
        System.assertEquals(true, updated.Is_Management_Block__c, 'Should be marked as management block');
    }

    @isTest
    static void testManagementBlockWithoutDuration() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-102' LIMIT 1];

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(
                new List<Id>{ unit.Id }, null, 'Indefinite management hold', true, null, null
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Management block without duration should succeed');
        Unit__c updated = [SELECT Block_Expiry__c FROM Unit__c WHERE Id = :unit.Id];
        System.assertEquals(null, updated.Block_Expiry__c, 'No expiry for indefinite management block');
    }

    @isTest
    static void testBlockWithBlockingForUser() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-103' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(
                new List<Id>{ unit.Id }, 5, 'For executive', false, currentUser, null
            );
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should block with blocking for user');
        Unit__c updated = [SELECT Blocking_For__c FROM Unit__c WHERE Id = :unit.Id];
        System.assertEquals(currentUser, updated.Blocking_For__c, 'Blocking For should be set');
    }

    @isTest
    static void testBlockUnits_blankReason_returnsFailure() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(
                new List<Id>{ unit.Id }, 5, '', false, null, null
            );
        Test.stopTest();

        System.assert(result.failureCount > 0, 'Should fail when reason is blank');
        System.assertEquals(0, result.successCount, 'Success count should be 0');
    }

    @isTest
    static void testBlockUnits_invalidDays_returnsFailure() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(
                new List<Id>{ unit.Id }, 0, 'Test', false, null, null
            );
        Test.stopTest();

        System.assert(result.failureCount > 0, 'Should fail for invalid days (0 < 1)');
    }

    @isTest
    static void testBlockUnits_emptyList_returnsZeroCounts() {
        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(new List<Id>(), 5, 'Test', false, null, null);
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'No units to block');
        System.assertEquals(0, result.failureCount, 'No failures for empty list');
    }

    @isTest
    static void testBlockUnits_unitNotFound_returnsFailure() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];
        Id unitId = unit.Id;
        delete unit;

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.blockUnits(new List<Id>{ unitId }, 5, 'Test', false, null, null);
        Test.stopTest();

        System.assertEquals(1, result.failureCount, 'Should fail: unit not found');
        System.assertEquals(0, result.successCount);
    }

    // ── unblockUnits ──────────────────────────────────────────────────

    @isTest
    static void testUnblockUnits_success() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-103' LIMIT 1];
        unit.Status__c = 'Blocked';
        unit.Block_Expiry__c = Date.today().addDays(5);
        unit.Blocked_By_User__c = UserInfo.getUserId();
        unit.Block_Reason__c = 'Test';
        unit.Is_Management_Block__c = true;
        unit.Blocking_For__c = UserInfo.getUserId();
        update unit;

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.unblockUnits(new List<Id>{ unit.Id });
        Test.stopTest();

        System.assertEquals(1, result.successCount, 'Should unblock 1 unit');

        Unit__c updated = [SELECT Status__c, Block_Expiry__c, Blocked_By_User__c,
                                  Block_Reason__c, Is_Management_Block__c, Blocking_For__c
                           FROM Unit__c WHERE Id = :unit.Id];
        System.assertEquals('Available', updated.Status__c, 'Status should be Available');
        System.assertEquals(null, updated.Block_Expiry__c, 'Expiry should be cleared');
        System.assertEquals(null, updated.Blocked_By_User__c, 'Blocked by should be cleared');
        System.assertEquals(null, updated.Block_Reason__c, 'Reason should be cleared');
        System.assertEquals(false, updated.Is_Management_Block__c, 'Management flag should be cleared');
        System.assertEquals(null, updated.Blocking_For__c, 'Blocking For should be cleared');
    }

    @isTest
    static void testUnblockUnits_notBlocked_fails() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.unblockUnits(new List<Id>{ unit.Id });
        Test.stopTest();

        System.assertEquals(0, result.successCount, 'Should not succeed');
        System.assertEquals(1, result.failureCount, 'Should fail: unit not blocked');
    }

    @isTest
    static void testUnblockUnits_unitNotFound_fails() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-102' LIMIT 1];
        Id unitId = unit.Id;
        delete unit;

        Test.startTest();
        UnitBlockingService.BlockResult result =
            UnitBlockingService.unblockUnits(new List<Id>{ unitId });
        Test.stopTest();

        System.assertEquals(1, result.failureCount, 'Should fail: unit not found');
    }

    // ── searchBlockedUnits ────────────────────────────────────────────

    @isTest
    static void testSearchBlockedUnits_byUser_returnsBlockedUnit() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];
        unit.Status__c = 'Blocked';
        unit.Blocked_By_User__c = UserInfo.getUserId();
        unit.Block_Reason__c = 'Test';
        unit.Is_Management_Block__c = true;
        update unit;

        Test.startTest();
        List<UnitBlockingService.UnitRow> results =
            UnitBlockingService.searchBlockedUnits(UserInfo.getUserId(), true, null);
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should find blocked unit');
        System.assertEquals(true, results[0].isManagementBlock, 'Should be management block');
    }

    @isTest
    static void testSearchBlockedUnits_noFilter_returnsAllBlocked() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];
        unit.Status__c = 'Blocked';
        unit.Block_Reason__c = 'No filter test';
        update unit;

        Test.startTest();
        List<UnitBlockingService.UnitRow> results =
            UnitBlockingService.searchBlockedUnits(null, null, null);
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should return at least 1 blocked unit');
    }

    @isTest
    static void testSearchBlockedUnits_byBlockingFor_returnsFiltered() {
        Unit__c unit = [SELECT Id FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];
        Id currentUser = UserInfo.getUserId();
        unit.Status__c = 'Blocked';
        unit.Block_Reason__c = 'For someone';
        unit.Blocking_For__c = currentUser;
        unit.Blocked_By_User__c = currentUser;
        update unit;

        Test.startTest();
        List<UnitBlockingService.UnitRow> results =
            UnitBlockingService.searchBlockedUnits(null, null, currentUser);
        Test.stopTest();

        System.assert(results.size() >= 1, 'Should find unit blocked for current user');
    }

    // ── createBlockRequest ────────────────────────────────────────────

    @isTest
    static void testCreateBlockRequest_success() {
        Unit__c unit = [SELECT Id, Project__c FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        Unit_Block_Request__c req = UnitBlockingService.createBlockRequest(
            unit.Id, unit.Project__c, null, currentUser, 5, 'Need for client', false
        );
        Test.stopTest();

        System.assertNotEquals(null, req.Id, 'Request should be created');
        System.assertEquals('Pending', req.Status__c, 'Status should be Pending');
    }

    // ── approveBlockRequest ───────────────────────────────────────────

    @isTest
    static void testApproveBlockRequest_success() {
        Unit__c unit = [SELECT Id, Project__c FROM Unit__c WHERE Unit_Number__c = 'A-102' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Unit_Block_Request__c req = UnitBlockingService.createBlockRequest(
            unit.Id, unit.Project__c, null, currentUser, 3, 'Approval test', false
        );

        Test.startTest();
        Unit_Block_Request__c approved = UnitBlockingService.approveBlockRequest(req.Id);
        Test.stopTest();

        System.assertEquals('Approved', approved.Status__c, 'Should be approved');
        Unit__c updated = [SELECT Status__c FROM Unit__c WHERE Id = :unit.Id];
        System.assertEquals('Blocked', updated.Status__c, 'Unit should be blocked after approval');
    }

    @isTest
    static void testApproveBlockRequest_alreadyApproved_throws() {
        Unit__c unit = [SELECT Id, Project__c FROM Unit__c WHERE Unit_Number__c = 'A-102' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Unit_Block_Request__c req = UnitBlockingService.createBlockRequest(
            unit.Id, unit.Project__c, null, currentUser, 3, 'Already approved test', false
        );
        UnitBlockingService.approveBlockRequest(req.Id); // First approval succeeds

        Boolean thrown = false;
        Test.startTest();
        try {
            UnitBlockingService.approveBlockRequest(req.Id); // Second call → throws
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Should throw when request is already approved');
    }

    // ── rejectBlockRequest ────────────────────────────────────────────

    @isTest
    static void testRejectBlockRequest_success() {
        Unit__c unit = [SELECT Id, Project__c FROM Unit__c WHERE Unit_Number__c = 'A-103' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Unit_Block_Request__c req = UnitBlockingService.createBlockRequest(
            unit.Id, unit.Project__c, null, currentUser, 3, 'Rejection test', false
        );

        Test.startTest();
        Unit_Block_Request__c rejected = UnitBlockingService.rejectBlockRequest(req.Id, 'Not needed');
        Test.stopTest();

        System.assertEquals('Rejected', rejected.Status__c, 'Should be rejected');
        System.assertEquals('Not needed', rejected.Response_Notes__c, 'Notes should be set');
    }

    @isTest
    static void testRejectBlockRequest_alreadyRejected_throws() {
        Unit__c unit = [SELECT Id, Project__c FROM Unit__c WHERE Unit_Number__c = 'A-103' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Unit_Block_Request__c req = UnitBlockingService.createBlockRequest(
            unit.Id, unit.Project__c, null, currentUser, 3, 'Already rejected test', false
        );
        UnitBlockingService.rejectBlockRequest(req.Id, 'First rejection');

        Boolean thrown = false;
        Test.startTest();
        try {
            UnitBlockingService.rejectBlockRequest(req.Id, 'Second rejection'); // → throws
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Should throw when request is already rejected');
    }

    // ── getPendingRequests / getMyRequests ────────────────────────────

    @isTest
    static void testGetPendingAndMyRequests() {
        Unit__c unit = [SELECT Id, Project__c FROM Unit__c WHERE Unit_Number__c = 'A-101' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        UnitBlockingService.createBlockRequest(
            unit.Id, unit.Project__c, null, currentUser, 5, 'Test request', false
        );

        Test.startTest();
        List<UnitBlockingService.BlockRequestRow> pending =
            UnitBlockingService.getPendingRequests(currentUser);
        List<UnitBlockingService.BlockRequestRow> myReqs =
            UnitBlockingService.getMyRequests(currentUser);
        Test.stopTest();

        System.assert(pending.size() >= 1, 'Should have pending requests');
        System.assert(myReqs.size() >= 1, 'Should have my requests');
    }

    // ── Inner wrapper class construction ──────────────────────────────

    @isTest
    static void testWrapperClasses_directConstruction() {
        UnitBlockingService.UnitRow row = new UnitBlockingService.UnitRow();
        row.unitNumber = 'B-201';
        row.isManagementBlock = true;
        System.assertEquals('B-201', row.unitNumber);
        System.assertEquals(true, row.isManagementBlock);

        UnitBlockingService.BlockResult br = new UnitBlockingService.BlockResult();
        System.assertEquals(0, br.successCount);
        System.assertEquals(0, br.failureCount);

        UnitBlockingService.BlockFailure bf =
            new UnitBlockingService.BlockFailure(null, 'B-201', 'Unit not found.');
        System.assertEquals('B-201', bf.unitNumber);
        System.assertEquals('Unit not found.', bf.reason);

        UnitBlockingService.BlockRequestRow reqRow = new UnitBlockingService.BlockRequestRow();
        reqRow.status = 'Pending';
        reqRow.isManagement = false;
        System.assertEquals('Pending', reqRow.status);
        System.assertEquals(false, reqRow.isManagement);
    }
}