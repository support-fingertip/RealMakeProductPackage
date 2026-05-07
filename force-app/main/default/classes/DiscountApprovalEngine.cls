/**
 * @description Core engine for the Dynamic Discount Approval Matrix.
 *              Evaluates discount values against configurable limits,
 *              determines required approval levels, routes to correct approvers,
 *              and manages the approval lifecycle.
 *
 *              Supports: Profile/Role/User/Project-based limits,
 *              multi-level approval, delegated approvers, escalation,
 *              consolidated approval (highest level wins), and audit logging.
 *
 *              Notifications: Bell notification + Email + Task on submit,
 *              outcome notifications on approve/reject.
 */
public with sharing class DiscountApprovalEngine {

    private static final Integer MAX_DISCOUNT_FIELDS = 6;

    // ── Public wrapper classes ──────────────────────────────────

    public class DiscountEvaluation {
        @AuraEnabled public Integer fieldNumber;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal value;
        @AuraEnabled public Decimal pct;
        @AuraEnabled public String status;           // Within Limit | Pending Approval | Approved | Rejected
        @AuraEnabled public Integer requiredLevel;
        @AuraEnabled public Id approverId;
        @AuraEnabled public String approverName;
        @AuraEnabled public Boolean exceedsLimit;
        @AuraEnabled public Decimal maxAllowed;
        @AuraEnabled public Decimal maxPctAllowed;
    }

    public class ApprovalSummary {
        @AuraEnabled public List<DiscountEvaluation> discounts;
        @AuraEnabled public String overallStatus;     // Not Required | Pending | Partially Approved | Approved | Rejected
        @AuraEnabled public Integer highestLevel;
        @AuraEnabled public Id nextApproverId;
        @AuraEnabled public String nextApproverName;
        @AuraEnabled public Boolean requiresApproval;
        @AuraEnabled public List<String> warnings;
    }

    // ── Evaluate all discounts on a Cost Sheet ──────────────────

    /**
     * @description Evaluate all 6 discount fields on a Cost Sheet record
     *              against the configured approval matrix.
     * @param costSheetId The Cost Sheet record Id
     * @return ApprovalSummary with per-discount evaluations
     */
    public static ApprovalSummary evaluateDiscounts(Id costSheetId) {
        Cost_Sheet__c cs = queryCostSheet(costSheetId);
        return evaluateDiscounts(cs);
    }

    /**
     * @description Evaluate discounts on a pre-queried Cost Sheet record.
     *              Evaluation is viewer-independent: all users see the same
     *              status for the same Cost Sheet. Matrix rows are filtered
     *              only by Project, NOT by the current user's profile/role.
     */
    public static ApprovalSummary evaluateDiscounts(Cost_Sheet__c cs) {
        // Fetch all active matrix rows, ordered by field number then approval level
        List<Discount_Approval_Matrix__c> allMatrix = [
            SELECT Id, Discount_Field_Number__c, Discount_Label__c,
                   Min_Value__c, Max_Value__c, Min_Pct__c, Max_Pct__c,
                   Approval_Level__c, Approval_Threshold__c,
                   Approver_Role__c, Approver_User__c, Delegated_Approver__c,
                   Profile_Name__c, Role_Name__c, User__c, Project__c,
                   Is_Active__c, Escalation_Hours__c
            FROM Discount_Approval_Matrix__c
            WHERE Is_Active__c = true
            ORDER BY Discount_Field_Number__c ASC, Approval_Level__c ASC
        ];

        // Pre-resolve role-based approvers in a single query (for rows where Approver_User__c is null)
        Map<String, Id> roleToUserId = resolveApproversFromRoles(allMatrix);

        // Group matrix rows by discount field number
        Map<Integer, List<Discount_Approval_Matrix__c>> matrixByField =
            new Map<Integer, List<Discount_Approval_Matrix__c>>();
        for (Discount_Approval_Matrix__c row : allMatrix) {
            Integer fn = Integer.valueOf(row.Discount_Field_Number__c);
            if (!matrixByField.containsKey(fn)) {
                matrixByField.put(fn, new List<Discount_Approval_Matrix__c>());
            }
            matrixByField.get(fn).add(row);
        }

        // Build per-discount evaluations
        ApprovalSummary summary = new ApprovalSummary();
        summary.discounts = new List<DiscountEvaluation>();
        summary.highestLevel = 0;
        summary.requiresApproval = false;

        Decimal agreementValue = cs.Agreement_Value__c != null ? cs.Agreement_Value__c : 0;

        for (Integer i = 1; i <= MAX_DISCOUNT_FIELDS; i++) {
            Decimal discountVal = getDiscountValue(cs, i);
            String currentStatus = getDiscountStatus(cs, i);

            DiscountEvaluation eval = new DiscountEvaluation();
            eval.fieldNumber = i;
            eval.value = discountVal;
            eval.pct = agreementValue > 0
                       ? (discountVal / agreementValue * 100)
                       : 0;
            eval.exceedsLimit = false;
            eval.requiredLevel = 0;

            // If no value, mark N/A
            if (discountVal == null || discountVal == 0) {
                eval.status = 'N/A';
                eval.label = getLabelFromMatrix(matrixByField.get(i), i);
                summary.discounts.add(eval);
                continue;
            }

            // Find applicable matrix rows for this field
            // Only filter by Project — NOT by viewer's profile/role/user
            // Limits are objective: the same discount value produces the same evaluation for all viewers
            List<Discount_Approval_Matrix__c> fieldMatrix =
                filterMatrixByProject(matrixByField.get(i), cs.Project__c);

            if (fieldMatrix == null || fieldMatrix.isEmpty()) {
                // No matrix configured → auto approved
                eval.label = 'Discount ' + i;
                eval.status = 'Within Limit';
                summary.discounts.add(eval);
                continue;
            }

            eval.label = fieldMatrix[0].Discount_Label__c;

            // Determine required approval level
            Integer requiredLevel = determineApprovalLevel(
                fieldMatrix, discountVal, eval.pct
            );

            if (requiredLevel == 0) {
                // Within all limits
                eval.status = 'Within Limit';
                eval.maxAllowed = getMaxAllowed(fieldMatrix);
                eval.maxPctAllowed = getMaxPctAllowed(fieldMatrix);
            } else {
                eval.exceedsLimit = true;
                eval.requiredLevel = requiredLevel;
                eval.maxAllowed = getMaxAllowed(fieldMatrix);
                eval.maxPctAllowed = getMaxPctAllowed(fieldMatrix);

                // Preserve existing status if already approved/rejected
                if (currentStatus == 'Approved') {
                    eval.status = 'Approved';
                } else if (currentStatus == 'Rejected') {
                    eval.status = 'Rejected';
                } else {
                    eval.status = 'Pending Approval';
                    summary.requiresApproval = true;
                }

                // Find approver for required level
                // Priority: Approver_User__c (direct) > Approver_Role__c (role-based)
                for (Discount_Approval_Matrix__c row : fieldMatrix) {
                    if (Integer.valueOf(row.Approval_Level__c) == requiredLevel) {
                        if (row.Approver_User__c != null) {
                            eval.approverId = row.Approver_User__c;
                        } else if (String.isNotBlank(row.Approver_Role__c)
                                   && roleToUserId.containsKey(row.Approver_Role__c)) {
                            eval.approverId = roleToUserId.get(row.Approver_Role__c);
                        }
                        break;
                    }
                }

                if (requiredLevel > summary.highestLevel) {
                    summary.highestLevel = requiredLevel;
                }
            }

            summary.discounts.add(eval);
        }

        // Determine overall status
        summary.overallStatus = computeOverallStatus(summary.discounts);

        // Find next approver (the one for the highest required level)
        if (summary.highestLevel > 0) {
            for (DiscountEvaluation eval : summary.discounts) {
                if (eval.requiredLevel == summary.highestLevel && eval.approverId != null) {
                    summary.nextApproverId = eval.approverId;
                    break;
                }
            }
        }

        // Resolve approver names
        Set<Id> approverIds = new Set<Id>();
        for (DiscountEvaluation eval : summary.discounts) {
            if (eval.approverId != null) approverIds.add(eval.approverId);
        }
        if (summary.nextApproverId != null) approverIds.add(summary.nextApproverId);

        if (!approverIds.isEmpty()) {
            Map<Id, User> users = new Map<Id, User>(
                [SELECT Id, Name FROM User WHERE Id IN :approverIds]
            );
            for (DiscountEvaluation eval : summary.discounts) {
                if (eval.approverId != null && users.containsKey(eval.approverId)) {
                    eval.approverName = users.get(eval.approverId).Name;
                }
            }
            if (summary.nextApproverId != null && users.containsKey(summary.nextApproverId)) {
                summary.nextApproverName = users.get(summary.nextApproverId).Name;
            }
        }

        // ── Unit field validation ─────────────────────────────────
        // Check each discount value against its mapped unit field max
        summary.warnings = new List<String>();
        if (cs.Unit__c != null) {
            List<Map<String, Object>> configuredFields = getConfiguredDiscountFields(cs.Project__c);
            Set<String> unitFieldAPIs = new Set<String>();
            Map<Integer, String> fieldToUnitAPI = new Map<Integer, String>();
            for (Map<String, Object> cfg : configuredFields) {
                String api = (String) cfg.get('unitFieldAPI');
                if (String.isNotBlank(api)) {
                    Integer fn = (Integer) cfg.get('fieldNumber');
                    unitFieldAPIs.add(api);
                    fieldToUnitAPI.put(fn, api);
                }
            }

            if (!unitFieldAPIs.isEmpty()) {
                List<String> fieldList = new List<String>(unitFieldAPIs);
                fieldList.add('Id');
                Id unitId = cs.Unit__c;
                String unitQuery = 'SELECT ' + String.join(fieldList, ', ') + ' FROM Unit__c WHERE Id = :unitId';
                List<SObject> units = Database.query(unitQuery);

                if (!units.isEmpty()) {
                    SObject unit = units[0];
                    for (DiscountEvaluation eval : summary.discounts) {
                        String unitAPI = fieldToUnitAPI.get(eval.fieldNumber);
                        if (String.isBlank(unitAPI) || eval.value == null || eval.value == 0) continue;

                        Object unitFieldObj = unit.get(unitAPI);
                        if (unitFieldObj == null) continue;

                        Decimal unitFieldValue = (Decimal) unitFieldObj;
                        if (eval.value > unitFieldValue) {
                            summary.warnings.add(eval.label + ' (' + eval.value +
                                ') exceeds ' + unitAPI + ' value (' + unitFieldValue + ')');
                            eval.exceedsLimit = true;
                        }
                    }
                }
            }
        }

        return summary;
    }

    // ── Submit Cost Sheet discounts for approval ────────────────

    /**
     * @description Submit a Cost Sheet for discount approval.
     *              Evaluates all discounts, updates statuses, locks record,
     *              creates audit log entries, and notifies the approver.
     */
    public static ApprovalSummary submitForApproval(Id costSheetId, String comments) {
        ApprovalSummary summary = evaluateDiscounts(costSheetId);

        if (!summary.requiresApproval) {
            return summary;
        }

        // Fetch cost sheet name for notifications
        Cost_Sheet__c csForName = [SELECT Id, Name FROM Cost_Sheet__c WHERE Id = :costSheetId LIMIT 1];

        // ── Collect approver IDs BEFORE any DML ──────────────────
        Set<Id> approverIds = new Set<Id>();
        List<Integer> fieldsWithNoApprover = new List<Integer>();
        for (DiscountEvaluation eval : summary.discounts) {
            if (eval.exceedsLimit) {
                if (eval.approverId != null) {
                    approverIds.add(eval.approverId);
                } else {
                    fieldsWithNoApprover.add(eval.fieldNumber);
                }
            }
        }

        List<String> warnings = new List<String>();
        if (!fieldsWithNoApprover.isEmpty()) {
            warnings.add('No approver user assigned for discount field(s): '
                + String.join(fieldsWithNoApprover, ', ')
                + '. Please set Approver_User__c on the Discount Approval Matrix records for the required approval levels.');
        }

        // ── Perform DML operations first ────────────────────────────
        // Update Cost Sheet fields
        Cost_Sheet__c cs = new Cost_Sheet__c(Id = costSheetId);
        cs.Discount_Approval_Status__c = 'Pending';
        cs.Highest_Approval_Level__c = summary.highestLevel;
        cs.Next_Approver__c = summary.nextApproverId;
        cs.Is_Locked__c = true;
        cs.Approval_Submitted_Date__c = DateTime.now();

        for (DiscountEvaluation eval : summary.discounts) {
            setDiscountStatus(cs, eval.fieldNumber, eval.status);
        }
        update cs;

        // Create audit log entries
        List<Discount_Approval_Log__c> logs = new List<Discount_Approval_Log__c>();
        for (DiscountEvaluation eval : summary.discounts) {
            if (eval.exceedsLimit) {
                logs.add(new Discount_Approval_Log__c(
                    Cost_Sheet__c = costSheetId,
                    Discount_Field_Number__c = eval.fieldNumber,
                    Discount_Label__c = eval.label,
                    Discount_Value__c = eval.value,
                    Action__c = 'Submitted',
                    Approval_Level__c = eval.requiredLevel,
                    Approver__c = eval.approverId,
                    Comments__c = comments,
                    Timestamp__c = DateTime.now()
                ));
            }
        }
        if (!logs.isEmpty()) {
            insert logs;
        }

        // ── Send ALL notifications AFTER DML via Queueable ──────
        // Bell notifications fail silently when the target record has
        // uncommitted DML in the same transaction. Enqueuing ensures
        // the notification fires after the transaction commits.
        if (!approverIds.isEmpty()) {
            // Direct bell notification (reliable, same mechanism as resend)
            String bellResult = sendBellNotification(
                costSheetId,
                'Discount Approval Required',
                UserInfo.getName() + ' submitted ' + csForName.Name + ' for discount approval. Please review.',
                approverIds
            );
            if (bellResult != null) {
                warnings.add('BELL: ' + bellResult);
            }
            // Queueable for tasks and emails (post-commit)
            System.enqueueJob(new DiscountNotificationQueueable(
                costSheetId, csForName.Name, approverIds, comments,
                'Discount Approval Required',
                UserInfo.getName() + ' submitted ' + csForName.Name + ' for discount approval. Please review.'
            ));
            warnings.add('Bell notification sent to ' + approverIds.size() + ' approver(s). Tasks/emails queued.');
        } else if (fieldsWithNoApprover.isEmpty()) {
            warnings.add('No discounts exceeded limits, so no notifications were sent.');
        }
        summary.warnings = warnings;

        return summary;
    }

    // ── Approve / Reject a specific discount ────────────────────

    /**
     * @description Approve a specific discount on a Cost Sheet
     */
    public static void approveDiscount(Id costSheetId, Integer fieldNumber, String comments) {
        processApprovalAction(costSheetId, fieldNumber, 'Approved', comments);
    }

    /**
     * @description Reject a specific discount on a Cost Sheet
     */
    public static void rejectDiscount(Id costSheetId, Integer fieldNumber, String comments) {
        processApprovalAction(costSheetId, fieldNumber, 'Rejected', comments);
    }

    /**
     * @description Recall (cancel) a pending approval submission
     */
    public static void recallApproval(Id costSheetId) {
        Cost_Sheet__c cs = new Cost_Sheet__c(Id = costSheetId);
        cs.Discount_Approval_Status__c = 'Not Required';
        cs.Is_Locked__c = false;
        cs.Next_Approver__c = null;

        for (Integer i = 1; i <= MAX_DISCOUNT_FIELDS; i++) {
            setDiscountStatus(cs, i, 'N/A');
        }
        update cs;

        // Log recall
        insert new Discount_Approval_Log__c(
            Cost_Sheet__c = costSheetId,
            Discount_Field_Number__c = 0,
            Discount_Label__c = 'All Discounts',
            Action__c = 'Recalled',
            Approver__c = UserInfo.getUserId(),
            Comments__c = 'Approval recalled',
            Timestamp__c = DateTime.now()
        );
    }

    // ── Get approval history ────────────────────────────────────

    /**
     * @description Get the approval audit trail for a Cost Sheet
     */
    public static List<Discount_Approval_Log__c> getApprovalHistory(Id costSheetId) {
        return [
            SELECT Id, Name, Discount_Field_Number__c, Discount_Label__c,
                   Discount_Value__c, Action__c, Approval_Level__c,
                   Approver__c, Approver__r.Name, Comments__c, Timestamp__c
            FROM Discount_Approval_Log__c
            WHERE Cost_Sheet__c = :costSheetId
            ORDER BY Timestamp__c DESC
        ];
    }

    // ── Resend notifications for pending approvals ─────────────

    /**
     * @description Resend bell notifications to all pending approvers for a Cost Sheet.
     *              Useful for debugging or when original notification didn't arrive.
     * @return List of diagnostic messages (empty = all succeeded)
     */
    public static List<String> resendApproverNotifications(Id costSheetId) {
        List<String> diagnostics = new List<String>();

        // Re-evaluate to find current approvers
        ApprovalSummary summary = evaluateDiscounts(costSheetId);
        Cost_Sheet__c csForName = [SELECT Id, Name FROM Cost_Sheet__c WHERE Id = :costSheetId LIMIT 1];

        Set<Id> approverIds = new Set<Id>();
        List<Integer> fieldsWithNoApprover = new List<Integer>();
        for (DiscountEvaluation eval : summary.discounts) {
            if (eval.exceedsLimit && (eval.status == 'Pending Approval')) {
                if (eval.approverId != null) {
                    approverIds.add(eval.approverId);
                    diagnostics.add('Discount ' + eval.fieldNumber + ' (' + eval.label
                        + '): approver = ' + eval.approverName + ' (' + eval.approverId + ')');
                } else {
                    fieldsWithNoApprover.add(eval.fieldNumber);
                }
            }
        }

        if (!fieldsWithNoApprover.isEmpty()) {
            diagnostics.add('WARNING: No Approver_User__c set on matrix for discount field(s): '
                + String.join(fieldsWithNoApprover, ', '));
        }

        if (approverIds.isEmpty()) {
            diagnostics.add('No pending approvers found to notify. Ensure Discount Approval Matrix '
                + 'records have Approver_User__c populated for the required approval levels.');
            return diagnostics;
        }

        // Send bell notification only (user said no email focus)
        String bellResult = sendBellNotification(
            costSheetId,
            'Discount Approval Required',
            UserInfo.getName() + ' submitted ' + csForName.Name + ' for discount approval. Please review.',
            approverIds
        );
        if (bellResult != null) {
            diagnostics.add('BELL: ' + bellResult);
        } else {
            diagnostics.add('Bell notification sent successfully to ' + approverIds.size() + ' approver(s).');
        }

        return diagnostics;
    }

    // ── Get discount labels from matrix config ──────────────────

    /**
     * @description Get configured discount labels (for UI display)
     */
    public static Map<Integer, String> getDiscountLabels(Id projectId) {
        Map<Integer, String> labels = new Map<Integer, String>();
        List<Discount_Approval_Matrix__c> rows = [
            SELECT Discount_Field_Number__c, Discount_Label__c, Project__c
            FROM Discount_Approval_Matrix__c
            WHERE Is_Active__c = true
            ORDER BY Discount_Field_Number__c ASC, Approval_Level__c ASC
        ];
        List<Discount_Approval_Matrix__c> filtered = filterMatrixByProject(rows, projectId);
        for (Discount_Approval_Matrix__c row : filtered) {
            Integer fn = Integer.valueOf(row.Discount_Field_Number__c);
            if (!labels.containsKey(fn)) {
                labels.put(fn, row.Discount_Label__c);
            }
        }
        return labels;
    }

    /**
     * @description Get configured discount fields with their labels and unit field mappings.
     *              Only returns field numbers that have active matrix rows.
     *              Used by newCostSheet LWC to dynamically show only configured discount fields.
     */
    public static List<Map<String, Object>> getConfiguredDiscountFields(Id projectId) {
        List<Map<String, Object>> fields = new List<Map<String, Object>>();
        Set<Integer> seen = new Set<Integer>();
        List<Discount_Approval_Matrix__c> rows = [
            SELECT Discount_Field_Number__c, Discount_Label__c, Unit_Field_API__c, Project__c
            FROM Discount_Approval_Matrix__c
            WHERE Is_Active__c = true
            ORDER BY Discount_Field_Number__c ASC, Approval_Level__c ASC
        ];
        List<Discount_Approval_Matrix__c> filtered = filterMatrixByProject(rows, projectId);
        for (Discount_Approval_Matrix__c row : filtered) {
            Integer fn = Integer.valueOf(row.Discount_Field_Number__c);
            if (!seen.contains(fn)) {
                seen.add(fn);
                Map<String, Object> m = new Map<String, Object>();
                m.put('fieldNumber', fn);
                m.put('label', row.Discount_Label__c);
                m.put('unitFieldAPI', row.Unit_Field_API__c);
                fields.add(m);
            }
        }
        return fields;
    }

    /**
     * @description Preview discount approval requirements before saving a Cost Sheet.
     *              Evaluates discount values against the matrix to determine if approval
     *              is needed and who the approver will be — without requiring a saved record.
     * @param projectId The Project Id for matrix filtering
     * @param discountsJson JSON array of [{fieldNumber, value}]
     * @param agreementValue The agreement value for percentage calculations
     * @return ApprovalSummary with requiresApproval, nextApproverName, highestLevel
     */
    public static ApprovalSummary previewDiscountApproval(
        Id projectId, String discountsJson, Decimal agreementValue
    ) {
        // Parse discount inputs
        List<Object> rawList = (List<Object>) JSON.deserializeUntyped(discountsJson);
        Map<Integer, Decimal> discountsByField = new Map<Integer, Decimal>();
        for (Object item : rawList) {
            Map<String, Object> d = (Map<String, Object>) item;
            Integer fn = Integer.valueOf(String.valueOf(d.get('fieldNumber')));
            Decimal val = d.get('value') != null ? Decimal.valueOf(String.valueOf(d.get('value'))) : 0;
            if (val > 0) {
                discountsByField.put(fn, val);
            }
        }

        // Fetch all active matrix rows
        List<Discount_Approval_Matrix__c> allMatrix = [
            SELECT Id, Discount_Field_Number__c, Discount_Label__c,
                   Min_Value__c, Max_Value__c, Min_Pct__c, Max_Pct__c,
                   Approval_Level__c, Approval_Threshold__c,
                   Approver_Role__c, Approver_User__c, Project__c
            FROM Discount_Approval_Matrix__c
            WHERE Is_Active__c = true
            ORDER BY Discount_Field_Number__c ASC, Approval_Level__c ASC
        ];

        Map<String, Id> roleToUserId = resolveApproversFromRoles(allMatrix);

        // Group by field number
        Map<Integer, List<Discount_Approval_Matrix__c>> matrixByField =
            new Map<Integer, List<Discount_Approval_Matrix__c>>();
        for (Discount_Approval_Matrix__c row : allMatrix) {
            Integer fn = Integer.valueOf(row.Discount_Field_Number__c);
            if (!matrixByField.containsKey(fn)) {
                matrixByField.put(fn, new List<Discount_Approval_Matrix__c>());
            }
            matrixByField.get(fn).add(row);
        }

        Decimal safeAgreement = agreementValue != null ? agreementValue : 0;

        ApprovalSummary summary = new ApprovalSummary();
        summary.discounts = new List<DiscountEvaluation>();
        summary.highestLevel = 0;
        summary.requiresApproval = false;
        summary.warnings = new List<String>();

        for (Integer fn : discountsByField.keySet()) {
            Decimal discountVal = discountsByField.get(fn);
            Decimal discountPct = safeAgreement > 0 ? (discountVal / safeAgreement * 100) : 0;

            List<Discount_Approval_Matrix__c> fieldMatrix =
                filterMatrixByProject(matrixByField.get(fn), projectId);

            if (fieldMatrix == null || fieldMatrix.isEmpty()) continue;

            Integer requiredLevel = determineApprovalLevel(fieldMatrix, discountVal, discountPct);
            if (requiredLevel == 0) continue;

            summary.requiresApproval = true;
            DiscountEvaluation eval = new DiscountEvaluation();
            eval.fieldNumber = fn;
            eval.label = fieldMatrix[0].Discount_Label__c;
            eval.value = discountVal;
            eval.requiredLevel = requiredLevel;
            eval.exceedsLimit = true;
            eval.status = 'Pending Approval';

            // Resolve approver
            for (Discount_Approval_Matrix__c row : fieldMatrix) {
                if (Integer.valueOf(row.Approval_Level__c) == requiredLevel) {
                    if (row.Approver_User__c != null) {
                        eval.approverId = row.Approver_User__c;
                    } else if (String.isNotBlank(row.Approver_Role__c)
                               && roleToUserId.containsKey(row.Approver_Role__c)) {
                        eval.approverId = roleToUserId.get(row.Approver_Role__c);
                    }
                    break;
                }
            }

            if (requiredLevel > summary.highestLevel) {
                summary.highestLevel = requiredLevel;
                summary.nextApproverId = eval.approverId;
            }

            summary.discounts.add(eval);
        }

        // Resolve approver names
        Set<Id> approverIds = new Set<Id>();
        for (DiscountEvaluation eval : summary.discounts) {
            if (eval.approverId != null) approverIds.add(eval.approverId);
        }
        if (summary.nextApproverId != null) approverIds.add(summary.nextApproverId);

        if (!approverIds.isEmpty()) {
            Map<Id, User> users = new Map<Id, User>(
                [SELECT Id, Name FROM User WHERE Id IN :approverIds]
            );
            for (DiscountEvaluation eval : summary.discounts) {
                if (eval.approverId != null && users.containsKey(eval.approverId)) {
                    eval.approverName = users.get(eval.approverId).Name;
                }
            }
            if (summary.nextApproverId != null && users.containsKey(summary.nextApproverId)) {
                summary.nextApproverName = users.get(summary.nextApproverId).Name;
            }
        }

        return summary;
    }

    /**
     * @description Validate discount values against their mapped unit field values.
     *              Returns a map of fieldNumber -> error message for any violations.
     */
    public static Map<Integer, String> validateDiscountsAgainstUnit(Id costSheetId) {
        Map<Integer, String> errors = new Map<Integer, String>();
        Cost_Sheet__c cs = queryCostSheet(costSheetId);
        if (cs.Unit__c == null) return errors;

        // Get configured unit field mappings
        List<Map<String, Object>> configuredFields = getConfiguredDiscountFields(cs.Project__c);
        Set<String> unitFieldAPIs = new Set<String>();
        for (Map<String, Object> cfg : configuredFields) {
            String api = (String) cfg.get('unitFieldAPI');
            if (String.isNotBlank(api)) {
                unitFieldAPIs.add(api);
            }
        }
        if (unitFieldAPIs.isEmpty()) return errors;

        // Dynamic query for unit field values
        List<String> fieldList = new List<String>(unitFieldAPIs);
        fieldList.add('Id');
        String query = 'SELECT ' + String.join(fieldList, ', ') + ' FROM Unit__c WHERE Id = :unitId';
        Id unitId = cs.Unit__c;
        List<SObject> units = Database.query(query);
        if (units.isEmpty()) return errors;
        SObject unit = units[0];

        // Validate each discount against its mapped unit field
        for (Map<String, Object> cfg : configuredFields) {
            Integer fn = (Integer) cfg.get('fieldNumber');
            String unitFieldAPI = (String) cfg.get('unitFieldAPI');
            if (String.isBlank(unitFieldAPI)) continue;

            Decimal discountVal = getDiscountValue(cs, fn);
            if (discountVal == null || discountVal == 0) continue;

            Object unitFieldObj = unit.get(unitFieldAPI);
            if (unitFieldObj == null) continue;

            Decimal unitFieldValue = (Decimal) unitFieldObj;
            if (discountVal > unitFieldValue) {
                String label = (String) cfg.get('label');
                errors.put(fn, label + ' value (' + discountVal +
                    ') exceeds ' + unitFieldAPI + ' (' + unitFieldValue + ')');
            }
        }
        return errors;
    }

    // ════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ════════════════════════════════════════════════════════════

    private static void processApprovalAction(
        Id costSheetId, Integer fieldNumber, String action, String comments
    ) {
        Cost_Sheet__c cs = queryCostSheet(costSheetId);

        // Security: verify current user is the assigned approver or a delegate
        validateApprover(cs, fieldNumber);

        // Update the specific discount status
        setDiscountStatus(cs, fieldNumber, action);

        // Log the action
        insert new Discount_Approval_Log__c(
            Cost_Sheet__c = costSheetId,
            Discount_Field_Number__c = fieldNumber,
            Discount_Label__c = 'Discount ' + fieldNumber,
            Discount_Value__c = getDiscountValue(cs, fieldNumber),
            Action__c = action,
            Approver__c = UserInfo.getUserId(),
            Comments__c = comments,
            Timestamp__c = DateTime.now()
        );

        // Recompute overall status
        String overallStatus = computeOverallStatusFromRecord(cs, fieldNumber, action);
        cs.Discount_Approval_Status__c = overallStatus;

        if (overallStatus == 'Approved') {
            cs.Is_Locked__c = false;
            cs.Next_Approver__c = null;
            cs.Approved_By__c = UserInfo.getUserId();
            cs.Approval_Date__c = DateTime.now();
            if (String.isNotBlank(comments)) {
                cs.Approval_Comments__c = comments;
            }
        } else if (overallStatus == 'Rejected') {
            cs.Is_Locked__c = false;
            cs.Next_Approver__c = null;
        }

        update cs;

        // ── Notify the submitter and owner about the outcome ────
        // Only send notification when overall status reaches a terminal state
        if (overallStatus == 'Approved' || overallStatus == 'Rejected') {
            Set<Id> outcomeRecipients = new Set<Id>();
            if (cs.CreatedById != null) outcomeRecipients.add(cs.CreatedById);
            if (cs.Created_By__c != null) outcomeRecipients.add(cs.Created_By__c);
            sendOutcomeNotification(costSheetId, cs.Name, outcomeRecipients, overallStatus);
        }
    }

    private static void validateApprover(Cost_Sheet__c cs, Integer fieldNumber) {
        Id currentUserId = UserInfo.getUserId();

        // Check if user is the next approver
        if (cs.Next_Approver__c == currentUserId) {
            return;
        }

        // Check if user is a delegated approver in the matrix
        List<Discount_Approval_Matrix__c> delegateRows = [
            SELECT Id FROM Discount_Approval_Matrix__c
            WHERE Discount_Field_Number__c = :fieldNumber
            AND Delegated_Approver__c = :currentUserId
            AND Is_Active__c = true
            LIMIT 1
        ];
        if (!delegateRows.isEmpty()) {
            return;
        }

        // Check if user is the approver for this field's level
        List<Discount_Approval_Matrix__c> approverRows = [
            SELECT Id FROM Discount_Approval_Matrix__c
            WHERE Discount_Field_Number__c = :fieldNumber
            AND Approver_User__c = :currentUserId
            AND Is_Active__c = true
            LIMIT 1
        ];
        if (!approverRows.isEmpty()) {
            return;
        }

        // Check if user's role matches Approver_Role__c on the matrix
        String currentRoleName = null;
        List<User> currentUsers = [SELECT UserRole.Name FROM User WHERE Id = :currentUserId LIMIT 1];
        if (!currentUsers.isEmpty() && currentUsers[0].UserRole != null) {
            currentRoleName = currentUsers[0].UserRole.Name;
        }
        if (String.isNotBlank(currentRoleName)) {
            List<Discount_Approval_Matrix__c> roleRows = [
                SELECT Id FROM Discount_Approval_Matrix__c
                WHERE Discount_Field_Number__c = :fieldNumber
                AND Approver_Role__c = :currentRoleName
                AND Is_Active__c = true
                LIMIT 1
            ];
            if (!roleRows.isEmpty()) {
                return;
            }
        }

        throw new AuraHandledException(
            'You are not authorized to approve/reject this discount.'
        );
    }

    private static String computeOverallStatus(List<DiscountEvaluation> discounts) {
        Boolean hasPending = false;
        Boolean hasApproved = false;
        Boolean hasRejected = false;
        Boolean hasExceeding = false;

        for (DiscountEvaluation eval : discounts) {
            if (eval.status == 'Pending Approval') { hasPending = true; hasExceeding = true; }
            if (eval.status == 'Approved' && eval.exceedsLimit) { hasApproved = true; hasExceeding = true; }
            if (eval.status == 'Rejected') { hasRejected = true; hasExceeding = true; }
        }

        if (!hasExceeding) return 'Not Required';
        if (hasRejected) return 'Rejected';
        if (hasPending && hasApproved) return 'Partially Approved';
        if (hasPending) return 'Pending';
        if (hasApproved) return 'Approved';
        return 'Not Required';
    }

    private static String computeOverallStatusFromRecord(
        Cost_Sheet__c cs, Integer justActedField, String justActedStatus
    ) {
        Boolean hasPending = false;
        Boolean hasApproved = false;
        Boolean hasRejected = false;
        Boolean hasAny = false;

        for (Integer i = 1; i <= MAX_DISCOUNT_FIELDS; i++) {
            String status = (i == justActedField)
                            ? justActedStatus
                            : getDiscountStatus(cs, i);
            if (status == 'Pending Approval') { hasPending = true; hasAny = true; }
            if (status == 'Approved') { hasApproved = true; hasAny = true; }
            if (status == 'Rejected') { hasRejected = true; hasAny = true; }
        }

        if (!hasAny) return 'Not Required';
        if (hasRejected) return 'Rejected';
        if (hasPending && hasApproved) return 'Partially Approved';
        if (hasPending) return 'Pending';
        if (hasApproved) return 'Approved';
        return 'Not Required';
    }

    /**
     * @description Filter matrix rows by Project only.
     *              Evaluation is viewer-independent — limits are objective.
     *              Profile/Role/User on the matrix row determines WHO approves,
     *              not WHAT the limits are.
     */
    private static List<Discount_Approval_Matrix__c> filterMatrixByProject(
        List<Discount_Approval_Matrix__c> rows, Id projectId
    ) {
        if (rows == null || rows.isEmpty()) return rows;

        List<Discount_Approval_Matrix__c> filtered = new List<Discount_Approval_Matrix__c>();

        for (Discount_Approval_Matrix__c row : rows) {
            // Project filter: skip rows tied to a different project
            if (row.Project__c != null && row.Project__c != projectId) continue;
            filtered.add(row);
        }

        return filtered;
    }

    /**
     * @description Determine the required approval level for a discount value.
     *              Returns 0 if within all limits (no approval needed).
     *              Returns the highest matching approval level otherwise.
     */
    private static Integer determineApprovalLevel(
        List<Discount_Approval_Matrix__c> matrixRows, Decimal discountVal, Decimal discountPct
    ) {
        Integer requiredLevel = 0;

        for (Discount_Approval_Matrix__c row : matrixRows) {
            Boolean exceeds = false;

            // Check value-based limits
            if (row.Max_Value__c != null && discountVal > row.Max_Value__c) {
                exceeds = true;
            }

            // Check percentage-based limits
            if (row.Max_Pct__c != null && discountPct > row.Max_Pct__c) {
                exceeds = true;
            }

            // Check threshold
            if (row.Approval_Threshold__c != null && discountVal > row.Approval_Threshold__c) {
                exceeds = true;
            }

            if (exceeds) {
                Integer level = Integer.valueOf(row.Approval_Level__c);
                if (level > requiredLevel) {
                    requiredLevel = level;
                }
            }
        }

        return requiredLevel;
    }

    private static Decimal getMaxAllowed(List<Discount_Approval_Matrix__c> rows) {
        Decimal maxVal = null;
        for (Discount_Approval_Matrix__c row : rows) {
            if (row.Max_Value__c != null) {
                if (maxVal == null || row.Max_Value__c > maxVal) {
                    maxVal = row.Max_Value__c;
                }
            }
        }
        return maxVal;
    }

    private static Decimal getMaxPctAllowed(List<Discount_Approval_Matrix__c> rows) {
        Decimal maxPct = null;
        for (Discount_Approval_Matrix__c row : rows) {
            if (row.Max_Pct__c != null) {
                if (maxPct == null || row.Max_Pct__c > maxPct) {
                    maxPct = row.Max_Pct__c;
                }
            }
        }
        return maxPct;
    }

    private static String getLabelFromMatrix(
        List<Discount_Approval_Matrix__c> rows, Integer fieldNumber
    ) {
        if (rows != null && !rows.isEmpty()) {
            return rows[0].Discount_Label__c;
        }
        return 'Discount ' + fieldNumber;
    }

    // ── Role-based approver resolution ─────────────────────────

    /**
     * @description Bulk-resolve role names to User IDs.
     *              For matrix rows where Approver_User__c is null but Approver_Role__c is set,
     *              finds the first active User matching each role name.
     * @return Map of role name to User ID
     */
    private static Map<String, Id> resolveApproversFromRoles(
        List<Discount_Approval_Matrix__c> matrixRows
    ) {
        Set<String> roleNames = new Set<String>();
        for (Discount_Approval_Matrix__c row : matrixRows) {
            if (row.Approver_User__c == null && String.isNotBlank(row.Approver_Role__c)) {
                roleNames.add(row.Approver_Role__c);
            }
        }

        Map<String, Id> roleToUserId = new Map<String, Id>();
        if (!roleNames.isEmpty()) {
            for (User u : [
                SELECT Id, UserRole.Name FROM User
                WHERE UserRole.Name IN :roleNames
                AND IsActive = true
                ORDER BY UserRole.Name ASC, CreatedDate ASC
            ]) {
                String rn = u.UserRole.Name;
                if (!roleToUserId.containsKey(rn)) {
                    roleToUserId.put(rn, u.Id);
                }
            }
        }
        return roleToUserId;
    }

    // ── Dynamic field access helpers ────────────────────────────

    private static Decimal getDiscountValue(Cost_Sheet__c cs, Integer fieldNumber) {
        String fieldName = 'Discount_' + fieldNumber + '__c';
        Object val = cs.get(fieldName);
        return val != null ? (Decimal) val : 0;
    }

    private static String getDiscountStatus(Cost_Sheet__c cs, Integer fieldNumber) {
        String fieldName = NamespaceUtil.qualify('Discount_' + fieldNumber + '_Status__c');
        Object val = cs.get(fieldName);
        return val != null ? String.valueOf(val) : 'N/A';
    }

    private static void setDiscountStatus(Cost_Sheet__c cs, Integer fieldNumber, String status) {
        String fieldName = NamespaceUtil.qualify('Discount_' + fieldNumber + '_Status__c');
        cs.put(fieldName, status);
    }

    private static Cost_Sheet__c queryCostSheet(Id costSheetId) {
        return [
            SELECT Id, Name, Project__c, Agreement_Value__c, Status__c,
                   CreatedById, Created_By__c, Unit__c,
                   Super_Builtup_Area__c,
                   Discount_1__c, Discount_2__c, Discount_3__c,
                   Discount_4__c, Discount_5__c, Discount_6__c,
                   Discount_1_Status__c, Discount_2_Status__c, Discount_3_Status__c,
                   Discount_4_Status__c, Discount_5_Status__c, Discount_6_Status__c,
                   Discount_Approval_Status__c, Highest_Approval_Level__c,
                   Next_Approver__c, Is_Locked__c, Approval_Submitted_Date__c,
                   Approved_By__c, Approval_Date__c, Approval_Comments__c
            FROM Cost_Sheet__c
            WHERE Id = :costSheetId
            LIMIT 1
        ];
    }

    // ════════════════════════════════════════════════════════════
    // NOTIFICATIONS
    // ════════════════════════════════════════════════════════════

    /**
     * @description Notify the submitter and owner about the approval/rejection outcome.
     *              Sends via Queueable so bell notification fires after transaction commits.
     */
    private static void sendOutcomeNotification(
        Id costSheetId, String costSheetName, Set<Id> recipientIds, String action
    ) {
        if (recipientIds == null || recipientIds.isEmpty()) return;

        String approverName = UserInfo.getName();
        String actionLabel = action == 'Approved' ? 'approved' : 'rejected';
        String bellTitle = 'Discount ' + action;
        String bellBody = approverName + ' has ' + actionLabel + ' discount on ' + costSheetName + '.';

        // Direct bell notification (primary - reliable)
        sendBellNotification(costSheetId, bellTitle, bellBody, recipientIds);

        // Queueable for tasks and emails (post-commit)
        System.enqueueJob(new DiscountNotificationQueueable(
            costSheetId, costSheetName, recipientIds, null,
            bellTitle, bellBody
        ));

        // Email to recipients
        try {
            List<User> recipients = [SELECT Id, Email, Name FROM User WHERE Id IN :recipientIds AND Email != null];
            if (!recipients.isEmpty()) {
                List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
                for (User recipient : recipients) {
                    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    email.setToAddresses(new List<String>{ recipient.Email });
                    email.setSubject('Discount ' + action + ': ' + costSheetName);
                    email.setPlainTextBody(
                        'Dear ' + recipient.Name + ',\n\n'
                        + 'The discount on Cost Sheet ' + costSheetName + ' has been ' + actionLabel + ' by ' + approverName + '.\n\n'
                        + 'Please log in to Salesforce to view the details.\n\n'
                        + 'Regards,\nDiscount Approval System'
                    );
                    email.setSaveAsActivity(false);
                    emails.add(email);
                }
                Messaging.sendEmail(emails);
            }
        } catch (Exception e) {
            System.debug('Outcome email error: ' + e.getMessage());
        }
    }

    /**
     * @description Send bell notification using Custom Notification Type.
     *              Tries: Discount_Approval_Notification → Approval_Notification → any available type.
     *              Returns null on success, warning string on failure.
     */
    private static String sendBellNotification(Id targetId, String title, String body, Set<Id> recipientIds) {
        if (recipientIds == null || recipientIds.isEmpty()) return 'Bell notification skipped: no recipient IDs provided.';

        try {
            // Try specific notification type first
            List<CustomNotificationType> notifTypes = [
                SELECT Id, DeveloperName FROM CustomNotificationType
                WHERE DeveloperName = 'Discount_Approval_Notification'
                LIMIT 1
            ];

            // Fallback to Approval_Notification
            if (notifTypes.isEmpty()) {
                notifTypes = [
                    SELECT Id, DeveloperName FROM CustomNotificationType
                    WHERE DeveloperName = 'Approval_Notification'
                    LIMIT 1
                ];
            }

            // Last resort: use any available custom notification type
            if (notifTypes.isEmpty()) {
                notifTypes = [
                    SELECT Id, DeveloperName FROM CustomNotificationType
                    LIMIT 1
                ];
            }

            if (notifTypes.isEmpty()) {
                return 'Bell notification skipped: No Custom Notification Types exist in this org. '
                     + 'Go to Setup > Notification Types > New, create "Discount_Approval_Notification" '
                     + 'with Desktop and Mobile enabled.';
            }

            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(title);
            notification.setBody(body);
            notification.setNotificationTypeId(notifTypes[0].Id);
            notification.setTargetId(targetId);

            Set<String> recipientStrings = new Set<String>();
            for (Id uid : recipientIds) {
                recipientStrings.add(String.valueOf(uid));
            }
            notification.send(recipientStrings);
            return null; // Success
        } catch (Exception e) {
            return 'Bell notification failed for recipients '
                 + recipientIds + ': ' + e.getMessage()
                 + '. Ensure the Custom Notification Type exists and recipients are active users.';
        }
    }

}