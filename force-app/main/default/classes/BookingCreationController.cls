/**
 * @description Controller for the Create Booking from Cost Sheet LWC quick action.
 *              Uses Project_Calculation_Template__c / Calculation_Step__c
 *              to run formula-based calculations from Cost Sheet to Booking.
 */
public with sharing class BookingCreationController {

    /**
     * @description Fetch cost sheet context: cost sheet data, calculation template info,
     *              and lead context for pre-populating the booking form.
     */
    @AuraEnabled
    public static Map<String, Object> getCostSheetContext(Id costSheetId) {
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet ID is required.');
        }

        // 1. Describe all accessible fields on Cost_Sheet__c
        Map<String, Schema.SObjectField> csFieldMap =
            Schema.SObjectType.Cost_Sheet__c.fields.getMap();
        List<String> csFields = new List<String>();
        for (String f : csFieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = csFieldMap.get(f).getDescribe();
            if (dfr.isAccessible()) {
                csFields.add(dfr.getName());
            }
        }

        String soql = 'SELECT ' + String.join(csFields, ', ')
                     + ' FROM Cost_Sheet__c WHERE Id = :costSheetId LIMIT 1';
        List<Cost_Sheet__c> sheets = Database.query(soql);
        if (sheets.isEmpty()) {
            throw new AuraHandledException('Cost Sheet not found.');
        }
        Cost_Sheet__c cs = sheets[0];

        // 2. Get active Project Calculation Template for Cost_Sheet__c -> Booking__c
        List<Project_Calculation_Template__c> templates = new List<Project_Calculation_Template__c>();
        if (cs.Project__c != null) {
            templates = [
                SELECT Id, Template_Name__c,
                       (SELECT Id, Step_Number__c, Store_In_Field__c
                        FROM Calculation_Steps__r
                        WHERE Is_Active__c = true
                        ORDER BY Step_Number__c ASC)
                FROM Project_Calculation_Template__c
                WHERE Project__c = :cs.Project__c
                  AND Source_Object_API_Name__c = 'Cost_Sheet__c'
                  AND Target_Object_API_Name__c = 'Booking__c'
                  AND Is_Active__c = true
                LIMIT 1
            ];
        }

        // 3. Build calculation step info for display
        List<Map<String, String>> calculationSteps = new List<Map<String, String>>();
        if (!templates.isEmpty()) {
            for (Calculation_Step__c step : templates[0].Calculation_Steps__r) {
                calculationSteps.add(new Map<String, String>{
                    'stepNumber' => String.valueOf(step.Step_Number__c),
                    'targetField' => step.Store_In_Field__c
                });
            }
        }

        // 4. Get lead info for pre-population
        Map<String, Object> leadInfo = new Map<String, Object>();
        if (cs.Lead__c != null) {
            List<Lead__c> leads = [
                SELECT Id, Name, Full_Name__c, Primary_Email__c,
                       Primary_Mobile__c, Project__c, Project__r.Name
                FROM Lead__c
                WHERE Id = :cs.Lead__c
                LIMIT 1
            ];
            if (!leads.isEmpty()) {
                Lead__c ld = leads[0];
                leadInfo.put('leadId', ld.Id);
                leadInfo.put('leadName', ld.Full_Name__c != null ? ld.Full_Name__c : ld.Name);
                leadInfo.put('email', ld.Primary_Email__c);
                leadInfo.put('phone', ld.Primary_Mobile__c);
                leadInfo.put('mobile', ld.Primary_Mobile__c);
            }
        }

        // 5. Get Project & Unit names for review display
        String projectName = '';
        String unitName = '';
        String towerName = '';
        if (cs.Project__c != null) {
            List<Project__c> projects = [SELECT Id, Name FROM Project__c WHERE Id = :cs.Project__c LIMIT 1];
            if (!projects.isEmpty()) {
                projectName = projects[0].Name;
            }
        }
        if (cs.Unit__c != null) {
            List<Unit__c> units = [SELECT Id, Name, Tower__c, Tower__r.Name FROM Unit__c WHERE Id = :cs.Unit__c LIMIT 1];
            if (!units.isEmpty()) {
                unitName = units[0].Name;
                if (units[0].Tower__c != null) {
                    towerName = units[0].Tower__r.Name;
                }
            }
        }

        // 6. Build context response
        Map<String, Object> result = new Map<String, Object>();
        result.put('costSheetId', cs.Id);
        result.put('costSheetName', cs.Name);
        result.put('projectId', cs.Project__c);
        result.put('projectName', projectName);
        result.put('unitId', cs.Unit__c);
        result.put('unitName', unitName);
        result.put('towerName', towerName);
        result.put('leadId', cs.Lead__c);
        result.put('agreementValue', cs.get('Agreement_Value__c'));
        result.put('calculationSteps', calculationSteps);
        result.put('leadInfo', leadInfo);
        result.put('hasCalculationTemplate', !templates.isEmpty());
        result.put('templateName', !templates.isEmpty() ? templates[0].Template_Name__c : '');
        // Keep backward-compatible keys for LWC
        result.put('mappingDetails', calculationSteps);
        result.put('hasMappingConfig', !templates.isEmpty());
        return result;
    }

    /**
     * @description Create Booking record with Project Calculation Template + Co-Applicants.
     *              After inserting the Booking, runs FormulaCalculationService to apply
     *              calculation steps from the active template.
     * @param costSheetId The source Cost Sheet
     * @param bookingDataJson JSON with user-entered booking field values
     * @param coApplicantsJson JSON array of co-applicant records
     * @return The newly created Booking Id
     */
    @AuraEnabled
    public static Id createBooking(Id costSheetId, String bookingDataJson, String coApplicantsJson) {
        if (costSheetId == null) {
            throw new AuraHandledException('Cost Sheet ID is required.');
        }

        // 1. Parse user-entered booking data
        Map<String, Object> bookingData =
            (Map<String, Object>) JSON.deserializeUntyped(bookingDataJson);

        // 2. Get Cost Sheet with all accessible fields
        Map<String, Schema.SObjectField> csFieldMap =
            Schema.SObjectType.Cost_Sheet__c.fields.getMap();
        List<String> csFields = new List<String>();
        for (String f : csFieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = csFieldMap.get(f).getDescribe();
            if (dfr.isAccessible()) {
                csFields.add(dfr.getName());
            }
        }
        String soql = 'SELECT ' + String.join(csFields, ', ')
                     + ' FROM Cost_Sheet__c WHERE Id = :costSheetId LIMIT 1';
        List<Cost_Sheet__c> sheets = Database.query(soql);
        if (sheets.isEmpty()) {
            throw new AuraHandledException('Cost Sheet not found.');
        }
        Cost_Sheet__c cs = sheets[0];

        // 3. Create Booking record
        Booking__c booking = new Booking__c();

        // Set core relationship fields
        booking.Cost_Sheet__c = costSheetId;
        if (cs.Project__c != null) booking.Project__c = cs.Project__c;
        if (cs.Unit__c != null) booking.Unit__c = cs.Unit__c;
        if (cs.Lead__c != null) booking.Lead__c = cs.Lead__c;

        // 4. Apply user-entered fields
        Map<String, Schema.SObjectField> bookingFieldMap =
            Schema.SObjectType.Booking__c.fields.getMap();

        for (String fieldName : bookingData.keySet()) {
            Object val = bookingData.get(fieldName);
            if (val == null) continue;

            Schema.SObjectField sField = bookingFieldMap.get(fieldName.toLowerCase());
            if (sField == null) {
                sField = bookingFieldMap.get(NamespaceUtil.qualify(fieldName).toLowerCase());
            }
            if (sField == null) continue;

            Schema.DescribeFieldResult dfr = sField.getDescribe();
            if (!dfr.isCreateable()) continue;

            try {
                booking.put(sField, convertValue(val, dfr.getType()));
            } catch (Exception e) {
                System.debug('Field set error: ' + fieldName + ': ' + e.getMessage());
            }
        }

        // Ensure required defaults
        if (booking.Booking_Stage__c == null) {
            booking.Booking_Stage__c = 'New';
        }

        insert booking;

        // 5. Run Project Calculation Template (Cost_Sheet__c -> Booking__c)
        try {
            FormulaCalculationService.FlowInput input = new FormulaCalculationService.FlowInput();
            input.targetRecordId = booking.Id;
            List<FormulaCalculationService.FlowOutput> calcResults =
                FormulaCalculationService.calculateFromFlow(
                    new List<FormulaCalculationService.FlowInput>{ input }
                );
            if (!calcResults.isEmpty() && !calcResults[0].success) {
                System.debug('Calculation template info: ' + calcResults[0].errorMessage);
            }
        } catch (Exception e) {
            System.debug('Calculation template error: ' + e.getMessage());
        }

        // 6. Create Co-Applicant records
        if (String.isNotBlank(coApplicantsJson)) {
            List<Object> coAppList =
                (List<Object>) JSON.deserializeUntyped(coApplicantsJson);

            List<Co_Applicants__c> coApplicants = new List<Co_Applicants__c>();
            Map<String, Schema.SObjectField> coAppFieldMap =
                Schema.SObjectType.Co_Applicants__c.fields.getMap();

            for (Object item : coAppList) {
                Map<String, Object> coData = (Map<String, Object>) item;
                Co_Applicants__c coApp = new Co_Applicants__c();
                coApp.Booking__c = booking.Id;

                for (String fieldName : coData.keySet()) {
                    Object val = coData.get(fieldName);
                    if (val == null || fieldName == 'key') continue;

                    Schema.SObjectField sField = coAppFieldMap.get(fieldName.toLowerCase());
                    if (sField == null) {
                        sField = coAppFieldMap.get(NamespaceUtil.qualify(fieldName).toLowerCase());
                    }
                    if (sField == null) continue;

                    Schema.DescribeFieldResult dfr = sField.getDescribe();
                    if (!dfr.isCreateable()) continue;

                    try {
                        coApp.put(sField, convertValue(val, dfr.getType()));
                    } catch (Exception e) {
                        System.debug('Co-applicant field error: ' + fieldName + ': ' + e.getMessage());
                    }
                }

                coApplicants.add(coApp);
            }

            if (!coApplicants.isEmpty()) {
                insert coApplicants;
            }
        }

        // 7. Update Unit status to Booked
        if (cs.Unit__c != null) {
            try {
                Unit__c unit = new Unit__c(Id = cs.Unit__c, Status__c = 'Booked');
                update unit;
            } catch (Exception e) {
                System.debug('Unit status update error: ' + e.getMessage());
            }
        }

        // 7b. Update Cost Sheet status to Converted and tag with Booking
        try {
            Cost_Sheet__c csToUpdate = new Cost_Sheet__c(Id = costSheetId, Status__c = 'Converted', Booking__c = booking.Id);
            update csToUpdate;
        } catch (Exception e) {
            System.debug('Cost Sheet status update error: ' + e.getMessage());
        }

        // 8. Copy CS_Payment_Line__c → Payment_Schedule__c
        //    Payment_Schedule__c is MasterDetail to Booking__c, so we can only
        //    create these now that the Booking exists.
        try {
            List<CS_Payment_Line__c> csLines = [
                SELECT Milestone_Name__c, Payment_Pct__c, Amount__c, Due_Date__c,
                       Sequence__c, Category__c, Status__c
                FROM CS_Payment_Line__c
                WHERE Cost_Sheet__c = :costSheetId
                ORDER BY Sequence__c ASC
            ];

            List<Payment_Schedule__c> paySchedules = new List<Payment_Schedule__c>();
            for (CS_Payment_Line__c line : csLines) {
                Payment_Schedule__c ps = new Payment_Schedule__c();
                ps.Booking__c = booking.Id;
                ps.Milestone_Name__c = line.Milestone_Name__c;
                ps.Percentage__c = line.Payment_Pct__c;
                ps.Amount__c = line.Amount__c != null ? line.Amount__c : 0;
                ps.Due_Date__c = line.Due_Date__c;
                ps.Sequence__c = line.Sequence__c;
                ps.Status__c = 'Pending';
                paySchedules.add(ps);
            }
            if (!paySchedules.isEmpty()) {
                insert paySchedules;
            }
        } catch (Exception e) {
            System.debug('Payment Schedule creation error: ' + e.getMessage());
        }

        return booking.Id;
    }

    /**
     * @description Convert a JSON-deserialized value to the appropriate Apex type for the target field.
     */
    private static Object convertValue(Object val, Schema.DisplayType fieldType) {
        if (val == null) return null;
        String strVal = String.valueOf(val);

        switch on fieldType {
            when DATE {
                return Date.valueOf(strVal);
            }
            when DATETIME {
                return Datetime.valueOf(strVal);
            }
            when DOUBLE, CURRENCY, PERCENT {
                return Decimal.valueOf(strVal);
            }
            when INTEGER {
                return Integer.valueOf(strVal);
            }
            when BOOLEAN {
                return Boolean.valueOf(strVal);
            }
            when else {
                return strVal;
            }
        }
    }
}