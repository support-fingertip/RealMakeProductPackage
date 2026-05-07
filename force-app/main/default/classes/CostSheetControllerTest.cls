/**
 * @description Test class for CostSheetController (100% coverage).
 */
@isTest
private class CostSheetControllerTest {

    @TestSetup
    static void setup() {
        Project__c p = TestDataFactory.createProject('CSC');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T');
        TestDataFactory.createUnit(p.Id, t.Id, 'U-101');
        TestDataFactory.createLead(p.Id, 'CSC', '9900005001');
    }

    @isTest
    static void getLeadContext_nullAndNotFound() {
        Boolean thrown = false;
        try { CostSheetController.getLeadContext(null); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);

        thrown = false;
        try { CostSheetController.getLeadContext('a0W000000000001'); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void getLeadContext_success() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Test.startTest();
        Map<String, Object> ctx = CostSheetController.getLeadContext(lead.Id);
        Test.stopTest();
        System.assertEquals(lead.Id, ctx.get('leadId'));
    }

    @isTest
    static void searchUnits_branches() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];

        Boolean thrown = false;
        try { CostSheetController.searchUnits(null, ''); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);

        Test.startTest();
        System.assert(CostSheetController.searchUnits(p.Id, '').size() >= 1);
        System.assert(CostSheetController.searchUnits(p.Id, 'U').size() >= 1);
        CostSheetController.searchUnits(p.Id, null);
        Test.stopTest();
    }

    @isTest
    static void getUnitCalculation_branches() {
        Unit__c u = [SELECT Id FROM Unit__c LIMIT 1];
        Test.startTest();
        Map<String, Object> calc = CostSheetController.getUnitCalculation(u.Id);
        Test.stopTest();
        System.assertEquals(u.Id, calc.get('unitId'));

        // Null
        Boolean thrown = false;
        try { CostSheetController.getUnitCalculation(null); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);

        // Not found
        thrown = false;
        try {
            Unit__c temp = new Unit__c(
                Project__c = [SELECT Id FROM Project__c LIMIT 1].Id,
                Tower__c = [SELECT Id FROM Tower__c LIMIT 1].Id,
                Unit_Number__c = 'TMP',
                Unit_Type__c = 'Apartment', BHK_Type__c = '2BHK',
                Facing__c = 'North', Status__c = 'Available',
                Super_Builtup_Area__c = 1000, Base_Rate_Sqft__c = 5000
            );
            insert temp;
            Id tempId = temp.Id;
            delete temp;
            CostSheetController.getUnitCalculation(tempId);
        } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void recalculate_withAndWithoutDiscounts() {
        Unit__c u = [SELECT Id FROM Unit__c LIMIT 1];

        Test.startTest();
        Map<String, Object> r1 = CostSheetController.recalculate(u.Id, null);
        System.assertEquals(u.Id, r1.get('unitId'));

        Map<String, Object> r2 = CostSheetController.recalculate(u.Id,
            '[{"unitFieldAPI":"Base_Price__c","value":1000,"fieldNumber":1}]');
        System.assertNotEquals(null, r2.get('Discount_1__c'));
        Test.stopTest();

        Boolean thrown = false;
        try { CostSheetController.recalculate(null, null); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void getStandardMilestones_branches() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        // Empty project id
        System.assertEquals(0,
            CostSheetController.getStandardMilestones(null, null).size());

        // Add a master schedule row
        Master_Payment_Schedule__c mps = new Master_Payment_Schedule__c(
            Project__c = p.Id, Name = 'MS1', Percentage__c = 10,
            Payment_Type__c = 'On Booking', Sequence__c = 1,
            Is_Active__c = true
        );
        insert mps;

        Test.startTest();
        System.assert(CostSheetController.getStandardMilestones(null, p.Id).size() >= 1);
        Test.stopTest();
    }

    @isTest
    static void saveCostSheet_happyPath() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Unit__c u = [SELECT Id FROM Unit__c LIMIT 1];
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];

        String linesJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'milestoneName' => 'M1',
                'paymentPct' => 10,
                'amount' => null,
                'sequence' => 1,
                'dueDate' => String.valueOf(Date.today().addDays(30)),
                'status' => 'Planned'
            },
            new Map<String, Object>{
                'milestoneName' => 'M2',
                'paymentPct' => 90,
                'amount' => 1000000,
                'sequence' => 2,
                'dueDate' => String.valueOf(Date.today().addDays(60))
            }
        });

        String discountsJson = '[{"unitFieldAPI":"Base_Price__c","value":500,"fieldNumber":1,"label":"PromoDisc"}]';

        Test.startTest();
        Id csId = CostSheetController.saveCostSheet(
            lead.Id, u.Id, p.Id, 'Standard', linesJson, discountsJson
        );
        Test.stopTest();
        System.assertNotEquals(null, csId);
        System.assert([SELECT COUNT() FROM CS_Payment_Line__c WHERE Cost_Sheet__c = :csId] >= 2);
    }

    @isTest
    static void saveCostSheet_customPlanNoDiscount() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Unit__c u = [SELECT Id FROM Unit__c LIMIT 1];
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];

        Id csId = CostSheetController.saveCostSheet(
            lead.Id, u.Id, p.Id, 'Custom', '[]', null
        );
        System.assertNotEquals(null, csId);
    }

    @isTest
    static void saveCostSheet_unitNotFound_throws() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Unit__c tmp = new Unit__c(
            Project__c = p.Id, Tower__c = [SELECT Id FROM Tower__c LIMIT 1].Id,
            Unit_Number__c = 'TMP2', Unit_Type__c = 'Apartment', BHK_Type__c = '2BHK',
            Facing__c = 'North', Status__c = 'Available',
            Super_Builtup_Area__c = 1000, Base_Rate_Sqft__c = 5000
        );
        insert tmp; Id tmpId = tmp.Id; delete tmp;

        Boolean thrown = false;
        try {
            CostSheetController.saveCostSheet(lead.Id, tmpId, p.Id, 'Standard', '[]', null);
        } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void getCostSheetFieldConfig_runs() {
        Test.startTest();
        CostSheetController.getCostSheetFieldConfig();
        Test.stopTest();
    }

    @isTest
    static void paymentLineInputPojo() {
        CostSheetController.PaymentLineInput li = new CostSheetController.PaymentLineInput();
        li.milestoneName = 'M'; li.category = 'C';
        li.paymentPct = 10; li.amount = 100;
        li.sequence = 1; li.dueDate = Date.today();
        li.status = 'Planned'; li.constructionMilestoneId = null;
        System.assertEquals('M', li.milestoneName);
    }
}