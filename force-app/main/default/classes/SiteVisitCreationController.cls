/**
 * @description LWC controller for the universal scheduleSiteVisit quick action.
 * Delegates to SiteVisitCreationService for same-project and cross-project site visits.
 */
public with sharing class SiteVisitCreationController {

    /**
     * @description Get initialization data for the site visit form.
     */
    @AuraEnabled(cacheable=true)
    public static InitData getInitData(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead ID is required.');
        }

        Lead__c lead = [
            SELECT Id, Name, Project__c, Project__r.Name, Owner__c, Owner__r.Name
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        InitData data = new InitData();
        data.leadName = lead.Name;
        data.currentProjectId = lead.Project__c;
        data.currentProjectName = lead.Project__r.Name;
        data.ownerName = lead.Owner__r.Name;
        data.crossProjectAllowed = ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed();
        return data;
    }

    /**
     * @description Create a site visit via the universal service.
     */
    @AuraEnabled
    public static SiteVisitCreationService.SiteVisitResult createSiteVisit(
        Id leadId, Id projectId, String scheduledDate,
        String visitType, Boolean needPickUp
    ) {
        if (String.isBlank(scheduledDate)) {
            throw new AuraHandledException('Scheduled Date is required.');
        }

        // Gate cross-project scheduling on the active General Setup
        if (!ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed()) {
            Lead__c leadForGate = [SELECT Id, Project__c FROM Lead__c WHERE Id = :leadId LIMIT 1];
            if (leadForGate.Project__c != projectId) {
                throw new AuraHandledException(
                    'Cross-project site visits are not allowed by the current General Setup. ' +
                    'Please contact your administrator.'
                );
            }
        }

        // Duplicate check: prevent scheduling if a visit is already scheduled for this lead+project
        List<Site_Visit__c> existingSV = [
            SELECT Id FROM Site_Visit__c
            WHERE Lead__c = :leadId
            AND Project__c = :projectId
            AND Status__c = 'Scheduled'
            LIMIT 1
        ];
        if (!existingSV.isEmpty()) {
            throw new AuraHandledException(
                'A site visit is already scheduled for this lead and project. Please cancel or complete it first.'
            );
        }

        DateTime svDateTime = parseDateTime(scheduledDate);
        if (svDateTime <DateTime.now().addSeconds(1)) {
            throw new AuraHandledException('Scheduled Date must be in the future.');
        }

        try {
            return SiteVisitCreationService.createSiteVisit(
                leadId, projectId, svDateTime, visitType, null, needPickUp
            );
        } catch (SiteVisitCreationService.SiteVisitCreationException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    private static DateTime parseDateTime(String dtStr) {
        if (String.isBlank(dtStr)) return null;
        if (dtStr.contains('.') || dtStr.endsWith('Z')) {
            return (DateTime) JSON.deserialize('"' + dtStr + '"', DateTime.class);
        }
        return DateTime.valueOf(dtStr.replace('T', ' '));
    }

    public class InitData {
        @AuraEnabled public String leadName;
        @AuraEnabled public Id currentProjectId;
        @AuraEnabled public String currentProjectName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Boolean crossProjectAllowed;
    }
}