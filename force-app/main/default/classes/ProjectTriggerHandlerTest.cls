/**
 * @description Test class for ProjectTriggerHandler.
 * Covers before-delete (tower existence) and before-update (completion
 * with remaining Available/Blocked units) validation rules.
 */
@isTest
private class ProjectTriggerHandlerTest {

    @TestSetup
    static void setup() {
        TestDataFactory.createProject('PTH Project');
    }

    @isTest
    static void deleteSucceedsWithNoChildren() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        delete p;
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Project__c WHERE Id = :p.Id]);
    }

    @isTest
    static void deleteBlockedWhenTowersExist() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        TestDataFactory.createTower(p.Id, 'T1');

        Boolean thrown = false;
        Test.startTest();
        try {
            delete p;
        } catch (DmlException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Towers exist'),
                'Error should mention towers: ' + e.getMessage());
        }
        Test.stopTest();
        System.assert(thrown, 'Delete should be blocked');
    }

    @isTest
    static void updateNotChangingStatusSucceeds() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        p.Name = 'Renamed';
        update p;
        Test.stopTest();
    }

    @isTest
    static void completeSucceedsWithNoUnits() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Test.startTest();
        p.Project_Status__c = 'Completed';
        update p;
        Test.stopTest();
        p = [SELECT Project_Status__c FROM Project__c WHERE Id = :p.Id];
        System.assertEquals('Completed', p.Project_Status__c);
    }

    @isTest
    static void completeBlockedWhenAvailableUnitsExist() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        TestDataFactory.createUnit(p.Id, t.Id, 'U-101'); // default Status = Available

        Boolean thrown = false;
        Test.startTest();
        try {
            p.Project_Status__c = 'Completed';
            update p;
        } catch (DmlException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Available'),
                'Error should mention Available units: ' + e.getMessage());
        }
        Test.stopTest();
        System.assert(thrown, 'Completion should be blocked');
    }
}