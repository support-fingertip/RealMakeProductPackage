/**
 * @description Controller for Bulk Lead Reassignment LWC.
 * Thin layer — delegates to BulkLeadReassignmentService and UnitBlockingService.
 */
public with sharing class BulkLeadReassignmentController {

    /**
     * @description Search leads with dynamic filters.
     */
    @AuraEnabled
    public static List<BulkLeadReassignmentService.LeadRow> searchLeads(
        Id ownerId, String project, Id projectId, String leadStatus, String leadSource,
        String leadId, String mobileNumber, String leadBucket
    ) {
        if (ownerId == null && String.isBlank(project) && projectId == null && String.isBlank(leadStatus)
            && String.isBlank(leadSource) && String.isBlank(leadId)
            && String.isBlank(mobileNumber) && String.isBlank(leadBucket)) {
            throw new AuraHandledException('Please apply at least one filter before searching.');
        }
        return BulkLeadReassignmentService.searchLeads(
            ownerId, project, projectId, leadStatus, leadSource, leadId, mobileNumber, leadBucket
        );
    }

    @AuraEnabled
    public static BulkLeadReassignmentService.ReassignmentResult reassignLeads(
        List<Id> leadIds, Id targetUserId, String targetBucket, Boolean suppressNotifications
    ) {
        if (leadIds == null || leadIds.isEmpty()) throw new AuraHandledException('No leads selected for reassignment.');
        if (targetUserId == null) throw new AuraHandledException('Please select a target user.');
        if (String.isBlank(targetBucket)) throw new AuraHandledException('Please select a target bucket.');
        return BulkLeadReassignmentService.reassignLeads(leadIds, targetUserId, targetBucket, suppressNotifications);
    }

    @AuraEnabled
    public static BulkLeadReassignmentService.ReassignmentResult reassignLeadsRoundRobin(
        List<Id> leadIds, List<Id> targetUserIds, String targetBucket, Boolean suppressNotifications
    ) {
        if (leadIds == null || leadIds.isEmpty()) throw new AuraHandledException('No leads selected for reassignment.');
        if (targetUserIds == null || targetUserIds.isEmpty()) throw new AuraHandledException('Please select at least one target user.');
        if (String.isBlank(targetBucket)) throw new AuraHandledException('Please select a target bucket.');
        return BulkLeadReassignmentService.reassignLeadsRoundRobin(leadIds, targetUserIds, targetBucket, suppressNotifications);
    }

    @AuraEnabled
    public static List<User> searchActiveUsers(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) return new List<User>();
        return BulkLeadReassignmentService.getActiveUsers(searchTerm);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEMPORARY LEAD OWNERSHIP
    // ═══════════════════════════════════════════════════════════════════

    @AuraEnabled
    public static BulkLeadReassignmentService.ReassignmentResult tempAssignLeads(
        List<Id> leadIds, Id tempOwnerId, Date startDate, Date endDate, String reason,
        String leadAccessLevel, Boolean shareFollowups, Boolean shareSiteVisits
    ) {
        if (leadIds == null || leadIds.isEmpty()) throw new AuraHandledException('No leads selected for temporary assignment.');
        if (tempOwnerId == null) throw new AuraHandledException('Please select a temporary owner.');
        if (startDate == null || endDate == null) throw new AuraHandledException('Please provide both start and end dates.');
        return BulkLeadReassignmentService.tempAssignLeads(
            leadIds, tempOwnerId, startDate, endDate, reason,
            leadAccessLevel != null ? leadAccessLevel : 'Edit',
            shareFollowups == true, shareSiteVisits == true
        );
    }

    @AuraEnabled
    public static BulkLeadReassignmentService.ReassignmentResult revokeTempAssignment(List<Id> leadIds) {
        if (leadIds == null || leadIds.isEmpty()) throw new AuraHandledException('No leads selected for revocation.');
        return BulkLeadReassignmentService.revokeTempAssignment(leadIds);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TEMPORARY SHARED RECORDS VIEWER (Tab 4)
    // ═══════════════════════════════════════════════════════════════════

    @AuraEnabled
    public static List<BulkLeadReassignmentService.TempShareRow> searchTempSharedRecords(Id tempOwnerId) {
        if (tempOwnerId == null) throw new AuraHandledException('Please select a user to search.');
        return BulkLeadReassignmentService.searchTempSharedRecords(tempOwnerId);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  UNIT BLOCKING
    // ═══════════════════════════════════════════════════════════════════

    @AuraEnabled
    public static List<UnitBlockingService.UnitRow> searchUnits(Id projectId, String unitStatus, String unitNumber) {
        if (projectId == null && String.isBlank(unitNumber)) {
            throw new AuraHandledException('Please select a project or enter a unit number.');
        }
        return UnitBlockingService.searchUnits(projectId, unitStatus, unitNumber);
    }

    @AuraEnabled
    public static UnitBlockingService.BlockResult blockUnits(
        List<Id> unitIds, Integer blockDays, String reason,
        Boolean isManagement, Id blockingForUserId, Id leadId
    ) {
        if (unitIds == null || unitIds.isEmpty()) throw new AuraHandledException('No units selected for blocking.');
        if (String.isBlank(reason)) throw new AuraHandledException('Block reason is mandatory.');
        if (isManagement != true && (blockDays == null || blockDays < 1)) {
            throw new AuraHandledException('Please enter a valid block duration (minimum 1 day).');
        }
        return UnitBlockingService.blockUnits(unitIds, blockDays, reason, isManagement == true, blockingForUserId, leadId);
    }

    @AuraEnabled
    public static UnitBlockingService.BlockResult unblockUnits(List<Id> unitIds) {
        if (unitIds == null || unitIds.isEmpty()) throw new AuraHandledException('No units selected for unblocking.');
        return UnitBlockingService.unblockUnits(unitIds);
    }

    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjects() {
        return [SELECT Id, Name, Max_Block_Days__c FROM Project__c ORDER BY Name ASC LIMIT 200];
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BLOCKED UNITS VIEWER (Tab 5)
    // ═══════════════════════════════════════════════════════════════════

    @AuraEnabled
    public static List<UnitBlockingService.UnitRow> searchBlockedUnits(
        Id blockedByUserId, Boolean isManagement, Id blockingForUserId
    ) {
        return UnitBlockingService.searchBlockedUnits(blockedByUserId, isManagement, blockingForUserId);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  UNIT BLOCK REQUESTS (Tab 6)
    // ═══════════════════════════════════════════════════════════════════

    @AuraEnabled
    public static Unit_Block_Request__c createBlockRequest(
        Id unitId, Id projectId, Id leadId, Id approverId,
        Integer blockDays, String reason, Boolean isManagement
    ) {
        if (unitId == null) throw new AuraHandledException('Please select a unit.');
        if (String.isBlank(reason)) throw new AuraHandledException('Please provide a block reason.');
        if (approverId == null) throw new AuraHandledException('Please select an approver.');
        return UnitBlockingService.createBlockRequest(unitId, projectId, leadId, approverId, blockDays, reason, isManagement);
    }

    @AuraEnabled
    public static Unit_Block_Request__c approveBlockRequest(Id requestId) {
        if (requestId == null) throw new AuraHandledException('No request selected.');
        return UnitBlockingService.approveBlockRequest(requestId);
    }

    @AuraEnabled
    public static Unit_Block_Request__c rejectBlockRequest(Id requestId, String notes) {
        if (requestId == null) throw new AuraHandledException('No request selected.');
        return UnitBlockingService.rejectBlockRequest(requestId, notes);
    }

    @AuraEnabled
    public static List<UnitBlockingService.BlockRequestRow> getPendingBlockRequests() {
        return UnitBlockingService.getPendingRequests(UserInfo.getUserId());
    }

    @AuraEnabled
    public static List<UnitBlockingService.BlockRequestRow> getMyBlockRequests() {
        return UnitBlockingService.getMyRequests(UserInfo.getUserId());
    }

    @AuraEnabled
    public static User getCurrentUserManager() {
        List<User> users = [SELECT Id, ManagerId, Manager.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (!users.isEmpty() && users[0].ManagerId != null) return users[0].Manager;
        return null;
    }

    @AuraEnabled
    public static List<BulkLeadReassignmentService.LeadRow> searchLeadsForLookup(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) return new List<BulkLeadReassignmentService.LeadRow>();
        String term = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        List<Lead__c> leads = [
            SELECT Id, Name, First_Name__c, Last_Name__c, OwnerId, Owner.Name,
                   Project__c, Project__r.Name, Lead_Status__c, Primary_Mobile__c,
                   RecordType.Name, RecordTypeId
            FROM Lead__c
            WHERE (Name LIKE :term OR First_Name__c LIKE :term OR Last_Name__c LIKE :term)
            ORDER BY CreatedDate DESC LIMIT 20
        ];
        List<BulkLeadReassignmentService.LeadRow> rows = new List<BulkLeadReassignmentService.LeadRow>();
        for (Lead__c l : leads) {
            BulkLeadReassignmentService.LeadRow row = new BulkLeadReassignmentService.LeadRow();
            row.leadId = l.Id;
            row.leadIdName = l.Name;
            row.leadName = ((l.First_Name__c != null ? l.First_Name__c : '') + ' ' + (l.Last_Name__c != null ? l.Last_Name__c : '')).trim();
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
}