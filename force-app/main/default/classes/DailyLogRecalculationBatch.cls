/**
 * @description Scheduled batch job to recompute Daily Log totals.
 * Safety net that runs twice daily (6 AM and 6 PM) to catch any missed
 * real-time updates (e.g., browser crash before logout upsert fired).
 * Uses shift-aware time windows per user.
 *
 * Schedule with:
 * System.schedule('DailyLog Recalc 6AM', '0 0 6 * * ?', new DailyLogRecalculationBatch());
 * System.schedule('DailyLog Recalc 6PM', '0 0 18 * * ?', new DailyLogRecalculationBatch());
 */
global class DailyLogRecalculationBatch implements Database.Batchable<sObject>, Schedulable {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Datetime last24h = Datetime.now().addHours(-24);
        return Database.getQueryLocator([
            SELECT Id, Shift__c
            FROM User
            WHERE IsActive = true
            AND Id IN (
                SELECT User__c
                FROM Availability_History__c
                WHERE Changed_Date__c >= :last24h
            )
        ]);
    }

    global void execute(Database.BatchableContext bc, List<User> scope) {
        Datetime now = Datetime.now();
        List<Daily_Log__c> logsToUpsert = new List<Daily_Log__c>();

        for (User u : scope) {
            String shiftName = String.isNotBlank(u.Shift__c) ? u.Shift__c : 'Day Shift';

            // Compute shift-aware window for current log date
            UserAvailabilityController.ShiftWindow sw = UserAvailabilityController.getShiftWindow(shiftName, now);

            // Query history for this user's window
            List<Availability_History__c> records = [
                SELECT Is_Available__c, Changed_Date__c, Is_Logout__c
                FROM Availability_History__c
                WHERE User__c = :u.Id
                AND Changed_Date__c >= :sw.windowStart
                AND Changed_Date__c <= :sw.windowEnd
                ORDER BY Changed_Date__c ASC
            ];

            // Compute time summary
            Datetime refTime = (now <= sw.windowEnd) ? now : sw.windowEnd;
            UserAvailabilityController.UserTimeSummary ts =
                UserAvailabilityController.computeTimeSummary(u.Id, '', records, refTime);

            // Build Daily Log record for upsert
            Daily_Log__c log = new Daily_Log__c();
            log.Unique_Key__c = String.valueOf(u.Id) + '-' + String.valueOf(sw.logDate);
            log.User__c = u.Id;
            log.Log_Date__c = sw.logDate;
            log.Shift__c = shiftName;
            log.Total_Available_Time__c = ts.totalAvailableSeconds;
            log.Total_Break_Time__c = ts.totalOfflineSeconds;
            log.Total_Session_Time__c = ts.totalSessionSeconds;
            logsToUpsert.add(log);
        }

        if (!logsToUpsert.isEmpty()) {
            Database.upsert(logsToUpsert, Daily_Log__c.Unique_Key__c, false);
        }
    }

    global void finish(Database.BatchableContext bc) {
        // Could send summary notification to admin
    }

    global void execute(SchedulableContext sc) {
        Database.executeBatch(new DailyLogRecalculationBatch(), 50);
    }
}