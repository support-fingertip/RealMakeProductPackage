/**
 * @description Controller for User Availability Management LWC.
 * Provides profile-based visibility via custom metadata, paginated user queries,
 * working/availability status toggling with audit history, shift management,
 * and shift-aware Daily Log tracking.
 */
public with sharing class UserAvailabilityController {

    // Test-only injection points for Custom Metadata Type records (CMDT can't be inserted via DML).
    @TestVisible private static List<User_Availability_Profile_Config__mdt> testProfileConfigs;
    @TestVisible private static List<Shift_Configuration__mdt> testShiftConfigs;

    // ═══════════════════════════════════════════════════════════════════
    //  INNER CLASSES
    // ═══════════════════════════════════════════════════════════════════

    public class UserRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public String managerName;
        @AuraEnabled public String profileName;
        @AuraEnabled public Boolean isWorking;
        @AuraEnabled public Boolean isAvailable;
        @AuraEnabled public Boolean isCurrentUser;
        @AuraEnabled public String shift;
    }

    public class StatusSummary {
        @AuraEnabled public Long totalAvailableSeconds;
        @AuraEnabled public Long totalOfflineSeconds;
        @AuraEnabled public Long totalSessionSeconds;
        @AuraEnabled public Boolean currentIsAvailable;
        @AuraEnabled public Datetime currentStatusStartTime;
        @AuraEnabled public Datetime sessionStartTime;
        @AuraEnabled public String userName;
        @AuraEnabled public Boolean isWorking;
        @AuraEnabled public String shift;
        @AuraEnabled public String shiftStartTime;
        @AuraEnabled public String shiftEndTime;
    }

    public class UserTimeSummary {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public Long totalAvailableSeconds;
        @AuraEnabled public Long totalOfflineSeconds;
        @AuraEnabled public Long totalSessionSeconds;
    }

    public class ShiftInfo {
        @AuraEnabled public String shiftName;
        @AuraEnabled public String startTime;
        @AuraEnabled public String endTime;
        @AuraEnabled public Boolean isDefault;
    }

    public class ShiftWindow {
        public Date logDate;
        public Datetime windowStart;
        public Datetime windowEnd;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PROFILE CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get visible profiles for the current user based on custom metadata.
     * @return Map with 'currentProfile' (String), 'visibleProfiles' (List<String>), and 'defaultShift' (String)
     */
    @AuraEnabled
    public static Map<String, Object> getProfileConfig() {
        Map<String, Object> result = new Map<String, Object>();

        String currentProfileName = [
            SELECT Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ].Profile.Name;

        result.put('currentProfile', currentProfileName);

        List<User_Availability_Profile_Config__mdt> configs;
        if (Test.isRunningTest() && testProfileConfigs != null) {
            configs = new List<User_Availability_Profile_Config__mdt>();
            for (User_Availability_Profile_Config__mdt c : testProfileConfigs) {
                if (c.Profile_Name__c == currentProfileName && c.Is_Active__c == true) {
                    configs.add(c);
                }
            }
        } else {
            configs = [
                SELECT Profile_Name__c, Visible_Profiles__c, Default_Shift__c
                FROM User_Availability_Profile_Config__mdt
                WHERE Profile_Name__c = :currentProfileName
                AND Is_Active__c = true
                LIMIT 1
            ];
        }

        List<String> visibleProfiles = new List<String>();
        String defaultShift = 'Day Shift';
        if (!configs.isEmpty()) {
            String raw = configs[0].Visible_Profiles__c;
            for (String p : raw.split(',')) {
                String trimmed = p.trim();
                if (String.isNotBlank(trimmed)) {
                    visibleProfiles.add(trimmed);
                }
            }
            if (String.isNotBlank(configs[0].Default_Shift__c)) {
                defaultShift = configs[0].Default_Shift__c;
            }
        }

        result.put('visibleProfiles', visibleProfiles);
        result.put('defaultShift', defaultShift);
        return result;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SHIFT CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get all active shift configurations from custom metadata.
     * @return List of ShiftInfo wrappers
     */
    @AuraEnabled(cacheable=true)
    public static List<ShiftInfo> getShiftConfigurations() {
        List<ShiftInfo> shifts = new List<ShiftInfo>();

        for (Shift_Configuration__mdt config : queryShiftConfigs()) {
            ShiftInfo info = new ShiftInfo();
            info.shiftName = config.Shift_Name__c;
            info.startTime = config.Start_Time__c;
            info.endTime = config.End_Time__c;
            info.isDefault = config.Is_Default__c;
            shifts.add(info);
        }

        return shifts;
    }

    /**
     * Returns active shift configs from CMDT, or the test mock when running under tests.
     * CMDT records cannot be inserted via DML, so tests assign in-memory instances to
     * `testShiftConfigs` instead.
     */
    private static List<Shift_Configuration__mdt> queryShiftConfigs() {
        if (Test.isRunningTest() && testShiftConfigs != null) {
            return testShiftConfigs;
        }
        return [
            SELECT Shift_Name__c, Start_Time__c, End_Time__c, Is_Default__c
            FROM Shift_Configuration__mdt
            WHERE Is_Active__c = true
            ORDER BY Is_Default__c DESC, Shift_Name__c ASC
        ];
    }

    private static List<Shift_Configuration__mdt> queryShiftByName(String shiftName) {
        if (Test.isRunningTest() && testShiftConfigs != null) {
            List<Shift_Configuration__mdt> matches = new List<Shift_Configuration__mdt>();
            for (Shift_Configuration__mdt c : testShiftConfigs) {
                if (c.Shift_Name__c == shiftName) {
                    matches.add(c);
                    break;
                }
            }
            return matches;
        }
        return [
            SELECT Shift_Name__c, Start_Time__c, End_Time__c, Is_Default__c
            FROM Shift_Configuration__mdt
            WHERE Shift_Name__c = :shiftName
            LIMIT 1
        ];
    }

    private static List<Shift_Configuration__mdt> queryDefaultShiftConfig() {
        if (Test.isRunningTest() && testShiftConfigs != null) {
            List<Shift_Configuration__mdt> matches = new List<Shift_Configuration__mdt>();
            for (Shift_Configuration__mdt c : testShiftConfigs) {
                if (c.Is_Default__c == true) {
                    matches.add(c);
                    break;
                }
            }
            return matches;
        }
        return [
            SELECT Shift_Name__c, Start_Time__c, End_Time__c, Is_Default__c
            FROM Shift_Configuration__mdt
            WHERE Is_Default__c = true
            LIMIT 1
        ];
    }

    /**
     * @description Get the shift configuration for the current user.
     * Falls back to the default shift if the user has no shift assigned.
     * @return ShiftInfo wrapper with shift details
     */
    @AuraEnabled
    public static ShiftInfo getMyShift() {
        User u = [
            SELECT Shift__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        String userShift = String.isNotBlank(u.Shift__c) ? u.Shift__c : 'Day Shift';

        List<Shift_Configuration__mdt> configs = queryShiftByName(userShift);

        if (configs.isEmpty()) {
            // Fallback to default shift
            configs = queryDefaultShiftConfig();
        }

        ShiftInfo info = new ShiftInfo();
        if (!configs.isEmpty()) {
            info.shiftName = configs[0].Shift_Name__c;
            info.startTime = configs[0].Start_Time__c;
            info.endTime = configs[0].End_Time__c;
            info.isDefault = configs[0].Is_Default__c;
        } else {
            info.shiftName = 'Day Shift';
            info.startTime = '09:00';
            info.endTime = '18:00';
            info.isDefault = true;
        }

        return info;
    }

    /**
     * @description Update the current user's shift assignment.
     * @param shiftName The name of the shift to assign
     */
    @AuraEnabled
    public static void updateMyShift(String shiftName) {
        if (String.isBlank(shiftName)) {
            throw new AuraHandledException('Shift name is required.');
        }

        // Validate that the shift exists
        List<Shift_Configuration__mdt> configs = queryShiftByName(shiftName);

        if (configs.isEmpty()) {
            throw new AuraHandledException('Invalid shift: ' + shiftName);
        }

        try {
            User u = new User(Id = UserInfo.getUserId());
            u.Shift__c = shiftName;
            update u;
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to update shift: ' + e.getMessage());
        }
    }

    /**
     * @description Update a user's shift assignment (admin use).
     * @param userId The user record Id
     * @param shiftName The name of the shift to assign
     */
    @AuraEnabled
    public static void updateUserShift(Id userId, String shiftName) {
        if (userId == null) {
            throw new AuraHandledException('User ID is required.');
        }
        if (String.isBlank(shiftName)) {
            throw new AuraHandledException('Shift name is required.');
        }

        List<Shift_Configuration__mdt> configs = queryShiftByName(shiftName);

        if (configs.isEmpty()) {
            throw new AuraHandledException('Invalid shift: ' + shiftName);
        }

        try {
            User u = new User(Id = userId);
            u.Shift__c = shiftName;
            update u;
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to update user shift: ' + e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  USER QUERIES (PAGINATED)
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get paginated users filtered by profile names and optionally by shift.
     * @param profileNames List of profile names to filter by
     * @param pageSize Number of records per page
     * @param offset SOQL offset for pagination
     * @return List of UserRow wrapper objects
     */
    @AuraEnabled
    public static List<UserRow> getUsers(List<String> profileNames, Integer pageSize, Integer offset) {
        if (profileNames == null || profileNames.isEmpty()) {
            return new List<UserRow>();
        }

        List<User> users = [
            SELECT Id, Name, Username, Manager.Name, Profile.Name,
                   is_working__c, Availability__c, Shift__c
            FROM User
            WHERE IsActive = true
            AND Profile.Name IN :profileNames
            ORDER BY Name ASC
            LIMIT :pageSize
            OFFSET :offset
        ];

        Id currentUserId = UserInfo.getUserId();
        List<UserRow> rows = new List<UserRow>();

        for (User u : users) {
            UserRow row = new UserRow();
            row.id = u.Id;
            row.name = u.Name;
            row.username = u.Username;
            row.managerName = u.Manager != null ? u.Manager.Name : '';
            row.profileName = u.Profile.Name;
            row.isWorking = u.is_working__c;
            row.isAvailable = u.Availability__c;
            row.isCurrentUser = u.Id == currentUserId;
            row.shift = String.isNotBlank(u.Shift__c) ? u.Shift__c : 'Day Shift';
            rows.add(row);
        }

        return rows;
    }

    /**
     * @description Get total user count for pagination.
     * @param profileNames List of profile names to filter by
     * @return Total count of matching active users
     */
    @AuraEnabled
    public static Integer getUserCount(List<String> profileNames) {
        if (profileNames == null || profileNames.isEmpty()) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM User
            WHERE IsActive = true
            AND Profile.Name IN :profileNames
        ];
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PERSONAL AVAILABILITY (MY TOGGLE)
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get the current logged-in user's availability status.
     * @return Map with 'isWorking' (Boolean), 'isAvailable' (Boolean), 'shift' (String)
     */
    @AuraEnabled
    public static Map<String, Object> getMyAvailability() {
        User u = [
            SELECT is_working__c, Availability__c, Name, Shift__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        List<Availability_History__c> histories = [
            SELECT Changed_Date__c
            FROM Availability_History__c
            WHERE User__c = :UserInfo.getUserId()
            ORDER BY Changed_Date__c DESC
            LIMIT 1
        ];

        Datetime lastChanged = !histories.isEmpty() ? histories[0].Changed_Date__c : DateTime.now();

        return new Map<String, Object>{
            'isWorking' => u.is_working__c,
            'isAvailable' => u.Availability__c,
            'userName' => u.Name,
            'lastChangedDate' => lastChanged,
            'shift' => String.isNotBlank(u.Shift__c) ? u.Shift__c : 'Day Shift'
        };
    }

    /**
     * @description Set the current user's availability and working status.
     * When isAvailable = true, sets both is_working__c and Availability__c to true.
     * When isAvailable = false, sets only Availability__c to false.
     * Skips DML if the user already has the desired state (optimization for page-load calls).
     * @param isAvailable The desired availability state
     * @param reason Optional unavailability reason (picklist value from Unavailability_Reason__c)
     */
    @AuraEnabled
    public static void setMyAvailability(Boolean isAvailable, String reason) {
        Id userId = UserInfo.getUserId();

        try {
            User current = [
                SELECT is_working__c, Availability__c, Shift__c
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];

            Boolean needsUpdate = false;
            User u = new User(Id = userId);

            if (isAvailable && (!current.is_working__c || !current.Availability__c)) {
                u.is_working__c = true;
                u.Availability__c = true;
                needsUpdate = true;
            } else if (!isAvailable && current.Availability__c) {
                u.Availability__c = false;
                needsUpdate = true;
            }

            if (needsUpdate) {
                update u;
                String userShift = String.isNotBlank(current.Shift__c) ? current.Shift__c : 'Day Shift';

                // Ensure Daily Log exists and get parent Id
                ShiftWindow sw = getShiftWindow(userShift, Datetime.now());
                Id dailyLogId = ensureDailyLog(userId, sw.logDate, userShift);

                createAvailabilityHistoryWithReason(userId, isAvailable, reason, userShift, dailyLogId);

                // Recompute and update daily log totals
                recomputeAndUpdateDailyLog(userId, sw, dailyLogId);
            }

        } catch (DmlException e) {
            throw new AuraHandledException('Failed to update your availability: ' + e.getMessage());
        }
    }

    /**
     * @description Get cumulative Available and Offline time for today.
     * Uses shift-aware time windows: midnight-to-midnight for day shift,
     * noon-to-noon for night shift.
     * @return StatusSummary with cumulative seconds and current status info
     */
    @AuraEnabled
    public static StatusSummary getTodayStatusSummary() {
        Id userId = UserInfo.getUserId();

        User u = [
            SELECT is_working__c, Availability__c, Name, Shift__c
            FROM User
            WHERE Id = :userId
            LIMIT 1
        ];

        String userShift = String.isNotBlank(u.Shift__c) ? u.Shift__c : 'Day Shift';

        // Compute shift-aware window
        ShiftWindow sw = getShiftWindow(userShift, Datetime.now());

        List<Availability_History__c> records = [
            SELECT Is_Available__c, Changed_Date__c, Is_Logout__c
            FROM Availability_History__c
            WHERE User__c = :userId
            AND Changed_Date__c >= :sw.windowStart
            AND Changed_Date__c <= :sw.windowEnd
            ORDER BY Changed_Date__c ASC
        ];

        // Auto-create initial session record if none exist for this shift window
        if (records.isEmpty()) {
            // Ensure Daily Log exists first (MD parent)
            Id dailyLogId = ensureDailyLog(userId, sw.logDate, userShift);

            // New day login — always start as Available
            Availability_History__c initial = new Availability_History__c();
            initial.User__c = userId;
            initial.Is_Available__c = true;
            initial.Changed_By__c = userId;
            initial.Changed_Date__c = Datetime.now();
            initial.Shift__c = userShift;
            initial.Daily_Log__c = dailyLogId;
            insert initial;

            // Ensure user fields reflect available status
            if (!u.is_working__c || !u.Availability__c) {
                User toUpdate = new User(Id = userId);
                toUpdate.is_working__c = true;
                toUpdate.Availability__c = true;
                update toUpdate;
            }

            // Re-query to include the new record
            records = [
                SELECT Is_Available__c, Changed_Date__c, Is_Logout__c
                FROM Availability_History__c
                WHERE User__c = :userId
                AND Changed_Date__c >= :sw.windowStart
                AND Changed_Date__c <= :sw.windowEnd
                ORDER BY Changed_Date__c ASC
            ];

            // Re-query user to get updated field values
            u = [
                SELECT is_working__c, Availability__c, Name, Shift__c
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];
        }

        Datetime now = Datetime.now();
        UserTimeSummary timeSummary = computeTimeSummary(userId, u.Name, records, now);

        // Update Daily Log totals
        Id dailyLogId = ensureDailyLog(userId, sw.logDate, userShift);
        updateDailyLogTotals(dailyLogId, timeSummary);

        // Get shift timing info
        ShiftInfo shiftInfo = getShiftInfoByName(userShift);

        StatusSummary summary = new StatusSummary();
        summary.totalAvailableSeconds = timeSummary.totalAvailableSeconds;
        summary.totalOfflineSeconds = timeSummary.totalOfflineSeconds;
        summary.totalSessionSeconds = timeSummary.totalSessionSeconds;
        summary.currentIsAvailable = u.Availability__c && u.is_working__c;
        summary.currentStatusStartTime = !records.isEmpty()
            ? records[records.size() - 1].Changed_Date__c
            : now;
        // Determine sessionStartTime from first non-logout record
        Datetime sessionStart = null;
        for (Availability_History__c rec : records) {
            if (!rec.Is_Logout__c) {
                sessionStart = rec.Changed_Date__c;
                break;
            }
        }
        summary.sessionStartTime = sessionStart;
        summary.userName = u.Name;
        summary.isWorking = u.is_working__c;
        summary.shift = userShift;
        summary.shiftStartTime = shiftInfo.startTime;
        summary.shiftEndTime = shiftInfo.endTime;

        return summary;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  STATUS UPDATES
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Update working status with cascade logic.
     * If isWorking = false, Availability is automatically set to false.
     * @param userId The user record Id
     * @param isWorking The new working status
     */
    @AuraEnabled
    public static void updateWorkingStatus(Id userId, Boolean isWorking) {
        if (userId == null) {
            throw new AuraHandledException('User ID is required.');
        }

        try {
            User current = [
                SELECT Shift__c
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];

            User u = new User(Id = userId);
            u.is_working__c = isWorking;

            if (!isWorking) {
                u.Availability__c = false;
            }

            update u;

            String userShift = String.isNotBlank(current.Shift__c) ? current.Shift__c : 'Day Shift';

            // Ensure Daily Log exists and get parent Id
            ShiftWindow sw = getShiftWindow(userShift, Datetime.now());
            Id dailyLogId = ensureDailyLog(userId, sw.logDate, userShift);

            createAvailabilityHistory(userId, isWorking, userShift, dailyLogId);

            // Recompute and update daily log totals
            recomputeAndUpdateDailyLog(userId, sw, dailyLogId);

        } catch (DmlException e) {
            throw new AuraHandledException('Failed to update working status: ' + e.getMessage());
        }
    }

    /**
     * @description Update availability status.
     * @param userId The user record Id
     * @param isAvailable The new availability status
     */
    @AuraEnabled
    public static void updateAvailability(Id userId, Boolean isAvailable) {
        if (userId == null) {
            throw new AuraHandledException('User ID is required.');
        }

        try {
            User current = [
                SELECT Shift__c
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];

            User u = new User(Id = userId);
            u.Availability__c = isAvailable;
            update u;

            String userShift = String.isNotBlank(current.Shift__c) ? current.Shift__c : 'Day Shift';

            // Ensure Daily Log exists and get parent Id
            ShiftWindow sw = getShiftWindow(userShift, Datetime.now());
            Id dailyLogId = ensureDailyLog(userId, sw.logDate, userShift);

            createAvailabilityHistory(userId, isAvailable, userShift, dailyLogId);

            // Recompute and update daily log totals
            recomputeAndUpdateDailyLog(userId, sw, dailyLogId);

        } catch (DmlException e) {
            throw new AuraHandledException('Failed to update availability: ' + e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SESSION LOGOUT
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Create a logout marker record to freeze time calculation.
     * Called when the user closes the browser/navigates away.
     * Sets user to offline and creates a history record with Is_Logout__c = true.
     */
    @AuraEnabled
    public static void logoutSession() {
        Id userId = UserInfo.getUserId();

        try {
            User current = [
                SELECT Shift__c
                FROM User
                WHERE Id = :userId
                LIMIT 1
            ];

            User u = new User(Id = userId);
            u.Availability__c = false;
            u.is_working__c = false;
            update u;

            String userShift = String.isNotBlank(current.Shift__c) ? current.Shift__c : 'Day Shift';

            // Ensure Daily Log exists and get parent Id
            ShiftWindow sw = getShiftWindow(userShift, Datetime.now());
            Id dailyLogId = ensureDailyLog(userId, sw.logDate, userShift);

            Availability_History__c history = new Availability_History__c();
            history.User__c = userId;
            history.Is_Available__c = false;
            history.Changed_By__c = userId;
            history.Changed_Date__c = DateTime.now();
            history.Is_Logout__c = true;
            history.Shift__c = userShift;
            history.Daily_Log__c = dailyLogId;
            insert history;

            // Recompute and update daily log totals
            recomputeAndUpdateDailyLog(userId, sw, dailyLogId);
        } catch (Exception e) {
            // Silently fail on logout - don't block the user from leaving
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ADMIN: BULK USER TIME SUMMARIES
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get daily time summaries for multiple users on a given date.
     * Uses shift-aware windows per user: midnight-to-midnight for day shift,
     * noon-to-noon for night shift.
     * @param userIds List of user record IDs to query
     * @param targetDate The date to compute summaries for
     * @return List of UserTimeSummary wrappers with computed seconds
     */
    @AuraEnabled
    public static List<UserTimeSummary> getUserTimeSummaries(List<Id> userIds, Date targetDate) {
        if (userIds == null || userIds.isEmpty() || targetDate == null) {
            return new List<UserTimeSummary>();
        }

        // Query user shifts upfront
        Map<Id, String> userShifts = new Map<Id, String>();
        for (User u : [SELECT Id, Shift__c FROM User WHERE Id IN :userIds]) {
            userShifts.put(u.Id, String.isNotBlank(u.Shift__c) ? u.Shift__c : 'Day Shift');
        }

        // Use widest possible window to fetch all records in one query
        // Day shift: targetDate 00:00 → 23:59
        // Night shift: targetDate 12:00 → targetDate+1 11:59
        // Widest: targetDate 00:00 → targetDate+1 11:59:59
        Datetime widestStart = Datetime.newInstance(targetDate.year(), targetDate.month(), targetDate.day(), 0, 0, 0);
        Date nextDay = targetDate.addDays(1);
        Datetime widestEnd = Datetime.newInstance(nextDay.year(), nextDay.month(), nextDay.day(), 11, 59, 59);

        // Single bulk query for all users with widest window
        List<Availability_History__c> allRecords = [
            SELECT User__c, User__r.Name, Is_Available__c, Changed_Date__c, Is_Logout__c
            FROM Availability_History__c
            WHERE User__c IN :userIds
            AND Changed_Date__c >= :widestStart
            AND Changed_Date__c <= :widestEnd
            ORDER BY User__c, Changed_Date__c ASC
        ];

        // Group records by user
        Map<Id, List<Availability_History__c>> recordsByUser = new Map<Id, List<Availability_History__c>>();
        Map<Id, String> userNames = new Map<Id, String>();
        for (Availability_History__c rec : allRecords) {
            if (!recordsByUser.containsKey(rec.User__c)) {
                recordsByUser.put(rec.User__c, new List<Availability_History__c>());
            }
            recordsByUser.get(rec.User__c).add(rec);
            userNames.put(rec.User__c, rec.User__r.Name);
        }

        // Compute summary for each requested user with their shift-specific window
        List<UserTimeSummary> results = new List<UserTimeSummary>();
        List<Daily_Log__c> logsToUpsert = new List<Daily_Log__c>();

        for (Id uid : userIds) {
            String shiftName = userShifts.containsKey(uid) ? userShifts.get(uid) : 'Day Shift';
            ShiftWindow sw = getShiftWindowForDate(shiftName, targetDate);

            // Filter records to this user's specific shift window
            List<Availability_History__c> userRecords = new List<Availability_History__c>();
            if (recordsByUser.containsKey(uid)) {
                for (Availability_History__c rec : recordsByUser.get(uid)) {
                    if (rec.Changed_Date__c >= sw.windowStart && rec.Changed_Date__c <= sw.windowEnd) {
                        userRecords.add(rec);
                    }
                }
            }

            String userName = userNames.containsKey(uid) ? userNames.get(uid) : '';

            // Determine reference time
            Datetime now = Datetime.now();
            Datetime referenceNow = (now >= sw.windowStart && now <= sw.windowEnd)
                ? now
                : sw.windowEnd;

            UserTimeSummary summary = computeTimeSummary(uid, userName, userRecords, referenceNow);
            results.add(summary);

            // Build Daily Log for bulk upsert
            Daily_Log__c log = new Daily_Log__c();
            log.Unique_Key__c = String.valueOf(uid) + '-' + String.valueOf(sw.logDate);
            log.User__c = uid;
            log.Log_Date__c = sw.logDate;
            log.Shift__c = shiftName;
            log.Total_Available_Time__c = summary.totalAvailableSeconds;
            log.Total_Break_Time__c = summary.totalOfflineSeconds;
            log.Total_Session_Time__c = summary.totalSessionSeconds;
            logsToUpsert.add(log);
        }

        // Bulk upsert all daily logs
        if (!logsToUpsert.isEmpty()) {
            Database.upsert(logsToUpsert, Daily_Log__c.Unique_Key__c, false);
        }

        return results;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SHIFT-AWARE WINDOW HELPERS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Compute shift-aware log date and query window for real-time calls.
     * Day Shift: midnight-to-midnight (logDate = today)
     * Night Shift: noon-to-noon (logDate = today if after noon, yesterday if before noon)
     * @param shiftName The user's shift name
     * @param referenceTime The current time to base calculations on
     * @return ShiftWindow with logDate, windowStart, windowEnd
     */
    public static ShiftWindow getShiftWindow(String shiftName, Datetime referenceTime) {
        ShiftWindow sw = new ShiftWindow();
        Date today = referenceTime.date();

        if (shiftName != null && shiftName.containsIgnoreCase('Night')) {
            // Night shift: noon-to-noon window
            Integer hour = referenceTime.hour();
            if (hour >= 12) {
                // After noon — shift is starting, logDate = today
                sw.logDate = today;
            } else {
                // Before noon — shift started yesterday
                sw.logDate = today.addDays(-1);
            }
            sw.windowStart = Datetime.newInstance(sw.logDate.year(), sw.logDate.month(), sw.logDate.day(), 12, 0, 0);
            Date nextDay = sw.logDate.addDays(1);
            sw.windowEnd = Datetime.newInstance(nextDay.year(), nextDay.month(), nextDay.day(), 11, 59, 59);
        } else {
            // Day shift (default): midnight-to-midnight
            sw.logDate = today;
            sw.windowStart = Datetime.newInstance(today.year(), today.month(), today.day(), 0, 0, 0);
            sw.windowEnd = Datetime.newInstance(today.year(), today.month(), today.day(), 23, 59, 59);
        }
        return sw;
    }

    /**
     * @description Compute shift-aware query window for a specific target date (admin/batch use).
     * @param shiftName The user's shift name
     * @param targetDate The date to compute the window for
     * @return ShiftWindow with logDate, windowStart, windowEnd
     */
    public static ShiftWindow getShiftWindowForDate(String shiftName, Date targetDate) {
        ShiftWindow sw = new ShiftWindow();
        sw.logDate = targetDate;

        if (shiftName != null && shiftName.containsIgnoreCase('Night')) {
            sw.windowStart = Datetime.newInstance(targetDate.year(), targetDate.month(), targetDate.day(), 12, 0, 0);
            Date nextDay = targetDate.addDays(1);
            sw.windowEnd = Datetime.newInstance(nextDay.year(), nextDay.month(), nextDay.day(), 11, 59, 59);
        } else {
            sw.windowStart = Datetime.newInstance(targetDate.year(), targetDate.month(), targetDate.day(), 0, 0, 0);
            sw.windowEnd = Datetime.newInstance(targetDate.year(), targetDate.month(), targetDate.day(), 23, 59, 59);
        }
        return sw;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DAILY LOG HELPERS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Ensure a Daily_Log__c record exists for the given user/date.
     * Uses upsert on Unique_Key__c external ID for idempotent creation.
     * @param userId The user record Id
     * @param logDate The shift-aware log date
     * @param shiftName The user's current shift
     * @return The Id of the upserted Daily_Log__c record
     */
    public static Id ensureDailyLog(Id userId, Date logDate, String shiftName) {
        String uniqueKey = String.valueOf(userId) + '-' + String.valueOf(logDate);
        Daily_Log__c log = new Daily_Log__c();
        log.Unique_Key__c = uniqueKey;
        log.User__c = userId;
        log.Log_Date__c = logDate;
        log.Shift__c = shiftName;
        upsert log Unique_Key__c;
        return log.Id;
    }

    /**
     * @description Update the time totals on an existing Daily_Log__c.
     * @param dailyLogId The Id of the Daily_Log__c to update
     * @param summary The computed time summary
     */
    private static void updateDailyLogTotals(Id dailyLogId, UserTimeSummary summary) {
        Daily_Log__c log = new Daily_Log__c(Id = dailyLogId);
        log.Total_Available_Time__c = summary.totalAvailableSeconds;
        log.Total_Break_Time__c = summary.totalOfflineSeconds;
        log.Total_Session_Time__c = summary.totalSessionSeconds;
        update log;
    }

    /**
     * @description Re-query history records in the shift window, recompute time summary,
     * and update the Daily Log totals.
     * @param userId The user record Id
     * @param sw The shift window to query within
     * @param dailyLogId The Daily_Log__c Id to update
     */
    private static void recomputeAndUpdateDailyLog(Id userId, ShiftWindow sw, Id dailyLogId) {
        List<Availability_History__c> windowRecords = [
            SELECT Is_Available__c, Changed_Date__c, Is_Logout__c
            FROM Availability_History__c
            WHERE User__c = :userId
            AND Changed_Date__c >= :sw.windowStart
            AND Changed_Date__c <= :sw.windowEnd
            ORDER BY Changed_Date__c ASC
        ];
        UserTimeSummary ts = computeTimeSummary(userId, '', windowRecords, Datetime.now());
        updateDailyLogTotals(dailyLogId, ts);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HELPERS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get shift info by name, with fallback to defaults.
     * @param shiftName The shift name to look up
     * @return ShiftInfo with the shift details
     */
    private static ShiftInfo getShiftInfoByName(String shiftName) {
        List<Shift_Configuration__mdt> configs = queryShiftByName(shiftName);

        ShiftInfo info = new ShiftInfo();
        if (!configs.isEmpty()) {
            info.shiftName = configs[0].Shift_Name__c;
            info.startTime = configs[0].Start_Time__c;
            info.endTime = configs[0].End_Time__c;
            info.isDefault = configs[0].Is_Default__c;
        } else {
            info.shiftName = 'Day Shift';
            info.startTime = '09:00';
            info.endTime = '18:00';
            info.isDefault = true;
        }
        return info;
    }

    /**
     * @description Create an audit history record for availability changes.
     * @param userId The user whose status changed
     * @param isAvailable The new availability/working value
     * @param shiftName The shift the user is currently on
     * @param dailyLogId The parent Daily_Log__c Id (Master-Detail)
     */
    private static void createAvailabilityHistory(Id userId, Boolean isAvailable, String shiftName, Id dailyLogId) {
        Availability_History__c history = new Availability_History__c();
        history.User__c = userId;
        history.Is_Available__c = isAvailable;
        history.Changed_By__c = UserInfo.getUserId();
        history.Changed_Date__c = DateTime.now();
        history.Shift__c = shiftName;
        history.Daily_Log__c = dailyLogId;
        insert history;
    }

    /**
     * @description Create an audit history record with an optional unavailability reason.
     * @param userId The user whose status changed
     * @param isAvailable The new availability value
     * @param reason Optional reason for unavailability (Leave, Meeting, Training, Other)
     * @param shiftName The shift the user is currently on
     * @param dailyLogId The parent Daily_Log__c Id (Master-Detail)
     */
    private static void createAvailabilityHistoryWithReason(Id userId, Boolean isAvailable, String reason, String shiftName, Id dailyLogId) {
        Availability_History__c history = new Availability_History__c();
        history.User__c = userId;
        history.Is_Available__c = isAvailable;
        history.Changed_By__c = UserInfo.getUserId();
        history.Changed_Date__c = DateTime.now();
        history.Shift__c = shiftName;
        history.Daily_Log__c = dailyLogId;

        if (String.isNotBlank(reason)) {
            history.Unavailability_Reason__c = reason;
        }

        insert history;
    }

    /**
     * @description Compute time summary from a list of availability history records.
     * Walks through records calculating cumulative available, offline, and session seconds.
     * @param userId The user ID for the summary
     * @param userName The user's display name
     * @param records Availability history records ordered by Changed_Date__c ASC
     * @param referenceNow The reference timestamp for trailing segment calculation
     * @return UserTimeSummary with computed seconds
     */
    public static UserTimeSummary computeTimeSummary(
        Id userId, String userName,
        List<Availability_History__c> records,
        Datetime referenceNow
    ) {
        Long availableSeconds = 0;
        Long offlineSeconds = 0;
        Long totalSessionSeconds = 0;

        if (!records.isEmpty()) {
            Datetime currentSessionStart = null;
            Datetime segmentStart = null;
            Boolean currentStatus = false;
            Boolean lastRecordIsLogout = false;

            for (Integer i = 0; i < records.size(); i++) {
                Availability_History__c rec = records[i];

                if (rec.Is_Logout__c) {
                    if (segmentStart != null) {
                        Long segmentSeconds = (rec.Changed_Date__c.getTime() - segmentStart.getTime()) / 1000;
                        if (segmentSeconds > 0) {
                            if (currentStatus) {
                                availableSeconds += segmentSeconds;
                            } else {
                                offlineSeconds += segmentSeconds;
                            }
                        }
                    }
                    if (currentSessionStart != null) {
                        totalSessionSeconds += (rec.Changed_Date__c.getTime() - currentSessionStart.getTime()) / 1000;
                    }
                    segmentStart = null;
                    currentSessionStart = null;
                    lastRecordIsLogout = true;
                } else {
                    if (currentSessionStart == null) {
                        currentSessionStart = rec.Changed_Date__c;
                    } else if (segmentStart != null) {
                        Long segmentSeconds = (rec.Changed_Date__c.getTime() - segmentStart.getTime()) / 1000;
                        if (segmentSeconds > 0) {
                            if (currentStatus) {
                                availableSeconds += segmentSeconds;
                            } else {
                                offlineSeconds += segmentSeconds;
                            }
                        }
                    }
                    currentStatus = rec.Is_Available__c;
                    segmentStart = rec.Changed_Date__c;
                    lastRecordIsLogout = false;
                }
            }

            if (!lastRecordIsLogout && segmentStart != null) {
                Long trailingSeconds = (referenceNow.getTime() - segmentStart.getTime()) / 1000;
                if (trailingSeconds > 0) {
                    if (currentStatus) {
                        availableSeconds += trailingSeconds;
                    } else {
                        offlineSeconds += trailingSeconds;
                    }
                }
                if (currentSessionStart != null) {
                    totalSessionSeconds += (referenceNow.getTime() - currentSessionStart.getTime()) / 1000;
                }
            }
        }

        UserTimeSummary summary = new UserTimeSummary();
        summary.userId = userId;
        summary.userName = userName;
        summary.totalAvailableSeconds = availableSeconds;
        summary.totalOfflineSeconds = offlineSeconds;
        summary.totalSessionSeconds = totalSessionSeconds;
        return summary;
    }
}