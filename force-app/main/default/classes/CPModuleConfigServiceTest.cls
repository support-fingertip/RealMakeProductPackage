@isTest
private class CPModuleConfigServiceTest {

    @isTest
    static void testGetConfigReturnsActiveRecord() {
        TestDataFactory.createCPModuleConfig();

        Test.startTest();
        CP_Module_Config__c cfg = CPModuleConfigService.getConfig();
        Test.stopTest();

        System.assertNotEquals(null, cfg, 'Config should not be null');
        System.assertEquals('Channel Partner', cfg.CP_Source_Name__c);
        System.assertEquals(90, cfg.Credit_Expiry_Days__c);
        System.assertEquals('Pre Sales', cfg.Assignment_Type__c);
    }

    @isTest
    static void testGetConfigThrowsWhenMissing() {
        Boolean threw = false;

        Test.startTest();
        try {
            CPModuleConfigService.getConfig();
        } catch (CPModuleConfigService.CPModuleConfigException e) {
            threw = true;
            System.assert(e.getMessage().contains('No active CP Module Configuration found'));
        }
        Test.stopTest();

        System.assert(threw, 'Should throw when no config exists');
    }

    @isTest
    static void testConvenienceGetters() {
        TestDataFactory.createCPModuleConfig();

        Test.startTest();
        String sourceName = CPModuleConfigService.getCPSourceName();
        Set<String> activeStatuses = CPModuleConfigService.getCPActiveStatuses();
        Set<String> inactiveStatuses = CPModuleConfigService.getLeadInactiveStatuses();
        Integer creditDays = CPModuleConfigService.getCreditExpiryDays();
        Test.stopTest();

        System.assertEquals('Channel Partner', sourceName);
        System.assert(activeStatuses.contains('Approved'));
        System.assert(activeStatuses.contains('Active'));
        System.assert(inactiveStatuses.contains('Unqualified'));
        System.assert(inactiveStatuses.contains('Closed Lost'));
        System.assert(inactiveStatuses.contains('Booked'));
        System.assertEquals(90, creditDays);
    }

    @isTest
    static void testCacheClearance() {
        TestDataFactory.createCPModuleConfig();

        // First call caches
        CPModuleConfigService.getConfig();

        // Clear cache
        CPModuleConfigService.clearCache();

        // Should query again without error
        CP_Module_Config__c cfg = CPModuleConfigService.getConfig();
        System.assertNotEquals(null, cfg);
    }
}