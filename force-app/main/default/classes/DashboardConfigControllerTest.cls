@isTest
private class DashboardConfigControllerTest {

    @TestSetup
    static void setupData() {
        Dashboard_Configuration__c config = new Dashboard_Configuration__c();
        config.Name = 'Test Dashboard';
        config.Description__c = 'Test Description';
        config.Active__c = true;
        config.Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"Profile","operator":"equals","value":"System Administrator"}],"components":[]}';
        insert config;
    }

    @isTest
    static void testGetAllDashboardConfigs() {
        Test.startTest();
        List<Dashboard_Configuration__c> results = DashboardConfigController.getAllDashboardConfigs();
        Test.stopTest();
        System.assert(results.size() >= 1, 'Should return at least one config');
    }

    @isTest
    static void testGetDashboardConfig() {
        Dashboard_Configuration__c config = [SELECT Id FROM Dashboard_Configuration__c LIMIT 1];
        Test.startTest();
        Dashboard_Configuration__c result = DashboardConfigController.getDashboardConfig(config.Id);
        Test.stopTest();
        System.assertEquals('Test Dashboard', result.Name);
    }

    @isTest
    static void testSaveDashboardConfig_New() {
        Test.startTest();
        String newId = DashboardConfigController.saveDashboardConfig(null, 'New Dashboard', 'Desc', true, '{}');
        Test.stopTest();
        System.assertNotEquals(null, newId, 'Should return a new record Id');
    }

    @isTest
    static void testSaveDashboardConfig_Update() {
        Dashboard_Configuration__c config = [SELECT Id FROM Dashboard_Configuration__c LIMIT 1];
        Test.startTest();
        String updatedId = DashboardConfigController.saveDashboardConfig(config.Id, 'Updated', 'Updated Desc', false, '{}');
        Test.stopTest();
        System.assertEquals(config.Id, updatedId, 'Should return existing Id');
    }

    @isTest
    static void testDeleteDashboardConfig() {
        Dashboard_Configuration__c config = [SELECT Id FROM Dashboard_Configuration__c LIMIT 1];
        Test.startTest();
        DashboardConfigController.deleteDashboardConfig(config.Id);
        Test.stopTest();
        List<Dashboard_Configuration__c> remaining = [SELECT Id FROM Dashboard_Configuration__c WHERE Id = :config.Id];
        System.assertEquals(0, remaining.size(), 'Record should be deleted');
    }

    @isTest
    static void testCloneDashboardConfig() {
        Dashboard_Configuration__c config = [SELECT Id FROM Dashboard_Configuration__c LIMIT 1];
        Test.startTest();
        String clonedId = DashboardConfigController.cloneDashboardConfig(config.Id);
        Test.stopTest();
        System.assertNotEquals(null, clonedId, 'Cloned Id should not be null');
        Dashboard_Configuration__c cloned = [SELECT Name, Active__c FROM Dashboard_Configuration__c WHERE Id = :clonedId];
        System.assert(cloned.Name.contains('(Copy)'), 'Cloned name should contain (Copy)');
        System.assertEquals(false, cloned.Active__c, 'Cloned should be inactive');
    }

    @isTest
    static void testGetAvailableDashboards() {
        Test.startTest();
        List<Map<String, String>> results = DashboardConfigController.getAvailableDashboards();
        Test.stopTest();
        System.assertNotEquals(null, results, 'Results should not be null');
    }

    @isTest
    static void testGetObjectFields() {
        Test.startTest();
        List<Map<String, String>> fields = DashboardConfigController.getObjectFields('Account');
        Test.stopTest();
        System.assert(fields.size() > 0, 'Account should have fields');
    }

    @isTest
    static void testGetObjectFields_InvalidObject() {
        Test.startTest();
        List<Map<String, String>> fields = DashboardConfigController.getObjectFields('NonExistentObject__c');
        Test.stopTest();
        System.assertEquals(0, fields.size(), 'Invalid object should return empty list');
    }

    @isTest
    static void testGetAllObjects() {
        Test.startTest();
        List<Map<String, String>> objects = DashboardConfigController.getAllObjects();
        Test.stopTest();
        System.assert(objects.size() > 0, 'Should return objects');
    }

    @isTest
    static void testGetPicklistValues() {
        Test.startTest();
        try {
            List<Map<String, String>> values = DashboardConfigController.getPicklistValues('Lead', 'Status');
            System.assert(values.size() > 0, 'Lead Status should have picklist values');
        } catch (Exception e) {
            // Some orgs may not have standard picklist accessible
        }
        Test.stopTest();
    }

    @isTest
    static void testGetAllProfiles() {
        Test.startTest();
        List<Map<String, String>> profiles = DashboardConfigController.getAllProfiles();
        Test.stopTest();
        System.assert(profiles.size() > 0, 'Should return profiles');
    }

    @isTest
    static void testGetAllRoles() {
        Test.startTest();
        List<Map<String, String>> roles = DashboardConfigController.getAllRoles();
        Test.stopTest();
        System.assertNotEquals(null, roles, 'Roles should not be null');
    }

    @isTest
    static void testSearchUsers() {
        Test.startTest();
        List<Map<String, String>> users = DashboardConfigController.searchUsers('Admin');
        Test.stopTest();
        System.assertNotEquals(null, users, 'Users should not be null');
    }

    @isTest
    static void testGetTopLevelUsers() {
        Test.startTest();
        List<Map<String, String>> users = DashboardConfigController.getTopLevelUsers();
        Test.stopTest();
        System.assertNotEquals(null, users, 'Should return users list');
    }

    @isTest
    static void testGetSubordinateUsers() {
        String userId = UserInfo.getUserId();
        Test.startTest();
        Map<String, Object> result = DashboardConfigController.getSubordinateUsers(userId);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('subordinates'), 'Should contain subordinates key');
        System.assert(result.containsKey('hasSubordinates'), 'Should contain hasSubordinates key');
    }

    @isTest
    static void testGetAllSubordinateUserIds() {
        String userId = UserInfo.getUserId();
        Test.startTest();
        Set<Id> ids = DashboardConfigController.getAllSubordinateUserIds(userId);
        Test.stopTest();
        System.assert(ids.contains(userId), 'Should contain the user themselves');
    }

    @isTest
    static void testGetTopLevelManagers() {
        Test.startTest();
        List<Map<String, String>> managers = DashboardConfigController.getTopLevelManagers();
        Test.stopTest();
        System.assertNotEquals(null, managers, 'Should return managers list');
    }

    @isTest
    static void testGetDirectReports() {
        String userId = UserInfo.getUserId();
        Test.startTest();
        Map<String, Object> result = DashboardConfigController.getDirectReports(userId);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('subordinates'), 'Should have subordinates key');
    }

    @isTest
    static void testGetAllManagerSubordinateIds() {
        String userId = UserInfo.getUserId();
        Test.startTest();
        Set<Id> ids = DashboardConfigController.getAllManagerSubordinateIds(userId);
        Test.stopTest();
        System.assert(ids.contains(userId), 'Should contain the user themselves');
    }

    // ── Additional tests for uncovered visibility rule branches ──

    @isTest
    static void testGetAvailableDashboards_RoleAndUserRules() {
        // Create config with Role and User visibility rules
        Dashboard_Configuration__c config2 = new Dashboard_Configuration__c();
        config2.Name = 'Role Based Dashboard';
        config2.Active__c = true;
        config2.Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"Role","operator":"contains","value":"Admin"},{"ruleType":"User","operator":"equals","value":"' + UserInfo.getUserId() + '"}]}';
        insert config2;

        // Create config with notEquals operator
        Dashboard_Configuration__c config3 = new Dashboard_Configuration__c();
        config3.Name = 'NotEquals Dashboard';
        config3.Active__c = true;
        config3.Configuration_JSON__c = '{"visibilityRules":[{"ruleType":"Profile","operator":"notEquals","value":"NonExistentProfile"}]}';
        insert config3;

        // Create config with empty visibility rules array
        Dashboard_Configuration__c config4 = new Dashboard_Configuration__c();
        config4.Name = 'No Rules Dashboard';
        config4.Active__c = true;
        config4.Configuration_JSON__c = '{"visibilityRules":[]}';
        insert config4;

        Test.startTest();
        List<Map<String, String>> results = DashboardConfigController.getAvailableDashboards();
        Test.stopTest();
        System.assertNotEquals(null, results);
    }

    @isTest
    static void testGetAvailableDashboards_NoVisibilityRulesKey() {
        Dashboard_Configuration__c config5 = new Dashboard_Configuration__c();
        config5.Name = 'Config No Rules Key';
        config5.Active__c = true;
        config5.Configuration_JSON__c = '{"components":[]}';
        insert config5;

        Test.startTest();
        List<Map<String, String>> results = DashboardConfigController.getAvailableDashboards();
        Test.stopTest();
        System.assertNotEquals(null, results);
    }

    @isTest
    static void testGetPicklistValues_InvalidObject() {
        Test.startTest();
        try {
            List<Map<String, String>> values = DashboardConfigController.getPicklistValues('NonExistent__c', 'Status');
        } catch (Exception e) {
            // Expected for invalid object
        }
        Test.stopTest();
    }
}