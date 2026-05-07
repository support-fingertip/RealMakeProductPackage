/**
 * @description Unified Approval Center Controller.
 *              Aggregates pending approvals from three systems:
 *              1. Standard Salesforce Approvals (ProcessInstanceWorkitem)
 *              2. Discount Approvals (Cost_Sheet__c custom approval)
 *              3. Dynamic Approvals (Approval_Configuration__c driven)
 *              Provides approve/reject routing, record detail lookups,.
 *              and approval history across all systems.
 */
public with sharing class ApprovalCenterController {

    private static final Integer MAX_APPROVER_FIELDS = 6;

    // ── Wrapper Classes ───────────────────────────────────────────

    public class UnifiedApprovalItem {
        @AuraEnabled public String id;
        @AuraEnabled public String recordId;
        @AuraEnabled public String recordName;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String approvalType;       // Standard | Discount | Dynamic
        @AuraEnabled public String approvalSubType;
        @AuraEnabled public String submittedBy;
        @AuraEnabled public DateTime submittedDate;
        @AuraEnabled public String status;
        @AuraEnabled public String workItemId;
        @AuraEnabled public Integer discountFieldNumber;
        @AuraEnabled public String configId;
        @AuraEnabled public String recordUrl;
    }

    public class ChildRelationshipInfo {
        @AuraEnabled public String childObject;
        @AuraEnabled public String childLabel;
        @AuraEnabled public String lookupField;
        @AuraEnabled public Integer recordCount;
    }

    // ── Get All Pending Approvals ─────────────────────────────────

    @AuraEnabled
    public static Map<String, Object> getAllPendingApprovals() {
        List<UnifiedApprovalItem> allItems = new List<UnifiedApprovalItem>();
        Map<String, Integer> stats = new Map<String, Integer>{
            'total' => 0, 'standard' => 0, 'discount' => 0, 'dynamic' => 0
        };

        // Cache object labels
        Map<String, String> objectLabelCache = new Map<String, String>();

        // 1. Standard Salesforce Approvals
        List<UnifiedApprovalItem> standardItems = getStandardApprovals(objectLabelCache);

        // 2. Discount Approvals (Cost Sheet)
        List<UnifiedApprovalItem> discountItems = getDiscountApprovals(objectLabelCache);

        // 3. Dynamic Approvals
        List<UnifiedApprovalItem> dynamicItems = getDynamicApprovals(objectLabelCache);

        // Deduplication: Dynamic approvals use Approval.process() which creates
        // ProcessInstanceWorkitem records. Remove standard duplicates, keep dynamic
        // entry enriched with workItemId.
        Set<String> dynamicRecordIds = new Set<String>();
        for (UnifiedApprovalItem item : dynamicItems) {
            dynamicRecordIds.add(item.recordId);
        }

        for (UnifiedApprovalItem stdItem : standardItems) {
            if (dynamicRecordIds.contains(stdItem.recordId)) {
                // Enrich matching dynamic item with workItemId
                for (UnifiedApprovalItem dynItem : dynamicItems) {
                    if (dynItem.recordId == stdItem.recordId && dynItem.workItemId == null) {
                        dynItem.workItemId = stdItem.workItemId;
                        break;
                    }
                }
            } else {
                allItems.add(stdItem);
            }
        }
        allItems.addAll(discountItems);
        allItems.addAll(dynamicItems);

        // Build stats
        for (UnifiedApprovalItem item : allItems) {
            if (item.approvalType == 'Standard') { stats.put('standard', stats.get('standard') + 1); }
            else if (item.approvalType == 'Discount') { stats.put('discount', stats.get('discount') + 1); }
            else if (item.approvalType == 'Dynamic') { stats.put('dynamic', stats.get('dynamic') + 1); }
        }
        stats.put('total', allItems.size());

        // Build object filter options
        Set<String> seenObjects = new Set<String>();
        List<Map<String, String>> objectOptions = new List<Map<String, String>>();
        objectOptions.add(new Map<String, String>{ 'label' => 'All Objects', 'value' => '' });
        for (UnifiedApprovalItem item : allItems) {
            if (!seenObjects.contains(item.objectApiName)) {
                seenObjects.add(item.objectApiName);
                objectOptions.add(new Map<String, String>{
                    'label' => item.objectLabel,
                    'value' => item.objectApiName
                });
            }
        }

        return new Map<String, Object>{
            'items' => allItems,
            'stats' => stats,
            'objectOptions' => objectOptions
        };
    }

    // ── Standard Approvals ────────────────────────────────────────

    private static List<UnifiedApprovalItem> getStandardApprovals(Map<String, String> labelCache) {
        List<UnifiedApprovalItem> items = new List<UnifiedApprovalItem>();

        try {
            List<ProcessInstanceWorkitem> workItems = [
                SELECT Id, ProcessInstance.TargetObjectId, ProcessInstance.Status,
                       ProcessInstance.CreatedById, ProcessInstance.CreatedBy.Name,
                       ProcessInstance.CreatedDate, ProcessInstance.TargetObject.Name,
                       ProcessInstance.TargetObject.Type
                FROM ProcessInstanceWorkitem
                WHERE ActorId = :UserInfo.getUserId()
                AND ProcessInstance.Status = 'Pending'
                ORDER BY ProcessInstance.CreatedDate DESC
                LIMIT 200
            ];

            for (ProcessInstanceWorkitem wi : workItems) {
                UnifiedApprovalItem item = new UnifiedApprovalItem();
                item.workItemId = wi.Id;
                item.id = wi.Id;
                item.recordId = wi.ProcessInstance.TargetObjectId;
                item.recordName = wi.ProcessInstance.TargetObject.Name;
                item.objectApiName = wi.ProcessInstance.TargetObject.Type;
                item.objectLabel = resolveObjectLabel(item.objectApiName, labelCache);
                item.approvalType = 'Standard';
                item.approvalSubType = '';
                item.submittedBy = wi.ProcessInstance.CreatedBy.Name;
                item.submittedDate = wi.ProcessInstance.CreatedDate;
                item.status = 'Pending';
                item.recordUrl = '/lightning/r/' + item.objectApiName + '/' + item.recordId + '/view';
                items.add(item);
            }
        } catch (Exception e) {
            System.debug('Error fetching standard approvals: ' + e.getMessage());
        }

        return items;
    }

    // ── Discount Approvals ────────────────────────────────────────

   private static List<UnifiedApprovalItem> getDiscountApprovals(Map<String, String> labelCache) {
    List<UnifiedApprovalItem> items = new List<UnifiedApprovalItem>();

    try {
        Id currentUserId = UserInfo.getUserId();
        System.debug('=== getDiscountApprovals START for user: ' + currentUserId + ' ===');

        // Step 1a: Find matrix rows for current user (direct or delegated)
        List<Discount_Approval_Matrix__c> userMatrixRows = [
            SELECT Discount_Field_Number__c, Approval_Level__c
            FROM Discount_Approval_Matrix__c
            WHERE Is_Active__c = true
            AND (Approver_User__c = :currentUserId
                 OR Delegated_Approver__c = :currentUserId)
        ];

        // Step 1b: Role-based
        User currentUser = [SELECT Id, UserRole.Name FROM User WHERE Id = :currentUserId LIMIT 1];
        String currentRoleName = (currentUser.UserRole != null) ? currentUser.UserRole.Name : null;

        if (String.isNotBlank(currentRoleName)) {
            List<Discount_Approval_Matrix__c> roleMatrixRows = [
                SELECT Discount_Field_Number__c, Approval_Level__c
                FROM Discount_Approval_Matrix__c
                WHERE Is_Active__c = true
                AND Approver_Role__c = :currentRoleName
            ];
            userMatrixRows.addAll(roleMatrixRows);
        }

        System.debug('Matrix rows found: ' + userMatrixRows.size());
        if (userMatrixRows.isEmpty()) return items;

        Set<Integer> approverFieldNumbers = new Set<Integer>();
        for (Discount_Approval_Matrix__c row : userMatrixRows) {
            approverFieldNumbers.add(Integer.valueOf(row.Discount_Field_Number__c));
        }
        System.debug('Approver field numbers: ' + approverFieldNumbers);

        // Step 2: Get ALL Cost Sheets (no status filter — engine decides)
        // ✅ FIX: Don't filter by stored status field since it's never updated
        List<Cost_Sheet__c> costSheets = [
            SELECT Id, Name, CreatedBy.Name, CreatedById, Approval_Submitted_Date__c,
                   Discount_Approval_Status__c
            FROM Cost_Sheet__c
            WHERE Discount_Approval_Status__c != 'Approved'
            AND Discount_Approval_Status__c != 'Rejected'
            LIMIT 200
        ];
        System.debug('Cost Sheets to evaluate: ' + costSheets.size());

        // Labels are obtained per-discount from disc.label (set by evaluateDiscounts)

        // Step 3: For each Cost Sheet, call evaluateDiscounts() — same as the panel does
        // This gives us the REAL computed status, not the stale stored value
        for (Cost_Sheet__c cs : costSheets) {
            try {
                DiscountApprovalEngine.ApprovalSummary summary =
                    DiscountApprovalEngine.evaluateDiscounts(cs.Id);

                if (summary == null || summary.discounts == null) continue;

                for (DiscountApprovalEngine.DiscountEvaluation disc : summary.discounts) {
                    // Skip if not this user's field number
                    if (!approverFieldNumbers.contains(disc.fieldNumber)) continue;

                    // Skip if not pending approval
                    if (disc.status != 'Pending Approval') continue;

                    // ✅ Only show if THIS user is the assigned approver
                    if (disc.approverId != currentUserId) continue;

                    System.debug('✅ Found pending discount: CS=' + cs.Name
                        + ' field=' + disc.fieldNumber
                        + ' approverId=' + disc.approverId);

                    UnifiedApprovalItem item = new UnifiedApprovalItem();
                    item.id = cs.Id + '-disc-' + disc.fieldNumber;
                    item.recordId = cs.Id;
                    item.recordName = cs.Name;
                    item.objectApiName = 'Cost_Sheet__c';
                    item.objectLabel = resolveObjectLabel('Cost_Sheet__c', labelCache);
                    item.approvalType = 'Discount';
                    item.approvalSubType = String.isNotBlank(disc.label)
                        ? disc.label : 'Discount ' + disc.fieldNumber;
                    item.submittedBy = cs.CreatedBy.Name;
                    item.submittedDate = cs.Approval_Submitted_Date__c;
                    item.status = 'Pending';
                    item.discountFieldNumber = disc.fieldNumber;
                    item.recordUrl = '/lightning/r/Cost_Sheet__c/' + cs.Id + '/view';
                    items.add(item);
                }
            } catch (Exception evalEx) {
                System.debug('Error evaluating CS ' + cs.Id + ': ' + evalEx.getMessage());
            }
        }

    } catch (Exception e) {
        System.debug('❌ Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
    }

    System.debug('=== getDiscountApprovals END — ' + items.size() + ' items ===');
    return items;
}

    // ── Dynamic Approvals ─────────────────────────────────────────

    private static List<UnifiedApprovalItem> getDynamicApprovals(Map<String, String> labelCache) {
        List<UnifiedApprovalItem> items = new List<UnifiedApprovalItem>();

        try {
            Id currentUserId = UserInfo.getUserId();

            // Get all active dynamic approval configurations
            List<Approval_Configuration__c> configs = [
                SELECT Id, Object_API_Name__c, Process_Type__c, Process_Label__c,
                       Status_Field_API_Name__c, Pending_Status_Value__c
                FROM Approval_Configuration__c
                WHERE Is_Active__c = true
                AND Status_Field_API_Name__c != null
                AND Pending_Status_Value__c != null
            ];

            if (configs.isEmpty()) {
                return items;
            }

            // Group configs by object
            Map<String, List<Approval_Configuration__c>> configsByObject = new Map<String, List<Approval_Configuration__c>>();
            for (Approval_Configuration__c cfg : configs) {
                if (!configsByObject.containsKey(cfg.Object_API_Name__c)) {
                    configsByObject.put(cfg.Object_API_Name__c, new List<Approval_Configuration__c>());
                }
                configsByObject.get(cfg.Object_API_Name__c).add(cfg);
            }

            // Track found record IDs to avoid duplicates in fallback
            Set<Id> foundRecordIds = new Set<Id>();

            // Query each object dynamically
            for (String objName : configsByObject.keySet()) {
                List<Approval_Configuration__c> objConfigs = configsByObject.get(objName);

                // Build field set and WHERE conditions
                Set<String> fields = new Set<String>{ 'Id', 'Name', 'CreatedBy.Name', 'CreatedById', 'CreatedDate' };
                List<String> statusConditions = new List<String>();

                // Filter out configs whose status field doesn't exist on the object
                List<Approval_Configuration__c> validConfigs = new List<Approval_Configuration__c>();
                for (Approval_Configuration__c cfg : objConfigs) {
                    if (hasField(objName, cfg.Status_Field_API_Name__c)) {
                        fields.add(cfg.Status_Field_API_Name__c);
                        statusConditions.add(
                            cfg.Status_Field_API_Name__c + ' = \'' +
                            String.escapeSingleQuotes(cfg.Pending_Status_Value__c) + '\''
                        );
                        validConfigs.add(cfg);
                    } else {
                        System.debug('Skipping config ' + cfg.Process_Label__c
                            + ': status field ' + cfg.Status_Field_API_Name__c
                            + ' not found on ' + objName);
                    }
                }

                if (statusConditions.isEmpty()) {
                    continue;
                }

                // Add approver fields if they exist
                List<String> approverConditions = new List<String>();
                for (Integer i = 1; i <= MAX_APPROVER_FIELDS; i++) {
                    String approverField = 'Approver_' + i + '__c';
                    if (hasField(objName, approverField)) {
                        fields.add(approverField);
                        approverConditions.add(approverField + ' = \'' + currentUserId + '\'');
                    }
                }

                // If no Approver fields, still query by status only (fallback will enrich via ProcessInstanceWorkitem)
                String soql;
                if (!approverConditions.isEmpty()) {
                    soql = 'SELECT ' + String.join(new List<String>(fields), ', ')
                        + ' FROM ' + String.escapeSingleQuotes(objName)
                        + ' WHERE (' + String.join(statusConditions, ' OR ') + ')'
                        + ' AND (' + String.join(approverConditions, ' OR ') + ')'
                        + ' ORDER BY CreatedDate DESC'
                        + ' LIMIT 200';
                } else {
                    // No Approver fields: skip direct query, rely on ProcessInstanceWorkitem fallback below
                    continue;
                }

                List<SObject> records;
                try {
                    records = Database.query(soql);
                } catch (Exception qe) {
                    System.debug('Error querying ' + objName + ': ' + qe.getMessage());
                    continue;
                }

                for (SObject rec : records) {
                    // Match each record to its active config(s)
                    for (Approval_Configuration__c cfg : validConfigs) {
                        Object statusVal = rec.get(cfg.Status_Field_API_Name__c);
                        if (statusVal != null && String.valueOf(statusVal) == cfg.Pending_Status_Value__c) {
                            UnifiedApprovalItem item = new UnifiedApprovalItem();
                            item.id = rec.Id + '-dyn-' + cfg.Id;
                            item.recordId = rec.Id;
                            item.recordName = (String) rec.get('Name');
                            item.objectApiName = objName;
                            item.objectLabel = resolveObjectLabel(objName, labelCache);
                            item.approvalType = 'Dynamic';
                            item.approvalSubType = cfg.Process_Label__c;
                            item.submittedBy = ((SObject) rec.getSObject('CreatedBy')).get('Name') != null
                                ? (String) ((SObject) rec.getSObject('CreatedBy')).get('Name') : '';
                            item.submittedDate = (DateTime) rec.get('CreatedDate');
                            item.status = 'Pending';
                            item.configId = cfg.Id;
                            item.recordUrl = '/lightning/r/' + objName + '/' + rec.Id + '/view';
                            items.add(item);
                            foundRecordIds.add(rec.Id);
                        }
                    }
                }
            }

            // ── Populate workItemId for dynamic items ──────────────────
            // Dynamic approvals use Approval.process() which creates
            // ProcessInstanceWorkitem records. Look up the workItemId so
            // approve/reject actions work correctly.
            if (!items.isEmpty()) {
                Set<Id> dynamicRecordIds = new Set<Id>();
                for (UnifiedApprovalItem item : items) {
                    dynamicRecordIds.add(Id.valueOf(item.recordId));
                }

                Map<Id, Id> recordToWorkItemId = new Map<Id, Id>();
                try {
                    for (ProcessInstanceWorkitem wi : [
                        SELECT Id, ProcessInstance.TargetObjectId
                        FROM ProcessInstanceWorkitem
                        WHERE ProcessInstance.TargetObjectId IN :dynamicRecordIds
                        AND ProcessInstance.Status = 'Pending'
                    ]) {
                        recordToWorkItemId.put(wi.ProcessInstance.TargetObjectId, wi.Id);
                    }
                } catch (Exception e) {
                    System.debug('Error looking up work items for dynamic approvals: ' + e.getMessage());
                }

                for (UnifiedApprovalItem item : items) {
                    Id recId = Id.valueOf(item.recordId);
                    if (recordToWorkItemId.containsKey(recId)) {
                        item.workItemId = String.valueOf(recordToWorkItemId.get(recId));
                    }
                }
            }

            // ── Fallback: Find dynamic approvals via ProcessInstanceWorkitem ──
            // Catches cases where Approver_X fields aren't populated but the
            // standard approval process routes to the current user
            try {
                Set<String> dynamicObjectNames = configsByObject.keySet();
                List<ProcessInstanceWorkitem> pendingWorkItems = [
                    SELECT Id, ProcessInstance.TargetObjectId, ProcessInstance.TargetObject.Name,
                           ProcessInstance.TargetObject.Type, ProcessInstance.CreatedBy.Name,
                           ProcessInstance.CreatedDate
                    FROM ProcessInstanceWorkitem
                    WHERE ActorId = :currentUserId
                    AND ProcessInstance.Status = 'Pending'
                    ORDER BY ProcessInstance.CreatedDate DESC
                    LIMIT 200
                ];

                for (ProcessInstanceWorkitem wi : pendingWorkItems) {
                    String objType = wi.ProcessInstance.TargetObject.Type;
                    Id targetId = wi.ProcessInstance.TargetObjectId;

                    // Only include if object has dynamic config and record not already found
                    if (dynamicObjectNames.contains(objType) && !foundRecordIds.contains(targetId)) {
                        List<Approval_Configuration__c> objConfigs = configsByObject.get(objType);
                        if (objConfigs != null && !objConfigs.isEmpty()) {
                            UnifiedApprovalItem item = new UnifiedApprovalItem();
                            item.id = wi.Id + '-dyn-' + objConfigs[0].Id;
                            item.recordId = targetId;
                            item.recordName = wi.ProcessInstance.TargetObject.Name;
                            item.objectApiName = objType;
                            item.objectLabel = resolveObjectLabel(objType, labelCache);
                            item.approvalType = 'Dynamic';
                            item.approvalSubType = objConfigs[0].Process_Label__c;
                            item.submittedBy = wi.ProcessInstance.CreatedBy.Name;
                            item.submittedDate = wi.ProcessInstance.CreatedDate;
                            item.status = 'Pending';
                            item.workItemId = wi.Id;
                            item.configId = objConfigs[0].Id;
                            item.recordUrl = '/lightning/r/' + objType + '/' + targetId + '/view';
                            items.add(item);
                            foundRecordIds.add(targetId);
                        }
                    }
                }
            } catch (Exception e) {
                System.debug('Error in dynamic approval fallback: ' + e.getMessage());
            }
        } catch (Exception e) {
            System.debug('Error fetching dynamic approvals: ' + e.getMessage());
        }
 System.debug('getDynamicApprovals  ----------> '+ items);
        return items;
    }

    // ── Process Action (Approve / Reject) ─────────────────────────

    @AuraEnabled
    public static Map<String, Object> processAction(
        String approvalType,
        String action,
        String recordId,
        String comments,
        String workItemId,
        Integer discountFieldNumber,
        String configId
    ) {
        try {
            if (approvalType == 'Standard' || approvalType == 'Dynamic') {
                if (String.isBlank(workItemId)) {
                    return new Map<String, Object>{ 'success' => false, 'message' => 'Work item ID is required' };
                }
                BulkApprovalController.ApprovalResponse response =
                    BulkApprovalController.processApprovals(
                        new List<Id>{ Id.valueOf(workItemId) }, action, comments
                    );
                return new Map<String, Object>{ 'success' => response.success, 'message' => response.message };
            }
            else if (approvalType == 'Discount') {
                if (String.isBlank(recordId) || discountFieldNumber == null) {
                    return new Map<String, Object>{ 'success' => false, 'message' => 'Record ID and field number are required' };
                }
                Id csId = Id.valueOf(recordId);
                if (action == 'Approve') {
                    DiscountApprovalEngine.approveDiscount(csId, discountFieldNumber, comments);
                } else {
                    DiscountApprovalEngine.rejectDiscount(csId, discountFieldNumber, comments);
                }
                return new Map<String, Object>{
                    'success' => true,
                    'message' => 'Discount ' + action.toLowerCase() + 'd successfully'
                };
            }
            return new Map<String, Object>{ 'success' => false, 'message' => 'Unknown approval type: ' + approvalType };
        } catch (Exception e) {
            return new Map<String, Object>{ 'success' => false, 'message' => e.getMessage() };
        }
    }

    // ── Bulk Action ───────────────────────────────────────────────

    @AuraEnabled
    public static Map<String, Object> processBulkAction(
        String itemsJson,
        String action,
        String comments
    ) {
        Integer successCount = 0;
        Integer failureCount = 0;
        List<String> errors = new List<String>();

        try {
            List<Object> rawItems = (List<Object>) JSON.deserializeUntyped(itemsJson);
            List<Map<String, Object>> itemsList = new List<Map<String, Object>>();
            for (Object item : rawItems) {
                itemsList.add((Map<String, Object>) item);
            }

            // Separate by type
            List<Id> standardWorkItemIds = new List<Id>();
            List<Map<String, Object>> discountItems = new List<Map<String, Object>>();

            for (Map<String, Object> item : itemsList) {
                String type = (String) item.get('approvalType');
                if (type == 'Standard' || type == 'Dynamic') {
                    String wiId = (String) item.get('workItemId');
                    if (String.isNotBlank(wiId)) {
                        standardWorkItemIds.add(Id.valueOf(wiId));
                    }
                } else if (type == 'Discount') {
                    discountItems.add(item);
                }
            }

            // Batch process standard/dynamic
            if (!standardWorkItemIds.isEmpty()) {
                BulkApprovalController.ApprovalResponse resp =
                    BulkApprovalController.processApprovals(standardWorkItemIds, action, comments);
                successCount += resp.successCount;
                failureCount += resp.failureCount;
                errors.addAll(resp.errors);
            }

            // Process discount items individually
            for (Map<String, Object> dItem : discountItems) {
                try {
                    Id csId = Id.valueOf((String) dItem.get('recordId'));
                    Integer fieldNum = ((Decimal) dItem.get('discountFieldNumber')).intValue();
                    if (action == 'Approve') {
                        DiscountApprovalEngine.approveDiscount(csId, fieldNum, comments);
                    } else {
                        DiscountApprovalEngine.rejectDiscount(csId, fieldNum, comments);
                    }
                    successCount++;
                } catch (Exception de) {
                    failureCount++;
                    errors.add(de.getMessage());
                }
            }
        } catch (Exception e) {
            return new Map<String, Object>{
                'success' => false,
                'message' => 'Error processing bulk action: ' + e.getMessage(),
                'successCount' => successCount,
                'failureCount' => failureCount
            };
        }

        Boolean success = failureCount == 0;
        String message = successCount + ' item(s) ' + action.toLowerCase() + 'd successfully';
        if (failureCount > 0) {
            message += ', ' + failureCount + ' failed';
        }

        return new Map<String, Object>{
            'success' => success,
            'message' => message,
            'successCount' => successCount,
            'failureCount' => failureCount,
            'errors' => errors
        };
    }

    // ── Record Details ────────────────────────────────────────────

   @AuraEnabled
public static Map<String, Object> getRecordDetails(Id recordId) {
    if (recordId == null) {
        throw new AuraHandledException('Record ID is required');
    }

    String objectApiName = NamespaceUtil.strip(recordId.getSObjectType().getDescribe().getName());
    String objectLabel = recordId.getSObjectType().getDescribe().getLabel();

    Map<String, Schema.SObjectField> fieldsMap =
        recordId.getSObjectType().getDescribe().fields.getMap();

    // ✅ FIX: Don't pre-add Id — let it come naturally from the fieldsMap loop
    // Track added fields in LOWERCASE to catch Id/id/ID all as duplicates
    Set<String> addedFields = new Set<String>();
    List<String> queryFields = new List<String>();
    List<Map<String, String>> fieldMeta = new List<Map<String, String>>();
    Integer fieldCount = 0;

    for (String fieldName : fieldsMap.keySet()) {
        Schema.DescribeFieldResult fd = fieldsMap.get(fieldName).getDescribe();

        if (!fd.isAccessible()) { continue; }

        // ✅ Deduplicate using lowercase field name
        String lowerName = fd.getName().toLowerCase();
        if (addedFields.contains(lowerName)) { continue; }

        Schema.DisplayType dt = fd.getType();
        if (dt == Schema.DisplayType.ADDRESS ||
            dt == Schema.DisplayType.LOCATION ||
            dt == Schema.DisplayType.BASE64) {
            continue;
        }

        addedFields.add(lowerName);
        queryFields.add(fd.getName());

        // Don't add Id to fieldMeta — we don't need to display it
        if (lowerName != 'id') {
            fieldMeta.add(new Map<String, String>{
                'name'  => fd.getName(),
                'label' => fd.getLabel(),
                'type'  => dt.name()
            });
            fieldCount++;
        }

        if (fieldCount >= 50) { break; }
    }

    // ✅ Ensure Id is always in the query for the WHERE clause
    if (!addedFields.contains('id')) {
        queryFields.add(0, 'Id');
    }

    System.debug('Query fields: ' + queryFields);

    String soql = 'SELECT ' + String.join(queryFields, ', ') +
                   ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                   ' WHERE Id = :recordId LIMIT 1';

    System.debug('SOQL: ' + soql);

    List<SObject> records = Database.query(soql);
    if (records.isEmpty()) {
        throw new AuraHandledException('Record not found');
    }

    SObject rec = records[0];
    List<Map<String, Object>> fields = new List<Map<String, Object>>();

    for (Map<String, String> fm : fieldMeta) {
        Object val = rec.get(fm.get('name'));
        if (val != null) {
            fields.add(new Map<String, Object>{
                'label' => fm.get('label'),
                'value' => String.valueOf(val),
                'type'  => fm.get('type')
            });
        }
    }

    return new Map<String, Object>{
        'fields'        => fields,
        'objectLabel'   => objectLabel,
        'objectApiName' => objectApiName
    };
}

    // ── Approval History ──────────────────────────────────────────

    @AuraEnabled
public static List<Map<String, Object>> getApprovalHistory(Id recordId, String approvalType) {
    if (recordId == null) {
        throw new AuraHandledException('Record ID is required');
    }

    if (approvalType == 'Discount') {
        try {
            // ✅ FIX: Wrap in try-catch so one failure doesn't break Promise.all
            List<Discount_Approval_Log__c> logs =
                DiscountApprovalEngine.getApprovalHistory(recordId);

            List<Map<String, Object>> result = new List<Map<String, Object>>();
            Integer idx = 0;
            for (Discount_Approval_Log__c log : logs) {
                result.add(new Map<String, Object>{
                    'id'           => String.valueOf(idx++),
                    'label'        => log.Discount_Label__c,
                    'action'       => log.Action__c,
                    'approverName' => log.Approver__r != null ? log.Approver__r.Name : '',
                    'comments'     => log.Comments__c,
                    'timestamp'    => log.Timestamp__c
                });
            }
            return result;
        } catch (Exception e) {
            System.debug('Error fetching discount history: ' + e.getMessage());
            return new List<Map<String, Object>>();
        }
    }

    // Standard and Dynamic — ProcessInstanceStep
    List<Map<String, Object>> history = new List<Map<String, Object>>();
    try {
        List<BulkApprovalController.ApprovalHistoryWrapper> wrappers =
            BulkApprovalController.getApprovalHistory(recordId);
        Integer idx = 0;
        for (BulkApprovalController.ApprovalHistoryWrapper w : wrappers) {
            history.add(new Map<String, Object>{
                'id'           => String.valueOf(idx++),
                'label'        => w.stepName,
                'action'       => w.status,
                'approverName' => w.actorName,
                'comments'     => w.comments,
                'timestamp'    => w.actionDate
            });
        }
    } catch (Exception e) {
        System.debug('Error fetching standard history: ' + e.getMessage());
    }
    return history;
}

    // ── Child Relationships ───────────────────────────────────────

    @AuraEnabled
    public static List<ChildRelationshipInfo> getChildObjects(Id recordId) {
        List<ChildRelationshipInfo> result = new List<ChildRelationshipInfo>();

        if (recordId == null) {
            return result;
        }

        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        List<Schema.ChildRelationship> childRels =
            recordId.getSObjectType().getDescribe().getChildRelationships();

        for (Schema.ChildRelationship rel : childRels) {
            Schema.DescribeSObjectResult childDescribe = rel.getChildSObject().getDescribe();
            if (!childDescribe.isAccessible() || !childDescribe.isQueryable()) {
                continue;
            }

            // Only include custom objects and key standard ones
            String childName = childDescribe.getName();
            if (!childDescribe.isCustom()) {
                continue;
            }

            String lookupField = rel.getField().getDescribe().getName();

            // Get count
            try {
                String countQuery = 'SELECT COUNT() FROM ' +
                    String.escapeSingleQuotes(childName) +
                    ' WHERE ' + String.escapeSingleQuotes(lookupField) +
                    ' = :recordId';
                Integer cnt = Database.countQuery(countQuery);

                if (cnt > 0) {
                    ChildRelationshipInfo info = new ChildRelationshipInfo();
                    info.childObject = childName;
                    info.childLabel = childDescribe.getLabelPlural();
                    info.lookupField = lookupField;
                    info.recordCount = cnt;
                    result.add(info);
                }
            } catch (Exception e) {
                // Skip relationships that can't be queried
            }
        }
		 System.debug('getChildObjects  ----------> '+ result);
        return result;
    }

    // ── Related Records ───────────────────────────────────────────

    @AuraEnabled
    public static Map<String, Object> getRelatedRecords(
        Id recordId, String childObject, String lookupField
    ) {
        if (recordId == null || String.isBlank(childObject) || String.isBlank(lookupField)) {
            throw new AuraHandledException('Record ID, child object, and lookup field are required');
        }

        Schema.SObjectType childType = NamespaceUtil.describeObject(childObject);
        if (childType == null) {
            throw new AuraHandledException('Invalid child object: ' + childObject);
        }
        String childApiName = childType.getDescribe().getName();
        String lookupApiName = NamespaceUtil.qualify(lookupField);

        Map<String, Schema.SObjectField> fieldsMap = childType.getDescribe().fields.getMap();

        // Select key displayable fields (limit to 8)
        List<String> queryFields = new List<String>{ 'Id' };
        List<Map<String, String>> columns = new List<Map<String, String>>();
        Integer fieldCount = 0;

        // Always include Name first
        if (fieldsMap.containsKey('name')) {
            queryFields.add('Name');
            columns.add(new Map<String, String>{ 'label' => 'Name', 'fieldName' => 'Name', 'type' => 'text' });
            fieldCount++;
        }

        for (String fieldName : fieldsMap.keySet()) {
            if (fieldName == 'name' || fieldName == 'id') { continue; }

            Schema.DescribeFieldResult fd = fieldsMap.get(fieldName).getDescribe();
            if (!fd.isAccessible()) { continue; }

            Schema.DisplayType dt = fd.getType();
            if (dt == Schema.DisplayType.ADDRESS || dt == Schema.DisplayType.LOCATION ||
                dt == Schema.DisplayType.BASE64 || dt == Schema.DisplayType.TEXTAREA) {
                continue;
            }

            // Skip lookup/reference fields to keep it simple
            if (dt == Schema.DisplayType.REFERENCE) { continue; }

            queryFields.add(fd.getName());
            String colType = 'text';
            if (dt == Schema.DisplayType.CURRENCY) { colType = 'currency'; }
            else if (dt == Schema.DisplayType.DATE || dt == Schema.DisplayType.DATETIME) { colType = 'date'; }
            else if (dt == Schema.DisplayType.DOUBLE || dt == Schema.DisplayType.INTEGER ||
                     dt == Schema.DisplayType.PERCENT) { colType = 'number'; }
            else if (dt == Schema.DisplayType.BOOLEAN) { colType = 'boolean'; }

            columns.add(new Map<String, String>{
                'label' => fd.getLabel(),
                'fieldName' => fd.getName(),
                'type' => colType
            });

            fieldCount++;
            if (fieldCount >= 8) { break; }
        }

        String soql = 'SELECT ' + String.join(queryFields, ', ') +
                       ' FROM ' + String.escapeSingleQuotes(childApiName) +
                       ' WHERE ' + String.escapeSingleQuotes(lookupApiName) + ' = :recordId' +
                       ' ORDER BY CreatedDate DESC LIMIT 50';

        List<SObject> records = Database.query(soql);
        List<Map<String, Object>> rows = new List<Map<String, Object>>();

        for (SObject rec : records) {
            Map<String, Object> row = new Map<String, Object>();
            for (String field : queryFields) {
                row.put(field, rec.get(field));
            }
            rows.add(row);
        }
		 System.debug('getRelatedRecords  method  ----------> '+ new Map<String, Object>{
            'columns' => columns,
            'records' => rows
        });

        return new Map<String, Object>{
            'columns' => columns,
            'records' => rows
        };
    }

    // ── Helpers ───────────────────────────────────────────────────

    private static String resolveObjectLabel(String objectApiName, Map<String, String> cache) {
        if (cache.containsKey(objectApiName)) {
            return cache.get(objectApiName);
        }

        String label = objectApiName;
        try {
            Schema.SObjectType sot = NamespaceUtil.describeObject(objectApiName);
            if (sot != null) {
                label = sot.getDescribe().getLabel();
            }
        } catch (Exception e) {
            // Fallback to API name
        }
        cache.put(objectApiName, label);
        System.debug('label  ----------> '+ label);
        return label;
    }

    private static Boolean hasField(String objectApiName, String fieldName) {
        Schema.SObjectType objectType = NamespaceUtil.describeObject(objectApiName);
        if (objectType == null) {
            return false;
        }
        Map<String, Schema.SObjectField> fmap = objectType.getDescribe().fields.getMap();
        return fmap.containsKey(fieldName.toLowerCase()) ||
               fmap.containsKey(NamespaceUtil.qualify(fieldName).toLowerCase());
    }
}