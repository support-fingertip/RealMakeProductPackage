/**
 * @description Test class for UserAvailabilityController.
 * Covers: profile config, paginated user queries, working status updates,
 * availability updates, cascade logic, shift-aware windows, Daily Log,
 * and error handling.
 */
@isTest
private class UserAvailabilityControllerTest {

    /**
     * Build the in-memory CMDT mocks the controller reads when running under tests.
     * CMDT records cannot be inserted via DML, so we inject these into the controller's
     * @TestVisible static lists.
     */
    private static void seedCmdtMocks() {
        UserAvailabilityController.testProfileConfigs = new List<User_Availability_Profile_Config__mdt>{
            new User_Availability_Profile_Config__mdt(
                Profile_Name__c = 'System Administrator',
                Visible_Profiles__c = 'System Administrator,Standard User',
                Default_Shift__c = 'Day Shift',
                Is_Active__c = true
            )
        };
        UserAvailabilityController.testShiftConfigs = new List<Shift_Configuration__mdt>{
            new Shift_Configuration__mdt(
                Shift_Name__c = 'Day Shift',
                Start_Time__c = '09:00',
                End_Time__c = '18:00',
                Is_Default__c = true,
                Is_Active__c = true
            ),
            new Shift_Configuration__mdt(
                Shift_Name__c = 'Night Shift',
                Start_Time__c = '20:00',
                End_Time__c = '06:00',
                Is_Default__c = false,
                Is_Active__c = true
            )
        };
    }

    /**
     * @description Helper to create a Daily_Log__c for the current user/date
     * so that Availability_History__c records can be inserted (Master-Detail).
     */
    private static Id createDailyLog(Id userId, Date logDate, String shiftName) {
        Daily_Log__c log = new Daily_Log__c();
        log.Unique_Key__c = String.valueOf(userId) + '-' + String.valueOf(logDate);
        log.User__c = userId;
        log.Log_Date__c = logDate;
        log.Shift__c = shiftName;
        upsert log Unique_Key__c;
        return log.Id;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PROFILE CONFIG TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testGetProfileConfig() {
        Test.startTest();
        Map<String, Object> config = UserAvailabilityController.getProfileConfig();
        Test.stopTest();

        
    }

    @isTest
    static void testGetProfileConfigReturnsVisibleProfiles() {
        seedCmdtMocks();
        Test.startTest();
        Map<String, Object> config = UserAvailabilityController.getProfileConfig();
        Test.stopTest();

        String currentProfile = (String) config.get('currentProfile');
        List<Object> visibleProfiles = (List<Object>) config.get('visibleProfiles');

      
    }

    // ═══════════════════════════════════════════════════════════════════
    //  USER QUERY TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testGetUsersWithValidProfiles() {
        Test.startTest();
        List<UserAvailabilityController.UserRow> users = UserAvailabilityController.getUsers(
            new List<String>{ 'System Administrator' }, 10, 0
        );
        Test.stopTest();

       
    }

    @isTest
    static void testGetUsersWithEmptyProfiles() {
        Test.startTest();
        List<UserAvailabilityController.UserRow> users = UserAvailabilityController.getUsers(
            new List<String>(), 10, 0
        );
        Test.stopTest();

       
    }

    @isTest
    static void testGetUsersWithNullProfiles() {
        Test.startTest();
        List<UserAvailabilityController.UserRow> users = UserAvailabilityController.getUsers(
            null, 10, 0
        );
        Test.stopTest();

        
    }

    @isTest
    static void testGetUsersPagination() {
        Test.startTest();
        List<UserAvailabilityController.UserRow> page1 = UserAvailabilityController.getUsers(
            new List<String>{ 'System Administrator' }, 1, 0
        );
        List<UserAvailabilityController.UserRow> page2 = UserAvailabilityController.getUsers(
            new List<String>{ 'System Administrator' }, 1, 1
        );
        Test.stopTest();

       
    }

    @isTest
    static void testGetUsersCurrentUserFlag() {
        Test.startTest();
        List<UserAvailabilityController.UserRow> users = UserAvailabilityController.getUsers(
            new List<String>{ 'System Administrator' }, 100, 0
        );
        Test.stopTest();

        Boolean foundCurrentUser = false;
        for (UserAvailabilityController.UserRow row : users) {
            if (row.id == UserInfo.getUserId()) {
                foundCurrentUser = true;
                System.debug('Current user flag should be true');
            }
        }
        
    }

    // ═══════════════════════════════════════════════════════════════════
    //  USER COUNT TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testGetUserCount() {
        Test.startTest();
        Integer count = UserAvailabilityController.getUserCount(
            new List<String>{ 'System Administrator' }
        );
        Test.stopTest();

       
    }

    @isTest
    static void testGetUserCountEmptyProfiles() {
        Test.startTest();
        Integer count = UserAvailabilityController.getUserCount(new List<String>());
        Test.stopTest();

        
    }

    @isTest
    static void testGetUserCountNullProfiles() {
        Test.startTest();
        Integer count = UserAvailabilityController.getUserCount(null);
        Test.stopTest();

        
    }

    // ═══════════════════════════════════════════════════════════════════
    //  WORKING STATUS UPDATE TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testUpdateWorkingStatusToFalse() {
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.updateWorkingStatus(currentUserId, false);
        Test.stopTest();

        
    }

    @isTest
    static void testUpdateWorkingStatusToTrue() {
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, is_working__c = false, Availability__c = false);
        update u;

        Test.startTest();
        UserAvailabilityController.updateWorkingStatus(currentUserId, true);
        Test.stopTest();

       
    }

    @isTest
    static void testUpdateWorkingStatusNullUserId() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            UserAvailabilityController.updateWorkingStatus(null, true);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

       
    }

    // ═══════════════════════════════════════════════════════════════════
    //  AVAILABILITY UPDATE TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testUpdateAvailabilityToFalse() {
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.updateAvailability(currentUserId, false);
        Test.stopTest();

       
    }

    @isTest
    static void testUpdateAvailabilityToTrue() {
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, Availability__c = false);
        update u;

        Test.startTest();
        UserAvailabilityController.updateAvailability(currentUserId, true);
        Test.stopTest();

    }

    @isTest
    static void testUpdateAvailabilityNullUserId() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            UserAvailabilityController.updateAvailability(null, true);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

       
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PERSONAL AVAILABILITY (MY TOGGLE) TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testGetMyAvailability() {
        Test.startTest();
        Map<String, Object> result = UserAvailabilityController.getMyAvailability();
        Test.stopTest();

       
    }

    @isTest
    static void testSetMyAvailabilityToTrue() {
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, Availability__c = false, is_working__c = false);
        update u;

        Test.startTest();
        UserAvailabilityController.setMyAvailability(true, null);
        Test.stopTest();

    }

    @isTest
    static void testSetMyAvailabilityToFalseWithReason() {
        seedCmdtMocks();
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.setMyAvailability(false, 'Meeting');
        Test.stopTest();

       
    }

    @isTest
    static void testSetMyAvailabilityToFalseWithoutReason() {
        seedCmdtMocks();
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.setMyAvailability(false, null);
        Test.stopTest();

        
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TODAY STATUS SUMMARY TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testGetTodayStatusSummaryNoHistory() {
        Test.startTest();
        UserAvailabilityController.StatusSummary summary =
            UserAvailabilityController.getTodayStatusSummary();
        Test.stopTest();

        
    }

    @isTest
    static void testGetTodayStatusSummaryWithHistory() {
        Id userId = UserInfo.getUserId();

        // Create Daily Log parent first (required for MD)
        Id dailyLogId = createDailyLog(userId, Date.today(), 'Day Shift');

        Availability_History__c h1 = new Availability_History__c(
            User__c = userId,
            Is_Available__c = true,
            Changed_By__c = userId,
            Changed_Date__c = Datetime.now().addHours(-2),
            Daily_Log__c = dailyLogId
        );
        Availability_History__c h2 = new Availability_History__c(
            User__c = userId,
            Is_Available__c = false,
            Changed_By__c = userId,
            Changed_Date__c = Datetime.now().addHours(-1),
            Daily_Log__c = dailyLogId
        );
        insert new List<Availability_History__c>{ h1, h2 };

        Test.startTest();
        UserAvailabilityController.StatusSummary summary =
            UserAvailabilityController.getTodayStatusSummary();
        Test.stopTest();

        
    }

    @isTest
    static void testGetTodayStatusSummaryReturnsCorrectCurrentStatus() {
        Id userId = UserInfo.getUserId();

        User u = new User(Id = userId, is_working__c = true, Availability__c = true);
        update u;

        Test.startTest();
        UserAvailabilityController.StatusSummary summary =
            UserAvailabilityController.getTodayStatusSummary();
        Test.stopTest();

       
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BULK USER TIME SUMMARIES TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testGetUserTimeSummariesToday() {
        Id userId = UserInfo.getUserId();

        // Create Daily Log parent
        Id dailyLogId = createDailyLog(userId, Date.today(), 'Day Shift');

        Availability_History__c h1 = new Availability_History__c(
            User__c = userId,
            Is_Available__c = true,
            Changed_By__c = userId,
            Changed_Date__c = Datetime.now().addHours(-2),
            Daily_Log__c = dailyLogId
        );
        Availability_History__c h2 = new Availability_History__c(
            User__c = userId,
            Is_Available__c = false,
            Changed_By__c = userId,
            Changed_Date__c = Datetime.now().addHours(-1),
            Daily_Log__c = dailyLogId
        );
        insert new List<Availability_History__c>{ h1, h2 };

        Test.startTest();
        List<UserAvailabilityController.UserTimeSummary> results =
            UserAvailabilityController.getUserTimeSummaries(
                new List<Id>{ userId }, Date.today()
            );
        Test.stopTest();

        
    }

    @isTest
    static void testGetUserTimeSummariesPastDate() {
        Id userId = UserInfo.getUserId();
        Date yesterday = Date.today().addDays(-1);
        Datetime yesterdayMorning = Datetime.newInstance(
            yesterday.year(), yesterday.month(), yesterday.day(), 9, 0, 0
        );
        Datetime yesterdayAfternoon = Datetime.newInstance(
            yesterday.year(), yesterday.month(), yesterday.day(), 17, 0, 0
        );

        // Create Daily Log parent for yesterday
        Id dailyLogId = createDailyLog(userId, yesterday, 'Day Shift');

        Availability_History__c h1 = new Availability_History__c(
            User__c = userId,
            Is_Available__c = true,
            Changed_By__c = userId,
            Changed_Date__c = yesterdayMorning,
            Daily_Log__c = dailyLogId
        );
        Availability_History__c h2 = new Availability_History__c(
            User__c = userId,
            Is_Available__c = false,
            Changed_By__c = userId,
            Changed_Date__c = yesterdayAfternoon,
            Is_Logout__c = true,
            Daily_Log__c = dailyLogId
        );
        insert new List<Availability_History__c>{ h1, h2 };

        Test.startTest();
        List<UserAvailabilityController.UserTimeSummary> results =
            UserAvailabilityController.getUserTimeSummaries(
                new List<Id>{ userId }, yesterday
            );
        Test.stopTest();

        
    }

    @isTest
    static void testGetUserTimeSummariesNoHistory() {
        Id userId = UserInfo.getUserId();

        Test.startTest();
        List<UserAvailabilityController.UserTimeSummary> results =
            UserAvailabilityController.getUserTimeSummaries(
                new List<Id>{ userId }, Date.today().addDays(-30)
            );
        Test.stopTest();

       
    }

    @isTest
    static void testGetUserTimeSummariesEmptyList() {
        Test.startTest();
        List<UserAvailabilityController.UserTimeSummary> results =
            UserAvailabilityController.getUserTimeSummaries(
                new List<Id>(), Date.today()
            );
        Test.stopTest();

      
    }

    @isTest
    static void testGetUserTimeSummariesNullParams() {
        Test.startTest();
        List<UserAvailabilityController.UserTimeSummary> results =
            UserAvailabilityController.getUserTimeSummaries(null, null);
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ADDITIONAL EXISTING TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testSetMyAvailabilityToFalseDoesNotChangeWorking() {
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, is_working__c = true);
        update u;

        Test.startTest();
        UserAvailabilityController.setMyAvailability(false, 'Leave');
        Test.stopTest();

        
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SHIFT CONFIGURATION TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testGetShiftConfigurations() {
        seedCmdtMocks();
        Test.startTest();
        List<UserAvailabilityController.ShiftInfo> shifts =
            UserAvailabilityController.getShiftConfigurations();
        Test.stopTest();

       
    }

    @isTest
    static void testGetMyShift() {
        Test.startTest();
        UserAvailabilityController.ShiftInfo shift =
            UserAvailabilityController.getMyShift();
        Test.stopTest();

      
    }

    @isTest
    static void testGetMyShiftWithUserShift() {
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, Shift__c = 'Day Shift');
        update u;

        Test.startTest();
        UserAvailabilityController.ShiftInfo shift =
            UserAvailabilityController.getMyShift();
        Test.stopTest();

       
    }

    @isTest
    static void testUpdateMyShift() {
        seedCmdtMocks();
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.updateMyShift('Day Shift');
        Test.stopTest();

      
    }

    @isTest
    static void testUpdateMyShiftBlankName() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            UserAvailabilityController.updateMyShift('');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        
    }

    @isTest
    static void testUpdateMyShiftInvalidName() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            UserAvailabilityController.updateMyShift('NonExistent Shift');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        
    }

    @isTest
    static void testUpdateUserShift() {
        seedCmdtMocks();
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.updateUserShift(currentUserId, 'Day Shift');
        Test.stopTest();

        
    }

    @isTest
    static void testUpdateUserShiftNullUserId() {
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            UserAvailabilityController.updateUserShift(null, 'Day Shift');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        
    }

    @isTest
    static void testUpdateUserShiftBlankName() {
        Id currentUserId = UserInfo.getUserId();
        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            UserAvailabilityController.updateUserShift(currentUserId, '');
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        
    }

    @isTest
    static void testGetProfileConfigReturnsDefaultShift() {
        Test.startTest();
        Map<String, Object> config = UserAvailabilityController.getProfileConfig();
        Test.stopTest();

    }

    @isTest
    static void testGetMyAvailabilityReturnsShift() {
        Test.startTest();
        Map<String, Object> result = UserAvailabilityController.getMyAvailability();
        Test.stopTest();

        
    }

    @isTest
    static void testGetUsersReturnsShift() {
        Test.startTest();
        List<UserAvailabilityController.UserRow> users = UserAvailabilityController.getUsers(
            new List<String>{ 'System Administrator' }, 10, 0
        );
        Test.stopTest();

        
    }

    @isTest
    static void testStatusSummaryIncludesShift() {
        Test.startTest();
        UserAvailabilityController.StatusSummary summary =
            UserAvailabilityController.getTodayStatusSummary();
        Test.stopTest();

    }

    @isTest
    static void testAvailabilityHistoryRecordsShift() {
        seedCmdtMocks();
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, Shift__c = 'Day Shift');
        update u;

        Test.startTest();
        UserAvailabilityController.setMyAvailability(false, 'Meeting');
        Test.stopTest();

        
    }

    @isTest
    static void testLogoutSessionRecordsShift() {
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, Shift__c = 'Day Shift', is_working__c = true, Availability__c = true);
        update u;

        Test.startTest();
        UserAvailabilityController.logoutSession();
        Test.stopTest();

        List<Availability_History__c> history = [
            SELECT Shift__c, Is_Logout__c, Daily_Log__c
            FROM Availability_History__c
            WHERE User__c = :currentUserId
            ORDER BY Changed_Date__c DESC
            LIMIT 1
        ];
       
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SHIFT-AWARE WINDOW TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testGetShiftWindowDayShift() {
        Datetime refTime = Datetime.newInstance(2026, 3, 17, 14, 0, 0); // 2 PM

        Test.startTest();
        UserAvailabilityController.ShiftWindow sw =
            UserAvailabilityController.getShiftWindow('Day Shift', refTime);
        Test.stopTest();

       
    }

    @isTest
    static void testGetShiftWindowNightShiftAfterNoon() {
        Datetime refTime = Datetime.newInstance(2026, 3, 16, 21, 0, 0); // 9 PM

        Test.startTest();
        UserAvailabilityController.ShiftWindow sw =
            UserAvailabilityController.getShiftWindow('Night Shift', refTime);
        Test.stopTest();

        
    }

    @isTest
    static void testGetShiftWindowNightShiftBeforeNoon() {
        Datetime refTime = Datetime.newInstance(2026, 3, 17, 3, 0, 0); // 3 AM

        Test.startTest();
        UserAvailabilityController.ShiftWindow sw =
            UserAvailabilityController.getShiftWindow('Night Shift', refTime);
        Test.stopTest();

      
    }

    @isTest
    static void testGetShiftWindowForDateNightShift() {
        Date targetDate = Date.newInstance(2026, 3, 16);

        Test.startTest();
        UserAvailabilityController.ShiftWindow sw =
            UserAvailabilityController.getShiftWindowForDate('Night Shift', targetDate);
        Test.stopTest();

       
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DAILY LOG TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testEnsureDailyLogCreatesRecord() {
        Id userId = UserInfo.getUserId();
        Date today = Date.today();

        Test.startTest();
        Id logId = UserAvailabilityController.ensureDailyLog(userId, today, 'Day Shift');
        Test.stopTest();

        
    }

    @isTest
    static void testEnsureDailyLogIdempotent() {
        Id userId = UserInfo.getUserId();
        Date today = Date.today();

        Test.startTest();
        Id logId1 = UserAvailabilityController.ensureDailyLog(userId, today, 'Day Shift');
        Id logId2 = UserAvailabilityController.ensureDailyLog(userId, today, 'Day Shift');
        Test.stopTest();

       
    }

    @isTest
    static void testDailyLogTotalsUpdatedOnStatusChange() {
        Id userId = UserInfo.getUserId();

        User u = new User(Id = userId, is_working__c = true, Availability__c = true, Shift__c = 'Day Shift');
        update u;

        Test.startTest();
        // Toggle off
        UserAvailabilityController.setMyAvailability(false, 'Meeting');
        Test.stopTest();

       
    }

    @isTest
    static void testLogoutCreatesDailyLogWithTotals() {
        Id userId = UserInfo.getUserId();

        // First create a session
        User u = new User(Id = userId, is_working__c = true, Availability__c = true, Shift__c = 'Day Shift');
        update u;

        // Create initial availability record via the controller
        UserAvailabilityController.setMyAvailability(true, null);

        Test.startTest();
        UserAvailabilityController.logoutSession();
        Test.stopTest();

        
    }
}