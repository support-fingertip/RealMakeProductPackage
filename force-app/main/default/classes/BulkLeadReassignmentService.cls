/**
 * @description Service class for Bulk Lead Reassignment.
 * Handles business logic: dynamic SOQL filter building, mobile search
 * across Lead + Enquiry_Source__c, bucket transition validation,
 * and bulk reassignment with partial success handling.
 */
public with sharing class BulkLeadReassignmentService {

    // ═══════════════════════════════════════════════════════════════════
    //  CONSTANTS
    // ═══════════════════════════════════════════════════════════════════

    private static final String RT_PRE_SALES = 'Pre_Sales';
    private static final String RT_SALES = 'Sales';
    private static final String RT_CHANNEL_PARTNER = 'Channel_Partner';

    private static final Map<String, String> BUCKET_TO_RT = new Map<String, String>{
        'Pre Sales' => RT_PRE_SALES,
        'Sales' => RT_SALES,
        'Channel Partners' => RT_CHANNEL_PARTNER
    };

    // Allowed bucket transitions: Source → Set<Target>
    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        'Pre_Sales' => new Set<String>{ 'Pre_Sales', 'Sales' },
        'Sales'     => new Set<String>{ 'Sales', 'Pre_Sales' }
    };

    // ═══════════════════════════════════════════════════════════════════
    //  INNER CLASSES
    // ═══════════════════════════════════════════════════════════════════

    public class LeadRow {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadIdName;
        @AuraEnabled public String leadName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String project;
        @AuraEnabled public String leadStatus;
        @AuraEnabled public String primaryMobile;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public Id recordTypeId;
    }

    public class ReassignmentResult {
        @AuraEnabled public Integer successCount = 0;
        @AuraEnabled public Integer failureCount = 0;
        @AuraEnabled public List<FailureDetail> failures = new List<FailureDetail>();
    }

    public class FailureDetail {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String reason;

        public FailureDetail(Id leadId, String leadName, String reason) {
            this.leadId = leadId;
            this.leadName = leadName;
            this.reason = reason;
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SEARCH LEADS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Search leads using dynamic filters.
     * At least one filter must be provided (enforced in controller).
     */
    public static List<LeadRow> searchLeads(
        Id ownerId,
        String project,
        Id projectId,
        String leadStatus,
        String leadSource,
        String leadId,
        String mobileNumber,
        String leadBucket
    ) {
        // Mobile search uses a special two-step approach
        if (String.isNotBlank(mobileNumber)) {
            return searchByMobile(mobileNumber, ownerId, project, projectId, leadStatus, leadSource, leadBucket);
        }

        // Build dynamic SOQL for non-mobile filters
        String soql = buildFilterSOQL(ownerId, project, projectId, leadStatus, leadSource, leadId, leadBucket);
        List<Lead__c> leads = Database.query(soql);
        return mapToLeadRows(leads);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  MOBILE SEARCH (Two-Step)
    // ═══════════════════════════════════════════════════════════════════

    private static List<LeadRow> searchByMobile(
        String mobile,
        Id ownerId,
        String project,
        Id projectId,
        String leadStatus,
        String leadSource,
        String leadBucket
    ) {
        String mobileTrimmed = mobile.trim();
        Set<Id> leadIds = new Set<Id>();

        // STEP 1: Search directly in Lead__c
        String leadMobileSoql = 'SELECT Id FROM Lead__c WHERE (Primary_Mobile__c = :mobileTrimmed OR Secondary_Mobile__c = :mobileTrimmed)';
        leadMobileSoql += buildAdditionalFilters(ownerId, project, projectId, leadStatus, leadSource, leadBucket);
        leadMobileSoql += ' LIMIT 2000';

        for (Lead__c l : Database.query(leadMobileSoql)) {
            leadIds.add(l.Id);
        }

        // STEP 2: Search in Enquiry_Source__c and fetch linked Leads
        List<Enquiry_Source__c> enquiries = [
            SELECT Lead__c
            FROM Enquiry_Source__c
            WHERE (Primary_Mobile__c = :mobileTrimmed OR Secondary_Mobile__c = :mobileTrimmed)
            AND Lead__c != null
            LIMIT 2000
        ];

        Set<Id> enquiryLeadIds = new Set<Id>();
        for (Enquiry_Source__c es : enquiries) {
            enquiryLeadIds.add(es.Lead__c);
        }

        // Combine, but apply remaining filters to enquiry-sourced leads too
        if (!enquiryLeadIds.isEmpty()) {
            String enqLeadSoql = 'SELECT Id FROM Lead__c WHERE Id IN :enquiryLeadIds';
            enqLeadSoql += buildAdditionalFilters(ownerId, project, projectId, leadStatus, leadSource, leadBucket);
            enqLeadSoql += ' LIMIT 2000';

            for (Lead__c l : Database.query(enqLeadSoql)) {
                leadIds.add(l.Id);
            }
        }

        if (leadIds.isEmpty()) {
            return new List<LeadRow>();
        }

        // Final query with all display fields
        List<Lead__c> results = [
            SELECT Id, Name, First_Name__c, Last_Name__c, OwnerId, Owner.Name,
                   Project__c, Project__r.Name, Lead_Status__c, Primary_Mobile__c,
                   RecordType.Name, RecordTypeId
            FROM Lead__c
            WHERE Id IN :leadIds
            ORDER BY CreatedDate DESC
            LIMIT 2000
        ];

        return mapToLeadRows(results);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DYNAMIC SOQL BUILDER
    // ═══════════════════════════════════════════════════════════════════

    private static String buildFilterSOQL(
        Id ownerId,
        String project,
        Id projectId,
        String leadStatus,
        String leadSource,
        String leadId,
        String leadBucket
    ) {
        String soql = 'SELECT Id, Name, First_Name__c, Last_Name__c, OwnerId, Owner.Name, '
            + 'Project__c, Project__r.Name, Lead_Status__c, Primary_Mobile__c, '
            + 'RecordType.Name, RecordTypeId '
            + 'FROM Lead__c WHERE Id != null';

        if (ownerId != null) {
            soql += ' AND OwnerId = \'' + String.escapeSingleQuotes(String.valueOf(ownerId)) + '\'';
        }
        if (projectId != null) {
            soql += ' AND Project__c = \'' + String.escapeSingleQuotes(String.valueOf(projectId)) + '\'';
        } else if (String.isNotBlank(project)) {
            soql += ' AND Project__r.Name LIKE \'%' + String.escapeSingleQuotes(project) + '%\'';
        }
        if (String.isNotBlank(leadStatus)) {
            soql += ' AND Lead_Status__c = \'' + String.escapeSingleQuotes(leadStatus) + '\'';
        }
        if (String.isNotBlank(leadSource)) {
            soql += ' AND Lead_Source__c = \'' + String.escapeSingleQuotes(leadSource) + '\'';
        }
        if (String.isNotBlank(leadId)) {
            String sanitizedId = String.escapeSingleQuotes(leadId.trim());
            soql += ' AND Name = \'' + sanitizedId + '\'';
        }
        if (String.isNotBlank(leadBucket)) {
            String rtDevName = BUCKET_TO_RT.get(leadBucket);
            if (rtDevName != null) {
                Id rtId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
                    .get(rtDevName).getRecordTypeId();
                soql += ' AND RecordTypeId = \'' + String.valueOf(rtId) + '\'';
            }
        }

        soql += ' ORDER BY CreatedDate DESC LIMIT 2000';
        return soql;
    }

    private static String buildAdditionalFilters(
        Id ownerId,
        String project,
        Id projectId,
        String leadStatus,
        String leadSource,
        String leadBucket
    ) {
        String filters = '';
        if (ownerId != null) {
            filters += ' AND OwnerId = \'' + String.escapeSingleQuotes(String.valueOf(ownerId)) + '\'';
        }
        if (projectId != null) {
            filters += ' AND Project__c = \'' + String.escapeSingleQuotes(String.valueOf(projectId)) + '\'';
        } else if (String.isNotBlank(project)) {
            filters += ' AND Project__r.Name LIKE \'%' + String.escapeSingleQuotes(project) + '%\'';
        }
        if (String.isNotBlank(leadStatus)) {
            filters += ' AND Lead_Status__c = \'' + String.escapeSingleQuotes(leadStatus) + '\'';
        }
        if (String.isNotBlank(leadSource)) {
            filters += ' AND Lead_Source__c = \'' + String.escapeSingleQuotes(leadSource) + '\'';
        }
        if (String.isNotBlank(leadBucket)) {
            String rtDevName = BUCKET_TO_RT.get(leadBucket);
            if (rtDevName != null) {
                Id rtId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
                    .get(rtDevName).getRecordTypeId();
                filters += ' AND RecordTypeId = \'' + String.valueOf(rtId) + '\'';
            }
        }
        return filters;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BULK REASSIGNMENT
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Reassign leads to target user with bucket transition validation.
     * Supports partial success — valid leads are updated, invalid ones reported.
     */
    public static ReassignmentResult reassignLeads(
        List<Id> leadIds,
        Id targetUserId,
        String targetBucket,
        Boolean suppressNotifications
    ) {
        ReassignmentResult result = new ReassignmentResult();

        // Validate target user is active
        List<User> targetUsers = [
            SELECT Id, Name, IsActive FROM User WHERE Id = :targetUserId LIMIT 1
        ];
        if (targetUsers.isEmpty() || !targetUsers[0].IsActive) {
            FailureDetail fd = new FailureDetail(null, null, 'Target user is inactive or does not exist.');
            result.failures.add(fd);
            result.failureCount = leadIds.size();
            return result;
        }

        // Get target RecordType Id
        String targetRTDevName = BUCKET_TO_RT.get(targetBucket);
        if (targetRTDevName == null) {
            FailureDetail fd = new FailureDetail(null, null, 'Invalid target bucket: ' + targetBucket);
            result.failures.add(fd);
            result.failureCount = leadIds.size();
            return result;
        }
        Id targetRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
            .get(targetRTDevName).getRecordTypeId();

        // Query leads for validation
        Map<Id, Lead__c> leadsMap = new Map<Id, Lead__c>([
            SELECT Id, Name, First_Name__c, Last_Name__c, OwnerId, RecordTypeId,
                   RecordType.DeveloperName
            FROM Lead__c
            WHERE Id IN :leadIds
        ]);

        List<Lead__c> toUpdate = new List<Lead__c>();

        for (Id lid : leadIds) {
            Lead__c lead = leadsMap.get(lid);
            if (lead == null) {
                result.failures.add(new FailureDetail(lid, 'Unknown', 'Lead not found.'));
                result.failureCount++;
                continue;
            }

            String leadName = (lead.First_Name__c != null ? lead.First_Name__c : '') + ' '
                + (lead.Last_Name__c != null ? lead.Last_Name__c : '');

            // Bucket transition validation
            String sourceRT = lead.RecordType.DeveloperName;
            if (!isTransitionAllowed(sourceRT, targetRTDevName)) {
                result.failures.add(new FailureDetail(
                    lid,
                    leadName.trim(),
                    'Bucket transition not allowed: ' + getReadableBucket(sourceRT) + ' → ' + targetBucket
                ));
                result.failureCount++;
                continue;
            }

            // Build update
            Lead__c upd = new Lead__c(Id = lid);
            upd.OwnerId = targetUserId;
            if (sourceRT != targetRTDevName) {
                upd.RecordTypeId = targetRTId;
            }
            // Store pre-sales user when transitioning Pre_Sales → Sales
            if (sourceRT == RT_PRE_SALES && targetRTDevName == RT_SALES) {
                upd.Pre_Sale_User__c = lead.OwnerId;
                upd.Transferred_On__c = System.now();
                upd.Transferred_By__c = UserInfo.getUserId();
            }
            // Reset pre-sales fields when transitioning Sales → Pre_Sales
            if (sourceRT == RT_SALES && targetRTDevName == RT_PRE_SALES) {
                upd.Pre_Sale_User__c = null;
                upd.Transferred_On__c = null;
                upd.Transferred_By__c = null;
                upd.Lead_Status__c = 'New Enquiry';
            }
            toUpdate.add(upd);
        }

        // Bulk DML with partial success
        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                Lead__c lead = leadsMap.get(toUpdate[i].Id);
                String leadName = (lead.First_Name__c != null ? lead.First_Name__c : '') + ' '
                    + (lead.Last_Name__c != null ? lead.Last_Name__c : '');

                if (sr.isSuccess()) {
                    result.successCount++;
                } else {
                    String errMsg = '';
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getMessage() + '; ';
                    }
                    result.failures.add(new FailureDetail(toUpdate[i].Id, leadName.trim(), errMsg));
                    result.failureCount++;
                }
            }
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ROUND ROBIN REASSIGNMENT
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Reassign leads round-robin across multiple target users.
     * Lead[0] → User[0], Lead[1] → User[1], ..., wraps around.
     * Same transition validation and field changes as single-user reassignment.
     */
    public static ReassignmentResult reassignLeadsRoundRobin(
        List<Id> leadIds,
        List<Id> targetUserIds,
        String targetBucket,
        Boolean suppressNotifications
    ) {
        ReassignmentResult result = new ReassignmentResult();

        // Validate target users are active
        Map<Id, User> activeUsersMap = new Map<Id, User>([
            SELECT Id, Name, IsActive FROM User WHERE Id IN :targetUserIds AND IsActive = true
        ]);
        List<Id> validUserIds = new List<Id>();
        for (Id uid : targetUserIds) {
            if (activeUsersMap.containsKey(uid)) {
                validUserIds.add(uid);
            }
        }
        if (validUserIds.isEmpty()) {
            FailureDetail fd = new FailureDetail(null, null, 'No active target users found.');
            result.failures.add(fd);
            result.failureCount = leadIds.size();
            return result;
        }

        // Get target RecordType Id
        String targetRTDevName = BUCKET_TO_RT.get(targetBucket);
        if (targetRTDevName == null) {
            FailureDetail fd = new FailureDetail(null, null, 'Invalid target bucket: ' + targetBucket);
            result.failures.add(fd);
            result.failureCount = leadIds.size();
            return result;
        }
        Id targetRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
            .get(targetRTDevName).getRecordTypeId();

        // Query leads for validation
        Map<Id, Lead__c> leadsMap = new Map<Id, Lead__c>([
            SELECT Id, Name, First_Name__c, Last_Name__c, OwnerId, RecordTypeId,
                   RecordType.DeveloperName
            FROM Lead__c
            WHERE Id IN :leadIds
        ]);

        List<Lead__c> toUpdate = new List<Lead__c>();
        Integer userIndex = 0;
        Integer userCount = validUserIds.size();

        for (Id lid : leadIds) {
            Lead__c lead = leadsMap.get(lid);
            if (lead == null) {
                result.failures.add(new FailureDetail(lid, 'Unknown', 'Lead not found.'));
                result.failureCount++;
                continue;
            }

            String leadName = (lead.First_Name__c != null ? lead.First_Name__c : '') + ' '
                + (lead.Last_Name__c != null ? lead.Last_Name__c : '');

            // Bucket transition validation
            String sourceRT = lead.RecordType.DeveloperName;
            if (!isTransitionAllowed(sourceRT, targetRTDevName)) {
                result.failures.add(new FailureDetail(
                    lid,
                    leadName.trim(),
                    'Bucket transition not allowed: ' + getReadableBucket(sourceRT) + ' → ' + targetBucket
                ));
                result.failureCount++;
                continue;
            }

            // Round-robin user assignment
            Id assignedUserId = validUserIds[Math.mod(userIndex, userCount)];
            userIndex++;

            // Build update
            Lead__c upd = new Lead__c(Id = lid);
            upd.OwnerId = assignedUserId;
            if (sourceRT != targetRTDevName) {
                upd.RecordTypeId = targetRTId;
            }
            // Store pre-sales user when transitioning Pre_Sales → Sales
            if (sourceRT == RT_PRE_SALES && targetRTDevName == RT_SALES) {
                upd.Pre_Sale_User__c = lead.OwnerId;
                upd.Transferred_On__c = System.now();
                upd.Transferred_By__c = UserInfo.getUserId();
            }
            // Reset pre-sales fields when transitioning Sales → Pre_Sales
            if (sourceRT == RT_SALES && targetRTDevName == RT_PRE_SALES) {
                upd.Pre_Sale_User__c = null;
                upd.Transferred_On__c = null;
                upd.Transferred_By__c = null;
                upd.Lead_Status__c = 'New Enquiry';
            }
            toUpdate.add(upd);
        }

        // Bulk DML with partial success
        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                Lead__c lead = leadsMap.get(toUpdate[i].Id);
                String leadName = (lead.First_Name__c != null ? lead.First_Name__c : '') + ' '
                    + (lead.Last_Name__c != null ? lead.Last_Name__c : '');

                if (sr.isSuccess()) {
                    result.successCount++;
                } else {
                    String errMsg = '';
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getMessage() + '; ';
                    }
                    result.failures.add(new FailureDetail(toUpdate[i].Id, leadName.trim(), errMsg));
                    result.failureCount++;
                }
            }
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BUCKET TRANSITION VALIDATOR
    // ═══════════════════════════════════════════════════════════════════

    public static Boolean isTransitionAllowed(String sourceRTDevName, String targetRTDevName) {
        Set<String> allowed = ALLOWED_TRANSITIONS.get(sourceRTDevName);
        if (allowed == null) {
            // Channel_Partner or any other — allow same-to-same only
            return sourceRTDevName == targetRTDevName;
        }
        return allowed.contains(targetRTDevName);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ACTIVE USERS (for target user lookup)
    // ═══════════════════════════════════════════════════════════════════

    public static List<User> getActiveUsers(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        return [
            SELECT Id, Name, Email, Profile.Name
            FROM User
            WHERE IsActive = true
            AND Name LIKE :term
            ORDER BY Name ASC
            LIMIT 20
        ];
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HELPERS
    // ═══════════════════════════════════════════════════════════════════

    private static List<LeadRow> mapToLeadRows(List<Lead__c> leads) {
        List<LeadRow> rows = new List<LeadRow>();
        for (Lead__c l : leads) {
            LeadRow row = new LeadRow();
            row.leadId = l.Id;
            row.leadIdName = l.Name;
            row.leadName = ((l.First_Name__c != null ? l.First_Name__c : '')
                + ' ' + (l.Last_Name__c != null ? l.Last_Name__c : '')).trim();
            row.ownerName = l.Owner != null ? l.Owner.Name : '';
            row.project = l.Project__c != null ? l.Project__r.Name : '';
            row.leadStatus = l.Lead_Status__c;
            row.primaryMobile = l.Primary_Mobile__c;
            row.recordTypeName = l.RecordType != null ? l.RecordType.Name : '';
            row.recordTypeId = l.RecordTypeId;
            rows.add(row);
        }
        return rows;
    }

    private static String getReadableBucket(String devName) {
        if (devName == RT_PRE_SALES) return 'Pre Sales';
        if (devName == RT_SALES) return 'Sales';
        if (devName == RT_CHANNEL_PARTNER) return 'Channel Partners';
        return devName;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEMPORARY LEAD OWNERSHIP
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Backward-compatible overload (defaults to Edit access, no followup/SV sharing).
     */
    public static ReassignmentResult tempAssignLeads(
        List<Id> leadIds, Id tempOwnerId, Date startDate, Date endDate, String reason
    ) {
        return tempAssignLeads(leadIds, tempOwnerId, startDate, endDate, reason, 'Edit', false, false);
    }

    /**
     * @description Assign temporary ownership of selected leads to a user.
     * Sets Temp_Owner__c, Temp_Start__c, Temp_Expiry__c and shares the leads
     * with the temporary owner via Apex managed sharing.
     * Optionally shares related Followups (via Lead master-detail) and Site Visits.
     */
    public static ReassignmentResult tempAssignLeads(
        List<Id> leadIds,
        Id tempOwnerId,
        Date startDate,
        Date endDate,
        String reason,
        String leadAccessLevel,
        Boolean shareFollowups,
        Boolean shareSiteVisits
    ) {
        ReassignmentResult result = new ReassignmentResult();

        String accessLevel = (leadAccessLevel == 'Read') ? 'Read' : 'Edit';

        // Validate temp owner is active
        List<User> tempUsers = [
            SELECT Id, Name, IsActive FROM User WHERE Id = :tempOwnerId LIMIT 1
        ];
        if (tempUsers.isEmpty() || !tempUsers[0].IsActive) {
            result.failures.add(new FailureDetail(null, null, 'Temporary owner is inactive or does not exist.'));
            result.failureCount = leadIds.size();
            return result;
        }

        // Validate dates
        if (startDate == null || endDate == null) {
            result.failures.add(new FailureDetail(null, null, 'Start date and end date are required.'));
            result.failureCount = leadIds.size();
            return result;
        }
        if (endDate < startDate) {
            result.failures.add(new FailureDetail(null, null, 'End date must be on or after start date.'));
            result.failureCount = leadIds.size();
            return result;
        }

        // Query leads
        Map<Id, Lead__c> leadsMap = new Map<Id, Lead__c>([
            SELECT Id, Name, First_Name__c, Last_Name__c, OwnerId, Temp_Owner__c,
                   Lead_Status__c
            FROM Lead__c
            WHERE Id IN :leadIds
        ]);

        List<Lead__c> toUpdate = new List<Lead__c>();
        List<Reassignment_History__c> histories = new List<Reassignment_History__c>();

        for (Id lid : leadIds) {
            Lead__c lead = leadsMap.get(lid);
            if (lead == null) {
                result.failures.add(new FailureDetail(lid, 'Unknown', 'Lead not found.'));
                result.failureCount++;
                continue;
            }

            String leadName = ((lead.First_Name__c != null ? lead.First_Name__c : '') + ' '
                + (lead.Last_Name__c != null ? lead.Last_Name__c : '')).trim();

            // Check if lead already has a temp owner
            if (lead.Temp_Owner__c != null) {
                result.failures.add(new FailureDetail(lid, leadName, 'Lead already has a temporary owner assigned.'));
                result.failureCount++;
                continue;
            }

            // Block same-owner temp assignment
            if (lead.OwnerId == tempOwnerId) {
                result.failures.add(new FailureDetail(lid, leadName,
                    'Cannot assign temporary ownership to the lead\'s current owner.'));
                result.failureCount++;
                continue;
            }

            Lead__c upd = new Lead__c(Id = lid);
            upd.Temp_Owner__c = tempOwnerId;
            upd.Temp_Start__c = startDate;
            upd.Temp_Expiry__c = endDate;
            toUpdate.add(upd);

            // Create history record with full lifecycle data
            Reassignment_History__c rh = new Reassignment_History__c();
            rh.Lead__c = lid;
            rh.Old_Owner__c = lead.OwnerId;
            rh.New_Owner__c = tempOwnerId;
            rh.Assigned_By__c = UserInfo.getUserId();
            rh.Reassigned_Date__c = System.now();
            rh.Reassignment_Type__c = 'Temporary';
            rh.Status__c = 'Active';
            rh.Ownership_Start_Date__c = System.now();
            rh.Entry_Status__c = lead.Lead_Status__c;
            rh.Temp_Expiry__c = endDate;
            rh.Reason__c = reason;
            rh.Lead_Access_Level__c = accessLevel;
            rh.Share_Followups__c = shareFollowups;
            rh.Share_Site_Visits__c = shareSiteVisits;
            histories.add(rh);
        }

        // Bulk DML
        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);
            List<Id> sharedLeadIds = new List<Id>();

            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                Lead__c lead = leadsMap.get(toUpdate[i].Id);
                String leadName = ((lead.First_Name__c != null ? lead.First_Name__c : '') + ' '
                    + (lead.Last_Name__c != null ? lead.Last_Name__c : '')).trim();

                if (sr.isSuccess()) {
                    result.successCount++;
                    sharedLeadIds.add(toUpdate[i].Id);
                } else {
                    String errMsg = '';
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getMessage() + '; ';
                    }
                    result.failures.add(new FailureDetail(toUpdate[i].Id, leadName, errMsg));
                    result.failureCount++;
                }
            }

            // Share leads with temp owner at selected access level
            // (Followup__c is MasterDetail to Lead — inherits Lead sharing automatically)
            if (!sharedLeadIds.isEmpty()) {
                try {
                    SharingUtility.shareLeadsWithUser(sharedLeadIds, tempOwnerId, accessLevel);
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Lead sharing skipped: ' + e.getMessage());
                }

                // Share Site Visits with per-status access levels
                if (shareSiteVisits) {
                    try {
                        SharingUtility.shareSiteVisitsForLeads(sharedLeadIds, tempOwnerId);
                    } catch (Exception e) {
                        System.debug(LoggingLevel.WARN, 'Site Visit sharing skipped: ' + e.getMessage());
                    }
                }
            }
        }

        // Insert history records
        if (!histories.isEmpty()) {
            Database.insert(histories, false);
        }

        return result;
    }

    /**
     * @description Revoke temporary ownership for selected leads before expiry.
     * Clears Temp_Owner__c, Temp_Start__c, Temp_Expiry__c and removes all sharing.
     */
    public static ReassignmentResult revokeTempAssignment(List<Id> leadIds) {
        ReassignmentResult result = new ReassignmentResult();

        Map<Id, Lead__c> leadsMap = new Map<Id, Lead__c>([
            SELECT Id, Name, First_Name__c, Last_Name__c, OwnerId, Temp_Owner__c,
                   Temp_Start__c, Temp_Expiry__c
            FROM Lead__c
            WHERE Id IN :leadIds
        ]);

        List<Lead__c> toUpdate = new List<Lead__c>();
        Map<Id, Id> leadToTempOwner = new Map<Id, Id>();

        for (Id lid : leadIds) {
            Lead__c lead = leadsMap.get(lid);
            if (lead == null) {
                result.failures.add(new FailureDetail(lid, 'Unknown', 'Lead not found.'));
                result.failureCount++;
                continue;
            }

            String leadName = ((lead.First_Name__c != null ? lead.First_Name__c : '') + ' '
                + (lead.Last_Name__c != null ? lead.Last_Name__c : '')).trim();

            if (lead.Temp_Owner__c == null) {
                result.failures.add(new FailureDetail(lid, leadName, 'Lead has no temporary owner.'));
                result.failureCount++;
                continue;
            }

            leadToTempOwner.put(lid, lead.Temp_Owner__c);

            Lead__c upd = new Lead__c(Id = lid);
            upd.Temp_Owner__c = null;
            upd.Temp_Start__c = null;
            upd.Temp_Expiry__c = null;
            toUpdate.add(upd);
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);
            Map<Id, Id> successfulRevokes = new Map<Id, Id>();

            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                Lead__c lead = leadsMap.get(toUpdate[i].Id);
                String leadName = ((lead.First_Name__c != null ? lead.First_Name__c : '') + ' '
                    + (lead.Last_Name__c != null ? lead.Last_Name__c : '')).trim();

                if (sr.isSuccess()) {
                    result.successCount++;
                    Id tempOwner = leadToTempOwner.get(toUpdate[i].Id);
                    if (tempOwner != null) {
                        successfulRevokes.put(toUpdate[i].Id, tempOwner);
                    }
                } else {
                    String errMsg = '';
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getMessage() + '; ';
                    }
                    result.failures.add(new FailureDetail(toUpdate[i].Id, leadName, errMsg));
                    result.failureCount++;
                }
            }

            // Remove lead and site visit sharing
            if (!successfulRevokes.isEmpty()) {
                try {
                    SharingUtility.removeLeadShares(successfulRevokes);
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Lead sharing removal skipped: ' + e.getMessage());
                }
                try {
                    SharingUtility.removeSiteVisitSharesForLeads(successfulRevokes);
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Site Visit sharing removal skipped: ' + e.getMessage());
                }
            }

            // Update existing Active Temporary history records in place
            List<Reassignment_History__c> historiesToUpdate = new List<Reassignment_History__c>();
            for (Reassignment_History__c rh : [
                SELECT Id, Lead__c
                FROM Reassignment_History__c
                WHERE Lead__c IN :successfulRevokes.keySet()
                AND Reassignment_Type__c = 'Temporary' AND Status__c = 'Active'
            ]) {
                rh.Status__c = 'Revoked';
                rh.Ownership_End_Date__c = System.now();
                rh.Exit_Status__c = 'Revoked';
                historiesToUpdate.add(rh);
            }
            if (!historiesToUpdate.isEmpty()) {
                update historiesToUpdate;
            }
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEMPORARY SHARED RECORDS VIEWER (Tab 4)
    // ═══════════════════════════════════════════════════════════════════

    public class TempShareRow {
        @AuraEnabled public Id historyId;
        @AuraEnabled public String historyName;
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String leadUrl;
        @AuraEnabled public String projectName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String tempOwnerName;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date expiryDate;
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public String accessLevel;
        @AuraEnabled public Boolean shareFollowups;
        @AuraEnabled public Boolean shareSiteVisits;
        @AuraEnabled public Datetime assignedDate;
        @AuraEnabled public String assignedByName;
    }

    public static List<TempShareRow> searchTempSharedRecords(Id tempOwnerId) {
        List<TempShareRow> rows = new List<TempShareRow>();

        List<Reassignment_History__c> records = [
            SELECT Id, Name, Lead__c, Lead__r.Name, Lead__r.First_Name__c, Lead__r.Last_Name__c,
                   Lead__r.Project__c, Lead__r.Project__r.Name,
                   Old_Owner__c, Old_Owner__r.Name, New_Owner__c, New_Owner__r.Name,
                   Status__c, Reason__c, Temp_Expiry__c, Lead_Access_Level__c,
                   Share_Followups__c, Share_Site_Visits__c, Reassigned_Date__c,
                   Assigned_By__c, Assigned_By__r.Name,
                   Lead__r.Temp_Start__c
            FROM Reassignment_History__c
            WHERE Reassignment_Type__c = 'Temporary'
            AND Status__c = 'Active'
            AND New_Owner__c = :tempOwnerId
            ORDER BY Reassigned_Date__c DESC
            LIMIT 500
        ];

        for (Reassignment_History__c rh : records) {
            TempShareRow row = new TempShareRow();
            row.historyId = rh.Id;
            row.historyName = rh.Name;
            row.leadId = rh.Lead__c;
            row.leadUrl = rh.Lead__c != null ? '/' + rh.Lead__c : null;
            row.leadName = rh.Lead__c != null
                ? ((rh.Lead__r.First_Name__c != null ? rh.Lead__r.First_Name__c : '') + ' '
                   + (rh.Lead__r.Last_Name__c != null ? rh.Lead__r.Last_Name__c : '')).trim()
                : '';
            row.projectName = rh.Lead__r.Project__c != null ? rh.Lead__r.Project__r.Name : '';
            row.ownerName = rh.Old_Owner__c != null ? rh.Old_Owner__r.Name : '';
            row.tempOwnerName = rh.New_Owner__c != null ? rh.New_Owner__r.Name : '';
            row.startDate = rh.Lead__r.Temp_Start__c;
            row.expiryDate = rh.Temp_Expiry__c;
            row.status = rh.Status__c;
            row.reason = rh.Reason__c;
            row.accessLevel = rh.Lead_Access_Level__c;
            row.shareFollowups = rh.Share_Followups__c;
            row.shareSiteVisits = rh.Share_Site_Visits__c;
            row.assignedDate = rh.Reassigned_Date__c;
            row.assignedByName = rh.Assigned_By__c != null ? rh.Assigned_By__r.Name : '';
            rows.add(row);
        }

        return rows;
    }
}