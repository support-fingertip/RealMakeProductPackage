@isTest
private class ProjectServiceTest {

    @isTest
    static void testPreventDeletionWithTowers() {
        Project__c p = TestDataFactory.createProject('Test Project');
        Tower__c t = TestDataFactory.createTower(p.Id, 'Tower A');

        Test.startTest();
        try {
            delete p;
            System.assert(false, 'Should have thrown exception');
        } catch (Exception e) {
            System.assert(
                e.getMessage().contains('Towers exist') ||
                e.getMessage().contains('FIELD_INTEGRITY_EXCEPTION') ||
                e.getMessage().contains('Cannot delete'),
                'Expected deletion prevention. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @isTest
    static void testPreventCompletionWithAvailableUnits() {
        Project__c p = TestDataFactory.createProject('Test Project');
        Tower__c t = TestDataFactory.createTower(p.Id, 'Tower A');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'A-101');

        Test.startTest();
        p.Project_Status__c = 'Completed';
        try {
            update p;
            System.assert(false, 'Should have thrown error');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('Cannot mark project as Completed') ||
                          e.getMessage().contains('Available or Blocked'),
                          'Expected completion prevention. Got: ' + e.getMessage());
        }
        Test.stopTest();
    }
}