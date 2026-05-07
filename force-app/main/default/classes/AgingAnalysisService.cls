/**
 * @description Service class for aging analysis reporting across demands, receipts,
 *              complaints, and snags. Provides configurable aging bucket analysis
 *              with project and booking-level drill-down.
 *
 *              Aging Buckets: Current, 1-30 days, 31-60 days, 61-90 days, 90+ days
 *
 *              Supported analysis types:
 *              - Demand Aging: Overdue demands grouped by aging buckets
 *              - Receipt Aging: Pending receipts by age since demand date
 *              - Complaint Aging: Open complaints by days since creation
 *              - Snag Aging: Open snags by days since creation
 *
 * @author System
 * @date 2026-03-31
 */
public with sharing class AgingAnalysisService {

    private static final List<AgingBucket> DEFAULT_BUCKETS = new List<AgingBucket>{
        new AgingBucket('Current', 0, 0),
        new AgingBucket('1-30 Days', 1, 30),
        new AgingBucket('31-60 Days', 31, 60),
        new AgingBucket('61-90 Days', 61, 90),
        new AgingBucket('90+ Days', 91, 9999)
    };

    // ==================== DEMAND AGING ====================

    @AuraEnabled
    public static AgingReport getDemandAgingReport(String projectId) {
        try {
            Date today = Date.today();
            String query = 'SELECT Id, Name, Booking__c, Booking__r.Name, ' +
                'Booking__r.First_Applicant_Name__c, Booking__r.Unit__r.Name, ' +
                'Project__c, Project__r.Name, ' +
                'Demand_Amount__c, Paid_Amount__c, Pending_Amount__c, ' +
                'Due_Date__c, Status__c, Demand_Type__c ' +
                'FROM Demands__c ' +
                'WHERE Status__c NOT IN (\'Paid\', \'Cancelled\', \'On Hold\') ' +
                'AND Due_Date__c < :today ';

            if (String.isNotBlank(projectId)) {
                query += 'AND Project__c = :projectId ';
            }
            query += 'ORDER BY Due_Date__c ASC LIMIT 2000';

            List<Demands__c> demands = Database.query(query);

            AgingReport report = new AgingReport();
            report.reportType = 'Demand Aging';
            report.generatedDate = DateTime.now();
            report.buckets = initBuckets();
            report.projectBreakdown = new List<ProjectAgingSummary>();

            Map<Id, ProjectAgingSummary> projectMap = new Map<Id, ProjectAgingSummary>();
            Decimal totalOverdue = 0;

            for (Demands__c demand : demands) {
                Integer daysOverdue = demand.Due_Date__c.daysBetween(today);
                Decimal pendingAmt = demand.Pending_Amount__c != null ? demand.Pending_Amount__c : 0;
                totalOverdue += pendingAmt;

                // Bucket the amount
                for (AgingBucketResult bucket : report.buckets) {
                    if (daysOverdue >= bucket.minDays && daysOverdue <= bucket.maxDays) {
                        bucket.amount += pendingAmt;
                        bucket.count++;
                        break;
                    }
                }

                // Project breakdown
                Id projId = demand.Project__c;
                if (projId != null) {
                    if (!projectMap.containsKey(projId)) {
                        ProjectAgingSummary ps = new ProjectAgingSummary();
                        ps.projectId = projId;
                        ps.projectName = demand.Project__r.Name;
                        ps.buckets = initBuckets();
                        ps.totalAmount = 0;
                        ps.totalCount = 0;
                        ps.records = new List<AgingRecord>();
                        projectMap.put(projId, ps);
                    }
                    ProjectAgingSummary ps = projectMap.get(projId);
                    ps.totalAmount += pendingAmt;
                    ps.totalCount++;

                    for (AgingBucketResult bucket : ps.buckets) {
                        if (daysOverdue >= bucket.minDays && daysOverdue <= bucket.maxDays) {
                            bucket.amount += pendingAmt;
                            bucket.count++;
                            break;
                        }
                    }

                    // Add individual record (limit per project for performance)
                    if (ps.records.size() < 100) {
                        AgingRecord rec = new AgingRecord();
                        rec.recordId = demand.Id;
                        rec.recordName = demand.Name;
                        rec.bookingName = demand.Booking__r != null ? demand.Booking__r.Name : '';
                        rec.customerName = demand.Booking__r != null ? demand.Booking__r.First_Applicant_Name__c : '';
                        rec.unitName = demand.Booking__r != null && demand.Booking__r.Unit__r != null
                            ? demand.Booking__r.Unit__r.Name : '';
                        rec.amount = pendingAmt;
                        rec.daysOverdue = daysOverdue;
                        rec.dueDate = demand.Due_Date__c;
                        rec.status = demand.Status__c;
                        ps.records.add(rec);
                    }
                }
            }

            report.totalAmount = totalOverdue;
            report.totalRecords = demands.size();
            report.projectBreakdown = projectMap.values();
            return report;
        } catch (Exception e) {
            throw new AuraHandledException('Error generating demand aging report: ' + e.getMessage());
        }
    }

    // ==================== COMPLAINT AGING ====================

    @AuraEnabled
    public static AgingReport getComplaintAgingReport(String projectId) {
        try {
            Date today = Date.today();
            String query = 'SELECT Id, Name, Subject__c, Category__c, Priority__c, Status__c, ' +
                'Complaint_Date__c, Expected_Resolution_Date__c, Escalation_Level__c, ' +
                'Customer_Name__c, Assigned_To__r.Name, ' +
                'Project__c, Project__r.Name, ' +
                'Booking__r.Name, Booking__r.Unit__r.Name ' +
                'FROM Complaint__c ' +
                'WHERE Status__c NOT IN (\'Closed\', \'Resolved\', \'Cancelled\') ';

            if (String.isNotBlank(projectId)) {
                query += 'AND Project__c = :projectId ';
            }
            query += 'ORDER BY Complaint_Date__c ASC LIMIT 2000';

            List<Complaint__c> complaints = Database.query(query);

            AgingReport report = new AgingReport();
            report.reportType = 'Complaint Aging';
            report.generatedDate = DateTime.now();
            report.buckets = initBuckets();
            report.projectBreakdown = new List<ProjectAgingSummary>();

            Map<Id, ProjectAgingSummary> projectMap = new Map<Id, ProjectAgingSummary>();

            for (Complaint__c complaint : complaints) {
                Integer daysOpen = complaint.Complaint_Date__c != null
                    ? Date.valueOf(complaint.Complaint_Date__c).daysBetween(today) : 0;

                for (AgingBucketResult bucket : report.buckets) {
                    if (daysOpen >= bucket.minDays && daysOpen <= bucket.maxDays) {
                        bucket.count++;
                        break;
                    }
                }

                Id projId = complaint.Project__c;
                if (projId != null) {
                    if (!projectMap.containsKey(projId)) {
                        ProjectAgingSummary ps = new ProjectAgingSummary();
                        ps.projectId = projId;
                        ps.projectName = complaint.Project__r.Name;
                        ps.buckets = initBuckets();
                        ps.totalAmount = 0;
                        ps.totalCount = 0;
                        ps.records = new List<AgingRecord>();
                        projectMap.put(projId, ps);
                    }
                    ProjectAgingSummary ps = projectMap.get(projId);
                    ps.totalCount++;

                    for (AgingBucketResult bucket : ps.buckets) {
                        if (daysOpen >= bucket.minDays && daysOpen <= bucket.maxDays) {
                            bucket.count++;
                            break;
                        }
                    }

                    if (ps.records.size() < 100) {
                        AgingRecord rec = new AgingRecord();
                        rec.recordId = complaint.Id;
                        rec.recordName = complaint.Name;
                        rec.bookingName = complaint.Booking__r != null ? complaint.Booking__r.Name : '';
                        rec.customerName = complaint.Customer_Name__c;
                        rec.unitName = complaint.Booking__r != null && complaint.Booking__r.Unit__r != null
                            ? complaint.Booking__r.Unit__r.Name : '';
                        rec.daysOverdue = daysOpen;
                        rec.dueDate = complaint.Expected_Resolution_Date__c;
                        rec.status = complaint.Status__c;
                        rec.priority = complaint.Priority__c;
                        rec.category = complaint.Category__c;
                        rec.escalationLevel = complaint.Escalation_Level__c != null
                            ? Integer.valueOf(complaint.Escalation_Level__c) : 0;
                        ps.records.add(rec);
                    }
                }
            }

            report.totalRecords = complaints.size();
            report.projectBreakdown = projectMap.values();
            return report;
        } catch (Exception e) {
            throw new AuraHandledException('Error generating complaint aging report: ' + e.getMessage());
        }
    }

    // ==================== SNAG AGING ====================

    @AuraEnabled
    public static AgingReport getSnagAgingReport(String projectId) {
        try {
            Date today = Date.today();
            String query = 'SELECT Id, Name, Description__c, Category__c, Priority__c, Status__c, ' +
                'CreatedDate, Expected_Completion_Date__c, ' +
                'Assigned_To__r.Name, ' +
                'Booking__c, Booking__r.Name, Booking__r.Unit__r.Name, ' +
                'Booking__r.Project__c, Booking__r.Project__r.Name ' +
                'FROM Snag__c ' +
                'WHERE Status__c NOT IN (\'Completed\', \'Closed\', \'Cancelled\', \'Verified\') ';

            if (String.isNotBlank(projectId)) {
                query += 'AND Booking__r.Project__c = :projectId ';
            }
            query += 'ORDER BY CreatedDate ASC LIMIT 2000';

            List<Snag__c> snags = Database.query(query);

            AgingReport report = new AgingReport();
            report.reportType = 'Snag Aging';
            report.generatedDate = DateTime.now();
            report.buckets = initBuckets();
            report.projectBreakdown = new List<ProjectAgingSummary>();

            Map<Id, ProjectAgingSummary> projectMap = new Map<Id, ProjectAgingSummary>();

            for (Snag__c snag : snags) {
                Integer daysOpen = Date.valueOf(snag.CreatedDate).daysBetween(today);

                for (AgingBucketResult bucket : report.buckets) {
                    if (daysOpen >= bucket.minDays && daysOpen <= bucket.maxDays) {
                        bucket.count++;
                        break;
                    }
                }

                Id projId = snag.Booking__r != null ? snag.Booking__r.Project__c : null;
                if (projId != null) {
                    if (!projectMap.containsKey(projId)) {
                        ProjectAgingSummary ps = new ProjectAgingSummary();
                        ps.projectId = projId;
                        ps.projectName = snag.Booking__r.Project__r.Name;
                        ps.buckets = initBuckets();
                        ps.totalAmount = 0;
                        ps.totalCount = 0;
                        ps.records = new List<AgingRecord>();
                        projectMap.put(projId, ps);
                    }
                    ProjectAgingSummary ps = projectMap.get(projId);
                    ps.totalCount++;

                    for (AgingBucketResult bucket : ps.buckets) {
                        if (daysOpen >= bucket.minDays && daysOpen <= bucket.maxDays) {
                            bucket.count++;
                            break;
                        }
                    }

                    if (ps.records.size() < 100) {
                        AgingRecord rec = new AgingRecord();
                        rec.recordId = snag.Id;
                        rec.recordName = snag.Name;
                        rec.bookingName = snag.Booking__r != null ? snag.Booking__r.Name : '';
                        rec.unitName = snag.Booking__r != null && snag.Booking__r.Unit__r != null
                            ? snag.Booking__r.Unit__r.Name : '';
                        rec.daysOverdue = daysOpen;
                        rec.dueDate = snag.Expected_Completion_Date__c;
                        rec.status = snag.Status__c;
                        rec.priority = snag.Priority__c;
                        rec.category = snag.Category__c;
                        ps.records.add(rec);
                    }
                }
            }

            report.totalRecords = snags.size();
            report.projectBreakdown = projectMap.values();
            return report;
        } catch (Exception e) {
            throw new AuraHandledException('Error generating snag aging report: ' + e.getMessage());
        }
    }

    // ==================== COMBINED OVERVIEW ====================

    @AuraEnabled
    public static Map<String, AgingReport> getAgingOverview(String projectId) {
        Map<String, AgingReport> overview = new Map<String, AgingReport>();
        overview.put('demands', getDemandAgingReport(projectId));
        overview.put('complaints', getComplaintAgingReport(projectId));
        overview.put('snags', getSnagAgingReport(projectId));
        return overview;
    }

    // ==================== PROJECT LIST ====================

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getProjectOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (Project__c p : [SELECT Id, Name FROM Project__c ORDER BY Name]) {
            Map<String, String> opt = new Map<String, String>();
            opt.put('label', p.Name);
            opt.put('value', p.Id);
            options.add(opt);
        }
        return options;
    }

    // ==================== HELPER METHODS ====================

    private static List<AgingBucketResult> initBuckets() {
        List<AgingBucketResult> buckets = new List<AgingBucketResult>();
        for (AgingBucket def : DEFAULT_BUCKETS) {
            AgingBucketResult b = new AgingBucketResult();
            b.label = def.label;
            b.minDays = def.minDays;
            b.maxDays = def.maxDays;
            b.count = 0;
            b.amount = 0;
            buckets.add(b);
        }
        return buckets;
    }

    // ==================== INNER CLASSES ====================

    private class AgingBucket {
        String label;
        Integer minDays;
        Integer maxDays;
        AgingBucket(String label, Integer minDays, Integer maxDays) {
            this.label = label;
            this.minDays = minDays;
            this.maxDays = maxDays;
        }
    }

    public class AgingReport {
        @AuraEnabled public String reportType;
        @AuraEnabled public DateTime generatedDate;
        @AuraEnabled public List<AgingBucketResult> buckets;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public List<ProjectAgingSummary> projectBreakdown;
    }

    public class AgingBucketResult {
        @AuraEnabled public String label;
        @AuraEnabled public Integer minDays;
        @AuraEnabled public Integer maxDays;
        @AuraEnabled public Integer count;
        @AuraEnabled public Decimal amount;
    }

    public class ProjectAgingSummary {
        @AuraEnabled public Id projectId;
        @AuraEnabled public String projectName;
        @AuraEnabled public List<AgingBucketResult> buckets;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<AgingRecord> records;
    }

    public class AgingRecord {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String bookingName;
        @AuraEnabled public String customerName;
        @AuraEnabled public String unitName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Integer daysOverdue;
        @AuraEnabled public Date dueDate;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String category;
        @AuraEnabled public Integer escalationLevel;
    }
}