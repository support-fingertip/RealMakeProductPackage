/**
 * @description Core service for the Target vs Actual Performance Management module.
 * Handles target CRUD, actuals calculation, dashboard aggregation, leaderboard, and cloning.
 * Uses aggregate SOQL for performance with large data volumes.
 */
public with sharing class PerformanceTargetService {

    // ═══════════════════════════════════════════════════════════════════
    //  INNER WRAPPER CLASSES
    // ═══════════════════════════════════════════════════════════════════

    public class TargetFilter {
        @AuraEnabled public Id projectId;
        @AuraEnabled public Id assigneeId;
        @AuraEnabled public String periodType;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String metric;
        @AuraEnabled public String level;
        @AuraEnabled public Id targetId;
    }

    public class FilterOptions {
        @AuraEnabled public List<OptionItem> projects;
        @AuraEnabled public List<OptionItem> users;
        @AuraEnabled public List<OptionItem> metrics;
        @AuraEnabled public List<OptionItem> periods;
        @AuraEnabled public List<OptionItem> teams;
        @AuraEnabled public List<OptionItem> targetLevels;
    }

    public class OptionItem {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public OptionItem(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class TargetSummary {
        @AuraEnabled public Performance_Target__c target;
        @AuraEnabled public Decimal liveActual;
        @AuraEnabled public String assigneeName;
    }

    public class DashboardData {
        @AuraEnabled public List<TargetSummary> targets;
        @AuraEnabled public Integer totalTargets;
        @AuraEnabled public Decimal avgAchievement;
        @AuraEnabled public String topPerformerName;
        @AuraEnabled public Integer targetsAtRisk;
        @AuraEnabled public List<MetricBreakdown> metricBreakdown;
        @AuraEnabled public List<TrendPoint> trendData;
    }

    public class MetricBreakdown {
        @AuraEnabled public String metric;
        @AuraEnabled public String metricLabel;
        @AuraEnabled public Decimal totalTarget;
        @AuraEnabled public Decimal totalActual;
        @AuraEnabled public Decimal achievementPct;
    }

    public class LeaderboardEntry {
        @AuraEnabled public Integer rank;
        @AuraEnabled public Id assigneeId;
        @AuraEnabled public String assigneeName;
        @AuraEnabled public Decimal achievementPct;
        @AuraEnabled public Decimal targetValue;
        @AuraEnabled public Decimal actualValue;
        @AuraEnabled public String metric;
    }

    public class TrendPoint {
        @AuraEnabled public Date snapshotDate;
        @AuraEnabled public Decimal actualValue;
        @AuraEnabled public Decimal achievementPct;
    }

    public class BulkAssignment {
        @AuraEnabled public String metric;
        @AuraEnabled public String periodType;
        @AuraEnabled public Date periodStart;
        @AuraEnabled public Date periodEnd;
        @AuraEnabled public Id projectId;
        @AuraEnabled public Id parentTargetId;
        @AuraEnabled public String description;
        @AuraEnabled public List<UserAssignment> assignments;
    }

    public class UserAssignment {
        @AuraEnabled public Id userId;
        @AuraEnabled public Decimal targetValue;
    }

    private static final Map<String, String> METRIC_LABELS = new Map<String, String>{
        'Leads_Generated' => 'Leads Generated',
        'Site_Visits_Completed' => 'Site Visits Completed',
        'Bookings_Closed' => 'Bookings Closed',
        'Revenue' => 'Revenue'
    };

    // ═══════════════════════════════════════════════════════════════════
    //  FILTER OPTIONS
    // ═══════════════════════════════════════════════════════════════════

    public static FilterOptions getFilterOptions() {
        FilterOptions opts = new FilterOptions();

        // Projects
        opts.projects = new List<OptionItem>();
        for (Project__c p : [SELECT Id, Name FROM Project__c ORDER BY Name LIMIT 200]) {
            opts.projects.add(new OptionItem(p.Name, p.Id));
        }

        // Active Users
        opts.users = new List<OptionItem>();
        for (User u : [SELECT Id, Name FROM User WHERE IsActive = true ORDER BY Name LIMIT 500]) {
            opts.users.add(new OptionItem(u.Name, u.Id));
        }

        // Metrics - dynamic from picklist
        opts.metrics = new List<OptionItem>();
        Schema.DescribeFieldResult metricField = Performance_Target__c.Metric__c.getDescribe();
        for (Schema.PicklistEntry ple : metricField.getPicklistValues()) {
            if (ple.isActive()) {
                opts.metrics.add(new OptionItem(ple.getLabel(), ple.getValue()));
            }
        }

        // Periods - dynamic from picklist
        opts.periods = new List<OptionItem>();
        Schema.DescribeFieldResult periodField = Performance_Target__c.Period_Type__c.getDescribe();
        for (Schema.PicklistEntry ple : periodField.getPicklistValues()) {
            if (ple.isActive()) {
                opts.periods.add(new OptionItem(ple.getLabel(), ple.getValue()));
            }
        }

        // Target Levels - dynamic from picklist
        opts.targetLevels = new List<OptionItem>();
        Schema.DescribeFieldResult levelField = Performance_Target__c.Target_Level__c.getDescribe();
        for (Schema.PicklistEntry ple : levelField.getPicklistValues()) {
            if (ple.isActive()) {
                opts.targetLevels.add(new OptionItem(ple.getLabel(), ple.getValue()));
            }
        }

        // Teams - from UserRole
        opts.teams = new List<OptionItem>();
        for (UserRole r : [SELECT Id, Name FROM UserRole WHERE PortalType = 'None' ORDER BY Name LIMIT 200]) {
            opts.teams.add(new OptionItem(r.Name, r.Name));
        }

        return opts;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  GET TARGETS
    // ═══════════════════════════════════════════════════════════════════

    public static List<TargetSummary> getTargets(TargetFilter filter) {
        String soql = 'SELECT Id, Name, Target_Level__c, Metric__c, Assignee__c, Assignee__r.Name, '
            + 'Team_Role__c, Project__c, Project__r.Name, Period_Type__c, Period_Start__c, Period_End__c, '
            + 'Period_Label__c, Target_Value__c, Actual_Value__c, Achievement_Pct__c, Remaining__c, '
            + 'Status__c, Is_Active__c, Last_Calculated__c, Parent_Target__c, Created_From__c, Description__c '
            + 'FROM Performance_Target__c WHERE Is_Active__c = true';

        List<Object> binds = new List<Object>();

        if (filter.targetId != null) {
            soql += ' AND Id = :targetId';
        }
        if (filter.projectId != null) {
            soql += ' AND Project__c = :projectId';
        }
        if (filter.assigneeId != null) {
            soql += ' AND Assignee__c = :assigneeId';
        }
        if (filter.metric != null && filter.metric != '') {
            soql += ' AND Metric__c = :metric';
        }
        if (filter.level != null && filter.level != '') {
            soql += ' AND Target_Level__c = :level';
        }
        if (filter.periodType != null && filter.periodType != '') {
            soql += ' AND Period_Type__c = :periodType';
        }
        if (filter.startDate != null) {
            soql += ' AND Period_Start__c >= :startDate';
        }
        if (filter.endDate != null) {
            soql += ' AND Period_End__c <= :endDate';
        }
        soql += ' ORDER BY Assignee__r.Name, Metric__c';

        // Bind variables
        Id targetId = filter.targetId;
        Id projectId = filter.projectId;
        Id assigneeId = filter.assigneeId;
        String metric = filter.metric;
        String level = filter.level;
        String periodType = filter.periodType;
        Date startDate = filter.startDate;
        Date endDate = filter.endDate;

        List<Performance_Target__c> targets = Database.query(soql);

        // Calculate live actuals
        Map<Id, Decimal> liveActuals = calculateLiveActuals(targets);

        List<TargetSummary> summaries = new List<TargetSummary>();
        for (Performance_Target__c t : targets) {
            TargetSummary s = new TargetSummary();
            s.target = t;
            s.liveActual = liveActuals.containsKey(t.Id) ? liveActuals.get(t.Id) : 0;
            s.assigneeName = t.Assignee__r != null ? t.Assignee__r.Name : (t.Team_Role__c != null ? t.Team_Role__c : 'Organization');
            summaries.add(s);
        }
        return summaries;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DASHBOARD DATA
    // ═══════════════════════════════════════════════════════════════════

    public static DashboardData getDashboardData(TargetFilter filter) {
        List<TargetSummary> targetSummaries = getTargets(filter);

        DashboardData data = new DashboardData();
        data.targets = targetSummaries;
        data.totalTargets = targetSummaries.size();
        data.targetsAtRisk = 0;
        data.topPerformerName = '';

        Decimal totalAchievement = 0;
        Decimal topAchievement = -1;
        Map<String, MetricBreakdown> breakdownMap = new Map<String, MetricBreakdown>();

        for (TargetSummary ts : targetSummaries) {
            Decimal pct = ts.target.Target_Value__c > 0
                ? (ts.liveActual / ts.target.Target_Value__c) * 100
                : 0;
            totalAchievement += pct;

            // At risk: achievement < 50%
            if (pct < 50) {
                data.targetsAtRisk++;
            }

            // Top performer
            if (pct > topAchievement && ts.target.Target_Level__c == 'User') {
                topAchievement = pct;
                data.topPerformerName = ts.assigneeName;
            }

            // Metric breakdown
            String m = ts.target.Metric__c;
            if (!breakdownMap.containsKey(m)) {
                MetricBreakdown mb = new MetricBreakdown();
                mb.metric = m;
                mb.metricLabel = METRIC_LABELS.containsKey(m) ? METRIC_LABELS.get(m) : m;
                mb.totalTarget = 0;
                mb.totalActual = 0;
                breakdownMap.put(m, mb);
            }
            MetricBreakdown mb = breakdownMap.get(m);
            mb.totalTarget += ts.target.Target_Value__c;
            mb.totalActual += ts.liveActual;
        }

        data.avgAchievement = data.totalTargets > 0 ? (totalAchievement / data.totalTargets).setScale(1) : 0;

        // Finalize metric breakdowns
        data.metricBreakdown = new List<MetricBreakdown>();
        for (MetricBreakdown mb : breakdownMap.values()) {
            mb.achievementPct = mb.totalTarget > 0 ? ((mb.totalActual / mb.totalTarget) * 100).setScale(1) : 0;
            data.metricBreakdown.add(mb);
        }

        // Trend data: get snapshots for the filtered period
        data.trendData = getAggregatedTrendData(filter);

        return data;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  LEADERBOARD
    // ═══════════════════════════════════════════════════════════════════

    public static List<LeaderboardEntry> getLeaderboard(TargetFilter filter) {
        // Force user-level only for leaderboard
        filter.level = 'User';
        List<TargetSummary> targets = getTargets(filter);

        // Group by assignee: average achievement across metrics
        Map<Id, LeaderboardEntry> entryMap = new Map<Id, LeaderboardEntry>();
        Map<Id, Integer> countMap = new Map<Id, Integer>();

        for (TargetSummary ts : targets) {
            if (ts.target.Assignee__c == null) continue;

            Id uid = ts.target.Assignee__c;
            Decimal pct = ts.target.Target_Value__c > 0
                ? (ts.liveActual / ts.target.Target_Value__c) * 100
                : 0;

            if (!entryMap.containsKey(uid)) {
                LeaderboardEntry e = new LeaderboardEntry();
                e.assigneeId = uid;
                e.assigneeName = ts.assigneeName;
                e.achievementPct = 0;
                e.targetValue = 0;
                e.actualValue = 0;
                e.metric = 'All';
                entryMap.put(uid, e);
                countMap.put(uid, 0);
            }

            LeaderboardEntry e = entryMap.get(uid);
            e.targetValue += ts.target.Target_Value__c;
            e.actualValue += ts.liveActual;
            e.achievementPct += pct;
            countMap.put(uid, countMap.get(uid) + 1);
        }

        // Average achievement and sort
        List<LeaderboardEntry> entries = new List<LeaderboardEntry>();
        for (Id uid : entryMap.keySet()) {
            LeaderboardEntry e = entryMap.get(uid);
            Integer cnt = countMap.get(uid);
            e.achievementPct = cnt > 0 ? (e.achievementPct / cnt).setScale(1) : 0;
            entries.add(e);
        }

        // Sort by achievement descending
        entries.sort(new LeaderboardComparator());

        // Assign ranks
        for (Integer i = 0; i < entries.size(); i++) {
            entries[i].rank = i + 1;
        }

        return entries;
    }

    // Custom comparator for leaderboard sorting
    private class LeaderboardComparator implements Comparator<LeaderboardEntry> {
        public Integer compare(LeaderboardEntry a, LeaderboardEntry b) {
            if (a.achievementPct > b.achievementPct) return -1;
            if (a.achievementPct < b.achievementPct) return 1;
            return 0;
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TARGET CRUD
    // ═══════════════════════════════════════════════════════════════════

    public static Performance_Target__c saveTarget(Performance_Target__c target) {
        upsert target;
        return target;
    }

    public static void deleteTarget(Id targetId) {
        Performance_Target__c t = [SELECT Id FROM Performance_Target__c WHERE Id = :targetId LIMIT 1];
        delete t;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BULK CREATE
    // ═══════════════════════════════════════════════════════════════════

    public static List<Performance_Target__c> bulkCreateTargets(BulkAssignment assignment) {
        List<Performance_Target__c> targets = new List<Performance_Target__c>();

        for (UserAssignment ua : assignment.assignments) {
            Performance_Target__c t = new Performance_Target__c();
            t.Target_Level__c = 'User';
            t.Metric__c = assignment.metric;
            t.Period_Type__c = assignment.periodType;
            t.Period_Start__c = assignment.periodStart;
            t.Period_End__c = assignment.periodEnd;
            t.Assignee__c = ua.userId;
            t.Target_Value__c = ua.targetValue;
            t.Is_Active__c = true;
            t.Description__c = assignment.description;

            if (assignment.projectId != null) {
                t.Project__c = assignment.projectId;
            }
            if (assignment.parentTargetId != null) {
                t.Parent_Target__c = assignment.parentTargetId;
            }
            targets.add(t);
        }

        insert targets;
        return targets;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  CLONE TARGETS
    // ═══════════════════════════════════════════════════════════════════

    public static List<Performance_Target__c> cloneTargets(TargetFilter sourceFilter, Date newPeriodStart, Date newPeriodEnd) {
        List<TargetSummary> sourceSummaries = getTargets(sourceFilter);
        List<Performance_Target__c> clones = new List<Performance_Target__c>();

        for (TargetSummary ts : sourceSummaries) {
            Performance_Target__c source = ts.target;
            Performance_Target__c clone = new Performance_Target__c();
            clone.Target_Level__c = source.Target_Level__c;
            clone.Metric__c = source.Metric__c;
            clone.Assignee__c = source.Assignee__c;
            clone.Team_Role__c = source.Team_Role__c;
            clone.Project__c = source.Project__c;
            clone.Period_Type__c = source.Period_Type__c;
            clone.Period_Start__c = newPeriodStart;
            clone.Period_End__c = newPeriodEnd;
            clone.Target_Value__c = source.Target_Value__c;
            clone.Actual_Value__c = 0;
            clone.Is_Active__c = true;
            clone.Created_From__c = source.Id;
            clone.Description__c = source.Description__c;
            clones.add(clone);
        }

        insert clones;
        return clones;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  LIVE ACTUALS CALCULATION
    // ═══════════════════════════════════════════════════════════════════

    public static Map<Id, Decimal> calculateLiveActuals(List<Performance_Target__c> targets) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();

        // Separate user-level vs parent-level targets
        List<Performance_Target__c> userTargets = new List<Performance_Target__c>();
        List<Performance_Target__c> parentTargets = new List<Performance_Target__c>();

        for (Performance_Target__c t : targets) {
            result.put(t.Id, 0);
            if (t.Target_Level__c == 'User' && t.Assignee__c != null) {
                userTargets.add(t);
            } else {
                parentTargets.add(t);
            }
        }

        // Group user targets by metric
        Map<String, List<Performance_Target__c>> byMetric = new Map<String, List<Performance_Target__c>>();
        for (Performance_Target__c t : userTargets) {
            if (!byMetric.containsKey(t.Metric__c)) {
                byMetric.put(t.Metric__c, new List<Performance_Target__c>());
            }
            byMetric.get(t.Metric__c).add(t);
        }

        // Calculate actuals per metric
        for (String metricKey : byMetric.keySet()) {
            List<Performance_Target__c> metricTargets = byMetric.get(metricKey);
            Map<Id, Decimal> metricActuals = calculateMetricActuals(metricKey, metricTargets);
            result.putAll(metricActuals);
        }

        // Roll up parent targets
        if (!parentTargets.isEmpty()) {
            Set<Id> parentIds = new Set<Id>();
            for (Performance_Target__c p : parentTargets) {
                parentIds.add(p.Id);
            }
            Map<Id, Decimal> parentActuals = calculateParentActuals(parentIds);
            result.putAll(parentActuals);
        }

        return result;
    }

    private static Map<Id, Decimal> calculateMetricActuals(String metricKey, List<Performance_Target__c> targets) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();

        // Build lookup: for each target, map its assignee+period+project to target Id
        // We need to query per unique (assignee, period) combination
        // For efficiency, gather all assignee IDs and find the widest date range
        Set<Id> assigneeIds = new Set<Id>();
        Date minStart = null;
        Date maxEnd = null;

        for (Performance_Target__c t : targets) {
            assigneeIds.add(t.Assignee__c);
            if (minStart == null || t.Period_Start__c < minStart) minStart = t.Period_Start__c;
            if (maxEnd == null || t.Period_End__c > maxEnd) maxEnd = t.Period_End__c;
            result.put(t.Id, 0);
        }

        if (assigneeIds.isEmpty() || minStart == null) return result;

        // Run aggregate query based on metric
        Map<String, Decimal> ownerActuals = new Map<String, Decimal>();

        if (metricKey == 'Leads_Generated') {
            ownerActuals = queryLeadActuals(assigneeIds, targets);
        } else if (metricKey == 'Site_Visits_Completed') {
            ownerActuals = querySiteVisitActuals(assigneeIds, targets);
        } else if (metricKey == 'Bookings_Closed') {
            ownerActuals = queryBookingCountActuals(assigneeIds, targets);
        } else if (metricKey == 'Revenue') {
            ownerActuals = queryRevenueActuals(assigneeIds, targets);
        }

        // Map results back to target IDs
        for (Performance_Target__c t : targets) {
            String key = buildActualKey(t);
            if (ownerActuals.containsKey(key)) {
                result.put(t.Id, ownerActuals.get(key));
            }
        }

        return result;
    }

    private static String buildActualKey(Performance_Target__c t) {
        return String.valueOf(t.Assignee__c) + '_' + String.valueOf(t.Period_Start__c) + '_' + String.valueOf(t.Period_End__c) + '_' + (t.Project__c != null ? String.valueOf(t.Project__c) : 'ALL');
    }

    private static Map<String, Decimal> queryLeadActuals(Set<Id> assigneeIds, List<Performance_Target__c> targets) {
        Map<String, Decimal> result = new Map<String, Decimal>();

        for (Performance_Target__c t : targets) {
            // Lead CreatedDate is DateTime, so use >= start and < end+1
            DateTime dtStart = DateTime.newInstance(t.Period_Start__c, Time.newInstance(0, 0, 0, 0));
            DateTime dtEnd = DateTime.newInstance(t.Period_End__c.addDays(1), Time.newInstance(0, 0, 0, 0));
            Id ownerId = t.Assignee__c;

            // Count leads where user is Owner OR Pre_Sale_User (covers leads pushed to sales)
            String soql = 'SELECT COUNT() FROM Lead__c WHERE (Owner__c = :ownerId OR Pre_Sale_User__c = :ownerId) AND CreatedDate >= :dtStart AND CreatedDate < :dtEnd';
            if (t.Project__c != null) {
                Id projId = t.Project__c;
                soql += ' AND Project__c = :projId';
            }
            Integer cnt = Database.countQuery(soql);
            result.put(buildActualKey(t), cnt);
        }

        return result;
    }

    private static Map<String, Decimal> querySiteVisitActuals(Set<Id> assigneeIds, List<Performance_Target__c> targets) {
        Map<String, Decimal> result = new Map<String, Decimal>();

        for (Performance_Target__c t : targets) {
            Id ownerId = t.Assignee__c;
            Date pStart = t.Period_Start__c;
            Date pEnd = t.Period_End__c;

            String soql = 'SELECT COUNT() FROM Site_Visit__c WHERE Assigned_To__c = :ownerId AND Completed_Date__c >= :pStart AND Completed_Date__c <= :pEnd AND Status__c = \'Completed\'';
            if (t.Project__c != null) {
                Id projId = t.Project__c;
                soql += ' AND Project__c = :projId';
            }
            Integer cnt = Database.countQuery(soql);
            result.put(buildActualKey(t), cnt);
        }

        return result;
    }

    private static Map<String, Decimal> queryBookingCountActuals(Set<Id> assigneeIds, List<Performance_Target__c> targets) {
        Map<String, Decimal> result = new Map<String, Decimal>();

        for (Performance_Target__c t : targets) {
            Id ownerId = t.Assignee__c;
            Date pStart = t.Period_Start__c;
            Date pEnd = t.Period_End__c;

            String soql = 'SELECT COUNT() FROM Booking__c WHERE Owner__c = :ownerId AND Booking_Date__c >= :pStart AND Booking_Date__c <= :pEnd';
            if (t.Project__c != null) {
                Id projId = t.Project__c;
                soql += ' AND Project__c = :projId';
            }
            Integer cnt = Database.countQuery(soql);
            result.put(buildActualKey(t), cnt);
        }

        return result;
    }

    private static Map<String, Decimal> queryRevenueActuals(Set<Id> assigneeIds, List<Performance_Target__c> targets) {
        Map<String, Decimal> result = new Map<String, Decimal>();

        for (Performance_Target__c t : targets) {
            Id ownerId = t.Assignee__c;
            Date pStart = t.Period_Start__c;
            Date pEnd = t.Period_End__c;

            String soql = 'SELECT SUM(Net_Value__c) total FROM Booking__c WHERE Owner__c = :ownerId AND Booking_Date__c >= :pStart AND Booking_Date__c <= :pEnd';
            if (t.Project__c != null) {
                Id projId = t.Project__c;
                soql += ' AND Project__c = :projId';
                List<AggregateResult> agg = Database.query(soql);
                Decimal total = agg[0].get('total') != null ? (Decimal) agg[0].get('total') : 0;
                result.put(buildActualKey(t), total);
            } else {
                List<AggregateResult> agg = Database.query(soql);
                Decimal total = agg[0].get('total') != null ? (Decimal) agg[0].get('total') : 0;
                result.put(buildActualKey(t), total);
            }
        }

        return result;
    }

    private static Map<Id, Decimal> calculateParentActuals(Set<Id> parentIds) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        for (Id pid : parentIds) {
            result.put(pid, 0);
        }

        for (AggregateResult ar : [
            SELECT Parent_Target__c parentId, SUM(Actual_Value__c) total
            FROM Performance_Target__c
            WHERE Parent_Target__c IN :parentIds AND Is_Active__c = true
            GROUP BY Parent_Target__c
        ]) {
            Id parentId = (Id) ar.get('parentId');
            Decimal total = ar.get('total') != null ? (Decimal) ar.get('total') : 0;
            result.put(parentId, total);
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ROLLUP PARENT TARGETS
    // ═══════════════════════════════════════════════════════════════════

    public static void rollupParentTargets(Set<Id> parentIds) {
        if (parentIds.isEmpty()) return;

        Map<Id, Decimal> parentActuals = calculateParentActuals(parentIds);
        List<Performance_Target__c> toUpdate = new List<Performance_Target__c>();

        for (Id pid : parentActuals.keySet()) {
            Performance_Target__c p = new Performance_Target__c(Id = pid);
            p.Actual_Value__c = parentActuals.get(pid);
            p.Last_Calculated__c = DateTime.now();
            toUpdate.add(p);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TREND DATA
    // ═══════════════════════════════════════════════════════════════════

    public static List<TrendPoint> getTrendData(Id targetId) {
        List<TrendPoint> points = new List<TrendPoint>();
        for (Performance_Snapshot__c snap : [
            SELECT Snapshot_Date__c, Actual_Value__c, Achievement_Pct__c
            FROM Performance_Snapshot__c
            WHERE Performance_Target__c = :targetId
            ORDER BY Snapshot_Date__c ASC
        ]) {
            TrendPoint tp = new TrendPoint();
            tp.snapshotDate = snap.Snapshot_Date__c;
            tp.actualValue = snap.Actual_Value__c;
            tp.achievementPct = snap.Achievement_Pct__c != null ? snap.Achievement_Pct__c * 100 : 0;
            points.add(tp);
        }

        // If no snapshot data exists, generate a current data point from live actuals
        // This ensures trend charts work even before the batch job has run
        Performance_Target__c target = [
            SELECT Id, Metric__c, Assignee__c, Target_Value__c, Period_Start__c, Period_End__c,
                   Project__c, Target_Level__c
            FROM Performance_Target__c WHERE Id = :targetId LIMIT 1
        ];

        if (target != null && target.Target_Level__c == 'User' && target.Assignee__c != null) {
            Map<Id, Decimal> liveActuals = calculateLiveActuals(new List<Performance_Target__c>{ target });
            Decimal currentActual = liveActuals.containsKey(target.Id) ? liveActuals.get(target.Id) : 0;
            Decimal currentPct = target.Target_Value__c > 0
                ? (currentActual / target.Target_Value__c) * 100
                : 0;

            // Check if we already have today's snapshot in the points list
            Boolean hasTodaySnapshot = false;
            for (TrendPoint tp : points) {
                if (tp.snapshotDate == Date.today()) {
                    // Update with live data
                    tp.actualValue = currentActual;
                    tp.achievementPct = currentPct.setScale(1);
                    hasTodaySnapshot = true;
                    break;
                }
            }

            // Add today's live data point if not already present
            if (!hasTodaySnapshot) {
                TrendPoint todayPoint = new TrendPoint();
                todayPoint.snapshotDate = Date.today();
                todayPoint.actualValue = currentActual;
                todayPoint.achievementPct = currentPct.setScale(1);
                points.add(todayPoint);
            }
        }

        return points;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  AGGREGATED TREND DATA (for dashboard)
    // ═══════════════════════════════════════════════════════════════════

    private static List<TrendPoint> getAggregatedTrendData(TargetFilter filter) {
        List<TrendPoint> points = new List<TrendPoint>();

        String soql = 'SELECT Snapshot_Date__c, AVG(Achievement_Pct__c) avgPct, SUM(Actual_Value__c) totalActual '
            + 'FROM Performance_Snapshot__c WHERE Performance_Target__c IN ('
            + 'SELECT Id FROM Performance_Target__c WHERE Is_Active__c = true AND Target_Level__c = \'User\'';

        if (filter.projectId != null) {
            soql += ' AND Project__c = \'' + String.escapeSingleQuotes(String.valueOf(filter.projectId)) + '\'';
        }
        if (filter.metric != null && filter.metric != '') {
            soql += ' AND Metric__c = \'' + String.escapeSingleQuotes(filter.metric) + '\'';
        }
        if (filter.startDate != null) {
            soql += ' AND Period_Start__c >= ' + String.valueOf(filter.startDate);
        }
        if (filter.endDate != null) {
            soql += ' AND Period_End__c <= ' + String.valueOf(filter.endDate);
        }

        soql += ') GROUP BY Snapshot_Date__c ORDER BY Snapshot_Date__c ASC LIMIT 90';

        for (AggregateResult ar : Database.query(soql)) {
            TrendPoint tp = new TrendPoint();
            tp.snapshotDate = (Date) ar.get('Snapshot_Date__c');
            tp.actualValue = ar.get('totalActual') != null ? (Decimal) ar.get('totalActual') : 0;
            tp.achievementPct = ar.get('avgPct') != null ? ((Decimal) ar.get('avgPct') * 100).setScale(1) : 0;
            points.add(tp);
        }

        // If no snapshot data, add a live data point based on current target summaries
        // so dashboard trend chart always shows something
        if (points.isEmpty()) {
            List<TargetSummary> summaries = getTargets(filter);
            if (!summaries.isEmpty()) {
                Decimal totalActual = 0;
                Decimal totalPct = 0;
                Integer count = 0;

                for (TargetSummary ts : summaries) {
                    totalActual += ts.liveActual;
                    Decimal pct = ts.target.Target_Value__c > 0
                        ? (ts.liveActual / ts.target.Target_Value__c)
                        : 0;
                    totalPct += pct;
                    count++;
                }

                TrendPoint tp = new TrendPoint();
                tp.snapshotDate = Date.today();
                tp.actualValue = totalActual;
                tp.achievementPct = count > 0 ? ((totalPct / count) * 100).setScale(1) : 0;
                points.add(tp);
            }
        }

        return points;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  EXPORT CSV
    // ═══════════════════════════════════════════════════════════════════

    public static String exportCSV(TargetFilter filter) {
        List<TargetSummary> targets = getTargets(filter);
        List<String> lines = new List<String>();

        lines.add('Target ID,Level,Metric,Assignee,Project,Period,Target Value,Actual Value,Achievement %,Status');

        for (TargetSummary ts : targets) {
            Performance_Target__c t = ts.target;
            Decimal pct = t.Target_Value__c > 0 ? (ts.liveActual / t.Target_Value__c * 100).setScale(1) : 0;
            String status = pct >= 100 ? 'Achieved' : (pct >= 75 ? 'On Track' : (pct >= 50 ? 'At Risk' : 'Behind'));

            lines.add(
                t.Name + ','
                + t.Target_Level__c + ','
                + t.Metric__c + ','
                + ts.assigneeName + ','
                + (t.Project__r != null ? t.Project__r.Name : '') + ','
                + t.Period_Label__c + ','
                + t.Target_Value__c + ','
                + ts.liveActual + ','
                + pct + '%,'
                + status
            );
        }

        return String.join(lines, '\n');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  RECALCULATE AND UPDATE STORED ACTUALS
    // ═══════════════════════════════════════════════════════════════════

    public static List<TargetSummary> recalculateAndUpdate(TargetFilter filter) {
        List<TargetSummary> summaries = getTargets(filter);

        List<Performance_Target__c> toUpdate = new List<Performance_Target__c>();
        for (TargetSummary ts : summaries) {
            Performance_Target__c upd = new Performance_Target__c(Id = ts.target.Id);
            upd.Actual_Value__c = ts.liveActual;
            upd.Last_Calculated__c = DateTime.now();
            toUpdate.add(upd);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        return summaries;
    }
}