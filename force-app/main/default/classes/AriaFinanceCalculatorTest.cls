@isTest
private class AriaFinanceCalculatorTest {

    @isTest
    static void emi_50_lakh_8pt5_20y() {
        Map<String, Object> r = AriaFinanceCalculator.calculateEmi(5000000, 8.5, 240);
        Decimal emi = (Decimal) r.get('monthly_emi');
        System.assert(emi > 43000 && emi < 44000, 'EMI ~43391 for 50L@8.5%/20y. Got: ' + emi);
        System.assert((Decimal) r.get('total_interest') > 0);
        System.assert((Decimal) r.get('total_payable') > 5000000);
    }

    @isTest
    static void emi_invalid_principal_returns_error() {
        Map<String, Object> r = AriaFinanceCalculator.calculateEmi(0, 8.5, 240);
        System.assertNotEquals(null, r.get('error'));
    }

    @isTest
    static void loan_eligibility_standard() {
        Map<String, Object> r = AriaFinanceCalculator.calculateLoanEligibility(
            100000, 10000, 8.5, 240
        );
        Decimal eligible = (Decimal) r.get('eligible_amount');
        System.assert(eligible > 0, 'Should be eligible for some loan amount');
        System.assertEquals(40000.0, (Decimal) r.get('max_emi'));
    }

    @isTest
    static void loan_eligibility_all_foir_consumed() {
        Map<String, Object> r = AriaFinanceCalculator.calculateLoanEligibility(
            100000, 55000, 8.5, 240
        );
        System.assertEquals(0, (Decimal) r.get('eligible_amount'));
    }

    @isTest
    static void cost_breakdown_happy_path() {
        Project__c p = TestDataFactory.createProject('Finance Test');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'F-101');

        Map<String, Object> r = AriaFinanceCalculator.getCostBreakdown(u.Id);
        System.assertNotEquals(null, r.get('grand_total'));
        System.assert((Decimal) r.get('grand_total') > 0);
        System.assertEquals('2BHK', r.get('bhk'));
    }

    @isTest
    static void cost_breakdown_null_unit_returns_error() {
        Map<String, Object> r = AriaFinanceCalculator.getCostBreakdown(null);
        System.assertNotEquals(null, r.get('error'));
    }
}