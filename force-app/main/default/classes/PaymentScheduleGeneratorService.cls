/**
 * @description Invocable Apex service called from Record-Triggered Flow on Booking__c (After Insert).
 *              Reads Payment Schedule configuration from Post_Sales_Configuration__c to determine
 *              which source object to copy from and how to match to the booking.
 *              Falls back to hardcoded defaults if no config exists.
 * @author System
 * @date 2026-03-15
 */
public with sharing class PaymentScheduleGeneratorService {

    // Default values (used when no config exists)
    private static final String DEFAULT_SOURCE_OBJECT = 'Master_Payment_Schedule__c';
    private static final String DEFAULT_SOURCE_PARENT = 'Project__c';
    private static final String DEFAULT_BOOKING_PARENT = 'Project__c';

    /**
     * @description Flow input wrapper
     */
    public class FlowInput {
        @InvocableVariable(required=true label='Booking Id')
        public Id bookingId;
    }

    @InvocableMethod(label='Generate Payment Schedules for Booking' description='Creates Payment Schedule records from configured source for a new Booking' category='Financial')
    public static void generateSchedules(List<FlowInput> inputs) {
        Set<Id> bookingIds = new Set<Id>();
        for (FlowInput input : inputs) {
            if (input.bookingId != null) {
                bookingIds.add(input.bookingId);
            }
        }

        if (bookingIds.isEmpty()) return;

        generateForBookings(bookingIds);
    }

    /**
     * @description Core generation logic. Reads config from Post_Sales_Configuration__c
     *              (type = 'Payment Schedule') to determine source object and parent matching.
     */
    public static void generateForBookings(Set<Id> bookingIds) {
        // Load Payment Schedule configuration
        Map<String, Object> creationConfig = loadCreationConfig();
        String sourceParentField = (String) creationConfig.get('sourceParentField');
        String bookingParentField = (String) creationConfig.get('bookingParentField');
        List<Object> fieldMappings = (List<Object>) creationConfig.get('fieldMappings');

        // Step 1: Query Bookings with the configured parent lookup field
        String bookingQuery = 'SELECT Id, Name, ' + bookingParentField + ', Unit__c, Unit__r.Unit_Type__c, '
            + 'Grand_Total__c, Total_Flat_Cost__c, GST_Amount__c, '
            + 'Total_Payable_Amount__c, Payment_Schedules_Created__c '
            + 'FROM Booking__c WHERE Id IN :bookingIds AND Payment_Schedules_Created__c = false';

        List<Booking__c> bookings = Database.query(bookingQuery);
        if (bookings.isEmpty()) return;

        // Collect parent IDs from the configured field
        Set<Id> parentIds = new Set<Id>();
        Map<Id, Booking__c> bookingMap = new Map<Id, Booking__c>();
        for (Booking__c b : bookings) {
            Id parentId = (Id) b.get(bookingParentField);
            if (parentId != null) {
                parentIds.add(parentId);
            }
            bookingMap.put(b.Id, b);
        }

        if (parentIds.isEmpty()) return;

        // Build the set of source fields to query (defaults + mapped fields)
        Set<String> sourceFields = new Set<String>{
            'Id', 'Name', sourceParentField, 'Sequence__c', 'Percentage__c',
            'Payment_Type__c', 'Status__c', 'Is_Active__c',
            'Days_After_Booking__c', 'Days_After_Previous__c',
            'Applicable_For__c', 'Description__c', 'Milestone_Description__c'
        };
        // Add any additional source fields from field mappings
        for (Object mObj : fieldMappings) {
            Map<String, Object> m = (Map<String, Object>) mObj;
            String sf = (String) m.get('sourceField');
            if (String.isNotBlank(sf)) sourceFields.add(sf);
        }

        // Step 2: Query Master Payment Schedules using configured parent field
        String masterQuery = 'SELECT ' + String.join(new List<String>(sourceFields), ', ')
            + ' FROM Master_Payment_Schedule__c '
            + 'WHERE ' + sourceParentField + ' IN :parentIds '
            + 'AND Is_Active__c = true '
            + 'ORDER BY Sequence__c ASC';

        List<Master_Payment_Schedule__c> masterSchedules = Database.query(masterQuery);
        if (masterSchedules.isEmpty()) return;

        // Group Master Schedules by parent
        Map<Id, List<Master_Payment_Schedule__c>> masterByParent = new Map<Id, List<Master_Payment_Schedule__c>>();
        for (Master_Payment_Schedule__c ms : masterSchedules) {
            Id parentId = (Id) ms.get(sourceParentField);
            if (!masterByParent.containsKey(parentId)) {
                masterByParent.put(parentId, new List<Master_Payment_Schedule__c>());
            }
            masterByParent.get(parentId).add(ms);
        }

        // Step 3: Create Payment Schedules for each Booking
        List<Payment_Schedule__c> schedulesToInsert = new List<Payment_Schedule__c>();
        List<Booking__c> bookingsToUpdate = new List<Booking__c>();

        for (Booking__c booking : bookings) {
            Id parentId = (Id) booking.get(bookingParentField);
            if (parentId == null) continue;

            List<Master_Payment_Schedule__c> masters = masterByParent.get(parentId);
            if (masters == null || masters.isEmpty()) continue;

            Decimal totalPayable = booking.Grand_Total__c != null ? booking.Grand_Total__c : 0;
            if (totalPayable == 0 && booking.Total_Flat_Cost__c != null) {
                totalPayable = booking.Total_Flat_Cost__c + (booking.GST_Amount__c != null ? booking.GST_Amount__c : 0);
            }

            Decimal baseAmount = booking.Total_Flat_Cost__c != null ? booking.Total_Flat_Cost__c : totalPayable;
            Decimal gstTotal = booking.GST_Amount__c != null ? booking.GST_Amount__c : 0;

            String unitType = booking.Unit__r != null ? booking.Unit__r.Unit_Type__c : null;

            List<Master_Payment_Schedule__c> applicableMasters = new List<Master_Payment_Schedule__c>();
            for (Master_Payment_Schedule__c ms : masters) {
                if (String.isBlank(ms.Applicable_For__c) || String.isBlank(unitType) ||
                    ms.Applicable_For__c.contains(unitType)) {
                    applicableMasters.add(ms);
                }
            }

            if (applicableMasters.isEmpty()) continue;

            Date bookingDate = Date.today();

            for (Master_Payment_Schedule__c ms : applicableMasters) {
                Payment_Schedule__c ps = new Payment_Schedule__c();
                ps.Booking__c = booking.Id;
                ps.Master_Payment_Schedule__c = ms.Id;
                ps.Is_Milestone_Based__c = true;
                ps.Status__c = 'Pending';
                ps.Demand_Raised__c = false;

                // Apply field mappings from config
                if (!fieldMappings.isEmpty()) {
                    for (Object mObj : fieldMappings) {
                        Map<String, Object> m = (Map<String, Object>) mObj;
                        String sf = (String) m.get('sourceField');
                        String tf = (String) m.get('targetField');
                        if (String.isNotBlank(sf) && String.isNotBlank(tf)) {
                            try {
                                ps.put(tf, ms.get(sf));
                            } catch (Exception e) {
                                System.debug('Field mapping error: ' + sf + ' -> ' + tf + ': ' + e.getMessage());
                            }
                        }
                    }
                } else {
                    // Default mappings when no config
                    ps.Sequence__c = ms.Sequence__c;
                    ps.S_No__c = ms.Sequence__c;
                    ps.Percentage__c = ms.Percentage__c;
                    ps.Milestone_Name__c = ms.Payment_Type__c;
                    ps.Description__c = ms.Description__c;
                }

                Decimal percentage = ms.Percentage__c != null ? ms.Percentage__c : 0;
                Decimal scheduleTotal = (totalPayable * percentage / 100).setScale(0, System.RoundingMode.HALF_UP);
                Decimal scheduleBase = (baseAmount * percentage / 100).setScale(0, System.RoundingMode.HALF_UP);
                Decimal scheduleGst = (gstTotal * percentage / 100).setScale(0, System.RoundingMode.HALF_UP);

                ps.Amount__c = scheduleTotal;
                ps.Payment_Schedule_Amount__c = scheduleBase;
                ps.GST_Amount__c = scheduleGst;
                ps.Pending_Amount__c = scheduleTotal;
                ps.Payment_Schedule_Amount_Pending__c = scheduleBase;
                ps.GST_Amount_Pending__c = scheduleGst;
                ps.Amount_Paid__c = 0;
                ps.Payment_Schedule_Amount_Paid__c = 0;
                ps.GST_Amount_Paid__c = 0;

                if (ms.Days_After_Booking__c != null && ms.Days_After_Booking__c > 0) {
                    ps.Due_Date__c = bookingDate.addDays(Integer.valueOf(ms.Days_After_Booking__c));
                } else if (ms.Days_After_Previous__c != null && ms.Days_After_Previous__c > 0) {
                    ps.Due_Date__c = bookingDate.addDays(Integer.valueOf(ms.Days_After_Previous__c));
                }

                schedulesToInsert.add(ps);
            }

            Booking__c bookingUpdate = new Booking__c();
            bookingUpdate.Id = booking.Id;
            bookingUpdate.Payment_Schedules_Created__c = true;
            if (totalPayable > 0) {
                bookingUpdate.Total_Payable_Amount__c = totalPayable;
            }
            bookingsToUpdate.add(bookingUpdate);
        }

        if (!schedulesToInsert.isEmpty()) {
            insert schedulesToInsert;
        }

        if (!bookingsToUpdate.isEmpty()) {
            update bookingsToUpdate;
        }
    }

    /**
     * Load creation config from Post_Sales_Configuration__c (type = 'Payment Schedule').
     * Returns sourceParentField, bookingParentField, and fieldMappings.
     */
    private static Map<String, Object> loadCreationConfig() {
        Map<String, Object> config = new Map<String, Object>{
            'sourceParentField' => DEFAULT_SOURCE_PARENT,
            'bookingParentField' => DEFAULT_BOOKING_PARENT,
            'fieldMappings' => new List<Object>()
        };

        try {
            List<Post_Sales_Configuration__c> configs = [
                SELECT Reminder_Config__c
                FROM Post_Sales_Configuration__c
                WHERE Configuration_Type__c = 'Payment Schedule'
                AND Is_Active__c = true
                LIMIT 1
            ];

            if (!configs.isEmpty() && String.isNotBlank(configs[0].Reminder_Config__c)) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(configs[0].Reminder_Config__c);
                String sp = (String) parsed.get('sourceParentField');
                String bp = (String) parsed.get('bookingParentField');
                if (String.isNotBlank(sp)) config.put('sourceParentField', sp);
                if (String.isNotBlank(bp)) config.put('bookingParentField', bp);

                List<Object> mappings = (List<Object>) parsed.get('fieldMappings');
                if (mappings != null && !mappings.isEmpty()) {
                    config.put('fieldMappings', mappings);
                }
            }
        } catch (Exception e) {
            System.debug('Error loading Payment Schedule config, using defaults: ' + e.getMessage());
        }

        return config;
    }
}