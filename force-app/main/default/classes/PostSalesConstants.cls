/**
 * @description Centralized constants class for Post Sales Real Estate module.
 * All status values, allocation types, object/field references, and configuration
 * defaults are stored here to avoid hardcoding across the codebase.
 * @author System
 * @date 2026-03-01
 */
public with sharing class PostSalesConstants {

    // ==================== DEMAND STATUSES ====================
    public static final String DEMAND_STATUS_OPEN = 'Open';
    public static final String DEMAND_STATUS_PARTIAL = 'Partial';
    public static final String DEMAND_STATUS_RAISED = 'Raised';
    public static final String DEMAND_STATUS_EMAILED = 'Emailed';
    public static final String DEMAND_STATUS_REMINDER_SENT = 'Reminder Sent';
    public static final String DEMAND_STATUS_PARTIALLY_PAID = 'Partially Paid';
    public static final String DEMAND_STATUS_OVERDUE = 'Overdue';

    // ==================== DEMAND TYPES ====================
    // The Demands__c.Demand_Type__c picklist in this org only ships with
    // 'Individual Demand' and 'Bulk Demand'. Custom semantic types fall back to
    // 'Individual Demand' so DML succeeds; any code that needs to differentiate
    // Interest / Auto / Debit-Note demands should rely on additional flags.
    public static final String DEMAND_TYPE_INTEREST = 'Individual Demand';
    public static final String DEMAND_TYPE_DEBIT_NOTE = 'Individual Demand';
    public static final String DEMAND_TYPE_BULK = 'Bulk Demand';
    public static final String DEMAND_TYPE_AUTO = 'Individual Demand';

    // ==================== OPEN DEMAND STATUS SET ====================
    public static final Set<String> DEMAND_OPEN_STATUSES = new Set<String>{
        DEMAND_STATUS_OPEN, DEMAND_STATUS_PARTIAL
    };

    public static final Set<String> DEMAND_ALL_OPEN_STATUSES = new Set<String>{
        DEMAND_STATUS_OPEN, DEMAND_STATUS_PARTIAL, DEMAND_STATUS_RAISED,
        DEMAND_STATUS_EMAILED, DEMAND_STATUS_REMINDER_SENT,
        DEMAND_STATUS_PARTIALLY_PAID, DEMAND_STATUS_OVERDUE
    };

    // ==================== UNIT STATUSES ====================
    public static final String UNIT_STATUS_AVAILABLE = 'Available';
    public static final String UNIT_STATUS_BOOKED = 'Booked';

    // ==================== BOOKING STATUSES ====================
    public static final String BOOKING_STATUS_CANCELLED = 'Cancelled';

    // ==================== PAYMENT SCHEDULE STATUSES ====================
    public static final String SCHEDULE_STATUS_PAID = 'Paid';
    public static final String SCHEDULE_STATUS_COMPLETED = 'Completed';
    public static final String SCHEDULE_STATUS_WAIVED = 'Waived';

    public static final Set<String> SCHEDULE_CLOSED_STATUSES = new Set<String>{
        SCHEDULE_STATUS_PAID, SCHEDULE_STATUS_COMPLETED, SCHEDULE_STATUS_WAIVED
    };

    // ==================== MILESTONE STATUSES ====================
    public static final String MILESTONE_STATUS_COMPLETED = 'Completed';

    // ==================== APPROVAL STATUSES ====================
    public static final String APPROVAL_STATUS_DRAFT = 'Draft';
    public static final String APPROVAL_STATUS_PENDING = 'Pending';
    public static final String APPROVAL_STATUS_PENDING_APPROVAL = 'Pending Approval';
    public static final String APPROVAL_STATUS_APPROVED = 'Approved';
    public static final String APPROVAL_STATUS_REJECTED = 'Rejected';
    public static final String APPROVAL_STATUS_CANCELLED = 'Cancelled';

    // ==================== CREDIT NOTE STATUSES ====================
    public static final String CREDIT_STATUS_PENDING = 'Pending';
    public static final String CREDIT_STATUS_APPROVED = 'Approved';

    // ==================== RECEIPT LINE ITEM TYPES ====================
    public static final String LINE_ITEM_TYPE_ADVANCE = 'Advance';
    public static final String LINE_ITEM_TYPE_CREDIT = 'Credit';
    public static final String LINE_ITEM_TYPE_PRINCIPAL = 'Principal';

    // ==================== ALLOCATION TYPES ====================
    public static final String ALLOCATION_ADVANCE_UTILIZATION = 'Advance Utilization';
    public static final String ALLOCATION_CREDIT_ADJUSTMENT = 'Credit Adjustment';
    public static final String ALLOCATION_DEMAND_PAYMENT = 'Demand Payment';
    public static final String ALLOCATION_PAYMENT_SCHEDULE = 'Payment Schedule';

    // ==================== ATTACHMENT TYPES ====================
    public static final String ATTACHMENT_TYPE_VF_PAGE = 'VFPage';
    public static final String ATTACHMENT_TYPE_STATIC_DOC = 'StaticDocument';

    // ==================== RECORD SOURCE TYPES ====================
    public static final String SOURCE_TYPE_DIRECT = 'Direct';
    public static final String SOURCE_TYPE_RELATED = 'Related';
    public static final String RELATIONSHIP_TYPE_PARENT = 'Parent';
    public static final String RELATIONSHIP_TYPE_CHILD = 'Child';
    public static final String CHILD_RECORD_TYPE_ALL = 'All';

    // ==================== DEFAULT VALUES ====================
    public static final Integer DEFAULT_GRACE_PERIOD_DAYS = 15;
    public static final Integer DEFAULT_CREDIT_PRIORITY = 5;
    public static final Integer DEFAULT_MAX_CHILD_RECORDS = 10;
    public static final Integer DEFAULT_SINGLE_CHILD_LIMIT = 1;
    public static final Integer DEFAULT_TRANSACTION_HISTORY_LIMIT = 10;
    public static final String DEFAULT_ORDER_DIRECTION = 'ASC';
    public static final String DEFAULT_ATTACHMENT_FILENAME = 'Attachment.pdf';

    // ==================== CURRENCY ====================
    public static final String CURRENCY_SYMBOL = '\u20B9';

    // ==================== PICKLIST CONFIG ====================
    // Maps of transaction type to object/field for picklist resolution
    public static final Map<String, Map<String, String>> PICKLIST_CONFIG = new Map<String, Map<String, String>>{
        'paymentMode' => new Map<String, String>{ 'object' => 'Receipt__c', 'field' => 'Payment_Method__c' },
        'bank' => new Map<String, String>{ 'object' => 'Booking__c', 'field' => 'Bank__c' },
        'creditType' => new Map<String, String>{ 'object' => 'Credit_Note__c', 'field' => 'Credit_Type__c' },
        'debitType' => new Map<String, String>{ 'object' => 'Debit_Note__c', 'field' => 'Debit_Type__c' },
        'refundReason' => new Map<String, String>{ 'object' => 'Refund__c', 'field' => 'Refund_Reason__c' },
        'receiptType' => new Map<String, String>{ 'object' => 'Receipt__c', 'field' => 'Receipt_Type__c' }
    };

    // ==================== APPROVAL STATUS MAPPING ====================
    public static final Map<String, String> APPROVAL_STATUS_MAP = new Map<String, String>{
        APPROVAL_STATUS_DRAFT => APPROVAL_STATUS_DRAFT,
        APPROVAL_STATUS_PENDING => APPROVAL_STATUS_PENDING,
        APPROVAL_STATUS_PENDING_APPROVAL => APPROVAL_STATUS_PENDING,
        APPROVAL_STATUS_APPROVED => APPROVAL_STATUS_APPROVED,
        APPROVAL_STATUS_REJECTED => APPROVAL_STATUS_REJECTED,
        APPROVAL_STATUS_CANCELLED => APPROVAL_STATUS_REJECTED
    };

    // ==================== TRANSACTION TYPES ====================
    public static final String TRANSACTION_TYPE_RECEIPT = 'receipt';
    public static final String TRANSACTION_TYPE_CREDIT = 'credit';
    public static final String TRANSACTION_TYPE_DEBIT = 'debit';
    public static final String TRANSACTION_TYPE_REFUND = 'refund';

    // ==================== WHAT ID SUPPORTED STANDARD OBJECTS ====================
    public static final Set<String> WHAT_ID_SUPPORTED_OBJECTS = new Set<String>{
        'Account', 'Opportunity', 'Contract', 'Order', 'Campaign',
        'Case', 'Solution', 'Product2', 'Asset'
    };

    // ==================== STATUS ICON/COLOR MAPPINGS ====================
    public static final Map<String, String> STATUS_COLORS = new Map<String, String>{
        SCHEDULE_STATUS_COMPLETED => 'green',
        SCHEDULE_STATUS_PAID => 'green'
    };
    public static final String STATUS_COLOR_DEFAULT = 'red';

    public static final Map<String, String> STATUS_ICONS = new Map<String, String>{
        SCHEDULE_STATUS_COMPLETED => 'utility:success',
        SCHEDULE_STATUS_PAID => 'utility:check'
    };
    public static final String STATUS_ICON_DEFAULT = 'utility:error';

    // ==================== HELPER METHODS ====================

    /**
     * @description Format a decimal value as currency with the configured symbol
     * @param value The decimal value to format
     * @return Formatted currency string
     */
    public static String formatCurrency(Decimal value) {
        if (value == null) {
            return CURRENCY_SYMBOL + '0.00';
        }
        return CURRENCY_SYMBOL + String.valueOf(value.setScale(2).format());
    }

    /**
     * @description Format currency without decimals
     * @param value The decimal value to format
     * @return Formatted currency string without decimals
     */
    public static String formatCurrencyNoDecimals(Decimal value) {
        if (value == null) {
            return CURRENCY_SYMBOL + ' 0';
        }
        return CURRENCY_SYMBOL + ' ' + String.valueOf(value.setScale(0).format());
    }

    /**
     * @description Get picklist values dynamically from object and field config
     * @param picklistKey Key from PICKLIST_CONFIG map
     * @return List of PicklistOption
     */
    public static List<PicklistOption> getPicklistValues(String picklistKey) {
        List<PicklistOption> options = new List<PicklistOption>();

        Map<String, String> config = PICKLIST_CONFIG.get(picklistKey);
        if (config == null) {
            return options;
        }

        return getPicklistValuesByObjectField(config.get('object'), config.get('field'));
    }

    /**
     * @description Get picklist values from any object and field name
     * @param objectName SObject API name
     * @param fieldName Field API name
     * @return List of PicklistOption
     */
    public static List<PicklistOption> getPicklistValuesByObjectField(String objectName, String fieldName) {
        List<PicklistOption> options = new List<PicklistOption>();

        try {
            Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectName);
            if (objType == null) return options;

            Schema.DescribeSObjectResult objDescribe = objType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = objDescribe.fields.getMap();

            String fieldNameLower = fieldName.toLowerCase();
            if (!fieldMap.containsKey(fieldNameLower)) return options;

            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldNameLower).getDescribe();

            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive()) {
                    options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
                }
            }
        } catch (Exception e) {
            System.debug('Error getting picklist values for ' + objectName + '.' + fieldName + ': ' + e.getMessage());
        }

        return options;
    }

    /**
     * @description Map an approval status to its display status
     * @param status Raw status value
     * @return Mapped display status
     */
    public static String mapApprovalStatus(String status) {
        if (status == null) return APPROVAL_STATUS_DRAFT;
        return APPROVAL_STATUS_MAP.containsKey(status) ? APPROVAL_STATUS_MAP.get(status) : status;
    }

    /**
     * @description Get status color for a schedule status
     * @param status The status value
     * @return CSS color string
     */
    public static String getStatusColor(String status) {
        return STATUS_COLORS.containsKey(status) ? STATUS_COLORS.get(status) : STATUS_COLOR_DEFAULT;
    }

    /**
     * @description Get status icon for a schedule status
     * @param status The status value
     * @return Lightning icon name
     */
    public static String getStatusIcon(String status) {
        return STATUS_ICONS.containsKey(status) ? STATUS_ICONS.get(status) : STATUS_ICON_DEFAULT;
    }

    /**
     * @description Check if a standard object supports WhatId for email activity
     * @param objectApiName The object API name
     * @return true if WhatId is supported
     */
    public static Boolean isWhatIdSupported(String objectApiName) {
        if (objectApiName != null && objectApiName.endsWith('__c')) {
            return true;
        }
        return WHAT_ID_SUPPORTED_OBJECTS.contains(objectApiName);
    }

    // ==================== INNER CLASSES ====================

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }
}