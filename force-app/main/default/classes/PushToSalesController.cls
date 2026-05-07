/**
 * @description Controller exposing PushToSalesService to LWC components.
 */
public with sharing class PushToSalesController {

    /**
     * @description Get lead details for the Push to Sales confirmation screen.
     */
    @AuraEnabled
    public static Map<String, Object> getLeadInfo(Id leadId) {
        if (leadId == null) {
            throw new AuraHandledException('Lead ID is required.');
        }

        List<Lead__c> leads = [
            SELECT Id, Name, Full_Name__c, Lead_Status__c,
                   OwnerId, Owner.Name,
                   RecordType.DeveloperName, RecordType.Name,
                   Project__r.Name
            FROM Lead__c
            WHERE Id = :leadId
            LIMIT 1
        ];

        if (leads.isEmpty()) {
            throw new AuraHandledException('Lead not found.');
        }

        Lead__c lead = leads[0];

        Map<String, Object> info = new Map<String, Object>();
        info.put('leadId', lead.Id);
        info.put('leadName', lead.Full_Name__c);
        info.put('leadIdName', lead.Name);
        info.put('leadStatus', lead.Lead_Status__c);
        info.put('ownerName', lead.Owner.Name);
        info.put('recordTypeName', lead.RecordType.Name);
        info.put('recordTypeDev', lead.RecordType.DeveloperName);
        info.put('projectName', lead.Project__r != null ? lead.Project__r.Name : '');
        info.put('isPreSales', lead.RecordType.DeveloperName == 'Pre_Sales');

        Set<String> allowedStatuses = new Set<String>{ 'Site Visit Scheduled', 'Site Visit Completed' };
        info.put('canPush', lead.RecordType.DeveloperName == 'Pre_Sales'
            && allowedStatuses.contains(lead.Lead_Status__c));
        return info;
    }

    /**
     * @description Execute manual push to sales.
     */
    @AuraEnabled
    public static void pushToSales(Id leadId) {
        try {
            PushToSalesService.pushManual(leadId);
        } catch (PushToSalesService.PushToSalesException e) {
            throw new AuraHandledException(e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('Push to Sales failed: ' + e.getMessage());
        }
    }
}