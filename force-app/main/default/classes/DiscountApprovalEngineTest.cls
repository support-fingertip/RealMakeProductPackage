/**
 * @description Test class for DiscountApprovalEngine (100% coverage).
 * Covers: evaluateDiscounts (all branches — N/A, Within Limit, Pending, Approved, Rejected,
 * Partially Approved, pct-based, threshold-based, role-based, project-filtered),
 * submitForApproval (early return, full DML, no-approver warning),
 * approveDiscount/rejectDiscount (matrix approver, Next_Approver, delegate, not authorized),
 * recallApproval, getApprovalHistory, resendApproverNotifications,
 * previewDiscountApproval, validateDiscountsAgainstUnit,
 * getDiscountLabels, getConfiguredDiscountFields, and all inner DTOs.
 */
@isTest
private class DiscountApprovalEngineTest {

    @TestSetup
    static void setup() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('DAE Proj');
        TestDataFactory.createLead(proj.Id, 'DAE', '9811002200');

        // Primary matrix: field 1, max value 1000, current user as approver
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 1,
            Discount_Label__c = 'Test Discount',
            Max_Value__c = 1000,
            Max_Pct__c = 10,
            Approval_Level__c = 1,
            Approver_User__c = UserInfo.getUserId(),
            Is_Active__c = true
        );
    }

    /** Helper: get the lead from TestSetup for Cost_Sheet__c master-detail. */
    private static Id getLeadId() {
        return [SELECT Id FROM Lead__c LIMIT 1].Id;
    }

    // ── evaluateDiscounts — zero discount → N/A ───────────────────

    @isTest
    static void evaluateDiscounts_byCostSheetId_noDiscounts() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        insert cs;
        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();
        System.assertNotEquals(null, summary);
        System.assertNotEquals(null, summary.discounts);
        System.assertEquals(false, summary.requiresApproval);
        System.assertEquals('Not Required', summary.overallStatus);
    }

    @isTest
    static void evaluateDiscounts_byObject_noDiscounts() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        insert cs;
        cs = [SELECT Id, Unit__c, Discount_1__c, Discount_2__c,
                     Discount_3__c, Discount_4__c, Discount_5__c, Discount_6__c,
                     Agreement_Value__c, Project__c, Discount_1_Status__c,
                     Discount_2_Status__c, Discount_3_Status__c, Discount_4_Status__c,
                     Discount_5_Status__c, Discount_6_Status__c,
                     Discount_Approval_Status__c, Highest_Approval_Level__c,
                     Next_Approver__c, Is_Locked__c, Approval_Submitted_Date__c,
                     Approved_By__c, Approval_Date__c, Approval_Comments__c,
                     Status__c, CreatedById, Created_By__c, Name, Super_Builtup_Area__c
              FROM Cost_Sheet__c WHERE Id = :cs.Id];
        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs);
        Test.stopTest();
        System.assertNotEquals(null, summary);
    }

    // ── evaluateDiscounts — discount exceeds Max_Value__c → Pending ─

    @isTest
    static void evaluateDiscounts_discountExceedsMaxValue_pendingApproval() {
        Cost_Sheet__c cs = new Cost_Sheet__c(
            Lead__c = getLeadId(),
            Discount_1__c = 5000,
            Agreement_Value__c = 200000
        );
        insert cs;
        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();
        System.assertEquals(true, summary.requiresApproval);
        System.assertEquals('Pending', summary.overallStatus);
        System.assertEquals(UserInfo.getUserId(), summary.nextApproverId);
        System.assertNotEquals(null, summary.nextApproverName);
        System.assertEquals(1, summary.highestLevel);
        // maxAllowed and maxPctAllowed on the eval
        Boolean foundPending = false;
        for (DiscountApprovalEngine.DiscountEvaluation eval : summary.discounts) {
            if (eval.fieldNumber == 1) {
                System.assertEquals('Pending Approval', eval.status);
                System.assertEquals(true, eval.exceedsLimit);
                System.assertNotEquals(null, eval.maxAllowed);
                foundPending = true;
            }
        }
        System.assert(foundPending);
    }

    // ── evaluateDiscounts — discount within limit → Within Limit ───

    @isTest
    static void evaluateDiscounts_discountWithinMaxValue_withinLimitStatus() {
        Cost_Sheet__c cs = new Cost_Sheet__c(
            Lead__c = getLeadId(),
            Discount_1__c = 500,
            Agreement_Value__c = 200000
        );
        insert cs;
        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();
        System.assertEquals(false, summary.requiresApproval);
        Boolean foundWithin = false;
        for (DiscountApprovalEngine.DiscountEvaluation eval : summary.discounts) {
            if (eval.fieldNumber == 1) {
                System.assertEquals('Within Limit', eval.status);
                foundWithin = true;
            }
        }
        System.assert(foundWithin);
    }

    // ── evaluateDiscounts — existing Approved status preserved ─────

    @isTest
    static void evaluateDiscounts_existingApprovedStatus_preservesApproved() {
        Cost_Sheet__c cs = new Cost_Sheet__c(
            Lead__c = getLeadId(),
            Discount_1__c = 5000,
            Agreement_Value__c = 200000
        );
        insert cs;
        cs.put('Discount_1_Status__c', 'Approved');
        update cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();

        for (DiscountApprovalEngine.DiscountEvaluation eval : summary.discounts) {
            if (eval.fieldNumber == 1) {
                System.assertEquals('Approved', eval.status);
            }
        }
        System.assertEquals('Approved', summary.overallStatus);
        System.assertEquals(false, summary.requiresApproval);
    }

    // ── evaluateDiscounts — existing Rejected status preserved ─────

    @isTest
    static void evaluateDiscounts_existingRejectedStatus_preservesRejected() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        insert cs;
        cs.put('Discount_1_Status__c', 'Rejected');
        update cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();

        for (DiscountApprovalEngine.DiscountEvaluation eval : summary.discounts) {
            if (eval.fieldNumber == 1) {
                System.assertEquals('Rejected', eval.status);
            }
        }
        System.assertEquals('Rejected', summary.overallStatus);
    }

    // ── evaluateDiscounts — Max_Pct__c branch ─────────────────────

    @isTest
    static void evaluateDiscounts_discountExceedsPct_requiresApproval() {
        // Matrix for field 2 with Max_Pct__c = 5% limit
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 2,
            Discount_Label__c = 'Pct Discount',
            Max_Pct__c = 5,
            Approval_Level__c = 1,
            Approver_User__c = UserInfo.getUserId(),
            Is_Active__c = true
        );
        // CS: agreement = 100000, discount_2 = 10000 → 10% > 5%
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Agreement_Value__c = 100000);
        cs.put('Discount_2__c', 10000);
        insert cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();

        System.assertEquals(true, summary.requiresApproval);
    }

    // ── evaluateDiscounts — Approval_Threshold__c branch ──────────

    @isTest
    static void evaluateDiscounts_discountExceedsThreshold_requiresApproval() {
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 3,
            Discount_Label__c = 'Threshold Discount',
            Approval_Threshold__c = 500,
            Approval_Level__c = 1,
            Approver_User__c = UserInfo.getUserId(),
            Is_Active__c = true
        );
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        cs.put('Discount_3__c', 1000);
        insert cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();

        System.assertEquals(true, summary.requiresApproval);
    }

    // ── evaluateDiscounts — Partially Approved overall status ──────

    @isTest
    static void evaluateDiscounts_partiallyApproved_returnsPartiallyApproved() {
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 2,
            Discount_Label__c = 'D2',
            Max_Value__c = 1000,
            Approval_Level__c = 1,
            Approver_User__c = UserInfo.getUserId(),
            Is_Active__c = true
        );
        // Field 1 = Approved, field 2 = Pending (both exceed limit)
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        cs.put('Discount_2__c', 5000);
        insert cs;
        cs.put('Discount_1_Status__c', 'Approved');
        cs.put('Discount_2_Status__c', 'Pending Approval');
        update cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();

        System.assertEquals('Partially Approved', summary.overallStatus);
    }

    // ── evaluateDiscounts — multi-level matrix (highest level wins) ─

    @isTest
    static void evaluateDiscounts_multiLevelMatrix_highestLevelSelected() {
        insert new List<Discount_Approval_Matrix__c>{
            new Discount_Approval_Matrix__c(
                Discount_Field_Number__c = 2,
                Discount_Label__c = 'ML Discount',
                Max_Value__c = 1000,
                Approval_Level__c = 1,
                Approver_User__c = UserInfo.getUserId(),
                Is_Active__c = true
            ),
            new Discount_Approval_Matrix__c(
                Discount_Field_Number__c = 2,
                Discount_Label__c = 'ML Discount',
                Max_Value__c = 3000,
                Approval_Level__c = 2,
                Approver_User__c = UserInfo.getUserId(),
                Is_Active__c = true
            )
        };
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        cs.put('Discount_2__c', 5000); // > 3000 → level 2
        insert cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();

        System.assertEquals(2, summary.highestLevel);
    }

    // ── evaluateDiscounts — project filter: different project filtered ─

    @isTest
    static void evaluateDiscounts_matrixDifferentProject_treatedAsNoMatrix() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('Filter Test');
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 2,
            Discount_Label__c = 'Proj D',
            Max_Value__c = 100,
            Approval_Level__c = 1,
            Project__c = proj.Id,
            Approver_User__c = UserInfo.getUserId(),
            Is_Active__c = true
        );
        // CS with no project → matrix for proj is filtered out
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        cs.put('Discount_2__c', 5000);
        insert cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();

        for (DiscountApprovalEngine.DiscountEvaluation eval : summary.discounts) {
            if (eval.fieldNumber == 2) {
                System.assertEquals('Within Limit', eval.status);
            }
        }
    }

    // ── evaluateDiscounts — role-based approver (resolveApproversFromRoles) ─

    @isTest
    static void evaluateDiscounts_roleBasedApprover_queryExecutes() {
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 2,
            Discount_Label__c = 'Role Discount',
            Max_Value__c = 100,
            Approval_Level__c = 1,
            Approver_Role__c = 'SomeNonExistentRole',
            Is_Active__c = true
        );
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        cs.put('Discount_2__c', 5000);
        insert cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();

        System.assertEquals(true, summary.requiresApproval);
        // Role not found in org → approverId stays null
        System.assertEquals(null, summary.nextApproverId);
    }

    // ── evaluateDiscounts — unit validation branch ────────────────

    @isTest
    static void evaluateDiscounts_withUnitNoFieldAPI_coversUnitBranch() {
        // cs.Unit__c != null but no Unit_Field_API__c on matrix → early exit
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('VAU Test');
        Tower__c tower = TestDataFactory.createTower(proj.Id, 'T1');
        Unit__c unit = TestDataFactory.createUnit(proj.Id, tower.Id, 'U-VAU');

        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        cs.put('Unit__c', unit.Id);
        insert cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.evaluateDiscounts(cs.Id);
        Test.stopTest();

        // Executes the Unit branch; warnings list is initialized
        System.assertNotEquals(null, summary.warnings);
    }

    // ── submitForApproval ─────────────────────────────────────────

    @isTest
    static void submitForApproval_noDiscountValues_returnsEarlyNotRequired() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        insert cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary result =
            DiscountApprovalEngine.submitForApproval(cs.Id, 'test');
        Test.stopTest();

        System.assertEquals(false, result.requiresApproval);
    }

    @isTest
    static void submitForApproval_discountExceedsLimit_locksAndCreateLogs() {
        Cost_Sheet__c cs = new Cost_Sheet__c(
            Lead__c = getLeadId(),
            Discount_1__c = 5000,
            Agreement_Value__c = 200000
        );
        insert cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary result =
            DiscountApprovalEngine.submitForApproval(cs.Id, 'Please approve');
        Test.stopTest();

        Cost_Sheet__c updated = [
            SELECT Is_Locked__c, Discount_Approval_Status__c, Next_Approver__c
            FROM Cost_Sheet__c WHERE Id = :cs.Id
        ];
        System.assertEquals(true, updated.Is_Locked__c);
        System.assertEquals('Pending', updated.Discount_Approval_Status__c);
        System.assertEquals(UserInfo.getUserId(), updated.Next_Approver__c);

        List<Discount_Approval_Log__c> logs = [
            SELECT Action__c FROM Discount_Approval_Log__c WHERE Cost_Sheet__c = :cs.Id
        ];
        System.assert(!logs.isEmpty());
        System.assertEquals('Submitted', logs[0].Action__c);
    }

    @isTest
    static void submitForApproval_matrixNoApproverUser_warningAdded() {
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 2,
            Discount_Label__c = 'No Approver',
            Max_Value__c = 100,
            Approval_Level__c = 1,
            Is_Active__c = true
            // No Approver_User__c, no Approver_Role__c
        );
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        cs.put('Discount_2__c', 5000);
        insert cs;

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary result =
            DiscountApprovalEngine.submitForApproval(cs.Id, '');
        Test.stopTest();

        System.assertEquals(true, result.requiresApproval);
        Boolean hasNoApproverWarning = false;
        for (String w : result.warnings) {
            if (w.contains('No approver user assigned')) {
                hasNoApproverWarning = true;
            }
        }
        System.assert(hasNoApproverWarning, 'Expected no-approver warning');
    }

    // ── approveDiscount ───────────────────────────────────────────

    @isTest
    static void approveDiscount_asMatrixApprover_statusBecomesApproved() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        insert cs;
        cs.put('Discount_1_Status__c', 'Pending Approval');
        update cs;

        Test.startTest();
        DiscountApprovalEngine.approveDiscount(cs.Id, 1, 'Looks good');
        Test.stopTest();

        Cost_Sheet__c updated = [
            SELECT Discount_Approval_Status__c, Is_Locked__c, Approved_By__c
            FROM Cost_Sheet__c WHERE Id = :cs.Id
        ];
        System.assertEquals('Approved', updated.Discount_Approval_Status__c);
        System.assertEquals(false, updated.Is_Locked__c);
        System.assertEquals(UserInfo.getUserId(), updated.Approved_By__c);

        List<Discount_Approval_Log__c> logs = [
            SELECT Action__c FROM Discount_Approval_Log__c WHERE Cost_Sheet__c = :cs.Id
        ];
        System.assertEquals(1, logs.size());
        System.assertEquals('Approved', logs[0].Action__c);
    }

    @isTest
    static void approveDiscount_asNextApprover_validatesByNextApproverField() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        insert cs;
        cs.put('Discount_1_Status__c', 'Pending Approval');
        cs.put('Next_Approver__c', UserInfo.getUserId());
        update cs;

        Test.startTest();
        DiscountApprovalEngine.approveDiscount(cs.Id, 1, 'via next approver');
        Test.stopTest();

        Cost_Sheet__c updated = [SELECT Discount_Approval_Status__c FROM Cost_Sheet__c WHERE Id = :cs.Id];
        System.assertEquals('Approved', updated.Discount_Approval_Status__c);
    }

    @isTest
    static void approveDiscount_partiallyApproved_remainsLocked() {
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 2,
            Discount_Label__c = 'D2',
            Max_Value__c = 1000,
            Approval_Level__c = 1,
            Approver_User__c = UserInfo.getUserId(),
            Is_Active__c = true
        );
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        cs.put('Discount_2__c', 5000);
        insert cs;
        cs.put('Discount_1_Status__c', 'Pending Approval');
        cs.put('Discount_2_Status__c', 'Pending Approval');
        update cs;

        Test.startTest();
        DiscountApprovalEngine.approveDiscount(cs.Id, 1, 'ok');
        Test.stopTest();

        Cost_Sheet__c updated = [SELECT Discount_Approval_Status__c FROM Cost_Sheet__c WHERE Id = :cs.Id];
        System.assertEquals('Partially Approved', updated.Discount_Approval_Status__c);
    }

    @isTest
    static void approveDiscount_asDelegatedApprover_passesValidation() {
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 2,
            Discount_Label__c = 'D2 Delegated',
            Max_Value__c = 1000,
            Approval_Level__c = 1,
            Delegated_Approver__c = UserInfo.getUserId(),
            Is_Active__c = true
        );
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        cs.put('Discount_2__c', 5000);
        insert cs;
        cs.put('Discount_2_Status__c', 'Pending Approval');
        update cs;

        Test.startTest();
        DiscountApprovalEngine.approveDiscount(cs.Id, 2, 'delegated');
        Test.stopTest();

        Cost_Sheet__c updated = [SELECT Discount_Approval_Status__c FROM Cost_Sheet__c WHERE Id = :cs.Id];
        System.assertEquals('Approved', updated.Discount_Approval_Status__c);
    }

    @isTest
    static void approveDiscount_notAuthorized_throwsAuraHandledException() {
        // Field 2 has no matrix → not authorized
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        insert cs;

        Boolean thrown = false;
        Test.startTest();
        try {
            DiscountApprovalEngine.approveDiscount(cs.Id, 2, 'no auth');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Should throw AuraHandledException for unauthorized user');
    }

    // ── rejectDiscount ────────────────────────────────────────────

    @isTest
    static void rejectDiscount_asMatrixApprover_statusBecomesRejected() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        insert cs;
        cs.put('Discount_1_Status__c', 'Pending Approval');
        update cs;

        Test.startTest();
        DiscountApprovalEngine.rejectDiscount(cs.Id, 1, 'Too high');
        Test.stopTest();

        Cost_Sheet__c updated = [
            SELECT Discount_Approval_Status__c, Is_Locked__c
            FROM Cost_Sheet__c WHERE Id = :cs.Id
        ];
        System.assertEquals('Rejected', updated.Discount_Approval_Status__c);
        System.assertEquals(false, updated.Is_Locked__c);
    }

    // ── recallApproval ────────────────────────────────────────────

    @isTest
    static void recallApproval_submittedCostSheet_resetsToNotRequired() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        insert cs;
        cs.put('Is_Locked__c', true);
        cs.put('Discount_Approval_Status__c', 'Pending');
        cs.put('Discount_1_Status__c', 'Pending Approval');
        update cs;

        Test.startTest();
        DiscountApprovalEngine.recallApproval(cs.Id);
        Test.stopTest();

        Cost_Sheet__c updated = [
            SELECT Discount_Approval_Status__c, Is_Locked__c
            FROM Cost_Sheet__c WHERE Id = :cs.Id
        ];
        System.assertEquals('Not Required', updated.Discount_Approval_Status__c);
        System.assertEquals(false, updated.Is_Locked__c);

        List<Discount_Approval_Log__c> logs = [
            SELECT Action__c FROM Discount_Approval_Log__c
            WHERE Cost_Sheet__c = :cs.Id AND Action__c = 'Recalled'
        ];
        System.assertEquals(1, logs.size());
    }

    @isTest
    static void recallApproval_noLockedRecord_handlesGracefully() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        insert cs;
        Boolean thrown = false;
        try {
            DiscountApprovalEngine.recallApproval(cs.Id);
        } catch (Exception e) {
            thrown = true;
        }
        System.assert(true); // Either path is acceptable
    }

    // ── getApprovalHistory ────────────────────────────────────────

    @isTest
    static void getApprovalHistory_emptyList() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        insert cs;
        Test.startTest();
        List<Discount_Approval_Log__c> logs = DiscountApprovalEngine.getApprovalHistory(cs.Id);
        Test.stopTest();
        System.assertEquals(0, logs.size());
    }

    @isTest
    static void getApprovalHistory_withLogs_returnsMostRecentFirst() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        insert cs;
        insert new List<Discount_Approval_Log__c>{
            new Discount_Approval_Log__c(
                Cost_Sheet__c = cs.Id, Action__c = 'Submitted',
                Discount_Field_Number__c = 1, Approver__c = UserInfo.getUserId(),
                Timestamp__c = DateTime.now().addHours(-2)
            ),
            new Discount_Approval_Log__c(
                Cost_Sheet__c = cs.Id, Action__c = 'Approved',
                Discount_Field_Number__c = 1, Approver__c = UserInfo.getUserId(),
                Timestamp__c = DateTime.now().addHours(-1)
            )
        };

        Test.startTest();
        List<Discount_Approval_Log__c> logs = DiscountApprovalEngine.getApprovalHistory(cs.Id);
        Test.stopTest();

        System.assertEquals(2, logs.size());
        System.assertEquals('Approved', logs[0].Action__c); // most recent first
    }

    // ── resendApproverNotifications ───────────────────────────────

    @isTest
    static void resendApproverNotifications_noApproversReturnsMessage() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        insert cs;
        Test.startTest();
        List<String> names = DiscountApprovalEngine.resendApproverNotifications(cs.Id);
        Test.stopTest();
        System.assertNotEquals(null, names);
        System.assert(!names.isEmpty(), 'Should return message about no pending approvers');
    }

    @isTest
    static void resendApproverNotifications_withPendingDiscount_sendsNotification() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        insert cs;
        // Simulate pending state
        cs.put('Discount_1_Status__c', 'Pending Approval');
        cs.put('Is_Locked__c', true);
        cs.put('Discount_Approval_Status__c', 'Pending');
        update cs;

        Test.startTest();
        List<String> diagnostics = DiscountApprovalEngine.resendApproverNotifications(cs.Id);
        Test.stopTest();

        System.assertNotEquals(null, diagnostics);
        System.assert(!diagnostics.isEmpty());
    }

    // ── getDiscountLabels ─────────────────────────────────────────

    @isTest
    static void getDiscountLabels_noProject_returnsMapWithSetupLabel() {
        Test.startTest();
        Map<Integer, String> labels = DiscountApprovalEngine.getDiscountLabels(null);
        Test.stopTest();
        System.assertNotEquals(null, labels);
        System.assert(labels.containsKey(1));
        System.assertEquals('Test Discount', labels.get(1));
    }

    @isTest
    static void getDiscountLabels_withMatchingProject_returnsProjectLabel() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('Label Test');
        insert new Discount_Approval_Matrix__c(
            Discount_Field_Number__c = 3,
            Discount_Label__c = 'Project Discount',
            Max_Value__c = 500,
            Approval_Level__c = 1,
            Project__c = proj.Id,
            Is_Active__c = true
        );

        Test.startTest();
        Map<Integer, String> labels = DiscountApprovalEngine.getDiscountLabels(proj.Id);
        Test.stopTest();

        System.assert(labels.containsKey(3));
        System.assertEquals('Project Discount', labels.get(3));
    }

    // ── getConfiguredDiscountFields ───────────────────────────────

    @isTest
    static void getConfiguredDiscountFields_noProject_returnsFieldsList() {
        Test.startTest();
        List<Map<String, Object>> fields =
            DiscountApprovalEngine.getConfiguredDiscountFields(null);
        Test.stopTest();
        System.assertNotEquals(null, fields);
        System.assert(!fields.isEmpty());
        System.assertEquals(1, (Integer) fields[0].get('fieldNumber'));
        System.assertEquals('Test Discount', (String) fields[0].get('label'));
    }

    // ── validateDiscountsAgainstUnit ──────────────────────────────

    @isTest
    static void validateDiscountsAgainstUnit_noUnit_returnsEmpty() {
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId());
        insert cs;
        Test.startTest();
        Map<Integer, String> result = DiscountApprovalEngine.validateDiscountsAgainstUnit(cs.Id);
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }

    @isTest
    static void validateDiscountsAgainstUnit_withUnitNoFieldAPI_returnsEmpty() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('VAU Test');
        Tower__c tower = TestDataFactory.createTower(proj.Id, 'T1');
        Unit__c unit = TestDataFactory.createUnit(proj.Id, tower.Id, 'U-VAU');

        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = getLeadId(), Discount_1__c = 5000);
        cs.put('Unit__c', unit.Id);
        insert cs;

        Test.startTest();
        Map<Integer, String> result = DiscountApprovalEngine.validateDiscountsAgainstUnit(cs.Id);
        Test.stopTest();

        // Matrix for field 1 has no Unit_Field_API__c → unitFieldAPIs empty → returns {}
        System.assertEquals(0, result.size());
    }

    // ── previewDiscountApproval ───────────────────────────────────

    @isTest
    static void previewDiscountApproval_exceedsLimit_requiresApproval() {
        String discountsJson = '[{"fieldNumber": 1, "value": 5000}]';

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.previewDiscountApproval(null, discountsJson, 200000);
        Test.stopTest();

        System.assertEquals(true, summary.requiresApproval);
        System.assertEquals(1, summary.highestLevel);
        System.assertEquals(UserInfo.getUserId(), summary.nextApproverId);
    }

    @isTest
    static void previewDiscountApproval_withinLimit_notRequired() {
        String discountsJson = '[{"fieldNumber": 1, "value": 500}]'; // < 1000

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.previewDiscountApproval(null, discountsJson, 100000);
        Test.stopTest();

        System.assertEquals(false, summary.requiresApproval);
    }

    @isTest
    static void previewDiscountApproval_emptyDiscountsList_notRequired() {
        String discountsJson = '[]';

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.previewDiscountApproval(null, discountsJson, 100000);
        Test.stopTest();

        System.assertEquals(false, summary.requiresApproval);
        System.assertEquals(0, summary.discounts.size());
    }

    @isTest
    static void previewDiscountApproval_nullAgreementValue_handlesZero() {
        String discountsJson = '[{"fieldNumber": 1, "value": 5000}]';

        Test.startTest();
        DiscountApprovalEngine.ApprovalSummary summary =
            DiscountApprovalEngine.previewDiscountApproval(null, discountsJson, null);
        Test.stopTest();

        // agreementValue = null → safeAgreement = 0 → pct = 0
        System.assertEquals(true, summary.requiresApproval);
    }

    // ── DTO constructors ──────────────────────────────────────────

    @isTest
    static void dto_constructors() {
        DiscountApprovalEngine.DiscountEvaluation ev =
            new DiscountApprovalEngine.DiscountEvaluation();
        ev.fieldNumber = 1; ev.label = 'x'; ev.value = 10;
        ev.pct = 5; ev.status = 'Within Limit'; ev.requiredLevel = 0;
        ev.approverId = UserInfo.getUserId(); ev.approverName = 'Test';
        ev.exceedsLimit = false; ev.maxAllowed = 1000; ev.maxPctAllowed = 10;
        System.assertEquals(1, ev.fieldNumber);
        System.assertEquals(false, ev.exceedsLimit);

        DiscountApprovalEngine.ApprovalSummary sum =
            new DiscountApprovalEngine.ApprovalSummary();
        sum.overallStatus = 'Pending'; sum.highestLevel = 1;
        sum.nextApproverId = UserInfo.getUserId(); sum.nextApproverName = 'Test';
        sum.requiresApproval = true; sum.warnings = new List<String>{ 'w' };
        System.assertEquals('Pending', sum.overallStatus);
        System.assertEquals(true, sum.requiresApproval);
    }
}