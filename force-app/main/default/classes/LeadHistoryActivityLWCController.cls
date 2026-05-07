public with sharing class LeadHistoryActivityLWCController {

    @AuraEnabled
    public static List<HistoryActivityWrapper> getData(String leadId, String filter) {
        if (String.isBlank(leadId)) {
            throw new AuraHandledException('Lead ID is required.');
        }

        List<HistoryActivityWrapper> results = new List<HistoryActivityWrapper>();

        // Dynamic field label resolution for Lead__c
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get('Lead__c')
            .getDescribe()
            .fields
            .getMap();

        // Lead Field History
        if (filter == 'All' || filter == 'Field Updates') {
            List<Lead__History> historyList = [
                SELECT Id, CreatedById, CreatedBy.Name, CreatedDate, Field, NewValue, OldValue
                FROM Lead__History
                WHERE ParentId = :leadId
            ];

            for (Lead__History lh : historyList) {
                if (lh.Field == null || lh.Field == 'Last_Comment__c') {
                    continue;
                }

                HistoryActivityWrapper wrapper = new HistoryActivityWrapper();
                wrapper.createdById = lh.CreatedById;
                wrapper.createdByName = lh.CreatedBy.Name;
                wrapper.createdDate = lh.CreatedDate;
                wrapper.recordType = 'History';
                wrapper.recordId = lh.Id;

                // Dynamic field label resolution
                if (fieldMap.containsKey(lh.Field)) {
                    wrapper.fieldLabel = fieldMap.get(lh.Field).getDescribe().getLabel();
                } else {
                    wrapper.fieldLabel = lh.Field;
                }

                // Filter out raw User IDs (starting with '005')
                String newVal = String.valueOf(lh.NewValue);
                String oldVal = String.valueOf(lh.OldValue);

                if (newVal != null && !newVal.startsWith('005')) {
                    wrapper.newValue = newVal;
                }
                if (oldVal != null && !oldVal.startsWith('005')) {
                    wrapper.oldValue = oldVal;
                }

                // Skip records where both values were filtered out (e.g. raw User IDs)
                // to avoid empty history entries with no visible content
                if (wrapper.newValue == null && wrapper.oldValue == null && wrapper.fieldLabel != 'created') {
                    continue;
                }

                results.add(wrapper);
            }
        }

        // Activity Histories
        if (filter == 'All' || filter == 'Activities') {
            List<Lead__c> leadList = [
                SELECT Id,
                    (SELECT Id, Subject, Description, CreatedDate, CreatedById, CreatedBy.Name
                     FROM ActivityHistories
                     ORDER BY ActivityDate DESC, LastModifiedDate DESC
                     LIMIT 500)
                FROM Lead__c
                WHERE Id = :leadId
            ];

            for (Lead__c lead : leadList) {
                for (ActivityHistory ah : lead.ActivityHistories) {
                    if (ah.Subject == null) {
                        continue;
                    }

                    HistoryActivityWrapper wrapper = new HistoryActivityWrapper();
                    wrapper.createdById = ah.CreatedById;
                    wrapper.createdByName = ah.CreatedBy.Name;
                    wrapper.createdDate = ah.CreatedDate;
                    wrapper.recordType = 'Activity';
                    wrapper.subject = ah.Subject;
                    wrapper.description = ah.Description;
                    wrapper.recordId = ah.Id;
                    results.add(wrapper);
                }
            }
        }

        // Call Details
        if (filter == 'All' || filter == 'Calls') {
            List<Call_Detail__c> callList = [
                SELECT Id, Name, CreatedDate, CreatedById, Call_From__c, Call_ID__c,
                       Call_To__c, Call_Type__c, Duration__c, Lead__c,
                       Recording_File__c, Status__c, Owner.Name, Comments__c
                FROM Call_Detail__c
                WHERE lead1__c = :leadId
            ];

            for (Call_Detail__c cd : callList) {
                HistoryActivityWrapper wrapper = new HistoryActivityWrapper();
                wrapper.createdByName = cd.Owner.Name;
                wrapper.createdDate = cd.CreatedDate;
                wrapper.createdById = cd.CreatedById;
                wrapper.recordType = 'Call';
                wrapper.recordId = cd.Id;
                wrapper.callType = cd.Call_Type__c;
                wrapper.callFrom = cd.Call_From__c;
                wrapper.callTo = cd.Call_To__c;
                wrapper.callStatus = cd.Status__c;
                wrapper.callUrl = cd.Recording_File__c;
                wrapper.comments = cd.Comments__c;
                results.add(wrapper);
            }
        }

        results.sort();
        return results;
    }

    @AuraEnabled
    public static Map<String, String> getRecordingBase64(String recordingUrl) {
        Map<String, String> result = new Map<String, String>();
        try {
            if (String.isBlank(recordingUrl)) {
                result.put('error', 'Recording URL is required.');
                return result;
            }
            HttpRequest req = new HttpRequest();
            req.setEndpoint(recordingUrl);
            req.setMethod('GET');
            req.setTimeout(30000);
            Http http = new Http();
            HttpResponse res = http.send(req);
            if (res.getStatusCode() == 200) {
                Blob body = res.getBodyAsBlob();
                String contentType = res.getHeader('Content-Type');
                if (String.isBlank(contentType)) {
                    contentType = 'audio/mpeg';
                }
                result.put('base64Data', EncodingUtil.base64Encode(body));
                result.put('contentType', contentType);
            } else {
                result.put('error', 'Failed to fetch recording. Status: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            result.put('error', e.getMessage());
        }
        return result;
    }

    // =========================================================================
    //  OWNERSHIP TIMELINE — table view of lead lifecycle events
    //  Combines Reassignment_History__c (ownership events) with Lead__History
    //  (non-terminal status changes) into a single chronological table.
    // =========================================================================

    private static final Set<String> TERMINAL_STATUSES = new Set<String>{
        'Booked', 'Unqualified', 'Closed Lost'
    };

    @AuraEnabled
    public static List<OwnershipTimelineWrapper> getOwnershipTimeline(String leadId) {
        if (String.isBlank(leadId)) {
            throw new AuraHandledException('Lead ID is required.');
        }

        List<OwnershipTimelineWrapper> timeline = new List<OwnershipTimelineWrapper>();

        // 1. Ownership lifecycle events from Reassignment_History__c
        List<Reassignment_History__c> rhList = [
            SELECT Id, New_Owner__c, New_Owner__r.Name, Old_Owner__c, Old_Owner__r.Name,
                   Reassignment_Type__c, Entry_Status__c, Exit_Status__c, Status__c,
                   Ownership_Start_Date__c, Ownership_End_Date__c, Reassigned_Date__c
            FROM Reassignment_History__c
            WHERE Lead__c = :leadId
            ORDER BY Reassigned_Date__c ASC
        ];

        // 2. Non-terminal status changes from Lead field history
        List<Lead__History> statusChanges = [
            SELECT Id, CreatedDate, NewValue, OldValue
            FROM Lead__History
            WHERE ParentId = :leadId AND Field = 'Lead_Status__c'
            ORDER BY CreatedDate ASC
        ];

        // 3. Build ownership periods for owner-at-time lookups
        List<OwnerPeriod> ownerPeriods = new List<OwnerPeriod>();
        Set<Long> ownerChangeTimestamps = new Set<Long>();

        for (Reassignment_History__c rh : rhList) {
            DateTime periodStart = rh.Ownership_Start_Date__c != null
                ? rh.Ownership_Start_Date__c : rh.Reassigned_Date__c;

            OwnerPeriod op = new OwnerPeriod();
            op.startDate = periodStart;
            op.endDate = rh.Ownership_End_Date__c;
            op.ownerName = rh.New_Owner__r.Name;
            ownerPeriods.add(op);

            // Add timeline row for each reassignment record
            OwnershipTimelineWrapper row = new OwnershipTimelineWrapper();
            row.createdDate = rh.Reassigned_Date__c;
            row.ownerName = rh.New_Owner__r.Name;

            if (rh.Reassignment_Type__c == 'Initial Assignment') {
                row.leadEvent = 'Created';
                row.statusValue = rh.Entry_Status__c;
                row.historyAction = 'Entry record created';
            } else if (rh.Reassignment_Type__c == 'Permanent') {
                row.leadEvent = 'Owner Change';
                row.statusValue = rh.Entry_Status__c;
                row.historyAction = 'Close + New record';
                ownerChangeTimestamps.add(rh.Reassigned_Date__c.getTime());
            }

            timeline.add(row);

            // For ownership records closed by a terminal status, synthesize an "Update exit" row
            if (rh.Exit_Status__c != null
                && TERMINAL_STATUSES.contains(rh.Exit_Status__c)) {
                OwnershipTimelineWrapper exitRow = new OwnershipTimelineWrapper();
                exitRow.createdDate = rh.Ownership_End_Date__c != null
                    ? rh.Ownership_End_Date__c : rh.Reassigned_Date__c;
                exitRow.ownerName = rh.New_Owner__r.Name;
                exitRow.leadEvent = 'Status';
                exitRow.statusValue = rh.Exit_Status__c;
                exitRow.historyAction = 'Update exit';
                timeline.add(exitRow);
            }
        }

        // 4. Add non-terminal status change rows from Lead__History
        //    (skip those that coincide with owner changes)
        for (Lead__History lh : statusChanges) {
            String newStatus = String.valueOf(lh.NewValue);

            // Skip terminal statuses — already represented by "Update exit" rows above
            if (TERMINAL_STATUSES.contains(newStatus)) continue;

            // Skip status changes that coincide with owner changes (within 5 seconds)
            Boolean isOwnerChangeTime = false;
            Long lhTime = lh.CreatedDate.getTime();
            for (Long octs : ownerChangeTimestamps) {
                if (Math.abs(lhTime - octs) < 5000) {
                    isOwnerChangeTime = true;
                    break;
                }
            }
            if (isOwnerChangeTime) continue;

            OwnershipTimelineWrapper row = new OwnershipTimelineWrapper();
            row.createdDate = lh.CreatedDate;
            row.leadEvent = 'Status';
            row.statusValue = newStatus;
            row.ownerName = resolveOwnerAtTime(ownerPeriods, lh.CreatedDate);
            row.historyAction = 'No change';

            timeline.add(row);
        }

        timeline.sort();
        return timeline;
    }

    private static String resolveOwnerAtTime(List<OwnerPeriod> periods, DateTime targetDate) {
        String lastOwner = null;
        for (OwnerPeriod p : periods) {
            lastOwner = p.ownerName;
            if (p.startDate <= targetDate && (p.endDate == null || p.endDate >= targetDate)) {
                return p.ownerName;
            }
        }
        return lastOwner;
    }

    private class OwnerPeriod {
        DateTime startDate;
        DateTime endDate;
        String ownerName;
    }

    public class OwnershipTimelineWrapper implements Comparable {
        @AuraEnabled public String leadEvent { get; set; }
        @AuraEnabled public String ownerName { get; set; }
        @AuraEnabled public String statusValue { get; set; }
        @AuraEnabled public String historyAction { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }

        public Integer compareTo(Object compareTo) {
            OwnershipTimelineWrapper other = (OwnershipTimelineWrapper) compareTo;
            if (createdDate > other.createdDate) return 1;
            if (createdDate < other.createdDate) return -1;
            return 0;
        }
    }

    public class HistoryActivityWrapper implements Comparable {
        @AuraEnabled public String createdById { get; set; }
        @AuraEnabled public String createdByName { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public String fieldLabel { get; set; }
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String leadId { get; set; }
        @AuraEnabled public String newValue { get; set; }
        @AuraEnabled public String oldValue { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String recordType { get; set; }
        @AuraEnabled public String callType { get; set; }
        @AuraEnabled public String callStatus { get; set; }
        @AuraEnabled public String callFrom { get; set; }
        @AuraEnabled public String callTo { get; set; }
        @AuraEnabled public String callUrl { get; set; }
        @AuraEnabled public String comments { get; set; }

        public Integer compareTo(Object compareTo) {
            HistoryActivityWrapper other = (HistoryActivityWrapper) compareTo;
            if (createdDate > other.createdDate) {
                return -1;
            } else if (createdDate < other.createdDate) {
                return 1;
            }
            return 0;
        }
    }
}