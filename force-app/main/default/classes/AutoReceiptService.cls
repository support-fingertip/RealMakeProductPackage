/**
 * @description Invocable Apex service called from Record-Triggered Flow on Booking__c (After Insert).
 *              Automatically creates a Receipt__c and Receipt_Line_Item__c when a Booking is created,
 *              based on Post_Sales_Configuration__c where Configuration_Type__c = 'Booking'
 *              and Receipt_Creation_Mode__c = 'Auto'.
 *              This service should be invoked AFTER PaymentScheduleGeneratorService so that
 *              Payment Schedule records already exist for line item allocation.
 * @author System
 * @date 2026-04-01
 */
public with sharing class AutoReceiptService {

    /**
     * @description Flow input wrapper
     */
    public class FlowInput {
        @InvocableVariable(required=true label='Booking Id')
        public Id bookingId;
    }

    /**
     * @description Inner class to deserialize receipt field mapping JSON entries.
     */
    private class FieldMappingEntry {
        public String bookingField;
        public String receiptField;
    }

    /**
     * @description Main entry point called from Flows.
     *              Creates Receipts and Receipt Line Items for each Booking when auto-receipt is configured.
     */
    @InvocableMethod(label='Auto-Create Receipt for Booking' description='Creates a Receipt and Receipt Line Item from the Booking configuration when Receipt_Creation_Mode is Auto' category='Financial')
    public static void createReceipts(List<FlowInput> inputs) {
        Set<Id> bookingIds = new Set<Id>();
        for (FlowInput input : inputs) {
            if (input.bookingId != null) {
                bookingIds.add(input.bookingId);
            }
        }

        if (bookingIds.isEmpty()) return;

        createReceiptsForBookings(bookingIds);
    }

    /**
     * @description Core logic that creates Receipt and Receipt Line Item records.
     *              1. Resolves the 'Booking' type Post_Sales_Configuration__c
     *              2. Checks if Receipt_Creation_Mode__c = 'Auto'
     *              3. Queries Booking records with the configured amount field (dynamic SOQL)
     *              4. Creates Receipt__c records with configured field mappings
     *              5. Creates Receipt_Line_Item__c allocated to the first Payment Schedule
     */
    public static void createReceiptsForBookings(Set<Id> bookingIds) {
        // Step 1: Query the active Booking configuration with receipt-specific fields
        List<Post_Sales_Configuration__c> configs = [
            SELECT Id, Configuration_Type__c, Receipt_Creation_Mode__c,
                   Receipt_Amount_Field__c, Receipt_Field_Mapping__c
            FROM Post_Sales_Configuration__c
            WHERE Configuration_Type__c = 'Booking'
            AND Is_Active__c = true
            LIMIT 1
        ];

        if (configs.isEmpty()) return;

        Post_Sales_Configuration__c config = configs[0];

        // Step 2: Check if auto-receipt creation is enabled
        if (config.Receipt_Creation_Mode__c != 'Auto') return;

        // Determine the amount field to read from Booking
        String amountField = String.isNotBlank(config.Receipt_Amount_Field__c)
            ? String.escapeSingleQuotes(config.Receipt_Amount_Field__c)
            : 'Grand_Total__c';

        // Parse field mappings if configured
        List<FieldMappingEntry> fieldMappings = new List<FieldMappingEntry>();
        Set<String> bookingFieldsToQuery = new Set<String>{ 'Id', amountField.toLowerCase() };

        if (String.isNotBlank(config.Receipt_Field_Mapping__c)) {
            try {
                fieldMappings = (List<FieldMappingEntry>) JSON.deserialize(
                    config.Receipt_Field_Mapping__c, List<FieldMappingEntry>.class
                );
                for (FieldMappingEntry mapping : fieldMappings) {
                    if (String.isNotBlank(mapping.bookingField)) {
                        bookingFieldsToQuery.add(String.escapeSingleQuotes(mapping.bookingField.toLowerCase()));
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'AutoReceiptService: Failed to parse Receipt_Field_Mapping__c: ' + e.getMessage());
            }
        }

        // Step 3: Query Booking records using dynamic SOQL to include the configurable amount field
        String fieldList = String.join(new List<String>(bookingFieldsToQuery), ', ');
        String query = 'SELECT ' + fieldList +
            ' FROM Booking__c WHERE Id IN :bookingIds';

        List<Booking__c> bookings;
        try {
            bookings = Database.query(query);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AutoReceiptService: Dynamic query failed: ' + e.getMessage());
            return;
        }

        if (bookings.isEmpty()) return;

        // Step 4: Create Receipt records
        List<Receipt__c> receiptsToInsert = new List<Receipt__c>();
        Map<Id, Decimal> bookingAmountMap = new Map<Id, Decimal>();

        for (Booking__c booking : bookings) {
            Decimal receiptAmount = 0;
            Object amountValue = booking.get(amountField);
            if (amountValue != null) {
                receiptAmount = (Decimal) amountValue;
            }

            Receipt__c receipt = new Receipt__c();
            receipt.Booking__c = booking.Id;
            receipt.Amount_received__c = receiptAmount;
            receipt.Receipt_Date__c = Date.today();
            receipt.Receipt_Type__c = 'Booking Amount';
            receipt.Status__c = 'Received';

            // Apply field mappings from configuration
            for (FieldMappingEntry mapping : fieldMappings) {
                if (String.isNotBlank(mapping.bookingField) && String.isNotBlank(mapping.receiptField)) {
                    try {
                        Object fieldValue = booking.get(mapping.bookingField);
                        receipt.put(mapping.receiptField, fieldValue);
                    } catch (Exception e) {
                        System.debug(LoggingLevel.WARN, 'AutoReceiptService: Failed to map field ' +
                            mapping.bookingField + ' -> ' + mapping.receiptField + ': ' + e.getMessage());
                    }
                }
            }

            receiptsToInsert.add(receipt);
            bookingAmountMap.put(booking.Id, receiptAmount);
        }

        if (receiptsToInsert.isEmpty()) return;

        try {
            insert receiptsToInsert;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'AutoReceiptService: Failed to insert receipts: ' + e.getMessage());
            return;
        }

        // Step 5: Query first Payment Schedule for each Booking (lowest Sequence)
        Map<Id, Payment_Schedule__c> bookingToFirstSchedule = new Map<Id, Payment_Schedule__c>();
        List<Payment_Schedule__c> schedules = [
            SELECT Id, Booking__c, Sequence__c
            FROM Payment_Schedule__c
            WHERE Booking__c IN :bookingIds
            ORDER BY Sequence__c ASC
        ];

        for (Payment_Schedule__c ps : schedules) {
            if (!bookingToFirstSchedule.containsKey(ps.Booking__c)) {
                bookingToFirstSchedule.put(ps.Booking__c, ps);
            }
        }

        // Step 6: Create Receipt Line Items allocated to the first schedule
        List<Receipt_Line_Item__c> lineItemsToInsert = new List<Receipt_Line_Item__c>();

        for (Receipt__c receipt : receiptsToInsert) {
            Payment_Schedule__c firstSchedule = bookingToFirstSchedule.get(receipt.Booking__c);
            if (firstSchedule == null) continue;

            Decimal amount = bookingAmountMap.get(receipt.Booking__c);

            Receipt_Line_Item__c lineItem = new Receipt_Line_Item__c();
            lineItem.Receipt__c = receipt.Id;
            lineItem.Payment_Schedule__c = firstSchedule.Id;
            lineItem.Booking__c = receipt.Booking__c;
            lineItem.Allocated_Amount__c = amount;
            lineItem.Line_Item_Type__c = 'Principal';

            lineItemsToInsert.add(lineItem);
        }

        if (!lineItemsToInsert.isEmpty()) {
            try {
                insert lineItemsToInsert;
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'AutoReceiptService: Failed to insert receipt line items: ' + e.getMessage());
            }
        }
    }
}