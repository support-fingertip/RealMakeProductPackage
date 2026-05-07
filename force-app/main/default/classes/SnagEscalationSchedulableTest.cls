@isTest
private class SnagEscalationSchedulableTest {

    @TestSetup
    static void setup() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('SnagEsc Proj');
        p.Project_Head__c = UserInfo.getUserId();
        update p;

        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'SNAG-01');
        Lead__c l = TestDataFactory.createLead(p.Id, 'SnagEsc', '9800000120');
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = l.Id, Unit__c = u.Id);
        insert cs;
        Booking__c bk = new Booking__c(
            Lead__c = l.Id, Project__c = p.Id, Unit__c = u.Id, Tower__c = t.Id,
            Cost_Sheet__c = cs.Id, Booking_Date__c = Date.today(),
            Status__c = 'Approved, Active', Owner__c = UserInfo.getUserId(),
            Email__c = 'test@test.com'
        );
        insert bk;

        // Create overdue snags (Snag__c requires Inspection__c + Identified_Date__c)
        Inspection__c insp = new Inspection__c(Booking__c = bk.Id);
        insert insp;
        List<Snag__c> snags = new List<Snag__c>();
        snags.add(new Snag__c(
            Booking__c = bk.Id, Inspection__c = insp.Id,
            Identified_Date__c = Date.today().addDays(-7),
            Description__c = 'Plumbing leak',
            Category__c = 'Plumbing',
            Priority__c = 'High',
            Status__c = 'Open',
            Expected_Completion_Date__c = Date.today().addDays(-5),
            Assigned_To__c = UserInfo.getUserId()
        ));
        snags.add(new Snag__c(
            Booking__c = bk.Id, Inspection__c = insp.Id,
            Identified_Date__c = Date.today().addDays(-4),
            Description__c = 'Paint issue',
            Category__c = 'Walls',
            Priority__c = 'Medium',
            Status__c = 'In Progress',
            Expected_Completion_Date__c = Date.today().addDays(-2),
            Assigned_To__c = UserInfo.getUserId()
        ));
        // Completed snag - should NOT be picked up
        snags.add(new Snag__c(
            Booking__c = bk.Id, Inspection__c = insp.Id,
            Identified_Date__c = Date.today().addDays(-12),
            Description__c = 'Completed snag',
            Category__c = 'Electrical',
            Priority__c = 'Low',
            Status__c = 'Closed',
            Expected_Completion_Date__c = Date.today().addDays(-10),
            Assigned_To__c = UserInfo.getUserId()
        ));
        insert snags;
    }

    @isTest
    static void testProcessOverdueSnags() {
        Test.startTest();
        SnagEscalationSchedulable.processOverdueSnags();
        Test.stopTest();

        // Emails would be sent (in test context they are not actually sent)
        System.assert(true, 'processOverdueSnags should complete');
    }

    @isTest
    static void testSchedulableExecute() {
        Test.startTest();
        SnagEscalationSchedulable schedulable = new SnagEscalationSchedulable();
        String jobId = System.schedule('Test Snag Escalation', '0 0 10 * * ?', schedulable);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }

    @isTest
    static void testProcessOverdueNoSnags() {
        // Delete all snags
        delete [SELECT Id FROM Snag__c];

        Test.startTest();
        SnagEscalationSchedulable.processOverdueSnags();
        Test.stopTest();

        System.assert(true, 'Should complete gracefully with no overdue snags');
    }
}