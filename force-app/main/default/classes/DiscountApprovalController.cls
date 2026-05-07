/**
 * @description LWC Controller for the Discount Approval Panel.
 *              Exposes the DiscountApprovalEngine methods to Lightning components.
 */
public with sharing class DiscountApprovalController {

    /**
     * @description Evaluate all discounts on a Cost Sheet and return the approval summary
     */
    @AuraEnabled
    public static DiscountApprovalEngine.ApprovalSummary evaluateDiscounts(Id costSheetId) {
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet ID is required.');
        }
        try {
            return DiscountApprovalEngine.evaluateDiscounts(costSheetId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Submit a Cost Sheet's discounts for approval
     */
    @AuraEnabled
    public static DiscountApprovalEngine.ApprovalSummary submitForApproval(
        Id costSheetId, String comments
    ) {
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet ID is required.');
        }
        try {
            return DiscountApprovalEngine.submitForApproval(costSheetId, comments);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Approve a specific discount field
     */
    @AuraEnabled
    public static void approveDiscount(
        Id costSheetId, Integer fieldNumber, String comments
    ) {
        if (costSheetId == null || fieldNumber == null) {
            throw new AuraHandledException('Cost Sheet ID and field number are required.');
        }
        try {
            DiscountApprovalEngine.approveDiscount(costSheetId, fieldNumber, comments);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Reject a specific discount field
     */
    @AuraEnabled
    public static void rejectDiscount(
        Id costSheetId, Integer fieldNumber, String comments
    ) {
        if (costSheetId == null || fieldNumber == null) {
            throw new AuraHandledException('Cost Sheet ID and field number are required.');
        }
        try {
            DiscountApprovalEngine.rejectDiscount(costSheetId, fieldNumber, comments);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Recall a pending approval
     */
    @AuraEnabled
    public static void recallApproval(Id costSheetId) {
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet ID is required.');
        }
        try {
            DiscountApprovalEngine.recallApproval(costSheetId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Get approval audit trail
     */
    @AuraEnabled
    public static List<Map<String, Object>> getApprovalHistory(Id costSheetId) {
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet ID is required.');
        }
        try {
            List<Discount_Approval_Log__c> logs =
                DiscountApprovalEngine.getApprovalHistory(costSheetId);

            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for (Discount_Approval_Log__c log : logs) {
                Map<String, Object> row = new Map<String, Object>();
                row.put('id', log.Id);
                row.put('logNumber', log.Name);
                row.put('fieldNumber', log.Discount_Field_Number__c);
                row.put('label', log.Discount_Label__c);
                row.put('value', log.Discount_Value__c);
                row.put('action', log.Action__c);
                row.put('level', log.Approval_Level__c);
                row.put('approverId', log.Approver__c);
                row.put('approverName', log.Approver__r != null ? log.Approver__r.Name : '');
                row.put('comments', log.Comments__c);
                row.put('timestamp', log.Timestamp__c);
                result.add(row);
            }
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Get configured discount labels for display in the Cost Sheet form
     */
    @AuraEnabled(cacheable=true)
    public static Map<Integer, String> getDiscountLabels(Id projectId) {
        try {
            return DiscountApprovalEngine.getDiscountLabels(projectId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Resend bell notification to pending approvers.
     *              Returns list of warnings/diagnostics (empty if all notifications succeeded).
     */
    @AuraEnabled
    public static List<String> resendNotification(Id costSheetId) {
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet ID is required.');
        }
        try {
            return DiscountApprovalEngine.resendApproverNotifications(costSheetId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Preview discount approval requirements before saving a Cost Sheet.
     *              Returns approval summary with approver name for UI toast.
     */
    @AuraEnabled
    public static DiscountApprovalEngine.ApprovalSummary previewDiscountApproval(
        Id projectId, String discountsJson, Decimal agreementValue
    ) {
        if (String.isBlank(discountsJson)) {
            throw new AuraHandledException('Discount values are required.');
        }
        try {
            return DiscountApprovalEngine.previewDiscountApproval(projectId, discountsJson, agreementValue);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Get configured discount fields with labels and unit field mappings.
     *              Only returns field numbers that have active matrix rows.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getConfiguredDiscountFields(Id projectId) {
        try {
            return DiscountApprovalEngine.getConfiguredDiscountFields(projectId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Get numeric fields from Unit__c for the Unit Field API picklist
     *              in the Discount Approval Matrix form.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getUnitNumericFields() {
        List<Map<String, String>> fields = new List<Map<String, String>>();
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Unit__c.fields.getMap();
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
            if (dfr.getType() == Schema.DisplayType.CURRENCY ||
                dfr.getType() == Schema.DisplayType.DOUBLE ||
                dfr.getType() == Schema.DisplayType.PERCENT ||
                dfr.getType() == Schema.DisplayType.INTEGER) {
                fields.add(new Map<String, String>{
                    'label' => dfr.getLabel() + ' (' + dfr.getName() + ')',
                    'value' => dfr.getName()
                });
            }
        }
        return fields;
    }

    /**
     * @description Get existing Discount_Field_Number values to enforce the 6-record limit.
     *              Returns which field numbers (1-6) are already taken.
     */
    @AuraEnabled
    public static Map<String, Object> getExistingFieldNumbers() {
        List<Integer> used = new List<Integer>();
        for (Discount_Approval_Matrix__c row : [
            SELECT Discount_Field_Number__c FROM Discount_Approval_Matrix__c
        ]) {
            Integer fn = Integer.valueOf(row.Discount_Field_Number__c);
            if (!used.contains(fn)) {
                used.add(fn);
            }
        }
        used.sort();
        List<Integer> available = new List<Integer>();
        for (Integer i = 1; i <= 6; i++) {
            if (!used.contains(i)) {
                available.add(i);
            }
        }
        Map<String, Object> result = new Map<String, Object>();
        result.put('usedFieldNumbers', used);
        result.put('availableFieldNumbers', available);
        result.put('count', used.size());
        result.put('isFull', used.size() >= 6);
        return result;
    }
}