/**
 * @description Test class for DailyLogRecalculationBatch.
 * Covers batch execution and schedulable interface.
 */
@isTest
private class DailyLogRecalculationBatchTest {

    @isTest
    static void testBatchExecution() {
        Id userId = UserInfo.getUserId();

        // Ensure user has a shift set
        User u = new User(Id = userId, Shift__c = 'Day Shift', is_working__c = true, Availability__c = true);
        update u;

        // Create Daily Log parent (required for MD)
        Daily_Log__c log = new Daily_Log__c();
        log.Unique_Key__c = String.valueOf(userId) + '-' + String.valueOf(Date.today());
        log.User__c = userId;
        log.Log_Date__c = Date.today();
        log.Shift__c = 'Day Shift';
        insert log;

        // Insert availability history within last 24 hours
        Availability_History__c h1 = new Availability_History__c(
            User__c = userId,
            Is_Available__c = true,
            Changed_By__c = userId,
            Changed_Date__c = Datetime.now().addHours(-2),
            Daily_Log__c = log.Id
        );
        Availability_History__c h2 = new Availability_History__c(
            User__c = userId,
            Is_Available__c = false,
            Changed_By__c = userId,
            Changed_Date__c = Datetime.now().addHours(-1),
            Daily_Log__c = log.Id
        );
        insert new List<Availability_History__c>{ h1, h2 };

        Test.startTest();
        Database.executeBatch(new DailyLogRecalculationBatch(), 200);
        Test.stopTest();

        // Verify Daily Log was upserted with totals
        Daily_Log__c updatedLog = [
            SELECT Total_Available_Time__c, Total_Break_Time__c, Total_Session_Time__c
            FROM Daily_Log__c
            WHERE User__c = :userId
            AND Log_Date__c = :Date.today()
            LIMIT 1
        ];
        System.assertNotEquals(null, updatedLog, 'Daily Log should exist after batch');
        System.assert(updatedLog.Total_Available_Time__c > 0, 'Available time should be computed');
        System.assert(updatedLog.Total_Session_Time__c > 0, 'Session time should be computed');
    }

    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        String jobId = System.schedule(
            'Test DailyLog Recalc',
            '0 0 6 * * ?',
            new DailyLogRecalculationBatch()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled successfully');
    }
}