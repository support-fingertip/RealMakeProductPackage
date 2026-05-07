/**
 * @description Thin controller for the Performance Targets LWC.
 * Delegates all logic to PerformanceTargetService. Follows Service-Controller pattern.
 */
public with sharing class PerformanceTargetController {

    // ═══════════════════════════════════════════════════════════════════
    //  FILTER OPTIONS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get available filter options (owners, periods, metric types).
     */
    @AuraEnabled(cacheable=true)
    public static PerformanceTargetService.FilterOptions getFilterOptions() {
        try {
            return PerformanceTargetService.getFilterOptions();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TARGETS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get performance targets matching the given filter.
     * @param filterJson JSON string of TargetFilter
     */
    @AuraEnabled
    public static List<PerformanceTargetService.TargetSummary> getTargets(String filterJson) {
        try {
            PerformanceTargetService.TargetFilter filter = parseFilter(filterJson);
            return PerformanceTargetService.getTargets(filter);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DASHBOARD DATA
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Composite loader for full dashboard data.
     * @param filterJson JSON string of TargetFilter
     */
    @AuraEnabled
    public static PerformanceTargetService.DashboardData getDashboardData(String filterJson) {
        try {
            PerformanceTargetService.TargetFilter filter = parseFilter(filterJson);
            return PerformanceTargetService.getDashboardData(filter);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  LEADERBOARD
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get leaderboard rankings for the given filter.
     * @param filterJson JSON string of TargetFilter
     */
    @AuraEnabled
    public static List<PerformanceTargetService.LeaderboardEntry> getLeaderboard(String filterJson) {
        try {
            PerformanceTargetService.TargetFilter filter = parseFilter(filterJson);
            return PerformanceTargetService.getLeaderboard(filter);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SAVE TARGET
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Upsert a single performance target record.
     * @param targetJson JSON string of Performance_Target__c
     */
    @AuraEnabled
    public static Performance_Target__c saveTarget(String targetJson) {
        try {
            Performance_Target__c target = (Performance_Target__c) JSON.deserialize(
                targetJson, Performance_Target__c.class
            );
            return PerformanceTargetService.saveTarget(target);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  BULK CREATE TARGETS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Bulk-create targets from an assignment specification.
     * @param assignmentJson JSON string of BulkAssignment
     */
    @AuraEnabled
    public static List<Performance_Target__c> bulkCreateTargets(String assignmentJson) {
        try {
            PerformanceTargetService.BulkAssignment assignment =
                (PerformanceTargetService.BulkAssignment) JSON.deserialize(
                    assignmentJson, PerformanceTargetService.BulkAssignment.class
                );
            return PerformanceTargetService.bulkCreateTargets(assignment);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  CLONE TARGETS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Clone targets from a source period into a new period.
     * @param sourceFilterJson JSON string of TargetFilter for source targets
     * @param newPeriodStart Start date of the new period
     * @param newPeriodEnd End date of the new period
     */
    @AuraEnabled
    public static List<Performance_Target__c> cloneTargets(String sourceFilterJson, Date newPeriodStart, Date newPeriodEnd) {
        try {
            PerformanceTargetService.TargetFilter filter = parseFilter(sourceFilterJson);
            return PerformanceTargetService.cloneTargets(filter, newPeriodStart, newPeriodEnd);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  DELETE TARGET
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Delete a single performance target by Id.
     * @param targetId Id of the Performance_Target__c to delete
     */
    @AuraEnabled
    public static void deleteTarget(Id targetId) {
        try {
            PerformanceTargetService.deleteTarget(targetId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  RECALCULATE ACTUALS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Recalculate actual values for targets matching the filter.
     * @param filterJson JSON string of TargetFilter
     */
    @AuraEnabled
    public static List<PerformanceTargetService.TargetSummary> recalculateActuals(String filterJson) {
        try {
            PerformanceTargetService.TargetFilter filter = parseFilter(filterJson);
            return PerformanceTargetService.recalculateAndUpdate(filter);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  TREND DATA
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Get historical trend data for a specific target.
     * @param targetId Id of the Performance_Target__c
     */
    @AuraEnabled
    public static List<PerformanceTargetService.TrendPoint> getTrendData(Id targetId) {
        try {
            return PerformanceTargetService.getTrendData(targetId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  EXPORT — CSV
    // ═══════════════════════════════════════════════════════════════════

    /**
     * @description Generate CSV export of performance target data.
     * @param filterJson JSON string of TargetFilter
     * @return CSV content as a string
     */
    @AuraEnabled
    public static String exportCSV(String filterJson) {
        try {
            PerformanceTargetService.TargetFilter filter = parseFilter(filterJson);
            return PerformanceTargetService.exportCSV(filter);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  PRIVATE HELPERS
    // ═══════════════════════════════════════════════════════════════════

    private static PerformanceTargetService.TargetFilter parseFilter(String filterJson) {
        if (String.isBlank(filterJson) || filterJson == '{}') {
            return new PerformanceTargetService.TargetFilter();
        }
        return (PerformanceTargetService.TargetFilter) JSON.deserialize(
            filterJson, PerformanceTargetService.TargetFilter.class
        );
    }
}