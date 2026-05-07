/**
 * @description Test class for FormulaCalculationService.
 * Exercises the public evaluator (arithmetic + IF + string comparisons),
 * the Flow invocable entry point across happy and error branches, and
 * the DTO constructors.
 */
@isTest
private class FormulaCalculationServiceTest {

    // ── evaluateFormulaPublic (direct arithmetic) ───────────────────

    @isTest
    static void evaluateFormulaPublic_arithmetic() {
        System.assertEquals(5, FormulaCalculationService.evaluateFormulaPublic('2+3'));
        System.assertEquals(1, FormulaCalculationService.evaluateFormulaPublic('3-2'));
        System.assertEquals(12, FormulaCalculationService.evaluateFormulaPublic('4*3'));
        System.assertEquals(2, FormulaCalculationService.evaluateFormulaPublic('6/3'));
        System.assertEquals(1, FormulaCalculationService.evaluateFormulaPublic('7%3'));
        // Unary minus
        System.assertEquals(-5, FormulaCalculationService.evaluateFormulaPublic('-5'));
        // Parentheses
        System.assertEquals(20, FormulaCalculationService.evaluateFormulaPublic('(2+3)*4'));
        // Nested parens
        System.assertEquals(14,
            FormulaCalculationService.evaluateFormulaPublic('((2+3)*2)+4'));
    }

    @isTest
    static void evaluateFormulaPublic_divisionByZeroThrows() {
        Boolean thrown = false;
        try {
            FormulaCalculationService.evaluateFormulaPublic('5/0');
        } catch (FormulaCalculationService.FormulaException e) {
            thrown = true;
        }
        System.assert(thrown, 'Division by zero should throw');
    }

    @isTest
    static void evaluateFormulaPublic_mismatchedParensThrows() {
        Boolean thrown = false;
        try {
            FormulaCalculationService.evaluateFormulaPublic('(1+2');
        } catch (FormulaCalculationService.FormulaException e) {
            thrown = true;
        }
        System.assert(thrown);
    }

    @isTest
    static void evaluateFormulaPublic_invalidNumberThrows() {
        Boolean thrown = false;
        try {
            FormulaCalculationService.evaluateFormulaPublic('abc');
        } catch (FormulaCalculationService.FormulaException e) {
            thrown = true;
        }
        System.assert(thrown);
    }

    // ── IF conditions (numeric + string) ────────────────────────────

    @isTest
    static void evaluateFormulaPublic_ifNumeric() {
        // IF (1>0, 10, 20)
        System.assertEquals(10,
            FormulaCalculationService.evaluateFormulaPublic('IF(1>0,10,20)'));
        System.assertEquals(20,
            FormulaCalculationService.evaluateFormulaPublic('IF(1<0,10,20)'));
        // Each operator
        System.assertEquals(10,
            FormulaCalculationService.evaluateFormulaPublic('IF(5>=5,10,20)'));
        System.assertEquals(10,
            FormulaCalculationService.evaluateFormulaPublic('IF(5<=5,10,20)'));
        System.assertEquals(10,
            FormulaCalculationService.evaluateFormulaPublic('IF(5==5,10,20)'));
        System.assertEquals(10,
            FormulaCalculationService.evaluateFormulaPublic('IF(5!=6,10,20)'));
    }

    @isTest
    static void evaluateFormulaPublic_ifString() {
        System.assertEquals(1,
            FormulaCalculationService.evaluateFormulaPublic('IF("a"=="a",1,2)'));
        System.assertEquals(2,
            FormulaCalculationService.evaluateFormulaPublic('IF("a"=="b",1,2)'));
        System.assertEquals(1,
            FormulaCalculationService.evaluateFormulaPublic('IF("a"!="b",1,2)'));
    }

    @isTest
    static void evaluateFormulaPublic_ifBadSyntaxThrows() {
        Boolean thrown = false;
        try {
            FormulaCalculationService.evaluateFormulaPublic('IF(1>0,10)'); // missing else
        } catch (FormulaCalculationService.FormulaException e) {
            thrown = true;
        }
        System.assert(thrown);
    }

    // ── calculateFromFlow (invocable) ───────────────────────────────

    @isTest
    static void calculateFromFlow_recordNotFound_errorOutput() {
        DuplicateConversionEngine.skipProcessing = true;
        // Use a valid Cost_Sheet__c Id then delete it so getRecordWithLookups → null
        Project__c proj = TestDataFactory.createProject('FCS-NF');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'FCS', '9800000001');
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = lead.Id);
        insert cs;
        Id csId = cs.Id;
        delete cs;

        FormulaCalculationService.FlowInput input = new FormulaCalculationService.FlowInput();
        input.targetRecordId = csId;

        Test.startTest();
        List<FormulaCalculationService.FlowOutput> outs =
            FormulaCalculationService.calculateFromFlow(
                new List<FormulaCalculationService.FlowInput>{ input }
            );
        Test.stopTest();
        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].success);
    }

    @isTest
    static void calculateFromFlow_noTemplate_errorOutput() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('FCS-NT');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'FCS2', '9800000002');
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = lead.Id);
        insert cs;

        FormulaCalculationService.FlowInput input = new FormulaCalculationService.FlowInput();
        input.targetRecordId = cs.Id;

        Test.startTest();
        List<FormulaCalculationService.FlowOutput> outs =
            FormulaCalculationService.calculateFromFlow(
                new List<FormulaCalculationService.FlowInput>{ input }
            );
        Test.stopTest();
        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].success);
        System.assert(outs[0].errorMessage != null);
    }

    @isTest
    static void calculateFromFlow_emptyInputs() {
        Test.startTest();
        List<FormulaCalculationService.FlowOutput> outs =
            FormulaCalculationService.calculateFromFlow(
                new List<FormulaCalculationService.FlowInput>()
            );
        Test.stopTest();
        System.assertEquals(0, outs.size());
    }

    @isTest
    static void calculateFromFlow_exceptionPathViaNullInput() {
        // A FlowInput with null targetRecordId triggers the catch block via
        // targetRecordId.getSObjectType() throwing NullPointerException.
        FormulaCalculationService.FlowInput input = new FormulaCalculationService.FlowInput();
        // leave targetRecordId null
        Test.startTest();
        List<FormulaCalculationService.FlowOutput> outs =
            FormulaCalculationService.calculateFromFlow(
                new List<FormulaCalculationService.FlowInput>{ input }
            );
        Test.stopTest();
        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].success);
    }

    // ── calculateRecords (trigger bulk entry) ───────────────────────

    @isTest
    static void calculateRecords_emptySourceIds_earlyReturn() {
        DuplicateConversionEngine.skipProcessing = true;
        // Target records with no source lookup set → sourceIds empty → early return
        Project__c proj = TestDataFactory.createProject('FCS-Empty');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'FCS3', '9800000003');
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = lead.Id);
        insert cs;
        List<Cost_Sheet__c> targets = new List<Cost_Sheet__c>{ cs };
        Test.startTest();
        FormulaCalculationService.calculateRecords(
            targets, 'Unit__c', 'Cost_Sheet__c', 'Unit__c'
        );
        Test.stopTest();
    }

    @isTest
    static void calculateRecords_sourceWithoutProjectOrTemplate() {
        DuplicateConversionEngine.skipProcessing = true;
        // Seed a Unit (source) but without a matching active template → each
        // target is skipped inside the per-record loop.
        Project__c proj = TestDataFactory.createProject('FCS');
        Tower__c t = TestDataFactory.createTower(proj.Id, 'F1');
        Unit__c unit = TestDataFactory.createUnit(proj.Id, t.Id, 'F-101');

        Lead__c lead = TestDataFactory.createLead(proj.Id, 'FCS4', '9800000004');
        Cost_Sheet__c cs = new Cost_Sheet__c(Unit__c = unit.Id, Lead__c = lead.Id);
        insert cs;

        cs = [SELECT Id, Unit__c FROM Cost_Sheet__c WHERE Id = :cs.Id];
        Test.startTest();
        FormulaCalculationService.calculateRecords(
            new List<Cost_Sheet__c>{ cs }, 'Unit__c', 'Cost_Sheet__c', 'Unit__c'
        );
        Test.stopTest();
        // No template → loop body skipped, no exception
    }

    // ── DTOs ────────────────────────────────────────────────────────

    @isTest
    static void dtos_setAndRead() {
        FormulaCalculationService.FlowInput i = new FormulaCalculationService.FlowInput();
        i.targetRecordId = UserInfo.getUserId();
        System.assertEquals(UserInfo.getUserId(), i.targetRecordId);

        FormulaCalculationService.FlowOutput o = new FormulaCalculationService.FlowOutput();
        o.success = true;
        o.targetRecordId = UserInfo.getUserId();
        o.message = 'm';
        o.errorMessage = 'e';
        System.assertEquals(true, o.success);
        System.assertEquals('m', o.message);
        System.assertEquals('e', o.errorMessage);

        FormulaCalculationService.FormulaException ex =
            new FormulaCalculationService.FormulaException('x');
        System.assertEquals('x', ex.getMessage());
    }

    // ── Additional formula evaluation tests ─────────────────────────

    @isTest
    static void evaluateFormulaPublic_complexArithmetic() {
        // Test order of operations
        System.assertEquals(11,
            FormulaCalculationService.evaluateFormulaPublic('2+3*3'));
        // Subtraction with preceding operator
        System.assertEquals(-3,
            FormulaCalculationService.evaluateFormulaPublic('2+-5'));
    }

    @isTest
    static void evaluateFormulaPublic_ifWithConditionFalse() {
        // Test condition that evaluates to false (no match)
        System.assertEquals(20,
            FormulaCalculationService.evaluateFormulaPublic('IF(0>1,10,20)'));
    }

    @isTest
    static void evaluateFormulaPublic_nestedIfFormula() {
        // Nested parentheses in IF
        System.assertEquals(6,
            FormulaCalculationService.evaluateFormulaPublic('IF(1>0,(2+4),(3+5))'));
    }

    @isTest
    static void evaluateFormulaPublic_stringNotEqual() {
        System.assertEquals(2,
            FormulaCalculationService.evaluateFormulaPublic('IF("x"!="x",1,2)'));
    }

    @isTest
    static void calculateRecords_withMultipleTargets() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('FCS-Multi');
        Tower__c t = TestDataFactory.createTower(proj.Id, 'FM1');
        Unit__c unit = TestDataFactory.createUnit(proj.Id, t.Id, 'FM-101');

        Lead__c lead1 = TestDataFactory.createLead(proj.Id, 'FM1', '9800000010');
        Lead__c lead2 = TestDataFactory.createLead(proj.Id, 'FM2', '9800000011');

        Cost_Sheet__c cs1 = new Cost_Sheet__c(Unit__c = unit.Id, Lead__c = lead1.Id);
        Cost_Sheet__c cs2 = new Cost_Sheet__c(Unit__c = unit.Id, Lead__c = lead2.Id);
        insert new List<Cost_Sheet__c>{ cs1, cs2 };

        List<Cost_Sheet__c> targets = [SELECT Id, Unit__c FROM Cost_Sheet__c WHERE Id IN (:cs1.Id, :cs2.Id)];

        Test.startTest();
        FormulaCalculationService.calculateRecords(
            targets, 'Unit__c', 'Cost_Sheet__c', 'Unit__c'
        );
        Test.stopTest();
    }
}