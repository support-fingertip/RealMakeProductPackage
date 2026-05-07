/**
 * @description Service to auto-apply approved Credit Notes against newly raised Demands.
 *              When a demand is created, this service checks for approved credit notes
 *              with available balance on the same booking, creates Credit_Note_Line_Item__c
 *              records linking demand + credit note + payment schedule, and updates
 *              the demand's Credit_Applied_Amount__c and the credit note's Available_Amount__c.
 * @author System
 * @date 2026-03-30
 */
public with sharing class CreditNoteApplicationService {

    /**
     * @description Flow input wrapper for invocable method
     */
    public class FlowInput {
        @InvocableVariable(required=true label='Demand Id')
        public Id demandId;
    }

    /**
     * @description Flow output wrapper
     */
    public class FlowOutput {
        @InvocableVariable(label='Total Credit Applied')
        public Decimal totalCreditApplied;

        @InvocableVariable(label='Number of Credit Notes Applied')
        public Integer creditNotesApplied;
    }

    /**
     * @description Invocable entry point callable from Flows
     */
    @InvocableMethod(label='Apply Credit Notes to Demand' description='Auto-applies approved credit notes with available balance against a demand' category='Financial')
    public static List<FlowOutput> applyCreditsFromFlow(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();
        List<Id> demandIds = new List<Id>();

        for (FlowInput input : inputs) {
            if (input.demandId != null) {
                demandIds.add(input.demandId);
            }
        }

        Map<Id, FlowOutput> resultMap = applyCreditsToNewDemands(demandIds);

        for (FlowInput input : inputs) {
            if (resultMap.containsKey(input.demandId)) {
                outputs.add(resultMap.get(input.demandId));
            } else {
                FlowOutput out = new FlowOutput();
                out.totalCreditApplied = 0;
                out.creditNotesApplied = 0;
                outputs.add(out);
            }
        }

        return outputs;
    }

    /**
     * @description Apply available credit notes to a list of newly created demands.
     *              Called from BulkDemandController after demands are inserted.
     * @param demandIds List of demand IDs to apply credits against
     */
    public static void applyCredits(List<Id> demandIds) {
        applyCreditsToNewDemands(demandIds);
    }

    /**
     * @description Core logic: for each demand, find approved credit notes on that booking
     *              with Available_Amount__c > 0, create Credit_Note_Line_Item__c records,
     *              and update both demand and credit note amounts.
     * @param demandIds List of demand IDs
     * @return Map of demand ID to FlowOutput with results
     */
    private static Map<Id, FlowOutput> applyCreditsToNewDemands(List<Id> demandIds) {
        Map<Id, FlowOutput> resultMap = new Map<Id, FlowOutput>();

        if (demandIds == null || demandIds.isEmpty()) {
            return resultMap;
        }

        // Query demands with their booking and payment schedule info
        List<Demands__c> demands = [
            SELECT Id, Booking__c, Payment_Schedule__c, Demand_Amount__c,
                   Credit_Applied_Amount__c, Status__c
            FROM Demands__c
            WHERE Id IN :demandIds
            AND Status__c != 'Cancelled'
        ];

        if (demands.isEmpty()) {
            return resultMap;
        }

        // Collect booking IDs
        Set<Id> bookingIds = new Set<Id>();
        for (Demands__c d : demands) {
            bookingIds.add(d.Booking__c);
        }

        // Query approved credit notes with available balance, ordered by priority then date
        List<Credit_Note__c> creditNotes = [
            SELECT Id, Booking__c, Credit_Amount__c, Available_Amount__c,
                   Payment_Schedule__c, Apply_To__c, Auto_Apply__c, Priority__c
            FROM Credit_Note__c
            WHERE Booking__c IN :bookingIds
            AND Status__c = :PostSalesConstants.CREDIT_STATUS_APPROVED
            AND Available_Amount__c > 0
            ORDER BY Priority__c ASC NULLS LAST, Credit_Date__c ASC
        ];

        if (creditNotes.isEmpty()) {
            return resultMap;
        }

        // Group credit notes by booking
        Map<Id, List<Credit_Note__c>> creditNotesByBooking = new Map<Id, List<Credit_Note__c>>();
        for (Credit_Note__c cn : creditNotes) {
            if (!creditNotesByBooking.containsKey(cn.Booking__c)) {
                creditNotesByBooking.put(cn.Booking__c, new List<Credit_Note__c>());
            }
            creditNotesByBooking.get(cn.Booking__c).add(cn);
        }

        List<Credit_Note_Line_Item__c> lineItemsToInsert = new List<Credit_Note_Line_Item__c>();
        List<Demands__c> demandsToUpdate = new List<Demands__c>();
        Map<Id, Credit_Note__c> creditNotesToUpdate = new Map<Id, Credit_Note__c>();

        for (Demands__c demand : demands) {
            List<Credit_Note__c> bookingCredits = creditNotesByBooking.get(demand.Booking__c);
            if (bookingCredits == null || bookingCredits.isEmpty()) {
                continue;
            }

            Decimal demandAmount = demand.Demand_Amount__c != null ? demand.Demand_Amount__c : 0;
            Decimal alreadyApplied = demand.Credit_Applied_Amount__c != null ? demand.Credit_Applied_Amount__c : 0;
            Decimal remainingDemand = demandAmount - alreadyApplied;

            if (remainingDemand <= 0) {
                continue;
            }

            Decimal totalCreditApplied = 0;
            Integer creditNotesApplied = 0;

            for (Credit_Note__c cn : bookingCredits) {
                if (remainingDemand <= 0) {
                    break;
                }

                // For Next Demand / Last Demand: only apply if the demand's payment schedule matches
                // the resolved schedule on the credit note
                if ((cn.Apply_To__c == 'Next Demand' || cn.Apply_To__c == 'Last Demand')
                    && cn.Payment_Schedule__c != null
                    && demand.Payment_Schedule__c != null
                    && cn.Payment_Schedule__c != demand.Payment_Schedule__c) {
                    continue;
                }

                // Custom Ly Raised: apply to any demand regardless of payment schedule
                // (no filtering needed - it applies generally)

                // Get current available amount (might have been reduced by earlier demand in this batch)
                Decimal available = cn.Available_Amount__c;
                if (creditNotesToUpdate.containsKey(cn.Id)) {
                    available = creditNotesToUpdate.get(cn.Id).Available_Amount__c;
                }

                if (available <= 0) {
                    continue;
                }

                // Calculate how much to apply
                Decimal applyAmount = Math.min(available, remainingDemand);

                // Create credit note line item
                Credit_Note_Line_Item__c lineItem = new Credit_Note_Line_Item__c();
                lineItem.Credit_Note__c = cn.Id;
                lineItem.Demand__c = demand.Id;
                lineItem.Payment_Schedule__c = demand.Payment_Schedule__c;
                lineItem.Booking__c = demand.Booking__c;
                lineItem.Credit_Amount__c = applyAmount;
                lineItem.Description__c = 'Auto-applied credit note ' + cn.Id + ' against demand';
                lineItemsToInsert.add(lineItem);

                // Track credit note update
                Credit_Note__c cnUpdate;
                if (creditNotesToUpdate.containsKey(cn.Id)) {
                    cnUpdate = creditNotesToUpdate.get(cn.Id);
                } else {
                    cnUpdate = new Credit_Note__c();
                    cnUpdate.Id = cn.Id;
                    cnUpdate.Available_Amount__c = cn.Available_Amount__c;
                }
                cnUpdate.Available_Amount__c = cnUpdate.Available_Amount__c - applyAmount;
                if (cnUpdate.Available_Amount__c <= 0) {
                    cnUpdate.Status__c = 'Fully Applied';
                }
                creditNotesToUpdate.put(cn.Id, cnUpdate);

                remainingDemand -= applyAmount;
                totalCreditApplied += applyAmount;
                creditNotesApplied++;
            }

            if (totalCreditApplied > 0) {
                demand.Credit_Applied_Amount__c = alreadyApplied + totalCreditApplied;
                demandsToUpdate.add(demand);

                FlowOutput output = new FlowOutput();
                output.totalCreditApplied = totalCreditApplied;
                output.creditNotesApplied = creditNotesApplied;
                resultMap.put(demand.Id, output);
            }
        }

        // DML operations
        if (!lineItemsToInsert.isEmpty()) {
            insert lineItemsToInsert;
        }

        if (!creditNotesToUpdate.isEmpty()) {
            update creditNotesToUpdate.values();
        }

        if (!demandsToUpdate.isEmpty()) {
            update demandsToUpdate;
        }

        return resultMap;
    }
}