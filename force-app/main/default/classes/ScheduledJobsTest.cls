@isTest
private class ScheduledJobsTest {

    @isTest
    static void testUnitBlockExpiryBatch() {
        Project__c p = TestDataFactory.createProject('Test');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'A-101');
        Lead__c l = TestDataFactory.createLead(p.Id, 'John', '9876543210');

        u.Status__c = 'Blocked';
        u.Blocked_By_Lead__c = l.Id;
        u.Block_Expiry__c = Date.today().addDays(-1);
        update u;

        Test.startTest();
        Database.executeBatch(new UnitBlockExpiryBatch(), 200);
        Test.stopTest();

        Unit__c updated = [SELECT Status__c FROM Unit__c WHERE Id = :u.Id];
        System.assertEquals('Available', updated.Status__c);
    }

    @isTest
    static void testTempAssignmentExpiryBatch() {
        Project__c p = TestDataFactory.createProject('Test');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Lead__c l = TestDataFactory.createLead(p.Id, 'Jane', '9876543211');

        // Create Active Temporary history record (as tempAssignLeads would)
        Reassignment_History__c rh = new Reassignment_History__c();
        rh.Lead__c = l.Id;
        rh.Old_Owner__c = l.OwnerId;
        rh.New_Owner__c = UserInfo.getUserId();
        rh.Assigned_By__c = UserInfo.getUserId();
        rh.Reassigned_Date__c = System.now();
        rh.Reassignment_Type__c = 'Temporary';
        rh.Status__c = 'Active';
        rh.Ownership_Start_Date__c = System.now();
        rh.Entry_Status__c = 'New Enquiry';
        rh.Temp_Expiry__c = Date.today().addDays(-1);
        insert rh;

        l.Temp_Owner__c = UserInfo.getUserId();
        l.Temp_Start__c = Date.today().addDays(-7);
        l.Temp_Expiry__c = Date.today().addDays(-1);
        update l;

        Test.startTest();
        Database.executeBatch(new TempAssignmentExpiryBatch(), 200);
        Test.stopTest();

        Lead__c updated = [SELECT Temp_Owner__c, Temp_Start__c, Temp_Expiry__c FROM Lead__c WHERE Id = :l.Id];
        System.assertEquals(null, updated.Temp_Owner__c, 'Temp owner should be cleared');
        System.assertEquals(null, updated.Temp_Start__c, 'Temp start should be cleared');
        System.assertEquals(null, updated.Temp_Expiry__c, 'Temp expiry should be cleared');

        // Verify history record was updated in place (not a new record)
        List<Reassignment_History__c> histories = [
            SELECT Id, Status__c, Ownership_End_Date__c, Exit_Status__c
            FROM Reassignment_History__c
            WHERE Lead__c = :l.Id AND Reassignment_Type__c = 'Temporary'
        ];
        System.assertEquals(1, histories.size(), 'Should have exactly 1 temp history record (updated in place)');
        System.assertEquals(rh.Id, histories[0].Id, 'Should be the same record (updated, not new)');
        System.assertEquals('Expired', histories[0].Status__c, 'Status should be Expired');
        System.assertNotEquals(null, histories[0].Ownership_End_Date__c, 'End date should be set');
        System.assertEquals('Expired', histories[0].Exit_Status__c, 'Exit status should be Expired');
    }

    @isTest
    static void testCPCreditExpiryBatch() {
        TestDataFactory.createCPModuleConfig();

        Test.startTest();
        Database.executeBatch(new CPCreditExpiryBatch(), 200);
        Test.stopTest();
    }

    @isTest
    static void testUnitBlockExpirySchedulable() {
        Test.startTest();
        String jobId = System.schedule('Test Unit Block Expiry', '0 0 6 * * ?', new UnitBlockExpiryBatch());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }

    @isTest
    static void testTempAssignmentExpirySchedulable() {
        Test.startTest();
        String jobId = System.schedule('Test Temp Assignment Expiry', '0 0 6 * * ?', new TempAssignmentExpiryBatch());
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }
}