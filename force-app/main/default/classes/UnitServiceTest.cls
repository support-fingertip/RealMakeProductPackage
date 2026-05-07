@isTest
private class UnitServiceTest {

    @isTest
    static void testGetAvailableUnits() {
        Project__c p = TestDataFactory.createProject('Test');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        TestDataFactory.createUnit(p.Id, t.Id, 'A-101');
        TestDataFactory.createUnit(p.Id, t.Id, 'A-102');

        Test.startTest();
        List<Unit__c> units = UnitService.getAvailableUnits(p.Id, null);
        System.assertEquals(2, units.size(), 'Should return 2 available units');
        Test.stopTest();
    }

    @isTest
    static void testGetAvailableUnitsWithTowerFilter() {
        Project__c p = TestDataFactory.createProject('Test');
        Tower__c t1 = TestDataFactory.createTower(p.Id, 'T1');
        Tower__c t2 = TestDataFactory.createTower(p.Id, 'T2');
        TestDataFactory.createUnit(p.Id, t1.Id, 'A-101');
        TestDataFactory.createUnit(p.Id, t2.Id, 'B-101');

        Test.startTest();
        List<Unit__c> units = UnitService.getAvailableUnits(p.Id, t1.Id);
        System.assertEquals(1, units.size(), 'Should return 1 unit for tower T1');
        Test.stopTest();
    }

    @isTest
    static void testValidStatusTransition() {
        System.assertEquals(true, UnitService.isValidTransition('Available', 'Blocked'));
        System.assertEquals(true, UnitService.isValidTransition('Blocked', 'Available'));
        System.assertEquals(true, UnitService.isValidTransition('Blocked', 'Booked'));
        System.assertEquals(false, UnitService.isValidTransition('Available', 'Sold'));
        System.assertEquals(false, UnitService.isValidTransition('Sold', 'Available'));
    }

    @isTest
    static void testUnblockExpiredUnits() {
        Project__c p = TestDataFactory.createProject('Test');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'A-101');
        Lead__c l = TestDataFactory.createLead(p.Id, 'John', '9876543210');

        // Block the unit with past expiry
        u.Status__c = 'Blocked';
        u.Blocked_By_Lead__c = l.Id;
        u.Block_Expiry__c = Date.today().addDays(-1);
        update u;

        Test.startTest();
        UnitService.unblockExpiredUnits();
        Test.stopTest();

        Unit__c updated = [SELECT Status__c, Blocked_By_Lead__c FROM Unit__c WHERE Id = :u.Id];
        System.assertEquals('Available', updated.Status__c, 'Unit should be unblocked');
        System.assertEquals(null, updated.Blocked_By_Lead__c, 'Blocked_By_Lead should be cleared');
    }
}