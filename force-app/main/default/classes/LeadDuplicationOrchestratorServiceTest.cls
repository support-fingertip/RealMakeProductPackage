@isTest
private class LeadDuplicationOrchestratorServiceTest {

    @TestSetup
    static void setup() {
        Project__c proj = TestDataFactory.createProject('Dedup Project');
        TestDataFactory.createLead(proj.Id, 'Existing', '9200000001');
    }

    @isTest
    static void testGetActiveRuleType_MobileOnly() {
        // Create config with mobile-only expression
        Duplication_Configuration__c config = new Duplication_Configuration__c(
            Primary_Object_API_Name__c = 'Lead__c',
            Primary_Expression__c = 'Primary_Mobile__c | Secondary_Mobile__c',
            Active__c = true
        );
        insert config;

        Test.startTest();
        String ruleType = LeadDuplicationOrchestratorService.getActiveRuleType();
        Test.stopTest();

        System.assertEquals('MOBILE_ONLY', ruleType);
    }

    @isTest
    static void testGetActiveRuleType_MobileProject() {
        Duplication_Configuration__c config = new Duplication_Configuration__c(
            Primary_Object_API_Name__c = 'Lead__c',
            Primary_Expression__c = '(Primary_Mobile__c | Secondary_Mobile__c) + Project__c',
            Active__c = true
        );
        insert config;

        Test.startTest();
        String ruleType = LeadDuplicationOrchestratorService.getActiveRuleType();
        Test.stopTest();

        System.assertEquals('MOBILE_PROJECT', ruleType);
    }

    @isTest
    static void testGetActiveRuleType_NoConfig() {
        Test.startTest();
        String ruleType = LeadDuplicationOrchestratorService.getActiveRuleType();
        Test.stopTest();

        System.assertEquals(null, ruleType);
    }

    @isTest
    static void testCheckDuplicate_MobileOnly_SameProject() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Duplication_Configuration__c config = new Duplication_Configuration__c(
            Primary_Object_API_Name__c = 'Lead__c',
            Primary_Expression__c = 'Primary_Mobile__c | Secondary_Mobile__c',
            Active__c = true
        );
        insert config;

        Test.startTest();
        LeadDuplicationOrchestratorService.DuplicationResult result =
            LeadDuplicationOrchestratorService.checkDuplicate('9200000001', null, proj.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertNotEquals('NO_DUPLICATE', result.action);
        System.assertNotEquals(null, result.existingLeadId);
    }

    @isTest
    static void testCheckDuplicate_MobileOnly_DifferentProject() {
        Project__c projB = TestDataFactory.createProject('Other Project');

        Duplication_Configuration__c config = new Duplication_Configuration__c(
            Primary_Object_API_Name__c = 'Lead__c',
            Primary_Expression__c = 'Primary_Mobile__c | Secondary_Mobile__c',
            Active__c = true
        );
        insert config;

        Test.startTest();
        LeadDuplicationOrchestratorService.DuplicationResult result =
            LeadDuplicationOrchestratorService.checkDuplicate('9200000001', null, projB.Id);
        Test.stopTest();

        System.assertEquals('CROSS_PROJECT_SV', result.action);
    }

    @isTest
    static void testCheckDuplicate_NoDuplicate() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Duplication_Configuration__c config = new Duplication_Configuration__c(
            Primary_Object_API_Name__c = 'Lead__c',
            Primary_Expression__c = 'Primary_Mobile__c | Secondary_Mobile__c',
            Active__c = true
        );
        insert config;

        Test.startTest();
        LeadDuplicationOrchestratorService.DuplicationResult result =
            LeadDuplicationOrchestratorService.checkDuplicate('9999999999', null, proj.Id);
        Test.stopTest();

        System.assertEquals('NO_DUPLICATE', result.action);
    }

    @isTest
    static void testCheckDuplicate_NoConfig() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        LeadDuplicationOrchestratorService.DuplicationResult result =
            LeadDuplicationOrchestratorService.checkDuplicate('9200000001', null, proj.Id);
        Test.stopTest();

        System.assertEquals('NEW', result.action);
    }

    @isTest
    static void testParseRuleType() {
        System.assertEquals('MOBILE_ONLY',
            LeadDuplicationOrchestratorService.parseRuleType('Primary_Mobile__c | Secondary_Mobile__c'));
        System.assertEquals('MOBILE_PROJECT',
            LeadDuplicationOrchestratorService.parseRuleType('(Primary_Mobile__c | Secondary_Mobile__c) + Project__c'));
        System.assertEquals('MOBILE_ONLY',
            LeadDuplicationOrchestratorService.parseRuleType(null));
        System.assertEquals('MOBILE_ONLY',
            LeadDuplicationOrchestratorService.parseRuleType(''));
    }
}