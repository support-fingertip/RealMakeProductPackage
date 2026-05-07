/**
 * @description Service class for unit blocking with management blocking support,
 * executive selection, lead association, and block request/approval flow.
 */
public with sharing class UnitBlockingService {

    // ═══════════════════════════════════════════════════════════════════
    //  INNER CLASSES
    // ═══════════════════════════════════════════════════════════════════

    public class UnitRow {
        @AuraEnabled public Id unitId;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public String unitName;
        @AuraEnabled public String unitUrl;
        @AuraEnabled public String projectName;
        @AuraEnabled public Id projectId;
        @AuraEnabled public String towerName;
        @AuraEnabled public String floor;
        @AuraEnabled public String unitType;
        @AuraEnabled public String bhkType;
        @AuraEnabled public String unitStatus;
        @AuraEnabled public String blockedByUser;
        @AuraEnabled public String blockingForUser;
        @AuraEnabled public String blockReason;
        @AuraEnabled public Date blockExpiry;
        @AuraEnabled public Boolean isManagementBlock;
        @AuraEnabled public String blockedByLead;
        @AuraEnabled public Integer maxBlockDays;
    }

    public class BlockResult {
        @AuraEnabled public Integer successCount = 0;
        @AuraEnabled public Integer failureCount = 0;
        @AuraEnabled public List<BlockFailure> failures = new List<BlockFailure>();
    }

    public class BlockFailure {
        @AuraEnabled public Id unitId;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public String reason;

        public BlockFailure(Id unitId, String unitNumber, String reason) {
            this.unitId = unitId;
            this.unitNumber = unitNumber;
            this.reason = reason;
        }
    }

    public class BlockRequestRow {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestName;
        @AuraEnabled public String unitNumber;
        @AuraEnabled public String projectName;
        @AuraEnabled public String leadName;
        @AuraEnabled public String requestedByName;
        @AuraEnabled public String approverName;
        @AuraEnabled public Integer blockDays;
        @AuraEnabled public String reason;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean isManagement;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime responseDate;
        @AuraEnabled public String responseNotes;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SEARCH UNITS
    // ═══════════════════════════════════════════════════════════════════

    public static List<UnitRow> searchUnits(Id projectId, String unitStatus, String unitNumber) {
        String soql = 'SELECT Id, Name, Unit_Number__c, Project__c, Project__r.Name, '
            + 'Project__r.Max_Block_Days__c, '
            + 'Tower__c, Tower__r.Name, Floor__c, Unit_Type__c, BHK_Type__c, '
            + 'Status__c, Blocked_By_User__c, Blocked_By_User__r.Name, '
            + 'Blocking_For__c, Blocking_For__r.Name, '
            + 'Block_Reason__c, Block_Expiry__c, Is_Management_Block__c, '
            + 'Blocked_By_Lead__c, Blocked_By_Lead__r.Name '
            + 'FROM Unit__c WHERE Id != null';

        if (projectId != null) {
            soql += ' AND Project__c = \'' + String.escapeSingleQuotes(String.valueOf(projectId)) + '\'';
        }
        if (String.isNotBlank(unitStatus)) {
            soql += ' AND Status__c = \'' + String.escapeSingleQuotes(unitStatus) + '\'';
        }
        if (String.isNotBlank(unitNumber)) {
            String searchPattern = '%' + String.escapeSingleQuotes(unitNumber.trim()) + '%';
            soql += ' AND (Unit_Number__c LIKE \'' + searchPattern + '\' OR Name LIKE \'' + searchPattern + '\')';
        }

        soql += ' ORDER BY Project__r.Name, Tower__r.Name, Floor__c, Unit_Number__c LIMIT 500';

        List<Unit__c> units = Database.query(soql);
        return mapToUnitRows(units);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BLOCK UNITS (enhanced with management, blocking for, lead)
    // ═══════════════════════════════════════════════════════════════════

    public static BlockResult blockUnits(List<Id> unitIds, Integer blockDays, String reason) {
        return blockUnits(unitIds, blockDays, reason, false, null, null);
    }

    public static BlockResult blockUnits(
        List<Id> unitIds,
        Integer blockDays,
        String reason,
        Boolean isManagement,
        Id blockingForUserId,
        Id leadId
    ) {
        BlockResult result = new BlockResult();

        // Block reason is mandatory
        if (String.isBlank(reason)) {
            result.failures.add(new BlockFailure(null, null, 'Block reason is mandatory.'));
            result.failureCount = unitIds.size();
            return result;
        }

        // For non-management blocks, duration is mandatory
        if (!isManagement && (blockDays == null || blockDays < 1)) {
            result.failures.add(new BlockFailure(null, null, 'Block duration is required (minimum 1 day).'));
            result.failureCount = unitIds.size();
            return result;
        }

        Map<Id, Unit__c> unitsMap = new Map<Id, Unit__c>([
            SELECT Id, Unit_Number__c, Status__c, Project__c, Project__r.Max_Block_Days__c
            FROM Unit__c
            WHERE Id IN :unitIds
        ]);

        List<Unit__c> toUpdate = new List<Unit__c>();
        Date expiryDate = (blockDays != null && blockDays > 0) ? Date.today().addDays(blockDays) : null;

        for (Id uid : unitIds) {
            Unit__c unit = unitsMap.get(uid);
            if (unit == null) {
                result.failures.add(new BlockFailure(uid, 'Unknown', 'Unit not found.'));
                result.failureCount++;
                continue;
            }

            // Only Available units can be blocked
            if (unit.Status__c != 'Available') {
                result.failures.add(new BlockFailure(uid, unit.Unit_Number__c,
                    'Unit status is \'' + unit.Status__c + '\'. Only Available units can be blocked.'));
                result.failureCount++;
                continue;
            }

            // Validate against project max block days (skip for management blocks)
            if (!isManagement && unit.Project__r.Max_Block_Days__c != null
                && blockDays != null && blockDays > unit.Project__r.Max_Block_Days__c) {
                result.failures.add(new BlockFailure(uid, unit.Unit_Number__c,
                    'Block duration exceeds project maximum of ' + unit.Project__r.Max_Block_Days__c.intValue() + ' days.'));
                result.failureCount++;
                continue;
            }

            Unit__c upd = new Unit__c(Id = uid);
            upd.Status__c = 'Blocked';
            upd.Block_Expiry__c = expiryDate;
            upd.Blocked_By_User__c = UserInfo.getUserId();
            upd.Block_Reason__c = reason;
            upd.Block_Duration_Days__c = blockDays;
            upd.Is_Management_Block__c = isManagement;
            if (blockingForUserId != null) {
                upd.Blocking_For__c = blockingForUserId;
            }
            if (leadId != null) {
                upd.Blocked_By_Lead__c = leadId;
            }
            toUpdate.add(upd);
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                Unit__c unit = unitsMap.get(toUpdate[i].Id);

                if (sr.isSuccess()) {
                    result.successCount++;
                } else {
                    String errMsg = '';
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getMessage() + '; ';
                    }
                    result.failures.add(new BlockFailure(
                        toUpdate[i].Id, unit != null ? unit.Unit_Number__c : 'Unknown', errMsg));
                    result.failureCount++;
                }
            }
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  UNBLOCK UNITS
    // ═══════════════════════════════════════════════════════════════════

    public static BlockResult unblockUnits(List<Id> unitIds) {
        BlockResult result = new BlockResult();

        Map<Id, Unit__c> unitsMap = new Map<Id, Unit__c>([
            SELECT Id, Unit_Number__c, Status__c
            FROM Unit__c
            WHERE Id IN :unitIds
        ]);

        List<Unit__c> toUpdate = new List<Unit__c>();

        for (Id uid : unitIds) {
            Unit__c unit = unitsMap.get(uid);
            if (unit == null) {
                result.failures.add(new BlockFailure(uid, 'Unknown', 'Unit not found.'));
                result.failureCount++;
                continue;
            }

            if (unit.Status__c != 'Blocked') {
                result.failures.add(new BlockFailure(uid, unit.Unit_Number__c,
                    'Unit is not blocked (status: \'' + unit.Status__c + '\').'));
                result.failureCount++;
                continue;
            }

            Unit__c upd = new Unit__c(Id = uid);
            upd.Status__c = 'Available';
            upd.Block_Expiry__c = null;
            upd.Blocked_By_Lead__c = null;
            upd.Blocked_By_User__c = null;
            upd.Block_Reason__c = null;
            upd.Block_Duration_Days__c = null;
            upd.Is_Management_Block__c = false;
            upd.Blocking_For__c = null;
            toUpdate.add(upd);
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                Unit__c unit = unitsMap.get(toUpdate[i].Id);

                if (sr.isSuccess()) {
                    result.successCount++;
                } else {
                    String errMsg = '';
                    for (Database.Error err : sr.getErrors()) {
                        errMsg += err.getMessage() + '; ';
                    }
                    result.failures.add(new BlockFailure(
                        toUpdate[i].Id, unit != null ? unit.Unit_Number__c : 'Unknown', errMsg));
                    result.failureCount++;
                }
            }
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BLOCKED UNITS VIEWER (Tab 5)
    // ═══════════════════════════════════════════════════════════════════

    public static List<UnitRow> searchBlockedUnits(Id blockedByUserId, Boolean isManagement, Id blockingForUserId) {
        String soql = 'SELECT Id, Name, Unit_Number__c, Project__c, Project__r.Name, '
            + 'Project__r.Max_Block_Days__c, '
            + 'Tower__c, Tower__r.Name, Floor__c, Unit_Type__c, BHK_Type__c, '
            + 'Status__c, Blocked_By_User__c, Blocked_By_User__r.Name, '
            + 'Blocking_For__c, Blocking_For__r.Name, '
            + 'Block_Reason__c, Block_Expiry__c, Is_Management_Block__c, '
            + 'Blocked_By_Lead__c, Blocked_By_Lead__r.Name '
            + 'FROM Unit__c WHERE Status__c = \'Blocked\'';

        if (blockedByUserId != null) {
            soql += ' AND Blocked_By_User__c = \'' + String.escapeSingleQuotes(String.valueOf(blockedByUserId)) + '\'';
        }
        if (isManagement != null) {
            soql += ' AND Is_Management_Block__c = ' + isManagement;
        }
        if (blockingForUserId != null) {
            soql += ' AND Blocking_For__c = \'' + String.escapeSingleQuotes(String.valueOf(blockingForUserId)) + '\'';
        }

        soql += ' ORDER BY Project__r.Name, Tower__r.Name, Floor__c, Unit_Number__c LIMIT 500';

        List<Unit__c> units = Database.query(soql);
        return mapToUnitRows(units);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  UNIT BLOCK REQUESTS (Tab 6)
    // ═══════════════════════════════════════════════════════════════════

    public static Unit_Block_Request__c createBlockRequest(
        Id unitId, Id projectId, Id leadId, Id approverId,
        Integer blockDays, String reason, Boolean isManagement
    ) {
        Unit_Block_Request__c req = new Unit_Block_Request__c();
        req.Unit__c = unitId;
        req.Project__c = projectId;
        req.Lead__c = leadId;
        req.Requested_By__c = UserInfo.getUserId();
        req.Approver__c = approverId;
        req.Block_Duration_Days__c = blockDays;
        req.Block_Reason__c = reason;
        req.Status__c = 'Pending';
        req.Is_Management_Block__c = isManagement == true;
        insert req;
        return req;
    }

    public static Unit_Block_Request__c approveBlockRequest(Id requestId) {
        Unit_Block_Request__c req = [
            SELECT Id, Status__c, Unit__c, Lead__c, Block_Duration_Days__c, Block_Reason__c,
                   Is_Management_Block__c, Requested_By__c
            FROM Unit_Block_Request__c
            WHERE Id = :requestId LIMIT 1
        ];

        if (req.Status__c != 'Pending') {
            throw new AuraHandledException('Request is already ' + req.Status__c + '.');
        }

        req.Status__c = 'Approved';
        req.Response_Date__c = System.now();
        update req;

        // Auto-block the unit
        Integer days = req.Block_Duration_Days__c != null ? req.Block_Duration_Days__c.intValue() : 0;
        blockUnits(
            new List<Id>{ req.Unit__c },
            days,
            req.Block_Reason__c,
            req.Is_Management_Block__c,
            req.Requested_By__c,
            req.Lead__c
        );

        return req;
    }

    public static Unit_Block_Request__c rejectBlockRequest(Id requestId, String notes) {
        Unit_Block_Request__c req = [
            SELECT Id, Status__c
            FROM Unit_Block_Request__c
            WHERE Id = :requestId LIMIT 1
        ];

        if (req.Status__c != 'Pending') {
            throw new AuraHandledException('Request is already ' + req.Status__c + '.');
        }

        req.Status__c = 'Rejected';
        req.Response_Date__c = System.now();
        req.Response_Notes__c = notes;
        update req;
        return req;
    }

    public static List<BlockRequestRow> getPendingRequests(Id approverId) {
        return mapToBlockRequestRows([
            SELECT Id, Name, Unit__c, Unit__r.Unit_Number__c,
                   Project__c, Project__r.Name,
                   Lead__c, Lead__r.First_Name__c, Lead__r.Last_Name__c,
                   Requested_By__c, Requested_By__r.Name,
                   Approver__c, Approver__r.Name,
                   Block_Duration_Days__c, Block_Reason__c, Status__c,
                   Is_Management_Block__c, CreatedDate,
                   Response_Date__c, Response_Notes__c
            FROM Unit_Block_Request__c
            WHERE Approver__c = :approverId
            AND Status__c = 'Pending'
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]);
    }

    public static List<BlockRequestRow> getMyRequests(Id requesterId) {
        return mapToBlockRequestRows([
            SELECT Id, Name, Unit__c, Unit__r.Unit_Number__c,
                   Project__c, Project__r.Name,
                   Lead__c, Lead__r.First_Name__c, Lead__r.Last_Name__c,
                   Requested_By__c, Requested_By__r.Name,
                   Approver__c, Approver__r.Name,
                   Block_Duration_Days__c, Block_Reason__c, Status__c,
                   Is_Management_Block__c, CreatedDate,
                   Response_Date__c, Response_Notes__c
            FROM Unit_Block_Request__c
            WHERE Requested_By__c = :requesterId
            ORDER BY CreatedDate DESC
            LIMIT 200
        ]);
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HELPERS
    // ═══════════════════════════════════════════════════════════════════

    private static List<UnitRow> mapToUnitRows(List<Unit__c> units) {
        List<UnitRow> rows = new List<UnitRow>();
        for (Unit__c u : units) {
            UnitRow row = new UnitRow();
            row.unitId = u.Id;
            row.unitUrl = '/' + u.Id;
            row.unitNumber = u.Unit_Number__c;
            row.unitName = u.Name;
            row.projectName = u.Project__c != null ? u.Project__r.Name : '';
            row.projectId = u.Project__c;
            row.towerName = u.Tower__c != null ? u.Tower__r.Name : '';
            row.floor = u.Floor__c != null ? String.valueOf(u.Floor__c.intValue()) : '';
            row.unitType = u.Unit_Type__c;
            row.bhkType = u.BHK_Type__c;
            row.unitStatus = u.Status__c;
            row.blockedByUser = u.Blocked_By_User__c != null ? u.Blocked_By_User__r.Name : '';
            row.blockingForUser = u.Blocking_For__c != null ? u.Blocking_For__r.Name : '';
            row.blockReason = u.Block_Reason__c;
            row.blockExpiry = u.Block_Expiry__c;
            row.isManagementBlock = u.Is_Management_Block__c;
            row.blockedByLead = u.Blocked_By_Lead__c != null ? u.Blocked_By_Lead__r.Name : '';
            row.maxBlockDays = u.Project__r.Max_Block_Days__c != null
                ? u.Project__r.Max_Block_Days__c.intValue() : null;
            rows.add(row);
        }
        return rows;
    }

    private static List<BlockRequestRow> mapToBlockRequestRows(List<Unit_Block_Request__c> requests) {
        List<BlockRequestRow> rows = new List<BlockRequestRow>();
        for (Unit_Block_Request__c r : requests) {
            BlockRequestRow row = new BlockRequestRow();
            row.requestId = r.Id;
            row.requestName = r.Name;
            row.unitNumber = r.Unit__c != null ? r.Unit__r.Unit_Number__c : '';
            row.projectName = r.Project__c != null ? r.Project__r.Name : '';
            row.leadName = r.Lead__c != null
                ? ((r.Lead__r.First_Name__c != null ? r.Lead__r.First_Name__c : '') + ' '
                   + (r.Lead__r.Last_Name__c != null ? r.Lead__r.Last_Name__c : '')).trim()
                : '';
            row.requestedByName = r.Requested_By__c != null ? r.Requested_By__r.Name : '';
            row.approverName = r.Approver__c != null ? r.Approver__r.Name : '';
            row.blockDays = r.Block_Duration_Days__c != null ? r.Block_Duration_Days__c.intValue() : null;
            row.reason = r.Block_Reason__c;
            row.status = r.Status__c;
            row.isManagement = r.Is_Management_Block__c;
            row.createdDate = r.CreatedDate;
            row.responseDate = r.Response_Date__c;
            row.responseNotes = r.Response_Notes__c;
            rows.add(row);
        }
        return rows;
    }
}