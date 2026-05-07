@isTest
private class PerformanceTargetServiceTest {

    @TestSetup
    static void setupTestData() {
        DuplicateConversionEngine.skipProcessing = true;
        // Create a Project
        Project__c proj = TestDataFactory.createProject('Test Project');

        Id currentUserId = UserInfo.getUserId();
        Date periodStart = Date.today().toStartOfMonth();
        Date periodEnd = periodStart.addMonths(1).addDays(-1);
        String periodLabel = DateTime.newInstance(periodStart, Time.newInstance(0,0,0,0)).format('MMMM yyyy');

        // Organization level target - Leads_Generated
        Performance_Target__c orgTarget = new Performance_Target__c(
            Target_Level__c = 'Organization',
            Metric__c = 'Leads_Generated',
            Period_Type__c = 'Monthly',
            Period_Start__c = periodStart,
            Period_End__c = periodEnd,

            Target_Value__c = 100,
            Actual_Value__c = 0,
            Is_Active__c = true,
            Project__c = proj.Id
        );

        // Team level target - Site_Visits_Completed
        Performance_Target__c teamTarget = new Performance_Target__c(
            Target_Level__c = 'Team',
            Metric__c = 'Site_Visits_Completed',
            Period_Type__c = 'Monthly',
            Period_Start__c = periodStart,
            Period_End__c = periodEnd,

            Target_Value__c = 50,
            Actual_Value__c = 0,
            Is_Active__c = true,
            Project__c = proj.Id
        );

        // User level target 1 - Bookings_Closed
        Performance_Target__c userTarget1 = new Performance_Target__c(
            Target_Level__c = 'User',
            Metric__c = 'Bookings_Closed',
            Period_Type__c = 'Monthly',
            Period_Start__c = periodStart,
            Period_End__c = periodEnd,

            Target_Value__c = 10,
            Actual_Value__c = 0,
            Is_Active__c = true,
            Assignee__c = currentUserId,
            Project__c = proj.Id
        );

        // User level target 2 - Bookings_Closed
        Performance_Target__c userTarget2 = new Performance_Target__c(
            Target_Level__c = 'User',
            Metric__c = 'Bookings_Closed',
            Period_Type__c = 'Monthly',
            Period_Start__c = periodStart,
            Period_End__c = periodEnd,

            Target_Value__c = 10,
            Actual_Value__c = 0,
            Is_Active__c = true,
            Assignee__c = currentUserId,
            Project__c = proj.Id
        );

        // User level Revenue target
        Performance_Target__c revenueTarget = new Performance_Target__c(
            Target_Level__c = 'User',
            Metric__c = 'Revenue',
            Period_Type__c = 'Monthly',
            Period_Start__c = periodStart,
            Period_End__c = periodEnd,

            Target_Value__c = 1000000,
            Actual_Value__c = 0,
            Is_Active__c = true,
            Assignee__c = currentUserId,
            Project__c = proj.Id
        );

        insert new List<Performance_Target__c>{ orgTarget, teamTarget, userTarget1, userTarget2, revenueTarget };
    }

    // ── Helpers ──────────────────────────────────────────────────

    static Project__c getTestProject() {
        return [SELECT Id, Name FROM Project__c WHERE Name = 'Test Project' LIMIT 1];
    }

    static List<Performance_Target__c> getTestTargets() {
        return [
            SELECT Id, Target_Level__c, Metric__c, Assignee__c, Project__c,
                   Period_Type__c, Period_Start__c, Period_End__c, Period_Label__c,
                   Target_Value__c, Actual_Value__c, Is_Active__c, Parent_Target__c,
                   Team_Role__c, Description__c, Created_From__c, Assignee__r.Name,
                   Project__r.Name, Achievement_Pct__c, Remaining__c, Status__c,
                   Last_Calculated__c, Name
            FROM Performance_Target__c
            WHERE Is_Active__c = true
        ];
    }

    static PerformanceTargetService.TargetFilter buildDefaultFilter() {
        PerformanceTargetService.TargetFilter f = new PerformanceTargetService.TargetFilter();
        f.projectId = getTestProject().Id;
        f.periodType = 'Monthly';
        f.startDate = Date.today().toStartOfMonth();
        f.endDate = Date.today().toStartOfMonth().addMonths(1).addDays(-1);
        return f;
    }

    // ── Test Methods ─────────────────────────────────────────────

    @isTest
    static void testGetFilterOptions() {
        PerformanceTargetService.FilterOptions opts = PerformanceTargetService.getFilterOptions();

        System.assertNotEquals(null, opts, 'FilterOptions should not be null');
        System.assertNotEquals(null, opts.projects, 'Projects list should not be null');
        System.assertNotEquals(null, opts.users, 'Users list should not be null');
        System.assertNotEquals(null, opts.metrics, 'Metrics list should not be null');
        System.assertNotEquals(null, opts.periods, 'Periods list should not be null');
        System.assert(opts.projects.size() > 0, 'Should have at least one project');
        System.assertEquals(4, opts.metrics.size(), 'Should have 4 metrics');
        System.assertEquals(4, opts.periods.size(), 'Should have 4 period types');
    }

    @isTest
    static void testGetTargets() {
        PerformanceTargetService.TargetFilter filter = buildDefaultFilter();

        Test.startTest();
        List<PerformanceTargetService.TargetSummary> summaries = PerformanceTargetService.getTargets(filter);
        Test.stopTest();

        System.assert(summaries.size() > 0, 'Should return target summaries');
        for (PerformanceTargetService.TargetSummary ts : summaries) {
            System.assertNotEquals(null, ts.target, 'Target record should not be null');
            System.assertNotEquals(null, ts.assigneeName, 'Assignee name should not be null');
        }
    }

    @isTest
    static void testGetDashboardData() {
        PerformanceTargetService.TargetFilter filter = buildDefaultFilter();

        Test.startTest();
        PerformanceTargetService.DashboardData data = PerformanceTargetService.getDashboardData(filter);
        Test.stopTest();

        System.assertNotEquals(null, data, 'DashboardData should not be null');
        System.assert(data.totalTargets > 0, 'Should have total targets');
        System.assertNotEquals(null, data.metricBreakdown, 'Metric breakdown should not be null');
        System.assertNotEquals(null, data.avgAchievement, 'Average achievement should not be null');
        System.assertNotEquals(null, data.targets, 'Targets list should not be null');
    }

    @isTest
    static void testGetLeaderboard() {
        PerformanceTargetService.TargetFilter filter = buildDefaultFilter();

        Test.startTest();
        List<PerformanceTargetService.LeaderboardEntry> entries = PerformanceTargetService.getLeaderboard(filter);
        Test.stopTest();

        System.assertNotEquals(null, entries, 'Leaderboard entries should not be null');
        // Should have at least one entry for the current user (user-level targets exist)
        if (!entries.isEmpty()) {
            System.assertEquals(1, entries[0].rank, 'First entry should have rank 1');
            System.assertNotEquals(null, entries[0].assigneeName, 'Assignee name should not be null');
        }
    }

    @isTest
    static void testSaveTarget() {
        Project__c proj = getTestProject();
        Date periodStart = Date.today().toStartOfMonth();
        Date periodEnd = periodStart.addMonths(1).addDays(-1);

        Performance_Target__c newTarget = new Performance_Target__c(
            Target_Level__c = 'User',
            Metric__c = 'Leads_Generated',
            Period_Type__c = 'Monthly',
            Period_Start__c = periodStart,
            Period_End__c = periodEnd,

            Target_Value__c = 25,
            Actual_Value__c = 0,
            Is_Active__c = true,
            Assignee__c = UserInfo.getUserId(),
            Project__c = proj.Id
        );

        Test.startTest();
        Performance_Target__c saved = PerformanceTargetService.saveTarget(newTarget);
        Test.stopTest();

        System.assertNotEquals(null, saved.Id, 'Saved target should have an Id');

        Performance_Target__c queried = [SELECT Target_Value__c FROM Performance_Target__c WHERE Id = :saved.Id];
        System.assertEquals(25, queried.Target_Value__c, 'Target value should be 25');
    }

    @isTest
    static void testBulkCreateTargets() {
        Project__c proj = getTestProject();
        Date periodStart = Date.today().toStartOfMonth();
        Date periodEnd = periodStart.addMonths(1).addDays(-1);

        PerformanceTargetService.BulkAssignment assignment = new PerformanceTargetService.BulkAssignment();
        assignment.metric = 'Leads_Generated';
        assignment.periodType = 'Monthly';
        assignment.periodStart = periodStart;
        assignment.periodEnd = periodEnd;
        assignment.projectId = proj.Id;
        assignment.description = 'Bulk test';

        PerformanceTargetService.UserAssignment ua = new PerformanceTargetService.UserAssignment();
        ua.userId = UserInfo.getUserId();
        ua.targetValue = 30;
        assignment.assignments = new List<PerformanceTargetService.UserAssignment>{ ua };

        Test.startTest();
        List<Performance_Target__c> created = PerformanceTargetService.bulkCreateTargets(assignment);
        Test.stopTest();

        System.assertEquals(1, created.size(), 'Should create one target');
        System.assertNotEquals(null, created[0].Id, 'Created target should have an Id');

        Performance_Target__c queried = [SELECT Target_Value__c, Metric__c FROM Performance_Target__c WHERE Id = :created[0].Id];
        System.assertEquals(30, queried.Target_Value__c, 'Target value should be 30');
        System.assertEquals('Leads_Generated', queried.Metric__c, 'Metric should be Leads_Generated');
    }

    @isTest
    static void testCloneTargets() {
        PerformanceTargetService.TargetFilter sourceFilter = buildDefaultFilter();
        Date newStart = Date.today().toStartOfMonth().addMonths(1);
        Date newEnd = newStart.addMonths(1).addDays(-1);

        Test.startTest();
        List<Performance_Target__c> clones = PerformanceTargetService.cloneTargets(sourceFilter, newStart, newEnd);
        Test.stopTest();

        System.assert(clones.size() > 0, 'Should create cloned targets');
        for (Performance_Target__c clone : clones) {
            System.assertNotEquals(null, clone.Id, 'Clone should have an Id');
            Performance_Target__c queried = [
                SELECT Actual_Value__c, Period_Start__c, Created_From__c
                FROM Performance_Target__c
                WHERE Id = :clone.Id
            ];
            System.assertEquals(0, queried.Actual_Value__c, 'Cloned target should have zero actuals');
            System.assertEquals(newStart, queried.Period_Start__c, 'Clone should have new period start');
            System.assertNotEquals(null, queried.Created_From__c, 'Clone should reference source target');
        }
    }

    @isTest
    static void testDeleteTarget() {
        Project__c proj = getTestProject();
        Date periodStart = Date.today().toStartOfMonth();
        Date periodEnd = periodStart.addMonths(1).addDays(-1);

        Performance_Target__c target = new Performance_Target__c(
            Target_Level__c = 'User',
            Metric__c = 'Leads_Generated',
            Period_Type__c = 'Monthly',
            Period_Start__c = periodStart,
            Period_End__c = periodEnd,
            Target_Value__c = 5,
            Is_Active__c = true,
            Assignee__c = UserInfo.getUserId(),
            Project__c = proj.Id
        );
        insert target;

        Test.startTest();
        PerformanceTargetService.deleteTarget(target.Id);
        Test.stopTest();

        List<Performance_Target__c> remaining = [SELECT Id FROM Performance_Target__c WHERE Id = :target.Id];
        System.assertEquals(0, remaining.size(), 'Target should be deleted');
    }

    @isTest
    static void testCalculateLiveActuals() {
        Project__c proj = getTestProject();
        Id currentUserId = UserInfo.getUserId();

        // Create Lead__c records for the current user and project
        DuplicateConversionEngine.skipProcessing = true;
        List<Lead__c> leads = new List<Lead__c>();
        for (Integer i = 0; i < 5; i++) {
            leads.add(new Lead__c(
                First_Name__c = 'Test',
                Last_Name__c = 'Lead ' + i,
                Primary_Mobile__c = '900000000' + i,
                Owner__c = currentUserId,
                Project__c = proj.Id,
                Lead_Source__c = 'Walk-in'
            ));
        }
        insert leads;

        // Query user-level Leads_Generated targets
        List<Performance_Target__c> leadsTargets = [
            SELECT Id, Target_Level__c, Metric__c, Assignee__c, Project__c,
                   Period_Start__c, Period_End__c, Target_Value__c, Actual_Value__c,
                   Is_Active__c, Parent_Target__c
            FROM Performance_Target__c
            WHERE Is_Active__c = true
              AND Metric__c = 'Leads_Generated'
              AND Target_Level__c = 'Organization'
        ];

        // For testability, create a user-level Leads_Generated target
        Date periodStart = Date.today().toStartOfMonth();
        Date periodEnd = periodStart.addMonths(1).addDays(-1);
        Performance_Target__c leadsUserTarget = new Performance_Target__c(
            Target_Level__c = 'User',
            Metric__c = 'Leads_Generated',
            Period_Type__c = 'Monthly',
            Period_Start__c = periodStart,
            Period_End__c = periodEnd,
            Target_Value__c = 100,
            Actual_Value__c = 0,
            Is_Active__c = true,
            Assignee__c = currentUserId,
            Project__c = proj.Id
        );
        insert leadsUserTarget;

        List<Performance_Target__c> targetsToCalc = [
            SELECT Id, Target_Level__c, Metric__c, Assignee__c, Project__c,
                   Period_Start__c, Period_End__c, Target_Value__c, Actual_Value__c,
                   Is_Active__c, Parent_Target__c
            FROM Performance_Target__c
            WHERE Id = :leadsUserTarget.Id
        ];

        Test.startTest();
        Map<Id, Decimal> actuals = PerformanceTargetService.calculateLiveActuals(targetsToCalc);
        Test.stopTest();

        System.assertNotEquals(null, actuals, 'Actuals map should not be null');
        System.assert(actuals.containsKey(leadsUserTarget.Id), 'Should contain the target Id');
        System.assertEquals(5, actuals.get(leadsUserTarget.Id), 'Should count 5 leads');
    }

    @isTest
    static void testExportCSV() {
        PerformanceTargetService.TargetFilter filter = buildDefaultFilter();

        Test.startTest();
        String csv = PerformanceTargetService.exportCSV(filter);
        Test.stopTest();

        System.assertNotEquals(null, csv, 'CSV should not be null');
        System.assert(csv.length() > 0, 'CSV should not be empty');
        System.assert(csv.contains('Target ID'), 'CSV should contain header row');
    }

    @isTest
    static void testGetTrendData() {
        // Use Organization-level target so live data fallback doesn't apply
        Performance_Target__c target = [
            SELECT Id FROM Performance_Target__c
            WHERE Target_Level__c = 'Organization' AND Is_Active__c = true
            LIMIT 1
        ];

        // Create a Performance_Snapshot__c record
        Performance_Snapshot__c snapshot = new Performance_Snapshot__c(
            Performance_Target__c = target.Id,
            Snapshot_Date__c = Date.today().addDays(-1),
            Actual_Value__c = 25,
            Achievement_Pct__c = 0.25,
            Period_Day_Number__c = 1
        );
        insert snapshot;

        Test.startTest();
        List<PerformanceTargetService.TrendPoint> points = PerformanceTargetService.getTrendData(target.Id);
        Test.stopTest();

        System.assertNotEquals(null, points, 'Trend points should not be null');
        System.assert(points.size() >= 1, 'Should have at least one trend point');
        System.assertEquals(Date.today().addDays(-1), points[0].snapshotDate, 'First snapshot date should be yesterday');
        System.assertEquals(25, points[0].actualValue, 'Actual value should be 25');
    }

    @isTest
    static void testGetTrendDataLiveFallback() {
        // Use a User-level target with no snapshots to test live fallback
        Performance_Target__c target = [
            SELECT Id FROM Performance_Target__c
            WHERE Target_Level__c = 'User' AND Is_Active__c = true
            LIMIT 1
        ];

        Test.startTest();
        List<PerformanceTargetService.TrendPoint> points = PerformanceTargetService.getTrendData(target.Id);
        Test.stopTest();

        System.assertNotEquals(null, points, 'Trend points should not be null');
        System.assert(points.size() >= 1, 'Should have at least one point (live fallback)');
        System.assertEquals(Date.today(), points[points.size() - 1].snapshotDate, 'Last point should be today from live data');
    }

    @isTest
    static void testGetTargetsWithTargetIdFilter() {
        Performance_Target__c target = [
            SELECT Id FROM Performance_Target__c
            WHERE Is_Active__c = true
            LIMIT 1
        ];

        PerformanceTargetService.TargetFilter filter = new PerformanceTargetService.TargetFilter();
        filter.targetId = target.Id;

        Test.startTest();
        List<PerformanceTargetService.TargetSummary> summaries = PerformanceTargetService.getTargets(filter);
        Test.stopTest();

        System.assertEquals(1, summaries.size(), 'Should return exactly one target');
        System.assertEquals(target.Id, summaries[0].target.Id, 'Should return the requested target');
    }

    @isTest
    static void testRecalculateAndUpdate() {
        PerformanceTargetService.TargetFilter filter = buildDefaultFilter();

        Test.startTest();
        List<PerformanceTargetService.TargetSummary> summaries = PerformanceTargetService.recalculateAndUpdate(filter);
        Test.stopTest();

        System.assertNotEquals(null, summaries, 'Summaries should not be null');
        System.assert(summaries.size() > 0, 'Should return summaries');

        // Verify that Last_Calculated__c was updated
        for (PerformanceTargetService.TargetSummary ts : summaries) {
            Performance_Target__c updated = [
                SELECT Last_Calculated__c FROM Performance_Target__c WHERE Id = :ts.target.Id
            ];
            System.assertNotEquals(null, updated.Last_Calculated__c, 'Last calculated should be set');
        }
    }
}