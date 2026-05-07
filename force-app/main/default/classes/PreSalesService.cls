/**
 * @description Service class for Pre-Sales execution.
 * Handles follow-up creation, site visit management, status updates, and push to sales.
 * Rules: PS_R01-R05, GRE_01-06
 */
public with sharing class PreSalesService {

    /**
     * @description Update pre-sales lead status with dependent actions
     * Rules: PS_R01-R05
     */
    public static void updatePreSalesStatus(Id leadId, String newStatus, Map<String, Object> params) {
        Lead__c lead = [SELECT Id, Owner__c, Project__c, Lead_Status__c FROM Lead__c WHERE Id = :leadId];

        switch on newStatus {
            when 'Follow-up' {
                String subject = (String) params.get('subject');
                DateTime dueDate = (DateTime) params.get('dueDate');
                if (String.isBlank(subject) || dueDate == null) {
                    throw new PreSalesException('Subject and Due Date are required for Follow-up.');
                }
                insert new Followup__c(
                    Lead__c = leadId, Subject__c = subject, Due_Date__c = dueDate,
                    Status__c = 'Pending', Assigned_To__c = lead.Owner__c
                );
            }
            when 'RNR' {
                String subject = (String) params.get('subject');
                DateTime dueDate = (DateTime) params.get('dueDate');
                if (String.isBlank(subject) || dueDate == null) {
                    throw new PreSalesException('Subject and Due Date are required for RNR retry.');
                }
                insert new Followup__c(
                    Lead__c = leadId, Subject__c = subject, Due_Date__c = dueDate,
                    Status__c = 'Pending', Assigned_To__c = lead.Owner__c
                );
            }
            when 'Site Visit Scheduled' {
                DateTime scheduledDate = (DateTime) params.get('scheduledDate');
                String visitType = (String) params.get('visitType');
                String sourceType = (String) params.get('sourceType');
                if (scheduledDate == null) {
                    throw new PreSalesException('Scheduled Date is required for Site Visit.');
                }
                Site_Visit__c sv = new Site_Visit__c();
                sv.Lead__c = leadId;
                sv.Project__c = lead.Project__c;
                sv.Scheduled_Date__c = scheduledDate;
                sv.Status__c = 'Scheduled';
                sv.Assigned_To__c = lead.Owner__c;
                sv.Mode_Of_Visit__c = String.isNotBlank(visitType) ? visitType : 'On Site';
                if (String.isNotBlank(sourceType)) sv.Source_Type__c = sourceType;
                insert sv;
            }
            when 'Unqualified' {
                String reason = (String) params.get('lostReason');
                if (String.isBlank(reason)) {
                    throw new PreSalesException('Lost Reason is required for Unqualified.');
                }
                lead.Lost_Reason__c = reason;
                // Cancel pending activities
                List<Followup__c> fus = [SELECT Id FROM Followup__c WHERE Lead__c = :leadId AND Status__c = 'Pending'];
                for (Followup__c fu : fus) fu.Status__c = 'Cancelled';
                if (!fus.isEmpty()) update fus;
                List<Site_Visit__c> svs = [SELECT Id FROM Site_Visit__c WHERE Lead__c = :leadId AND Status__c = 'Scheduled'];
                for (Site_Visit__c sv : svs) sv.Status__c = 'Cancelled';
                if (!svs.isEmpty()) update svs;
                // Assign to admin
                List<User> admins = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true LIMIT 1];
                if (!admins.isEmpty()) lead.Owner__c = admins[0].Id;
            }
        }

        lead.Lead_Status__c = newStatus;
        update lead;
    }

    /**
     * @description Push qualified lead to Sales team.
     * Delegates to PushToSalesService which handles RecordType change,
     * field mappings, round-robin assignment, and manual sharing.
     * Rule: PS_R05
     */
    public static void pushToSales(Id leadId) {
        PushToSalesService.pushManual(leadId);
    }

    /**
     * @description GRE walk-in flow: process walk-in customer
     * Rules: GRE_01-GRE_06
     */
    public static Id processGREWalkin(String customerPhone, String source, Id projectId, Map<String, String> customerDetails, Id salesExecId) {
        // Check for existing lead
        List<Lead__c> existingLeads = [
            SELECT Id, Lead_Status__c, Owner__c, Is_Active__c
            FROM Lead__c
            WHERE Project__c = :projectId
            AND (Primary_Mobile__c = :customerPhone OR Secondary_Mobile__c = :customerPhone)
            LIMIT 1
        ];

        Id leadId;

        if (existingLeads.isEmpty()) {
            // GRE_03: No lead found - create new
            Lead__c newLead = new Lead__c();
            newLead.First_Name__c = customerDetails.get('firstName');
            newLead.Last_Name__c = customerDetails.get('lastName');
            newLead.Primary_Mobile__c = customerPhone;
            newLead.Primary_Email__c = customerDetails.get('email');
            newLead.Project__c = projectId;
            newLead.Lead_Type__c = 'Fresh';
            newLead.Lead_Status__c = 'Site Visit Scheduled';
            newLead.Lead_Source__c = 'Walk-in';
            newLead.Owner__c = salesExecId != null ? salesExecId : RoundRobinService.getNextUser(projectId, 'Sales');
            insert newLead;
            leadId = newLead.Id;
        } else {
            Lead__c existing = existingLeads[0];
            leadId = existing.Id;

            Set<String> inactiveStatuses = new Set<String>{
                'Unqualified', 'Rejected', 'Request for Rejection', 'Closed Lost'
            };
            Boolean isActive = !inactiveStatuses.contains(existing.Lead_Status__c);

            if (!isActive) {
                // GRE_06: Inactive lead - reopen via unified service
                LeadReopenService.reopenLead(
                    existing.Id, 'Walk-in', null,
                    salesExecId, 'Site Visit Scheduled'
                );
            }

            // Create enquiry source
            Enquiry_Source__c es = new Enquiry_Source__c();
            es.Lead__c = leadId;
            es.Enquiry_Date__c = DateTime.now();
            es.Enquiry_Type__c = isActive ? 'Re-engaged' : 'Re-opened';
            es.Source__c = 'Walk-in';
            insert es;
        }

        // Create completed site visit
        Site_Visit__c sv = new Site_Visit__c();
        sv.Lead__c = leadId;
        sv.Project__c = projectId;
        sv.Scheduled_Date__c = DateTime.now();
        sv.Completed_Date__c = DateTime.now();
        sv.Status__c = 'Completed';
        sv.Mode_Of_Visit__c = 'On Site';
        sv.Source_Type__c = source == 'Channel Partner' ? 'Channel Partner' : 'Digital (Own)';
        sv.Assigned_To__c = salesExecId;
        insert sv;

        return leadId;
    }

    public class PreSalesException extends Exception {}
}