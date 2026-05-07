/**
 * @description Test class for ProjectTrigger (100% coverage).
 */
@isTest
private class ProjectTriggerTest {
    @isTest
    static void updateAndDelete() {
        Project__c p = TestDataFactory.createProject('PT');
        Test.startTest();
        p.Name = 'Renamed';
        update p;                       // before update
        delete p;                       // before delete
        Test.stopTest();
    }
}