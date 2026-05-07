/**
 * @description Service class for Sales executive actions.
 * Handles cost sheet creation, approval, unit blocking, and status updates.
 * Rules: CS_FLOW_01-07, CS_APPR_01-06, BLOCK_01-05, SALE_R01-05
 */
public with sharing class SalesService {

    /**
     * @description Create a new cost sheet from selected unit
     */
    public static Id createCostSheet(Id leadId, Id unitId, String paymentPlanType, List<CS_Payment_Line__c> customLines) {
        Unit__c unit = [
            SELECT Id, Unit_Number__c, Status__c, Project__c, Tower__c,
                   Carpet_Area__c, Super_Builtup_Area__c, UDS__c, Base_Rate_Sqft__c, Base_Price__c,
                   PLC_Charges__c, Floor_Rise_Sqft__c, Amenity_Charges__c, Infra_Charges__c,
                   Doc_Charges__c, Maintenance_Sqft_Month__c, Maintenance_Months__c,
                   Corpus_Fund_Sqft__c, Move_In_Charges__c, Stamp_Duty_Pct__c, Registration_Pct__c, GST_Percentage__c,
                   Tower__r.Sales_Active__c, Tower__r.Booking_Allowed__c
            FROM Unit__c WHERE Id = :unitId
        ];

        if (unit.Status__c != 'Available') {
            throw new SalesException('Unit ' + unit.Unit_Number__c + ' is not available. Current status: ' + unit.Status__c);
        }
        if (!unit.Tower__r.Sales_Active__c) {
            throw new SalesException('Sales are not active for this tower.');
        }

        Cost_Sheet__c cs = new Cost_Sheet__c();
        cs.Lead__c = leadId;
        cs.Project__c = unit.Project__c;
        cs.Unit__c = unitId;
        cs.Status__c = 'Draft';
        cs.Payment_Plan_Type__c = paymentPlanType;
        cs.Created_By__c = UserInfo.getUserId();

        // Snapshot pricing from unit
        cs.Carpet_Area__c = unit.Carpet_Area__c;
        cs.Super_Builtup_Area__c = unit.Super_Builtup_Area__c;
        cs.Super_Builtup_Area__c = unit.Super_Builtup_Area__c;
        cs.UDS__c = unit.UDS__c;
        cs.Base_Rate_Sqft__c = unit.Base_Rate_Sqft__c;
        cs.Base_Price__c = unit.Base_Price__c;
        cs.PLC_Charges__c = unit.PLC_Charges__c;
        cs.Floor_Rise_Sqft__c = unit.Floor_Rise_Sqft__c;
        cs.Amenity_Charges__c = unit.Amenity_Charges__c;
        cs.Infra_Charges__c = unit.Infra_Charges__c;
        cs.Doc_Charges__c = unit.Doc_Charges__c;
        cs.Maintenance_Sqft_Month__c = unit.Maintenance_Sqft_Month__c;
        cs.Maintenance_Months__c = unit.Maintenance_Months__c;
        cs.Corpus_Fund_Sqft__c = unit.Corpus_Fund_Sqft__c;
        cs.Move_In_Charges__c = unit.Move_In_Charges__c;
        cs.Stamp_Duty_Pct__c = unit.Stamp_Duty_Pct__c;
        cs.Registration_Pct__c = unit.Registration_Pct__c;
        cs.GST_Percentage__c = unit.GST_Percentage__c;

        insert cs;

        // Unit blocking is handled by CostSheetTrigger (after insert)

        // Create payment lines
        if (paymentPlanType == 'Standard') {
            createStandardPaymentLines(cs.Id, unit.Tower__c, unit.Project__c);
        } else if (customLines != null && !customLines.isEmpty()) {
            for (CS_Payment_Line__c line : customLines) {
                line.Cost_Sheet__c = cs.Id;
            }
            insert customLines;
        }

        // Auto-submit for approval if custom plan
        if (paymentPlanType == 'Custom') {
            cs.Status__c = 'Pending Approval';
            update cs;
        } else {
            cs.Status__c = 'Approved';
            cs.Approved_By__c = UserInfo.getUserId();
            cs.Approval_Date__c = DateTime.now();
            update cs;
        }

        return cs.Id;
    }

    private static void createStandardPaymentLines(Id costSheetId, Id towerId, Id projectId) {
        List<Payment_Milestone__c> milestones = [
            SELECT Id, Name, Payment_Pct__c, Sequence__c, Category__c, Construction_Milestone__c
            FROM Payment_Milestone__c
            WHERE (Tower__c = :towerId OR (Tower__c = null AND Project__c = :projectId))
            ORDER BY Sequence__c ASC
        ];

        Cost_Sheet__c cs = [SELECT Agreement_Value__c FROM Cost_Sheet__c WHERE Id = :costSheetId];

        List<CS_Payment_Line__c> lines = new List<CS_Payment_Line__c>();
        for (Payment_Milestone__c m : milestones) {
            CS_Payment_Line__c line = new CS_Payment_Line__c();
            line.Cost_Sheet__c = costSheetId;
            line.Milestone_Name__c = m.Name;
            line.Payment_Pct__c = m.Payment_Pct__c;
            line.Amount__c = cs.Agreement_Value__c != null ? cs.Agreement_Value__c * m.Payment_Pct__c / 100 : 0;
            line.Sequence__c = m.Sequence__c;
            line.Category__c = m.Category__c;
            line.Construction_Milestone__c = m.Construction_Milestone__c;
            lines.add(line);
        }
        if (!lines.isEmpty()) insert lines;
    }

    /**
     * @description Block a unit from an accepted cost sheet
     */
    public static void blockUnit(Id costSheetId) {
        Cost_Sheet__c cs = [
            SELECT Id, Unit__c, Lead__c, Status__c, Unit__r.Status__c,
                   Unit__r.Tower__r.Sales_Active__c, Unit__r.Tower__r.Booking_Allowed__c,
                   Project__c, Project__r.Max_Block_Days__c
            FROM Cost_Sheet__c WHERE Id = :costSheetId
        ];

        if (cs.Status__c != 'Accepted by Customer') {
            throw new SalesException('Only accepted cost sheets can be used to block a unit.');
        }
        if (cs.Unit__r.Status__c != 'Available') {
            throw new SalesException('Unit is no longer available. Status: ' + cs.Unit__r.Status__c);
        }
        if (!cs.Unit__r.Tower__r.Sales_Active__c || !cs.Unit__r.Tower__r.Booking_Allowed__c) {
            throw new SalesException('Sales or booking is not allowed for this tower.');
        }

        List<Unit__c> alreadyBlocked = [
            SELECT Id, Unit_Number__c FROM Unit__c
            WHERE Blocked_By_Lead__c = :cs.Lead__c AND Project__c = :cs.Project__c AND Status__c = 'Blocked'
            LIMIT 1
        ];
        if (!alreadyBlocked.isEmpty()) {
            throw new SalesException('Lead already has a blocked unit (' + alreadyBlocked[0].Unit_Number__c + ') in this project.');
        }

        Integer blockDays = cs.Project__r.Max_Block_Days__c != null ? (Integer) cs.Project__r.Max_Block_Days__c : 7;
        Unit__c unit = new Unit__c(Id = cs.Unit__c);
        unit.Status__c = 'Blocked';
        unit.Blocked_By_Lead__c = cs.Lead__c;
        unit.Block_Expiry__c = Date.today().addDays(blockDays);
        update unit;
    }

    /**
     * @description Update sales lead status with dependent actions
     */
    public static void updateSalesStatus(Id leadId, String newStatus, Map<String, Object> params) {
        Lead__c lead = [SELECT Id, Owner__c, Project__c, Lead_Status__c FROM Lead__c WHERE Id = :leadId];

        switch on newStatus {
            when 'SV Completed' {
                DateTime completedDate = (DateTime) params.get('completedDate');
                String feedback = (String) params.get('feedback');
                if (completedDate == null) {
                    throw new SalesException('Completed Date is required.');
                }
                List<Site_Visit__c> svs = [
                    SELECT Id FROM Site_Visit__c
                    WHERE Lead__c = :leadId AND Status__c = 'Scheduled'
                    ORDER BY Scheduled_Date__c DESC LIMIT 1
                ];
                if (!svs.isEmpty()) {
                    svs[0].Status__c = 'Completed';
                    svs[0].Completed_Date__c = completedDate;
                    svs[0].FeedBack__c = feedback;
                    update svs[0];
                }
            }
            when 'Follow-up' {
                String subject = (String) params.get('followupSubject');
                DateTime dueDate = (DateTime) params.get('followupDueDate');
                if (String.isBlank(subject) || dueDate == null) {
                    throw new SalesException('Follow-up Subject and Due Date are required.');
                }
                insert new Followup__c(
                    Lead__c = leadId, Subject__c = subject, Due_Date__c = dueDate,
                    Status__c = 'Pending', Assigned_To__c = lead.Owner__c
                );
            }
            when 'Closed Lost' {
                String reason = (String) params.get('lostReason');
                if (String.isBlank(reason)) {
                    throw new SalesException('Reason is required for Closed Lost.');
                }
                lead.Lost_Reason__c = reason;
                List<Followup__c> fus = [SELECT Id FROM Followup__c WHERE Lead__c = :leadId AND Status__c = 'Pending'];
                for (Followup__c fu : fus) fu.Status__c = 'Cancelled';
                if (!fus.isEmpty()) update fus;
                List<Site_Visit__c> svs = [SELECT Id FROM Site_Visit__c WHERE Lead__c = :leadId AND Status__c = 'Scheduled'];
                for (Site_Visit__c sv : svs) sv.Status__c = 'Cancelled';
                if (!svs.isEmpty()) update svs;
                List<User> admins = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = true LIMIT 1];
                if (!admins.isEmpty()) lead.Owner__c = admins[0].Id;
            }
        }

        lead.Lead_Status__c = newStatus;
        update lead;
    }

    public class SalesException extends Exception {}
}