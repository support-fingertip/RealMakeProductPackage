/**
 * @description Controller for the Home Notification Dashboard LWC.
 *              Thin layer exposing NotificationDashboardService to Lightning.
 *              Follows Service-Controller pattern (see PushToSalesController, UserAvailabilityController).
 */
public with sharing class NotificationDashboardController {

    // ═══════════════════════════════════════════════════════════════════
    //  CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Load all dashboard configuration in a single call.
     *              Returns tab configs, field configs, current user profile.
     * @return Map with keys: tabs, fields, currentProfile
     */
    @AuraEnabled
    public static Map<String, Object> getDashboardConfig() {
        try {
            return NotificationDashboardService.getDashboardConfig();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TAB DATA
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Load records for a specific tab.
     * @param tabKey Tab identifier (TODAY_AGENDAS, PENDING_ITEMS, TODAY_LEADS)
     * @param pageSize Number of records per page (used for TODAY_LEADS)
     * @param offset SOQL offset for pagination (used for TODAY_LEADS)
     * @return TabDataResult wrapper with records and totalCount
     */
    @AuraEnabled
    public static NotificationDashboardService.TabDataResult getTabData(
        String tabKey, Integer pageSize, Integer offset
    ) {
        try {
            return NotificationDashboardService.getTabData(tabKey, pageSize, offset);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  STATUS UPDATE
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Update status of a record (follow-up, site visit, or lead).
     * @param recordId The record to update
     * @param sObjectName API name of the sObject
     * @param statusField API name of the status field
     * @param newStatus New status value
     * @param additionalFieldsJson JSON map of any additional fields to set
     */
    @AuraEnabled
    public static void updateRecordStatus(
        Id recordId,
        String sObjectName,
        String statusField,
        String newStatus,
        String additionalFieldsJson
    ) {
        try {
            NotificationDashboardService.updateRecordStatus(
                recordId, sObjectName, statusField, newStatus, additionalFieldsJson
            );
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  MOVE LEAD TO FOLLOW-UP
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Moves a Lead to Follow-up status and creates a Followup__c record.
     * @param recordId The Lead record ID
     * @param subject  Follow-up subject
     * @param dueDate  Follow-up due date (ISO string)
     * @param notes    Optional follow-up notes
     */
    @AuraEnabled
    public static void moveLeadToFollowUp(Id recordId, String subject, String dueDate, String notes) {
        try {
            NotificationDashboardService.moveLeadToFollowUp(recordId, subject, dueDate, notes);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}