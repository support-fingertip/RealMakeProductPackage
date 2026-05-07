/**
 * @description LWC controller for the leadReopenAction quick action.
 * Allows users to manually reopen an inactive lead.
 */
public with sharing class LeadReopenController {

    /**
     * @description Get lead info for the reopen confirmation screen.
     */
    @AuraEnabled(cacheable=true)
    public static LeadInfo getLeadInfo(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead ID is required.');
        }

        Lead__c lead = [
            SELECT Id, Name, Lead_Status__c, Is_Active__c, Project__c, Project__r.Name
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        LeadInfo info = new LeadInfo();
        info.leadName = lead.Name;
        info.leadStatus = lead.Lead_Status__c;
        info.isActive = lead.Is_Active__c;
        info.projectName = lead.Project__r.Name;
        return info;
    }

    /**
     * @description Reopen an inactive lead.
     */
    @AuraEnabled
    public static LeadReopenService.ReopenResult reopenLead(
        Id leadId, String source, String subSource
    ) {
        try {
            return LeadReopenService.reopenLead(
                leadId,
                String.isNotBlank(source) ? source : 'Manual',
                String.isNotBlank(subSource) ? subSource : null
            );
        } catch (LeadReopenService.LeadReopenException e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public class LeadInfo {
        @AuraEnabled public String leadName;
        @AuraEnabled public String leadStatus;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String projectName;
    }
}