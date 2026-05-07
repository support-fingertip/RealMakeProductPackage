/**
 * @description Handler for Site Visit trigger.
 * Routes to PushToSalesService for automation-based push to sales.
 *
 * After Insert:
 *   If General Setup with "Automation /On Site-Visit Creation" is active,
 *   pushes the Lead to Sales when a new Site Visit is created.
 *
 * After Update:
 *   If General Setup with "Automation /On Site-Visit Completion" is active,
 *   pushes the Lead to Sales when Status__c changes to 'Completed'.
 */
public with sharing class SiteVisitTriggerHandler {

    /**
     * @description After Insert — trigger push on SV creation.
     *   • Scheduled SVs → pushOnSVScheduled
     *   • Completed SVs → pushOnSVCompleted  (e.g. GRE walk-in creates SV directly as Completed)
     */
    public static void onAfterInsert(List<Site_Visit__c> newSVs) {
        List<Site_Visit__c> scheduledSVs = new List<Site_Visit__c>();
        List<Site_Visit__c> completedSVs = new List<Site_Visit__c>();
        for (Site_Visit__c sv : newSVs) {
            if (sv.Status__c == 'Scheduled') {
                scheduledSVs.add(sv);
            } else if (sv.Status__c == 'Completed') {
                completedSVs.add(sv);
            }
        }
        if (!scheduledSVs.isEmpty()) {
            PushToSalesService.pushOnSVScheduled(scheduledSVs);
        }
        if (!completedSVs.isEmpty()) {
            PushToSalesService.pushOnSVCompleted(completedSVs);
        }
    }

    /**
     * @description After Update — trigger push when SV is marked Completed.
     */
    public static void onAfterUpdate(List<Site_Visit__c> newSVs, Map<Id, Site_Visit__c> oldMap) {
        List<Site_Visit__c> completedSVs = new List<Site_Visit__c>();
        for (Site_Visit__c sv : newSVs) {
            Site_Visit__c oldSV = oldMap.get(sv.Id);
            if (sv.Status__c == 'Completed' && oldSV.Status__c != 'Completed') {
                completedSVs.add(sv);
            }
        }
        if (!completedSVs.isEmpty()) {
            PushToSalesService.pushOnSVCompleted(completedSVs);
        }
    }
}