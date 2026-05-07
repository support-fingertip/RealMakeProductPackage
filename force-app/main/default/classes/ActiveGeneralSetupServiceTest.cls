@isTest
private class ActiveGeneralSetupServiceTest {

    @isTest
    static void noActiveSetupReturnsNullAndDisallows() {
        ActiveGeneralSetupService.clearCache();
        Test.startTest();
        System.assertEquals(null, ActiveGeneralSetupService.getActiveSetup(),
            'No active setup should return null');
        System.assertEquals(false, ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed(),
            'No active setup should disallow cross-project');
        Test.stopTest();
    }

    @isTest
    static void mobileOnlyAllowsCrossProject() {
        insert new General_Setup__c(
            Is_Active__c = true,
            Lead_Duplication_Type__c = 'Mobile Only'
        );
        ActiveGeneralSetupService.clearCache();

        Test.startTest();
        System.assertEquals(true, ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed(),
            'Mobile Only should allow cross-project');
        System.assertNotEquals(null, ActiveGeneralSetupService.getActiveSetup());
        Test.stopTest();
    }

    @isTest
    static void mobileWithProjectDisallowsCrossProject() {
        insert new General_Setup__c(
            Is_Active__c = true,
            Lead_Duplication_Type__c = 'Mobile with Project'
        );
        ActiveGeneralSetupService.clearCache();

        Test.startTest();
        System.assertEquals(false, ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed(),
            'Mobile with Project should disallow cross-project');
        Test.stopTest();
    }

    @isTest
    static void mobileWithProjectAndEmailDisallowsCrossProject() {
        insert new General_Setup__c(
            Is_Active__c = true,
            Lead_Duplication_Type__c = 'Mobile with Project & Email with Project'
        );
        ActiveGeneralSetupService.clearCache();

        Test.startTest();
        System.assertEquals(false, ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed(),
            'Mobile with Project & Email with Project should disallow cross-project');
        Test.stopTest();
    }

    @isTest
    static void activeSetupWithoutDuplicationTypeDisallows() {
        insert new General_Setup__c(Is_Active__c = true);
        ActiveGeneralSetupService.clearCache();

        Test.startTest();
        System.assertEquals(false, ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed(),
            'Active setup without duplication type should disallow');
        Test.stopTest();
    }

    @isTest
    static void cachingAvoidsSecondQuery() {
        insert new General_Setup__c(
            Is_Active__c = true,
            Lead_Duplication_Type__c = 'Mobile Only'
        );
        ActiveGeneralSetupService.clearCache();

        Test.startTest();
        Integer before = Limits.getQueries();
        ActiveGeneralSetupService.getActiveSetup();
        ActiveGeneralSetupService.getActiveSetup();
        ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed();
        Integer after = Limits.getQueries();
        Test.stopTest();

        System.assertEquals(1, after - before, 'Subsequent calls should hit the cache');
    }
}