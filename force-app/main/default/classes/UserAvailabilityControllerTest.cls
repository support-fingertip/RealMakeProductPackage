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

        System.assertNotEquals(null, config, 'Config should not be null');
        System.assertNotEquals(null, config.get('currentProfile'), 'Current profile should be set');
        System.assertNotEquals(null, config.get('visibleProfiles'), 'Visible profiles should be set');
    }

    @isTest
    static void testGetProfileConfigReturnsVisibleProfiles() {
        seedCmdtMocks();
        Test.startTest();
        Map<String, Object> config = UserAvailabilityController.getProfileConfig();
        Test.stopTest();

        String currentProfile = (String) config.get('currentProfile');
        List<Object> visibleProfiles = (List<Object>) config.get('visibleProfiles');

        System.assertEquals('System Administrator', currentProfile,
            'Running user should be System Administrator');
        System.assert(visibleProfiles.size() > 0,
            'System Administrator should have visible profiles configured');
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

        System.assert(users != null, 'Users list should not be null');
        System.assert(users.size() >= 1, 'Should find at least one System Administrator');

        UserAvailabilityController.UserRow firstUser = users[0];
        System.assertNotEquals(null, firstUser.id, 'User Id should be set');
        System.assertNotEquals(null, firstUser.name, 'User Name should be set');
        System.assertNotEquals(null, firstUser.username, 'Username should be set');
        System.assertNotEquals(null, firstUser.profileName, 'Profile name should be set');
    }

    @isTest
    static void testGetUsersWithEmptyProfiles() {
        Test.startTest();
        List<UserAvailabilityController.UserRow> users = UserAvailabilityController.getUsers(
            new List<String>(), 10, 0
        );
        Test.stopTest();

        System.assertEquals(0, users.size(), 'Empty profiles should return empty list');
    }

    @isTest
    static void testGetUsersWithNullProfiles() {
        Test.startTest();
        List<UserAvailabilityController.UserRow> users = UserAvailabilityController.getUsers(
            null, 10, 0
        );
        Test.stopTest();

        System.assertEquals(0, users.size(), 'Null profiles should return empty list');
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

        System.assert(page1.size() <= 1, 'Page 1 should have at most 1 user');
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
                System.assertEquals(true, row.isCurrentUser, 'Current user flag should be true');
            }
        }
        System.assert(foundCurrentUser, 'Current user should be in the results');
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

        System.assert(count >= 1, 'Should count at least one System Administrator');
    }

    @isTest
    static void testGetUserCountEmptyProfiles() {
        Test.startTest();
        Integer count = UserAvailabilityController.getUserCount(new List<String>());
        Test.stopTest();

        System.assertEquals(0, count, 'Empty profiles should return 0');
    }

    @isTest
    static void testGetUserCountNullProfiles() {
        Test.startTest();
        Integer count = UserAvailabilityController.getUserCount(null);
        Test.stopTest();

        System.assertEquals(0, count, 'Null profiles should return 0');
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

        User updated = [SELECT is_working__c, Availability__c FROM User WHERE Id = :currentUserId];
        System.assertEquals(false, updated.is_working__c, 'Working status should be false');
        System.assertEquals(false, updated.Availability__c, 'Availability should cascade to false');

        List<Availability_History__c> history = [
            SELECT Is_Available__c, Changed_By__c, Daily_Log__c
            FROM Availability_History__c
            WHERE User__c = :currentUserId
            ORDER BY Changed_Date__c DESC
            LIMIT 1
        ];
        System.assertEquals(1, history.size(), 'Should create audit history record');
        System.assertEquals(false, history[0].Is_Available__c, 'History should record false');
        System.assertEquals(currentUserId, history[0].Changed_By__c, 'Changed by should be current user');
        System.assertNotEquals(null, history[0].Daily_Log__c, 'History should be linked to Daily Log');
    }

    @isTest
    static void testUpdateWorkingStatusToTrue() {
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, is_working__c = false, Availability__c = false);
        update u;

        Test.startTest();
        UserAvailabilityController.updateWorkingStatus(currentUserId, true);
        Test.stopTest();

        User updated = [SELECT is_working__c FROM User WHERE Id = :currentUserId];
        System.assertEquals(true, updated.is_working__c, 'Working status should be true');
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

        System.assert(exceptionThrown, 'Should throw AuraHandledException for null userId');
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

        User updated = [SELECT Availability__c FROM User WHERE Id = :currentUserId];
        System.assertEquals(false, updated.Availability__c, 'Availability should be false');

        List<Availability_History__c> history = [
            SELECT Is_Available__c, Daily_Log__c
            FROM Availability_History__c
            WHERE User__c = :currentUserId
            ORDER BY Changed_Date__c DESC
            LIMIT 1
        ];
        System.assert(!history.isEmpty(), 'Should create audit history record');
        System.assertEquals(false, history[0].Is_Available__c, 'History should record false');
        System.assertNotEquals(null, history[0].Daily_Log__c, 'History should be linked to Daily Log');
    }

    @isTest
    static void testUpdateAvailabilityToTrue() {
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, Availability__c = false);
        update u;

        Test.startTest();
        UserAvailabilityController.updateAvailability(currentUserId, true);
        Test.stopTest();

        User updated = [SELECT Availability__c FROM User WHERE Id = :currentUserId];
        System.assertEquals(true, updated.Availability__c, 'Availability should be true');
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

        System.assert(exceptionThrown, 'Should throw AuraHandledException for null userId');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PERSONAL AVAILABILITY (MY TOGGLE) TESTS
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void testGetMyAvailability() {
        Test.startTest();
        Map<String, Object> result = UserAvailabilityController.getMyAvailability();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('isWorking'), 'Should contain isWorking key');
        System.assert(result.containsKey('isAvailable'), 'Should contain isAvailable key');
        System.assert(result.containsKey('userName'), 'Should contain userName key');
        System.assertNotEquals(null, result.get('userName'), 'userName should not be null');
    }

    @isTest
    static void testSetMyAvailabilityToTrue() {
        Id currentUserId = UserInfo.getUserId();

        User u = new User(Id = currentUserId, Availability__c = false, is_working__c = false);
        update u;

        Test.startTest();
        UserAvailabilityController.setMyAvailability(true, null);
        Test.stopTest();

        User updated = [SELECT Availability__c, is_working__c FROM User WHERE Id = :currentUserId];
        System.assertEquals(true, updated.Availability__c, 'Availability should be true');
        System.assertEquals(true, updated.is_working__c, 'Working status should be true when setting available');

        List<Availability_History__c> history = [
            SELECT Is_Available__c, Unavailability_Reason__c, Changed_By__c, Daily_Log__c
            FROM Availability_History__c
            WHERE User__c = :currentUserId
            ORDER BY Changed_Date__c DESC
            LIMIT 1
        ];
        System.assertEquals(1, history.size(), 'Should create audit history record');
        System.assertEquals(true, history[0].Is_Available__c, 'History should record true');
        System.assertEquals(currentUserId, history[0].Changed_By__c, 'Changed by should be current user');
        System.assertNotEquals(null, history[0].Daily_Log__c, 'History should be linked to Daily Log');
    }

    @isTest
    static void testSetMyAvailabilityToFalseWithReason() {
        seedCmdtMocks();
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.setMyAvailability(false, 'Meeting');
        Test.stopTest();

        User updated = [SELECT Availability__c FROM User WHERE Id = :currentUserId];
        System.assertEquals(false, updated.Availability__c, 'Availability should be false');

        List<Availability_History__c> history = [
            SELECT Is_Available__c, Unavailability_Reason__c, Daily_Log__c
            FROM Availability_History__c
            WHERE User__c = :currentUserId
            ORDER BY Changed_Date__c DESC
            LIMIT 1
        ];
        System.assertEquals(1, history.size(), 'Should create audit history record');
        System.assertEquals(false, history[0].Is_Available__c, 'History should record false');
        System.assertEquals('Meeting', history[0].Unavailability_Reason__c, 'Reason should be Meeting');
        System.assertNotEquals(null, history[0].Daily_Log__c, 'History should be linked to Daily Log');
    }

    @isTest
    static void testSetMyAvailabilityToFalseWithoutReason() {
        seedCmdtMocks();
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.setMyAvailability(false, null);
        Test.stopTest();

        User updated = [SELECT Availability__c FROM User WHERE Id = :currentUserId];
        System.assertEquals(false, updated.Availability__c, 'Availability should be false');

        List<Availability_History__c> history = [
            SELECT Unavailability_Reason__c
            FROM Availability_History__c
            WHERE User__c = :currentUserId
            ORDER BY Changed_Date__c DESC
            LIMIT 1
        ];
        System.assertEquals(null, history[0].Unavailability_Reason__c, 'Reason should be null');
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

        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assertNotEquals(null, summary.userName, 'userName should be populated');
        System.assert(summary.totalAvailableSeconds >= 0, 'Available seconds should be non-negative');
        System.assert(summary.totalOfflineSeconds >= 0, 'Offline seconds should be non-negative');

        // Verify Daily Log was created
        List<Daily_Log__c> logs = [
            SELECT Id, Log_Date__c, User__c
            FROM Daily_Log__c
            WHERE User__c = :UserInfo.getUserId()
        ];
        System.assert(!logs.isEmpty(), 'Daily Log should be created on first summary call');
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

        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assert(summary.totalAvailableSeconds > 0, 'Should have some available seconds');
        System.assert(summary.totalOfflineSeconds > 0, 'Should have some offline seconds');

        // Verify Daily Log totals were updated
        Daily_Log__c log = [
            SELECT Total_Available_Time__c, Total_Break_Time__c, Total_Session_Time__c
            FROM Daily_Log__c
            WHERE Id = :dailyLogId
        ];
        System.assert(log.Total_Available_Time__c > 0, 'Daily Log available time should be updated');
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

        System.assertEquals(true, summary.currentIsAvailable, 'Should reflect current available status');
        System.assertEquals(true, summary.isWorking, 'Should reflect current working status');
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

        System.assertEquals(1, results.size(), 'Should return one summary');
        System.assertEquals(userId, results[0].userId, 'Should match user ID');
        System.assert(results[0].totalAvailableSeconds > 0, 'Should have available seconds');
        System.assert(results[0].totalOfflineSeconds > 0, 'Should have offline seconds');
        System.assert(results[0].totalSessionSeconds > 0, 'Should have session seconds');
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

        System.assertEquals(1, results.size(), 'Should return one summary');
        System.assert(results[0].totalAvailableSeconds > 0, 'Should have available seconds for yesterday');
        // 8 hours = 28800 seconds
        System.assert(results[0].totalAvailableSeconds >= 28000,
            'Available seconds should be approximately 8 hours');
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

        System.assertEquals(1, results.size(), 'Should return one summary');
        System.assertEquals(0, results[0].totalAvailableSeconds, 'Should be zero available');
        System.assertEquals(0, results[0].totalOfflineSeconds, 'Should be zero offline');
        System.assertEquals(0, results[0].totalSessionSeconds, 'Should be zero session');
    }

    @isTest
    static void testGetUserTimeSummariesEmptyList() {
        Test.startTest();
        List<UserAvailabilityController.UserTimeSummary> results =
            UserAvailabilityController.getUserTimeSummaries(
                new List<Id>(), Date.today()
            );
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty list');
    }

    @isTest
    static void testGetUserTimeSummariesNullParams() {
        Test.startTest();
        List<UserAvailabilityController.UserTimeSummary> results =
            UserAvailabilityController.getUserTimeSummaries(null, null);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty list for null params');
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

        User updated = [SELECT is_working__c, Availability__c FROM User WHERE Id = :currentUserId];
        System.assertEquals(true, updated.is_working__c, 'Working status should remain true');
        System.assertEquals(false, updated.Availability__c, 'Availability should be false');
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

        System.assertNotEquals(null, shifts, 'Shifts should not be null');
        System.assert(shifts.size() > 0, 'Should have at least one shift configured');

        // Verify Day Shift exists as default
        Boolean foundDefault = false;
        for (UserAvailabilityController.ShiftInfo s : shifts) {
            System.assertNotEquals(null, s.shiftName, 'Shift name should be set');
            System.assertNotEquals(null, s.startTime, 'Start time should be set');
            System.assertNotEquals(null, s.endTime, 'End time should be set');
            if (s.isDefault) {
                foundDefault = true;
            }
        }
        System.assert(foundDefault, 'Should have a default shift');
    }

    @isTest
    static void testGetMyShift() {
        Test.startTest();
        UserAvailabilityController.ShiftInfo shift =
            UserAvailabilityController.getMyShift();
        Test.stopTest();

        System.assertNotEquals(null, shift, 'Shift info should not be null');
        System.assertNotEquals(null, shift.shiftName, 'Shift name should be set');
        System.assertNotEquals(null, shift.startTime, 'Start time should be set');
        System.assertNotEquals(null, shift.endTime, 'End time should be set');
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

        System.assertEquals('Day Shift', shift.shiftName, 'Should return Day Shift');
    }

    @isTest
    static void testUpdateMyShift() {
        seedCmdtMocks();
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.updateMyShift('Day Shift');
        Test.stopTest();

        User updated = [SELECT Shift__c FROM User WHERE Id = :currentUserId];
        System.assertEquals('Day Shift', updated.Shift__c, 'Shift should be Day Shift');
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

        System.assert(exceptionThrown, 'Should throw exception for blank shift name');
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

        System.assert(exceptionThrown, 'Should throw exception for invalid shift name');
    }

    @isTest
    static void testUpdateUserShift() {
        seedCmdtMocks();
        Id currentUserId = UserInfo.getUserId();

        Test.startTest();
        UserAvailabilityController.updateUserShift(currentUserId, 'Day Shift');
        Test.stopTest();

        User updated = [SELECT Shift__c FROM User WHERE Id = :currentUserId];
        System.assertEquals('Day Shift', updated.Shift__c, 'Shift should be Day Shift');
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

        System.assert(exceptionThrown, 'Should throw exception for null userId');
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

        System.assert(exceptionThrown, 'Should throw exception for blank shift name');
    }

    @isTest
    static void testGetProfileConfigReturnsDefaultShift() {
        Test.startTest();
        Map<String, Object> config = UserAvailabilityController.getProfileConfig();
        Test.stopTest();

        System.assert(config.containsKey('defaultShift'), 'Should contain defaultShift key');
        System.assertNotEquals(null, config.get('defaultShift'), 'Default shift should not be null');
    }

    @isTest
    static void testGetMyAvailabilityReturnsShift() {
        Test.startTest();
        Map<String, Object> result = UserAvailabilityController.getMyAvailability();
        Test.stopTest();

        System.assert(result.containsKey('shift'), 'Should contain shift key');
        System.assertNotEquals(null, result.get('shift'), 'Shift should not be null');
    }

    @isTest
    static void testGetUsersReturnsShift() {
        Test.startTest();
        List<UserAvailabilityController.UserRow> users = UserAvailabilityController.getUsers(
            new List<String>{ 'System Administrator' }, 10, 0
        );
        Test.stopTest();

        System.assert(users.size() > 0, 'Should return users');
        System.assertNotEquals(null, users[0].shift, 'Shift should be set on user row');
    }

    @isTest
    static void testStatusSummaryIncludesShift() {
        Test.startTest();
        UserAvailabilityController.StatusSummary summary =
            UserAvailabilityController.getTodayStatusSummary();
        Test.stopTest();

        System.assertNotEquals(null, summary.shift, 'Summary should include shift');
        System.assertNotEquals(null, summary.shiftStartTime, 'Summary should include shift start time');
        System.assertNotEquals(null, summary.shiftEndTime, 'Summary should include shift end time');
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

        List<Availability_History__c> history = [
            SELECT Shift__c, Daily_Log__c
            FROM Availability_History__c
            WHERE User__c = :currentUserId
            ORDER BY Changed_Date__c DESC
            LIMIT 1
        ];
        System.assertEquals(1, history.size(), 'Should create history record');
        System.assertEquals('Day Shift', history[0].Shift__c, 'History should record shift');
        System.assertNotEquals(null, history[0].Daily_Log__c, 'History should be linked to Daily Log');
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
        System.assertEquals(1, history.size(), 'Should create logout history record');
        System.assertEquals(true, history[0].Is_Logout__c, 'Should be a logout record');
        System.assertEquals('Day Shift', history[0].Shift__c, 'Logout should record shift');
        System.assertNotEquals(null, history[0].Daily_Log__c, 'Logout history should be linked to Daily Log');
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

        System.assertEquals(Date.newInstance(2026, 3, 17), sw.logDate, 'Day shift logDate should be today');
        System.assertEquals(
            Datetime.newInstance(2026, 3, 17, 0, 0, 0), sw.windowStart,
            'Day shift should start at midnight'
        );
        System.assertEquals(
            Datetime.newInstance(2026, 3, 17, 23, 59, 59), sw.windowEnd,
            'Day shift should end at 23:59:59'
        );
    }

    @isTest
    static void testGetShiftWindowNightShiftAfterNoon() {
        Datetime refTime = Datetime.newInstance(2026, 3, 16, 21, 0, 0); // 9 PM

        Test.startTest();
        UserAvailabilityController.ShiftWindow sw =
            UserAvailabilityController.getShiftWindow('Night Shift', refTime);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 3, 16), sw.logDate,
            'Night shift after noon: logDate should be today');
        System.assertEquals(
            Datetime.newInstance(2026, 3, 16, 12, 0, 0), sw.windowStart,
            'Night shift should start at noon'
        );
        System.assertEquals(
            Datetime.newInstance(2026, 3, 17, 11, 59, 59), sw.windowEnd,
            'Night shift should end at next day 11:59:59'
        );
    }

    @isTest
    static void testGetShiftWindowNightShiftBeforeNoon() {
        Datetime refTime = Datetime.newInstance(2026, 3, 17, 3, 0, 0); // 3 AM

        Test.startTest();
        UserAvailabilityController.ShiftWindow sw =
            UserAvailabilityController.getShiftWindow('Night Shift', refTime);
        Test.stopTest();

        System.assertEquals(Date.newInstance(2026, 3, 16), sw.logDate,
            'Night shift before noon: logDate should be yesterday');
        System.assertEquals(
            Datetime.newInstance(2026, 3, 16, 12, 0, 0), sw.windowStart,
            'Night shift window should start at yesterday noon'
        );
        System.assertEquals(
            Datetime.newInstance(2026, 3, 17, 11, 59, 59), sw.windowEnd,
            'Night shift window should end at today 11:59:59'
        );
    }

    @isTest
    static void testGetShiftWindowForDateNightShift() {
        Date targetDate = Date.newInstance(2026, 3, 16);

        Test.startTest();
        UserAvailabilityController.ShiftWindow sw =
            UserAvailabilityController.getShiftWindowForDate('Night Shift', targetDate);
        Test.stopTest();

        System.assertEquals(targetDate, sw.logDate, 'logDate should match target');
        System.assertEquals(
            Datetime.newInstance(2026, 3, 16, 12, 0, 0), sw.windowStart,
            'Should start at target date noon'
        );
        System.assertEquals(
            Datetime.newInstance(2026, 3, 17, 11, 59, 59), sw.windowEnd,
            'Should end at next day 11:59:59'
        );
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

        System.assertNotEquals(null, logId, 'Should return Daily Log Id');

        Daily_Log__c log = [
            SELECT Unique_Key__c, User__c, Log_Date__c, Shift__c
            FROM Daily_Log__c
            WHERE Id = :logId
        ];
        System.assertEquals(userId, log.User__c, 'User should match');
        System.assertEquals(today, log.Log_Date__c, 'Log date should match');
        System.assertEquals('Day Shift', log.Shift__c, 'Shift should match');
    }

    @isTest
    static void testEnsureDailyLogIdempotent() {
        Id userId = UserInfo.getUserId();
        Date today = Date.today();

        Test.startTest();
        Id logId1 = UserAvailabilityController.ensureDailyLog(userId, today, 'Day Shift');
        Id logId2 = UserAvailabilityController.ensureDailyLog(userId, today, 'Day Shift');
        Test.stopTest();

        System.assertEquals(logId1, logId2, 'Same user+date should return same Daily Log Id');

        Integer logCount = [SELECT COUNT() FROM Daily_Log__c WHERE User__c = :userId AND Log_Date__c = :today];
        System.assertEquals(1, logCount, 'Should only have one Daily Log for same user+date');
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

        List<Daily_Log__c> logs = [
            SELECT Total_Available_Time__c, Total_Break_Time__c, Total_Session_Time__c
            FROM Daily_Log__c
            WHERE User__c = :userId
            AND Log_Date__c = :Date.today()
        ];
        System.assertEquals(1, logs.size(), 'Should have exactly one Daily Log');
        System.assert(logs[0].Total_Session_Time__c >= 0, 'Session time should be non-negative');
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

        List<Daily_Log__c> logs = [
            SELECT Total_Available_Time__c, Total_Break_Time__c, Total_Session_Time__c
            FROM Daily_Log__c
            WHERE User__c = :userId
            AND Log_Date__c = :Date.today()
        ];
        System.assertEquals(1, logs.size(), 'Should have one Daily Log after logout');
    }
}