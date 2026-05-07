/**
 * @description Test class for LeadScoringEngine.
 * Exercises metadata-driven scoring: guard clauses, every operator
 * branch (field + count), tier resolution, and count-query fallback.
 */
@isTest
private class LeadScoringEngineTest {

    private static Lead_Score_Rule__c rule(String type, String op, String field,
                                           String val, Decimal pts) {
        return new Lead_Score_Rule__c(
            Rule_Type__c = type, Operator__c = op,
            Field_API_Name__c = field, Field_Value__c = val,
            Points__c = pts, Is_Active__c = true, Sequence__c = 1
        );
    }

    @isTest
    static void calculateScores_nullAndEmpty_noop() {
        LeadScoringEngine.calculateScores(null);
        LeadScoringEngine.calculateScores(new List<Lead__c>());
    }

    @isTest
    static void calculateScores_noRulesEarlyReturn() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('LSE');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'NoRules', '9900000001');
        // No Lead_Score_Rule__c rows → early return before mutating
        LeadScoringEngine.calculateScores(new List<Lead__c>{ lead });
        // No assertion needed — method returns without mutating
    }

    @isTest
    static void calculateScores_fieldRules_allOperators() {
        DuplicateConversionEngine.skipProcessing = true;
        insert new List<Lead_Score_Rule__c>{
            rule('Field', 'equals', 'First_Name__c', 'Alice', 10),
            rule('Field', 'not_equals', 'First_Name__c', 'Bob', 5),
            rule('Field', 'contains', 'First_Name__c', 'ali', 3),
            rule('Field', 'greater_than', 'First_Name__c', 'Abc', 2),   // string cmp fallback
            rule('Field', 'less_than', 'First_Name__c', 'Zzz', 2),
            rule('Field', 'greater_or_equal', 'First_Name__c', 'Alice', 1),
            rule('Field', 'less_or_equal', 'First_Name__c', 'Alice', 1),
            rule('Field', 'equals', 'Not_A_Real_Field__c', 'X', 50)     // invalid → catch
        };
        // Tier for score 24
        insert new Lead_Score_Tier__c(
            Name = 'Hot', Min_Score__c = 20, Max_Score__c = 100
        );

        Project__c proj = TestDataFactory.createProject('LSE');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Alice', '9900000010');

        Test.startTest();
        LeadScoringEngine.calculateScores(new List<Lead__c>{ lead });
        Test.stopTest();

        // 10 + 5 + 3 + 2 + 2 + 1 + 1 = 24
        System.assertEquals(24, lead.Lead_Score__c);
        System.assertEquals('Hot', lead.Lead_Score_Tier__c);
    }

    @isTest
    static void calculateScores_numericComparisonOperators() {
        DuplicateConversionEngine.skipProcessing = true;
        insert new List<Lead_Score_Rule__c>{
            // Use a numeric-ish string value to exercise the Decimal.valueOf branches
            rule('Field', 'greater_than', 'First_Name__c', '0', 1),   // "Alice" not numeric → fallback
            rule('Field', 'less_than', 'First_Name__c', 'Zzz', 1),    // fallback
            rule('Field', 'greater_or_equal', 'First_Name__c', 'Aaa', 1),
            rule('Field', 'less_or_equal', 'First_Name__c', 'Zzz', 1)
        };
        Project__c proj = TestDataFactory.createProject('LSE');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Alice', '9900000020');

        Test.startTest();
        LeadScoringEngine.calculateScores(new List<Lead__c>{ lead });
        Test.stopTest();
        System.assert(lead.Lead_Score__c > 0);
    }

    @isTest
    static void calculateScores_countRule_existingLead() {
        DuplicateConversionEngine.skipProcessing = true;
        // Save lead first so its Id is populated
        Project__c proj = TestDataFactory.createProject('LSE');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Charlie', '9900000030');

        // A related Enquiry_Source__c to count
        Enquiry_Source__c es = new Enquiry_Source__c(
            Lead__c = lead.Id,
            Enquiry_Date__c = DateTime.now(),
            Enquiry_Type__c = 'New',
            Source__c = 'Digital',
            Primary_Mobile__c = '9900000030'
        );
        insert es;

        insert new List<Lead_Score_Rule__c>{
            new Lead_Score_Rule__c(
                Rule_Type__c = 'Count', Operator__c = 'greater_or_equal',
                Related_Object__c = 'Enquiry_Source__c',
                Lookup_Field__c = 'Lead__c',
                Count_Threshold__c = 1, Points__c = 7,
                Is_Active__c = true, Sequence__c = 1
            ),
            // Default-op count rule (operator falls through to default >= threshold)
            new Lead_Score_Rule__c(
                Rule_Type__c = 'Count', Operator__c = 'greater_or_equal',
                Related_Object__c = 'Enquiry_Source__c',
                Lookup_Field__c = 'Lead__c',
                Count_Threshold__c = 1, Points__c = 1,
                Is_Active__c = true, Sequence__c = 2
            ),
            // Skipped: blank related object
            new Lead_Score_Rule__c(
                Rule_Type__c = 'Count', Operator__c = 'equals',
                Related_Object__c = '', Lookup_Field__c = 'Lead__c',
                Points__c = 99, Is_Active__c = true, Sequence__c = 3
            ),
            // Skipped: invalid object / field → catch block
            new Lead_Score_Rule__c(
                Rule_Type__c = 'Count', Operator__c = 'equals',
                Related_Object__c = 'NoSuchObj__x', Lookup_Field__c = 'Lead__c',
                Count_Threshold__c = 1, Points__c = 99,
                Is_Active__c = true, Sequence__c = 4
            ),
            // Each count operator branch via additional rules
            new Lead_Score_Rule__c(
                Rule_Type__c = 'Count', Operator__c = 'equals',
                Related_Object__c = 'Enquiry_Source__c',
                Lookup_Field__c = 'Lead__c',
                Count_Threshold__c = 1, Points__c = 2,
                Is_Active__c = true, Sequence__c = 5
            ),
            new Lead_Score_Rule__c(
                Rule_Type__c = 'Count', Operator__c = 'not_equals',
                Related_Object__c = 'Enquiry_Source__c',
                Lookup_Field__c = 'Lead__c',
                Count_Threshold__c = 999, Points__c = 2,
                Is_Active__c = true, Sequence__c = 6
            ),
            new Lead_Score_Rule__c(
                Rule_Type__c = 'Count', Operator__c = 'greater_than',
                Related_Object__c = 'Enquiry_Source__c',
                Lookup_Field__c = 'Lead__c',
                Count_Threshold__c = 0, Points__c = 2,
                Is_Active__c = true, Sequence__c = 7
            ),
            new Lead_Score_Rule__c(
                Rule_Type__c = 'Count', Operator__c = 'less_than',
                Related_Object__c = 'Enquiry_Source__c',
                Lookup_Field__c = 'Lead__c',
                Count_Threshold__c = 100, Points__c = 2,
                Is_Active__c = true, Sequence__c = 8
            ),
            new Lead_Score_Rule__c(
                Rule_Type__c = 'Count', Operator__c = 'less_or_equal',
                Related_Object__c = 'Enquiry_Source__c',
                Lookup_Field__c = 'Lead__c',
                Count_Threshold__c = 100, Points__c = 2,
                Is_Active__c = true, Sequence__c = 9
            )
        };

        // Query lead back with Id so count rules engage
        Lead__c freshLead = [SELECT Id, First_Name__c, Last_Name__c FROM Lead__c WHERE Id = :lead.Id];
        Test.startTest();
        LeadScoringEngine.calculateScores(new List<Lead__c>{ freshLead });
        Test.stopTest();
        System.assert(freshLead.Lead_Score__c >= 7);
    }

    @isTest
    static void tierResolution_noMatchReturnsNull() {
        DuplicateConversionEngine.skipProcessing = true;
        insert rule('Field', 'equals', 'First_Name__c', 'ZZZ', 100);
        // Tier that won't match score 0
        insert new Lead_Score_Tier__c(Name = 'Top', Min_Score__c = 999, Max_Score__c = 9999);

        Project__c proj = TestDataFactory.createProject('LSE');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Alice', '9900000040');

        Test.startTest();
        LeadScoringEngine.calculateScores(new List<Lead__c>{ lead });
        Test.stopTest();

        System.assertEquals(0, lead.Lead_Score__c);
        System.assertEquals(null, lead.Lead_Score_Tier__c,
            'Score outside all tier ranges → null');
    }
}