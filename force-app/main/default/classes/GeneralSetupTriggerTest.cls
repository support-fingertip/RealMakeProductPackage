/**
 * @description Test class for GeneralSetupTrigger (100% coverage).
 */
@isTest
private class GeneralSetupTriggerTest {
    @isTest
    static void insertAndUpdate() {
        Test.startTest();
        General_Setup__c gs = new General_Setup__c(Is_Active__c = false);
        insert gs;                      // before insert
        gs.Is_Active__c = true;
        update gs;                      // before update (activation)
        Test.stopTest();
    }
}