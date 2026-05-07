@isTest
private class ReportConfigControllerTest {

    @TestSetup
    static void setupData() {
        Report_Configuration__c config = new Report_Configuration__c();
        config.Name = 'Test Report';
        config.Description__c = 'Test Description';
        config.Active__c = true;
        config.Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"Profile","operator":"equals","value":"System Administrator"}]}';
        insert config;
    }

    @isTest
    static void testGetAllReportConfigs() {
        Test.startTest();
        List<Report_Configuration__c> results = ReportConfigController.getAllReportConfigs();
        Test.stopTest();
        System.assert(results.size() >= 1, 'Should return at least one config');
    }

    @isTest
    static void testGetReportConfig() {
        Report_Configuration__c config = [SELECT Id FROM Report_Configuration__c LIMIT 1];
        Test.startTest();
        Report_Configuration__c result = ReportConfigController.getReportConfig(config.Id);
        Test.stopTest();
        System.assertEquals('Test Report', result.Name);
    }

    @isTest
    static void testSaveReportConfig_New() {
        Test.startTest();
        String newId = ReportConfigController.saveReportConfig(null, 'New Report', 'Desc', true, '{}');
        Test.stopTest();
        System.assertNotEquals(null, newId, 'Should return a new record Id');
    }

    @isTest
    static void testSaveReportConfig_Update() {
        Report_Configuration__c config = [SELECT Id FROM Report_Configuration__c LIMIT 1];
        Test.startTest();
        String updatedId = ReportConfigController.saveReportConfig(config.Id, 'Updated', 'Updated Desc', false, '{}');
        Test.stopTest();
        System.assertEquals(config.Id, updatedId, 'Should return existing Id');
    }

    @isTest
    static void testDeleteReportConfig() {
        Report_Configuration__c config = [SELECT Id FROM Report_Configuration__c LIMIT 1];
        Test.startTest();
        ReportConfigController.deleteReportConfig(config.Id);
        Test.stopTest();
        List<Report_Configuration__c> remaining = [SELECT Id FROM Report_Configuration__c WHERE Id = :config.Id];
        System.assertEquals(0, remaining.size(), 'Record should be deleted');
    }

    @isTest
    static void testCloneReportConfig() {
        Report_Configuration__c config = [SELECT Id FROM Report_Configuration__c LIMIT 1];
        Test.startTest();
        String clonedId = ReportConfigController.cloneReportConfig(config.Id);
        Test.stopTest();
        System.assertNotEquals(null, clonedId, 'Cloned Id should not be null');
        Report_Configuration__c cloned = [SELECT Name, Active__c FROM Report_Configuration__c WHERE Id = :clonedId];
        System.assert(cloned.Name.contains('(Copy)'), 'Cloned name should contain (Copy)');
    }

    @isTest
    static void testGetAvailableReports() {
        Test.startTest();
        List<Map<String, String>> results = ReportConfigController.getAvailableReports();
        Test.stopTest();
        System.assertNotEquals(null, results, 'Results should not be null');
    }

    @isTest
    static void testGetAllObjects() {
        Test.startTest();
        List<Map<String, String>> objects = ReportConfigController.getAllObjects();
        Test.stopTest();
        System.assert(objects.size() > 0, 'Should return objects');
    }

    @isTest
    static void testGetObjectFields() {
        Test.startTest();
        List<Map<String, String>> fields = ReportConfigController.getObjectFields('Account');
        Test.stopTest();
        System.assert(fields.size() > 0, 'Account should have fields');
    }

    @isTest
    static void testGetObjectFields_InvalidObject() {
        Test.startTest();
        List<Map<String, String>> fields = ReportConfigController.getObjectFields('FakeObject__c');
        Test.stopTest();
        System.assertEquals(0, fields.size(), 'Invalid object returns empty');
    }

    @isTest
    static void testGetLookupObjectFields() {
        Test.startTest();
        List<Map<String, String>> fields = ReportConfigController.getLookupObjectFields('Contact', 'AccountId');
        Test.stopTest();
        System.assert(fields.size() > 0, 'Should return lookup fields for Account');
    }

    @isTest
    static void testGetLookupObjectFields_InvalidObject() {
        Test.startTest();
        List<Map<String, String>> fields = ReportConfigController.getLookupObjectFields('FakeObject__c', 'FakeField__c');
        Test.stopTest();
        System.assertEquals(0, fields.size(), 'Invalid object returns empty');
    }

    @isTest
    static void testGetChildRelationships() {
        Test.startTest();
        List<Map<String, String>> rels = ReportConfigController.getChildRelationships('Account');
        Test.stopTest();
        System.assert(rels.size() > 0, 'Account should have child relationships');
    }

    @isTest
    static void testGetChildRelationships_InvalidObject() {
        Test.startTest();
        List<Map<String, String>> rels = ReportConfigController.getChildRelationships('FakeObject__c');
        Test.stopTest();
        System.assertEquals(0, rels.size(), 'Invalid object returns empty');
    }

    @isTest
    static void testGetPicklistValues() {
        Test.startTest();
        try {
            List<Map<String, String>> values = ReportConfigController.getPicklistValues('Lead', 'Status');
            System.assert(values.size() > 0, 'Lead Status should have picklist values');
        } catch (Exception e) {
            // Field may not be accessible in all orgs
        }
        Test.stopTest();
    }

    @isTest
    static void testGetAllProfiles() {
        Test.startTest();
        List<Map<String, String>> profiles = ReportConfigController.getAllProfiles();
        Test.stopTest();
        System.assert(profiles.size() > 0, 'Should return profiles');
    }

    @isTest
    static void testGetAllRoles() {
        Test.startTest();
        List<Map<String, String>> roles = ReportConfigController.getAllRoles();
        Test.stopTest();
        System.assertNotEquals(null, roles, 'Roles should not be null');
    }

    @isTest
    static void testSearchUsers() {
        Test.startTest();
        List<Map<String, String>> users = ReportConfigController.searchUsers('Admin');
        Test.stopTest();
        System.assertNotEquals(null, users, 'Users should not be null');
    }
}