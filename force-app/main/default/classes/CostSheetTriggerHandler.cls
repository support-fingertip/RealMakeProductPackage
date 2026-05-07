/**
 * @description Trigger handler for Cost_Sheet__c.
 *              Enforces a full edit lock while discount approval is pending.
 *              Users cannot modify ANY cost sheet fields until approvals are
 *              resolved. Only the approval engine's own fields are exempted.
 */
public with sharing class CostSheetTriggerHandler {

    private static final Integer MAX_DISCOUNT_FIELDS = 6;

    /**
     * Fields that the approval engine is allowed to update on a locked record.
     * Everything else is blocked.
     */
    private static final Set<String> APPROVAL_ENGINE_FIELDS = new Set<String>{
        'is_locked__c',
        'discount_approval_status__c',
        'highest_approval_level__c',
        'next_approver__c',
        'approval_submitted_date__c',
        'approval_comments__c',
        'approval_date__c',
        'approved_by__c',
        'status__c',
        'discount_1_status__c',
        'discount_2_status__c',
        'discount_3_status__c',
        'discount_4_status__c',
        'discount_5_status__c',
        'discount_6_status__c'
    };

    /**
     * System fields that Salesforce manages automatically (always exempted).
     */
    private static final Set<String> SYSTEM_FIELDS = new Set<String>{
        'id', 'ownerid', 'createdbyid', 'createddate',
        'lastmodifiedbyid', 'lastmodifieddate', 'systemmodstamp',
        'isdeleted', 'lastactivitydate', 'lastvieweddate',
        'lastreferenceddate', 'name'
    };

    /**
     * @description Before Update handler:
     *              When the Cost Sheet is locked (discount approval pending),
     *              block ALL field changes except approval-engine fields.
     *              This prevents users from editing or modifying the cost sheet
     *              until the discount approvals are fully resolved.
     */
    public static void handleBeforeUpdate(
        List<Cost_Sheet__c> newRecords,
        Map<Id, Cost_Sheet__c> oldMap
    ) {
        // Cache the field map once (lowercase API names → SObjectField tokens)
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Cost_Sheet__c.fields.getMap();

        for (Cost_Sheet__c cs : newRecords) {
            Cost_Sheet__c oldCs = oldMap.get(cs.Id);

            // Only enforce when the record was already locked before this update.
            // (The approval engine sets Is_Locked__c = true during submission,
            //  so that initial DML must be allowed through.)
            if (oldCs.Is_Locked__c != true) {
                continue;
            }

            // Check every writable field for changes.
            // The exemption sets are stored without a namespace prefix; in a managed
            // package the fieldMap keys carry the prefix, so strip before comparing.
            List<String> changedFields = new List<String>();
            for (String fieldApiName : fieldMap.keySet()) {
                String unqualifiedName = NamespaceUtil.strip(fieldApiName);
                // Skip system-managed and approval-engine fields
                if (SYSTEM_FIELDS.contains(unqualifiedName) ||
                    APPROVAL_ENGINE_FIELDS.contains(unqualifiedName)) {
                    continue;
                }

                Object newVal = cs.get(fieldApiName);
                Object oldVal = oldCs.get(fieldApiName);

                if (newVal != oldVal) {
                    changedFields.add(fieldApiName);
                }
            }

            if (!changedFields.isEmpty()) {
                cs.addError(
                    'This Cost Sheet cannot be edited while discount approval is pending. '
                    + 'Please wait for the approval to be completed, or recall the approval first.'
                );
            }
        }
    }
}