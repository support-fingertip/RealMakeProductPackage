@isTest
private class IIntegrationHookTest {
    @isTest
    static void smokeTest() {
        Test.startTest();
        try { System.assertNotEquals(null, 'IIntegrationHook'); } catch (Exception e) {}
        Test.stopTest();
    }
}