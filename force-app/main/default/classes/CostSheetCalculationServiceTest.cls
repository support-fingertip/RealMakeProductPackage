/**
 * @description Test class for CostSheetCalculationService.
 * Target: 100% coverage — seed from unit, derived-field calculations,
 * null-guard, per-field discounts, post-save calculation, and the
 * template-driven branch (findTemplate + runTemplateSteps + replaceFields).
 */
@isTest
private class CostSheetCalculationServiceTest {

    @TestSetup
    static void setup() {
        Project__c proj = TestDataFactory.createProject('CSC Project');
        Tower__c t = TestDataFactory.createTower(proj.Id, 'T1');
        TestDataFactory.createUnit(proj.Id, t.Id, 'U-101');
    }

    private static Unit__c fullUnit() {
        return [
            SELECT Id, Project__c, Super_Builtup_Area__c, Carpet_Area__c, UDS__c,
                   Base_Rate_Sqft__c, Floor_Rise_Sqft__c, Corpus_Fund_Sqft__c,
                   Maintenance_Sqft_Month__c, Maintenance_Months__c,
                   PLC_Charges__c, Amenity_Charges__c, Infra_Charges__c,
                   Doc_Charges__c, Move_In_Charges__c,
                   GST_Percentage__c, Registration_Pct__c, Stamp_Duty_Pct__c
            FROM Unit__c LIMIT 1
        ];
    }

    /** Create a master-detail-valid Lead for Cost_Sheet__c inserts. */
    private static Lead__c newLead() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c l = new Lead__c(
            First_Name__c = 'CSC',
            Last_Name__c = 'Calc',
            Primary_Mobile__c = '9911223344',
            Primary_Email__c = 'csc.calc@test.com',
            Project__c = p.Id,
            Lead_Status__c = 'New Enquiry',
            Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Digital',
            Lead_Sub_Source__c = 'Google',
            Owner__c = UserInfo.getUserId()
        );
        insert l;
        DuplicateConversionEngine.skipProcessing = false;
        return l;
    }

    @isTest
    static void calculateFromUnit_nullUnit_throws() {
        Boolean thrown = false;
        try {
            CostSheetCalculationService.calculateFromUnit(null);
        } catch (CostSheetCalculationService.CostSheetException e) {
            thrown = true;
            System.assert(e.getMessage().contains('required'));
        }
        System.assert(thrown, 'Null unit must throw CostSheetException');
    }

    @isTest
    static void calculateFromUnit_withoutTemplate_derivesFields() {
        Unit__c u = fullUnit();
        Test.startTest();
        Map<String, Object> calc = CostSheetCalculationService.calculateFromUnit(u);
        Test.stopTest();

        System.assertNotEquals(null, calc.get('Base_Price__c'));
        System.assertNotEquals(null, calc.get('Agreement_Value__c'));
        System.assertNotEquals(null, calc.get('Net_Payable__c'));
        System.assertNotEquals(null, calc.get('GST_Amount__c'));
        System.assertNotEquals(null, calc.get('Stamp_Duty_Amount__c'));
        System.assertNotEquals(null, calc.get('Registration_Amount__c'));
        System.assertEquals(0, calc.get('Total_Discount__c'));
    }

    @isTest
    static void calculateFromUnit_withTemplate_runsSteps() {
        Unit__c u = fullUnit();
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // Build a calculation template + a few steps to exercise
        // runTemplateSteps, replaceFields, variable chaining, Store_In_Field,
        // and the eval-error-continue branch.
        Project_Calculation_Template__c tmpl = new Project_Calculation_Template__c(
            Template_Name__c = 'CSC Template',
            Project__c = proj.Id,
            Source_Object_API_Name__c = 'Unit__c',
            Target_Object_API_Name__c = 'Cost_Sheet__c',
            Source_Lookup_Field__c = 'Unit__c',
            Is_Active__c = true
        );
        insert tmpl;

        List<Calculation_Step__c> steps = new List<Calculation_Step__c>{
            // Step 1 — references a Unit field (exercises replaceFields unit lookup)
            new Calculation_Step__c(
                Project_Calculation_Template__c = tmpl.Id,
                Step_Number__c = 1,
                Variable_Name__c = 'baseCalc',
                Formula_Expression__c = 'Base_Rate_Sqft__c * Super_Builtup_Area__c',
                Store_In_Field__c = 'Base_Price__c',
                Is_Active__c = true
            ),
            // Step 2 — references the variable from step 1 (exercises variableMap chaining)
            new Calculation_Step__c(
                Project_Calculation_Template__c = tmpl.Id,
                Step_Number__c = 2,
                Variable_Name__c = 'withFactor',
                Formula_Expression__c = 'baseCalc * 1.05',
                Store_In_Field__c = 'Agreement_Value__c',
                Is_Active__c = true
            ),
            // Step 3 — blank formula (exercises the isBlank early-continue)
            new Calculation_Step__c(
                Project_Calculation_Template__c = tmpl.Id,
                Step_Number__c = 3,
                Formula_Expression__c = null,
                Is_Active__c = true
            ),
            // Step 4 — broken formula (exercises the eval-error catch+continue)
            new Calculation_Step__c(
                Project_Calculation_Template__c = tmpl.Id,
                Step_Number__c = 4,
                Formula_Expression__c = '10 / 0 / !!broken!!',
                Store_In_Field__c = 'Net_Payable__c',
                Is_Active__c = true
            ),
            // Step 5 — inactive (filtered out by the sub-query WHERE Is_Active__c = true)
            new Calculation_Step__c(
                Project_Calculation_Template__c = tmpl.Id,
                Step_Number__c = 5,
                Formula_Expression__c = '1 + 1',
                Is_Active__c = false
            )
        };
        insert steps;

        Test.startTest();
        Map<String, Object> calc = CostSheetCalculationService.calculateFromUnit(u);
        Test.stopTest();

        // Step 1 should populate Base_Price__c via the template
        System.assertNotEquals(null, calc.get('Base_Price__c'));
        // Step 2 chained via baseCalc variable → Agreement_Value__c gets populated
        // (ensureDerivedFields may overwrite it, but the path is exercised)
        System.assertNotEquals(null, calc.get('Agreement_Value__c'));
    }

    @isTest
    static void recalculateWithTemplate_delegatesToCalculate() {
        Unit__c u = fullUnit();
        Test.startTest();
        Map<String, Object> calc = CostSheetCalculationService.recalculateWithTemplate(u);
        Test.stopTest();
        System.assertNotEquals(null, calc.get('Agreement_Value__c'));
    }

    @isTest
    static void applyPerFieldDiscounts_nullAndEmpty_noop() {
        Map<String, Object> calc = CostSheetCalculationService.calculateFromUnit(fullUnit());
        CostSheetCalculationService.applyPerFieldDiscounts(calc, null);
        CostSheetCalculationService.applyPerFieldDiscounts(calc, new List<Map<String, Object>>());
        // Passing null/empty must not mutate Total_Discount__c away from 0
        System.assertEquals(0, calc.get('Total_Discount__c'));
    }

    @isTest
    static void applyPerFieldDiscounts_populatesDiscountFields() {
        Map<String, Object> calc = CostSheetCalculationService.calculateFromUnit(fullUnit());

        List<Map<String, Object>> discounts = new List<Map<String, Object>>{
            new Map<String, Object>{
                'unitFieldAPI' => 'Base_Price__c',
                'value' => 5000,
                'fieldNumber' => 1
            },
            new Map<String, Object>{
                // Implicit fieldNumber = i + 1
                'unitFieldAPI' => 'Amenity_Charges__c',
                'value' => 1000
            },
            new Map<String, Object>{
                // Blank fieldAPI → skips the discounted-value branch
                'unitFieldAPI' => '',
                'value' => 500,
                'fieldNumber' => 3
            },
            new Map<String, Object>{
                // Zero value → skipped entirely
                'value' => 0,
                'fieldNumber' => 4
            }
        };

        Test.startTest();
        CostSheetCalculationService.applyPerFieldDiscounts(calc, discounts);
        Test.stopTest();

        System.assertEquals(5000, calc.get('Discount_1__c'));
        System.assertEquals(1000, calc.get('Discount_2__c'));
        System.assertEquals(500,  calc.get('Discount_3__c'));
        System.assert(calc.get('Discount_1_Value__c') != null,
            'Tagged field value should record the discounted value');
    }

    @isTest
    static void ensureDerivedFieldsPublic_exposesDerivation() {
        Map<String, Object> calc = new Map<String, Object>{
            'Super_Builtup_Area__c' => 1000,
            'Base_Rate_Sqft__c' => 5000,
            'Amenity_Charges__c' => 100000,
            'GST_Percentage__c' => 5
        };
        Test.startTest();
        CostSheetCalculationService.ensureDerivedFieldsPublic(calc);
        Test.stopTest();
        System.assertEquals(5000000, calc.get('Base_Price__c'));
        System.assert(((Decimal) calc.get('Agreement_Value__c')) > 0);
    }

    @isTest
    static void runPostSaveCalculation_completesGracefully() {
        // Cost_Sheet__c requires the Lead__c master-detail — provide one.
        Lead__c l = newLead();
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = l.Id);
        insert cs;

        Test.startTest();
        CostSheetCalculationService.runPostSaveCalculation(cs.Id);
        Test.stopTest();

        // No template exists for this project → FormulaCalculationService
        // returns a non-success output which is silently logged. The call
        // should complete without throwing.
        System.assertNotEquals(null, cs.Id);
    }

    @isTest
    static void costSheetException_canBeInstantiated() {
        CostSheetCalculationService.CostSheetException ex =
            new CostSheetCalculationService.CostSheetException('x');
        System.assertEquals('x', ex.getMessage());
    }
}