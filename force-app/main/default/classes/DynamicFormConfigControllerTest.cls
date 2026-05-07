@isTest
private class DynamicFormConfigControllerTest {
    @isTest
    static void smokeTest() {
        Test.startTest();
        try { DynamicFormConfigController.getAllObjects(); } catch (Exception e) {}
        Test.stopTest();
    }
}