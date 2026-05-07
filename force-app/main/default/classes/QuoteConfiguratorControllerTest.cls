@isTest
private class QuoteConfiguratorControllerTest {

    @isTest
    static void testValidateFormula() {
        Test.startTest();
        String result = QuoteConfiguratorController.validateFormula('1 + 1');
        Test.stopTest();
        // Result depends on FormulaEvaluator implementation
        System.assertNotEquals(null, result, 'Should return a result');
    }

    @isTest
    static void testValidateFormulaError() {
        Test.startTest();
        String result = QuoteConfiguratorController.validateFormula(null);
        Test.stopTest();
        // Null formula may return error or be handled gracefully
        System.assertNotEquals(null, result);
    }

    @isTest
    static void testGetUnitNumericFields() {
        Project__c p = TestDataFactory.createProject('QCC Proj');

        Test.startTest();
        QuoteConfiguratorController.InitWrapper wrapper = QuoteConfiguratorController.getUnitNumericFields(p.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper, 'Should return init wrapper');
        System.assertNotEquals(null, wrapper.FieldInfos, 'Should return field infos');
        System.assert(wrapper.FieldInfos.size() > 0, 'Should have numeric fields on Unit__c');
    }

    @isTest
    static void testSaveFormulaRec() {
        Project__c p = TestDataFactory.createProject('QCC Save Proj');
        String formula = 'Base_Rate_Sqft__c * Carpet_Area__c';

        Test.startTest();
        QuoteConfiguratorController.saveFormulaRec(p.Id, formula);
        Test.stopTest();

        Project__c updated = [SELECT Quote_Calculation_Logic__c FROM Project__c WHERE Id = :p.Id];
        System.assertEquals(formula, updated.Quote_Calculation_Logic__c, 'Formula should be saved');
    }

    @isTest
    static void testInitWrapper() {
        QuoteConfiguratorController.InitWrapper w = new QuoteConfiguratorController.InitWrapper();
        w.FieldInfos = new List<QuoteConfiguratorController.FieldInfo>();
        w.QuoteCalculationLogic = 'test';
        System.assertEquals('test', w.QuoteCalculationLogic);
    }

    @isTest
    static void testFieldInfo() {
        QuoteConfiguratorController.FieldInfo fi = new QuoteConfiguratorController.FieldInfo('Label', 'API_Name__c');
        System.assertEquals('Label', fi.label);
        System.assertEquals('API_Name__c', fi.apiName);
    }
}