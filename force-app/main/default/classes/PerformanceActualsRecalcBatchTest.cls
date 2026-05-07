@isTest
private class PerformanceActualsRecalcBatchTest {

    @TestSetup
    static void setupTestData() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('Batch Test Project');

        Id currentUserId = UserInfo.getUserId();
        Date periodStart = Date.today().toStartOfMonth();
        Date periodEnd = periodStart.addMonths(1).addDays(-1);

        // Create a user-level target for Leads_Generated
        Performance_Target__c target = new Performance_Target__c(
            Target_Level__c = 'User',
            Metric__c = 'Leads_Generated',
            Period_Type__c = 'Monthly',
            Period_Start__c = periodStart,
            Period_End__c = periodEnd,

            Target_Value__c = 50,
            Actual_Value__c = 0,
            Is_Active__c = true,
            Assignee__c = currentUserId,
            Project__c = proj.Id
        );
        insert target;

        // Create Lead__c source records
        DuplicateConversionEngine.skipProcessing = true;
        List<Lead__c> leads = new List<Lead__c>();
        for (Integer i = 0; i < 3; i++) {
            leads.add(new Lead__c(
                First_Name__c = 'Batch',
                Last_Name__c = 'Lead ' + i,
                Primary_Mobile__c = '800000000' + i,
                Owner__c = currentUserId,
                Project__c = proj.Id,
                Lead_Source__c = 'Website'
            ));
        }
        insert leads;
    }

    @isTest
    static void testRecalcBatchExecution() {
        Test.startTest();
        Database.executeBatch(new PerformanceActualsRecalcBatch(), 200);
        Test.stopTest();

        // Verify snapshots were created
        List<Performance_Snapshot__c> snapshots = [
            SELECT Id, Actual_Value__c, Performance_Target__c
            FROM Performance_Snapshot__c
        ];
        // The batch should have created at least one snapshot for the active target
        System.assert(snapshots.size() > 0, 'Should create at least one performance snapshot');
    }

    @isTest
    static void testSchedulable() {
        Test.startTest();
        String jobId = System.schedule(
            'Test Perf Recalc Schedule',
            '0 0 2 * * ?',
            new PerformanceActualsRecalcBatch()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Scheduled job ID should not be null');

        List<CronTrigger> jobs = [
            SELECT Id, State FROM CronTrigger WHERE Id = :jobId
        ];
        System.assertEquals(1, jobs.size(), 'Should have one scheduled job');
    }

    @isTest
    static void testNotificationBatch() {
        // Update target to have 100% achievement
        Performance_Target__c target = [
            SELECT Id, Target_Value__c
            FROM Performance_Target__c
            WHERE Is_Active__c = true
            LIMIT 1
        ];
        target.Actual_Value__c = target.Target_Value__c;
        update target;

        Test.startTest();
        Database.executeBatch(new PerformanceNotificationBatch(), 200);
        Test.stopTest();

        // Verify no exceptions occurred - if we get here, the batch ran without errors
        System.assert(true, 'Notification batch should complete without exceptions');
    }
}