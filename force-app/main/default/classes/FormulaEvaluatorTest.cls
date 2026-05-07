@isTest
private class FormulaEvaluatorTest {

    @isTest
    static void testEvaluate_Addition() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('1+2', unit);
        Test.stopTest();
        System.assertEquals(3, result, '1+2 should equal 3');
    }

    @isTest
    static void testEvaluate_Subtraction() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('3-1', unit);
        Test.stopTest();
        System.assertEquals(2, result, '3-1 should equal 2');
    }

    @isTest
    static void testEvaluate_Multiplication() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('10*5', unit);
        Test.stopTest();
        System.assertEquals(50, result, '10*5 should equal 50');
    }

    @isTest
    static void testEvaluate_Division() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('100/4', unit);
        Test.stopTest();
        System.assertEquals(25, result, '100/4 should equal 25');
    }

    @isTest
    static void testEvaluate_DivisionByZero() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('10/0', unit);
        Test.stopTest();
        System.assertEquals(0, result, 'Division by zero should return 0');
    }

    @isTest
    static void testEvaluate_ComplexExpression() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('(2+3)*4', unit);
        Test.stopTest();
        System.assertEquals(20, result, '(2+3)*4 should equal 20');
    }

    @isTest
    static void testEvaluate_Precedence() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('2+3*4', unit);
        Test.stopTest();
        System.assertEquals(14, result, '2+3*4 should equal 14 (precedence)');
    }

    @isTest
    static void testEvaluate_BlankFormula() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('', unit);
        Test.stopTest();
        System.assertEquals(0, result, 'Blank formula should return 0');
    }

    @isTest
    static void testEvaluate_NullFormula() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate(null, unit);
        Test.stopTest();
        System.assertEquals(0, result, 'Null formula should return 0');
    }

    @isTest
    static void testEvaluate_NullUnit() {
        Test.startTest();
        try {
            FormulaEvaluator.evaluate('1+1', null);
            System.assert(false, 'Should throw exception for null unit');
        } catch (FormulaEvaluator.FormulaEvaluatorException e) {
            System.assert(e.getMessage().contains('null'), 'Should mention null');
        }
        Test.stopTest();
    }

    @isTest
    static void testEvaluate_Percentage() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('50%', unit);
        Test.stopTest();
        System.assertEquals(0.50, result, '50% should equal 0.50');
    }

    @isTest
    static void testEvaluate_UnaryMinus() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('-5+10', unit);
        Test.stopTest();
        System.assertEquals(5, result, '-5+10 should equal 5');
    }

    @isTest
    static void testEvaluate_Decimal() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('1.5+2.5', unit);
        Test.stopTest();
        System.assertEquals(4.0, result, '1.5+2.5 should equal 4.0');
    }

    @isTest
    static void testEvaluate_Function_ABS() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('ABS(-10)', unit);
        Test.stopTest();
        System.assertEquals(10, result, 'ABS(-10) should equal 10');
    }

    @isTest
    static void testEvaluate_Function_CEIL() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('CEIL(1.2)', unit);
        Test.stopTest();
        System.assertEquals(2, result, 'CEIL(1.2) should equal 2');
    }

    @isTest
    static void testEvaluate_Function_FLOOR() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('FLOOR(1.8)', unit);
        Test.stopTest();
        System.assertEquals(1, result, 'FLOOR(1.8) should equal 1');
    }

    @isTest
    static void testEvaluate_Function_ROUND() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('ROUND(1.456,2)', unit);
        Test.stopTest();
        System.assertEquals(1.46, result, 'ROUND(1.456,2) should equal 1.46');
    }

    @isTest
    static void testEvaluate_Function_MIN() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('MIN(3,7)', unit);
        Test.stopTest();
        System.assertEquals(3, result, 'MIN(3,7) should equal 3');
    }

    @isTest
    static void testEvaluate_Function_MAX() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('MAX(3,7)', unit);
        Test.stopTest();
        System.assertEquals(7, result, 'MAX(3,7) should equal 7');
    }

    @isTest
    static void testEvaluate_Function_POWER() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('POWER(2,3)', unit);
        Test.stopTest();
        System.assertEquals(8, result, 'POWER(2,3) should equal 8');
    }

    @isTest
    static void testEvaluate_UnsupportedFunction() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        try {
            FormulaEvaluator.evaluate('SQRT(4)', unit);
            System.assert(false, 'Should throw exception for unsupported function');
        } catch (FormulaEvaluator.FormulaEvaluatorException e) {
            System.assert(e.getMessage().contains('Unsupported'), 'Should mention unsupported');
        }
        Test.stopTest();
    }

    @isTest
    static void testEvaluate_InvalidCharacter() {
        Unit__c unit = new Unit__c();
        Test.startTest();
        try {
            FormulaEvaluator.evaluate('1&2', unit);
            System.assert(false, 'Should throw exception');
        } catch (FormulaEvaluator.FormulaEvaluatorException e) {
            System.assert(e.getMessage().contains('Invalid character'), 'Should mention invalid character');
        }
        Test.stopTest();
    }

    @isTest
    static void testEvaluate_WithUnitRecord() {
        Unit__c unit = new Unit__c();
        // Insert a unit record so we can test with field references
        try {
            insert unit;
            unit = [SELECT Id FROM Unit__c WHERE Id = :unit.Id LIMIT 1];
        } catch (Exception e) {
            // May fail due to required fields; use unsaved record
        }

        Test.startTest();
        Decimal result = FormulaEvaluator.evaluate('5*10', unit);
        Test.stopTest();
        System.assertEquals(50, result, '5*10 should equal 50');
    }

    @isTest
    static void testValidate_ValidFormula() {
        Test.startTest();
        String result = FormulaEvaluator.validate('1+2*3');
        Test.stopTest();
        System.assertEquals('VALID', result, 'Simple formula should be valid');
    }

    @isTest
    static void testValidate_BlankFormula() {
        Test.startTest();
        String result = FormulaEvaluator.validate('');
        Test.stopTest();
        System.assert(result.contains('empty'), 'Should indicate formula is empty');
    }

    @isTest
    static void testValidate_NullFormula() {
        Test.startTest();
        String result = FormulaEvaluator.validate(null);
        Test.stopTest();
        System.assert(result.contains('empty'), 'Should indicate formula is empty');
    }

    @isTest
    static void testValidate_InvalidField() {
        Test.startTest();
        String result = FormulaEvaluator.validate('FakeField__c+1');
        Test.stopTest();
        System.assert(result.contains('Error'), 'Should return error for invalid field');
    }

    @isTest
    static void testValidate_MismatchedParens() {
        Test.startTest();
        String result = FormulaEvaluator.validate('(1+2');
        Test.stopTest();
        System.assert(result.contains('Error'), 'Should return error for mismatched parens');
    }

    @isTest
    static void testValidate_WithFunction() {
        Test.startTest();
        String result = FormulaEvaluator.validate('ABS(1)+CEIL(2.5)');
        Test.stopTest();
        System.assertEquals('VALID', result, 'Formula with functions should be valid');
    }

    @isTest
    static void testValidate_ComplexFormula() {
        Test.startTest();
        String result = FormulaEvaluator.validate('ROUND(MAX(1,2)+MIN(3,4),0)');
        Test.stopTest();
        System.assertEquals('VALID', result, 'Complex formula should be valid');
    }
}