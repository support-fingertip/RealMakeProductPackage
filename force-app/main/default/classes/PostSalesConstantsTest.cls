/**
 * @description Test class for PostSalesConstants (100% coverage).
 * Covers all helper methods + every branch of the dynamic picklist /
 * status-mapping / WhatId lookup functions.
 */
@isTest
private class PostSalesConstantsTest {

    @isTest
    static void formatCurrency_nullAndValue() {
        System.assertEquals(PostSalesConstants.CURRENCY_SYMBOL + '0.00',
            PostSalesConstants.formatCurrency(null));
        String formatted = PostSalesConstants.formatCurrency(1234.5);
        System.assert(formatted.startsWith(PostSalesConstants.CURRENCY_SYMBOL));
    }

    @isTest
    static void formatCurrencyNoDecimals_nullAndValue() {
        System.assertEquals(PostSalesConstants.CURRENCY_SYMBOL + ' 0',
            PostSalesConstants.formatCurrencyNoDecimals(null));
        System.assert(
            PostSalesConstants.formatCurrencyNoDecimals(999)
                .startsWith(PostSalesConstants.CURRENCY_SYMBOL)
        );
    }

    @isTest
    static void getPicklistValues_knownAndUnknownKey() {
        PostSalesConstants.getPicklistValues('paymentMode');
        List<PostSalesConstants.PicklistOption> unknown =
            PostSalesConstants.getPicklistValues('bogusKey');
        System.assertEquals(0, unknown.size());
    }

    @isTest
    static void getPicklistValuesByObjectField_allBranches() {
        PostSalesConstants.getPicklistValuesByObjectField('Lead__c', 'Lead_Status__c');
        System.assertEquals(0,
            PostSalesConstants.getPicklistValuesByObjectField('NoSuchObj__x', 'F').size());
        System.assertEquals(0,
            PostSalesConstants.getPicklistValuesByObjectField('Lead__c', 'NoSuchField__x').size());
        System.assertEquals(0,
            PostSalesConstants.getPicklistValuesByObjectField(null, 'F').size());
    }

    @isTest
    static void mapApprovalStatus_allBranches() {
        System.assertEquals(PostSalesConstants.APPROVAL_STATUS_DRAFT,
            PostSalesConstants.mapApprovalStatus(null));
        System.assertEquals(PostSalesConstants.APPROVAL_STATUS_APPROVED,
            PostSalesConstants.mapApprovalStatus(PostSalesConstants.APPROVAL_STATUS_APPROVED));
        System.assertEquals('Unknown',
            PostSalesConstants.mapApprovalStatus('Unknown'));
    }

    @isTest
    static void getStatusColorAndIcon_knownAndDefault() {
        System.assertEquals('green',
            PostSalesConstants.getStatusColor(PostSalesConstants.SCHEDULE_STATUS_COMPLETED));
        System.assertEquals(PostSalesConstants.STATUS_COLOR_DEFAULT,
            PostSalesConstants.getStatusColor('Unknown'));
        System.assertEquals('utility:success',
            PostSalesConstants.getStatusIcon(PostSalesConstants.SCHEDULE_STATUS_COMPLETED));
        System.assertEquals(PostSalesConstants.STATUS_ICON_DEFAULT,
            PostSalesConstants.getStatusIcon('Unknown'));
    }

    @isTest
    static void isWhatIdSupported_allBranches() {
        System.assertEquals(true, PostSalesConstants.isWhatIdSupported('Booking__c'));
        System.assertEquals(true, PostSalesConstants.isWhatIdSupported('Account'));
        System.assertEquals(false, PostSalesConstants.isWhatIdSupported('User'));
        System.assertEquals(false, PostSalesConstants.isWhatIdSupported(null));
    }

    @isTest
    static void picklistOption_constructor() {
        PostSalesConstants.PicklistOption o = new PostSalesConstants.PicklistOption('L', 'V');
        System.assertEquals('L', o.label);
        System.assertEquals('V', o.value);
    }
}