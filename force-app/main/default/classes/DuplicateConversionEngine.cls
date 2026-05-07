/**
* ENTERPRISE DUPLICATE DETECTION & CONVERSION ENGINE (FINAL CORRECTED)
*
* ACTUAL SCENARIOS:
* 1. No Lead duplicate + No Enquiry duplicate
*    -> Create Lead + Create Enquiry Source (keep both)
*
* 2. Lead duplicate exists
*    -> Create new Lead + Create Enquiry Source + Delete NEW Lead
*    Final: Old Lead remains + Enquiry created + New Lead removed
*
* 3. No Lead duplicate + Enquiry duplicate exists
*    -> Create Lead + Create Enquiry Source + Delete NEW Lead
*    Final: No new Lead + Enquiry created
*
* 4. Both Lead AND Enquiry duplicates exist
*    -> Create Lead + Create Enquiry Source + Delete NEW Lead
*    Final: Old Lead remains + Enquiry created + New Lead removed
*/

public with sharing class DuplicateConversionEngine {

    // Static bypass flag - set to true from controllers (e.g. GRE) that
    // create their own Enquiry Source to prevent duplicate creation.
    public static Boolean skipProcessing = false;

    // ============================================================================
    // MAIN ENTRY POINT - Called from trigger
    // ============================================================================
    public static List<Id> processRecordWithConversion(List<SObject> newRecords, String objectApiName) {
        List<Id> newRecordsToDelete = new List<Id>();
        Map<Id, Id> duplicateMapping = new Map<Id, Id>(); // newLeadId -> existingLeadId

        if (newRecords.isEmpty()) {
            return newRecordsToDelete;
        }

        // Get configuration for this object
        Duplication_Configuration__c config = getConfiguration(objectApiName);
        if (config == null) {
            System.debug(LoggingLevel.WARN, 'No active Duplication_Configuration__c found for: ' + objectApiName + '. Enquiry Source will NOT be created.');
            return newRecordsToDelete; // No configuration, skip
        }

        System.debug('Config found - Primary: ' + config.Primary_Object_API_Name__c
            + ', Related: ' + config.Related_Object_API_Name__c);

        // Get field mappings linked to this duplication configuration
        List<Field_Mapping__c> mappings = getFieldMappings(config.Id);
        System.debug('Field mappings found: ' + mappings.size());

        // Process each record - returns the existing lead Id if duplicate, null otherwise
        for (SObject record : newRecords) {
            Id existingLeadId = processSingleRecord(record, config, mappings);
            if (existingLeadId != null && record.Id != null) {
                newRecordsToDelete.add(record.Id);
                duplicateMapping.put(record.Id, existingLeadId);
            }
        }

        // Set Duplicate_Of__c on duplicate leads so the record-page LWC can
        // redirect the user to the existing lead before async deletion occurs.
        if (!duplicateMapping.isEmpty()) {
            List<Lead__c> leadsToMark = new List<Lead__c>();
            for (Id newId : duplicateMapping.keySet()) {
                leadsToMark.add(new Lead__c(
                    Id = newId,
                    Duplicate_Of__c = duplicateMapping.get(newId)
                ));
            }
            try {
                skipProcessing = true;
                update leadsToMark;
            } catch (Exception e) {
                System.debug('Error setting Duplicate_Of__c: ' + e.getMessage());
            } finally {
                skipProcessing = false;
            }
        }

        return newRecordsToDelete;
    }

    // ============================================================================
    // CORE PROCESSING LOGIC
    // Returns: existing lead Id if duplicate found (caller should delete new lead),
    //          null if no duplicate (caller should keep new lead)
    // ============================================================================
    private static Id processSingleRecord(
        SObject newRecord,
        Duplication_Configuration__c config,
        List<Field_Mapping__c> mappings
    ) {

        String primaryObjectName = config.Primary_Object_API_Name__c;
        String relatedObjectName = config.Related_Object_API_Name__c;
        Boolean hasRelatedObject = String.isNotBlank(relatedObjectName);

        // 1. Find primary duplicates (Lead)
        List<SObject> primaryDuplicates = findDuplicates(
            newRecord,
            config.Primary_Expression__c,
            primaryObjectName,
            null
        );

        // 2. Find related duplicates (Enquiry) - only when related object is configured
        List<SObject> relatedDuplicates = hasRelatedObject
            ? findDuplicates(
                newRecord,
                config.Related_Expression__c,
                relatedObjectName,
                config.Primary_Object_API_Name__c
              )
            : new List<SObject>();

        Id leadToUse;
        Id existingLeadId = null; // Non-null only when a duplicate is found

        // ================================
        // SCENARIO A: Lead duplicate exists
        // ================================
        if (!primaryDuplicates.isEmpty()) {

            leadToUse = primaryDuplicates[0].Id;
            existingLeadId = leadToUse;

            System.debug('Using EXISTING Lead from primary duplicate');

        }

        // ==========================================
        // SCENARIO B: No Lead duplicate, but Enquiry duplicate exists
        // ==========================================
        else if (!relatedDuplicates.isEmpty()) {

            String lookupField = config.Primary_Object_API_Name__c;

            if (String.isNotBlank(lookupField)) {
                leadToUse = (Id) relatedDuplicates[0].get(lookupField);
                existingLeadId = leadToUse;
            }

            System.debug('Using Lead from EXISTING Enquiry');

        }

        // ================================
        // SCENARIO C: No duplicates
        // ================================
        else {

            leadToUse = newRecord.Id;
            existingLeadId = null;

            System.debug('Using NEW Lead');

        }

        // Create related record (e.g. Enquiry) when related object is configured.
        // Mappings may be empty — essential fields (Lead lookup, Enquiry_Date__c,
        // Enquiry_Type__c) are set independently of Field_Mapping__c records.
        System.debug('Enquiry creation check - hasRelatedObject: ' + hasRelatedObject
            + ', relatedObjectName: ' + relatedObjectName
            + ', mappings count: ' + mappings.size()
            + ', leadToUse: ' + leadToUse);
        // Apply Re-engaged / Re-opened logic for Lead duplicates and
        // determine the correct enquiry type based on active/inactive status.
        String resolvedEnquiryType = 'New';
        if (existingLeadId != null) {
            resolvedEnquiryType = applyReengageReopenLogic(newRecord, existingLeadId, config);
        }

        if (hasRelatedObject) {
            createRelatedRecord(newRecord, config, mappings, leadToUse, resolvedEnquiryType);
        }

        return existingLeadId;
    }

    // ============================================================================
    // RE-ENGAGED / RE-OPENED LOGIC FOR UI-INSERTED LEADS
    // ============================================================================
    private static String applyReengageReopenLogic(
        SObject newRecord,
        Id existingLeadId,
        Duplication_Configuration__c config
    ) {
        String primaryObjectName = config.Primary_Object_API_Name__c;

        // Resolve config values with safe fallback defaults so the lead update
        // always executes even when CP_Module_Config__c is not configured.
        String reengagedType = 'Re-engaged';
        String reopenedType = 'Re-opened';
        String defaultStatus = 'New Enquiry';
        String assignmentType = null;
        Set<String> inactiveStatuses = new Set<String>();

        try {
            CP_Module_Config__c cfg = CPModuleConfigService.getConfig();
            if (String.isNotBlank(cfg.Lead_Reengaged_Type__c)) {
                reengagedType = cfg.Lead_Reengaged_Type__c;
            }
            if (String.isNotBlank(cfg.Lead_Reopened_Type__c)) {
                reopenedType = cfg.Lead_Reopened_Type__c;
            }
            if (String.isNotBlank(cfg.Lead_Default_Status__c)) {
                defaultStatus = cfg.Lead_Default_Status__c;
            }
            assignmentType = cfg.Assignment_Type__c;
            inactiveStatuses = CPModuleConfigService.getLeadInactiveStatuses();
        } catch (Exception configEx) {
            System.debug(LoggingLevel.WARN, 'CP_Module_Config not available, using defaults: ' + configEx.getMessage());
        }

        try {
            // Dynamic query using config's primary object
            String query = 'SELECT Id, Lead_Status__c, Is_Active__c, Project__c,'
                + ' Lead_Source__c, Lead_Sub_Source__c'
                + ' FROM ' + String.escapeSingleQuotes(primaryObjectName)
                + ' WHERE Id = :existingLeadId LIMIT 1';
            List<SObject> results = Database.query(query);
            if (results.isEmpty()) return reengagedType;

            SObject existing = results[0];

            // Read source info from the incoming (new) record
            String newSource = (String) newRecord.get('Lead_Source__c');
            String newSubSource = (String) newRecord.get('Lead_Sub_Source__c');

            // Use the Is_Active__c formula field as the source of truth.
            // Fall back to config-based inactive statuses if formula is unavailable.
            Boolean isActive;
            Object isActiveFormula = existing.get('Is_Active__c');
            if (isActiveFormula != null) {
                isActive = (Boolean) isActiveFormula;
            } else {
                String leadStatus = (String) existing.get('Lead_Status__c');
                isActive = !inactiveStatuses.contains(leadStatus);
            }

            if (isActive) {
                // Re-engaged: active duplicate
                existing.put('Lead_Type__c', reengagedType);
                existing.put('Last_Reengaged_Source__c', newSource);
                existing.put('Last_Reengaged_Sub__c', newSubSource);
                existing.put('Last_Reengaged_Date__c',  Date.today());

                try {
                    skipProcessing = true;
                    update existing;
                } finally {
                    skipProcessing = false;
                }

                return reengagedType;
            } else {
                // Re-opened: inactive duplicate — delegate to unified LeadReopenService
                try {
                    skipProcessing = true;
                    system.debug('calling lead reopen from duplicate conversion');
                    LeadReopenService.reopenLead(existingLeadId, newSource, newSubSource);
                    system.debug('called done  lead reopen from duplicate conversion');
                } finally {
                    skipProcessing = false;
                }

                return reopenedType;
            }

        } catch (Exception e) {
            skipProcessing = false;
            System.debug(LoggingLevel.ERROR, 'Re-engage/Re-open logic FAILED: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());

            // If the lead was inactive, still attempt a basic reopen (without RR)
            // so the status and type are correctly updated even if LeadReopenService failed
            try {
                SObject fallbackLead = Database.query(
                    'SELECT Id, Is_Active__c FROM ' + String.escapeSingleQuotes(primaryObjectName)
                    + ' WHERE Id = :existingLeadId LIMIT 1'
                );
                Boolean wasInactive = fallbackLead.get('Is_Active__c') != null
                    && !(Boolean) fallbackLead.get('Is_Active__c');
                if (wasInactive) {
                    fallbackLead.put('Lead_Status__c', defaultStatus);
                    fallbackLead.put('Lead_Type__c', reopenedType);
                    fallbackLead.put('Last_Reopened_Date__c', Date.today());
                    update fallbackLead;
                    return reopenedType;
                }
            } catch (Exception fallbackEx) {
                System.debug(LoggingLevel.ERROR, 'Fallback reopen also failed: ' + fallbackEx.getMessage());
            }

            // Log to error object so admins can investigate why Lead_Type__c was not updated
            try {
                Field_Mapping_Error_Log__c errorLog = new Field_Mapping_Error_Log__c();
                errorLog.Error_Message__c = 'Re-engage/Re-open failed for Lead ' + existingLeadId + ': ' + e.getMessage();
                errorLog.Operation_Type__c = 'Insert';
                errorLog.Source_Record_Id__c = String.valueOf(existingLeadId);
                errorLog.Error_Timestamp__c = DateTime.now();
                insert errorLog;
            } catch (Exception logEx) {
                System.debug(LoggingLevel.ERROR, 'Failed to log re-engage error: ' + logEx.getMessage());
            }

            return reengagedType;
        }
    }

    // ============================================================================
    // DUPLICATE SCENARIO HANDLING - FINAL CORRECTED LOGIC
    // ============================================================================
    private static Boolean handleDuplicateScenarios(
        SObject newRecord,
        List<SObject> primaryDuplicates,
        List<SObject> relatedDuplicates) {

            Boolean hasPrimaryDuplicate = !primaryDuplicates.isEmpty();
            Boolean hasRelatedDuplicate = !relatedDuplicates.isEmpty();

            if (!hasPrimaryDuplicate && !hasRelatedDuplicate) {
                System.debug('SCENARIO 1: No duplicates found. Keeping both Lead and Enquiry Source.');
                return false;

            } else if (hasPrimaryDuplicate && !hasRelatedDuplicate) {
                System.debug('SCENARIO 2: Lead duplicate found. Deleting new Lead, keeping old Lead and Enquiry.');
                return true;

            } else if (!hasPrimaryDuplicate && hasRelatedDuplicate) {
                System.debug('SCENARIO 3: Enquiry duplicate found. Deleting new Lead, keeping Enquiry.');
                return true;

            } else {
                System.debug('SCENARIO 4: Both duplicates found. Deleting new Lead, keeping old Lead and Enquiry.');
                return true;
            }
        }

    // ============================================================================
    // DUPLICATE FINDING LOGIC
    // ============================================================================
    private static List<SObject> findDuplicates(
        SObject record,
        String expression,
        String objectApiName,
        String lookupFieldToSelect
    ) {
        System.debug('================ FIND DUPLICATES START ================');
        System.debug('Object API Name: ' + objectApiName);
        System.debug('Expression from Config: ' + expression);
        System.debug('Lookup field to select: ' + lookupFieldToSelect);
        System.debug('Incoming Record Id: ' + record.Id);
        System.debug('Incoming Record Values: ' + JSON.serialize(record));

        if (String.isBlank(expression) || String.isBlank(objectApiName)) {
            System.debug('Expression or Object API Name is blank. Exiting.');
            return new List<SObject>();
        }

        String whereClause = DuplicationDetectionHelper.buildWhereClauseFromExpression(record, expression);

        System.debug('Generated WHERE Clause: ' + whereClause);

        if (String.isBlank(whereClause)) {
            System.debug('WHERE clause is blank. No duplicate search performed.');
            return new List<SObject>();
        }

        String query = 'SELECT Id';

        // Include lookup field if provided
        if (String.isNotBlank(lookupFieldToSelect)) {
            query += ', ' + lookupFieldToSelect;
        }

        query += ' FROM ' + objectApiName +
            ' WHERE ' + whereClause;

        if (record.Id != null) {
            query += ' AND Id != \'' + record.Id + '\'';
        }

        query += ' LIMIT 50';

        System.debug('Final SOQL Query: ' + query);

        try {
            List<SObject> results = Database.query(query);

            System.debug('Duplicate Records Found Count: ' + results.size());

            for (SObject dup : results) {
                System.debug('Duplicate Record: ' + JSON.serialize(dup));
            }

            System.debug('================ FIND DUPLICATES END =================');
            return results;

        } catch (Exception e) {
            System.debug('ERROR in duplicate query: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            return new List<SObject>();
        }
    }



    // ============================================================================
    // RELATED RECORD CREATION (Dynamic)
    // Creates Enquiry Source from the NEW Lead (before it might be deleted)
    // ============================================================================
    private static SObject createRelatedRecord(
        SObject primaryRecord,
        Duplication_Configuration__c config,
        List<Field_Mapping__c> mappings,
        Id leadToUse,
        String enquiryType
    ) {
        try {

            String relatedObjectName = config.Related_Object_API_Name__c;
            SObject relatedRecord = createDynamicObject(relatedObjectName);

            // Map configured fields
            for (Field_Mapping__c mapping : mappings) {

                String sourceField = mapping.Primary_Object_Field_value__c;
                String targetField = mapping.Related_object_field__c;
                String mappingType = mapping.Mapping_Type__c;

                Object value = mapFieldValue(primaryRecord, sourceField, mappingType, mapping);

                if (value != null) {
                    setFieldValue(relatedRecord, targetField, value);
                }
            }

            // Dynamically link Lead using config
            if (leadToUse != null && String.isNotBlank(config.Primary_Object_API_Name__c)) {
                relatedRecord.put(config.Primary_Object_API_Name__c, leadToUse);
            }

            // Set essential fields that may not be in field mappings.
            // These ensure Enquiry Sources are always created with core data
            // regardless of whether Field_Mapping__c records are configured.
            setFieldValue(relatedRecord, 'Enquiry_Date__c', DateTime.now());
            if (String.isNotBlank(enquiryType)) {
                setFieldValue(relatedRecord, 'Enquiry_Type__c', enquiryType);
            }

            // Source & Project from the Lead record (only if not already set by mappings)
            setIfBlank(relatedRecord, 'Source__c', getFieldValue(primaryRecord, 'Lead_Source__c'));
            setIfBlank(relatedRecord, 'Sub_Source__c', getFieldValue(primaryRecord, 'Lead_Sub_Source__c'));
            setIfBlank(relatedRecord, 'Project__c', getFieldValue(primaryRecord, 'Project__c'));

            // Contact info from the Lead record
            Object mobileVal = getFieldValue(primaryRecord, 'Primary_Mobile__c');
            setIfBlank(relatedRecord, 'Primary_Mobile__c', mobileVal);
            setIfBlank(relatedRecord, 'Secondary_Mobile__c', getFieldValue(primaryRecord, 'Secondary_Mobile__c'));
            Object emailVal = getFieldValue(primaryRecord, 'Primary_Email__c');
            setIfBlank(relatedRecord, 'Primary_Email__c', emailVal);

            insert relatedRecord;

            System.debug('Created related record: ' + relatedRecord.Id);

            return relatedRecord;

        } catch (Exception e) {

            System.debug(LoggingLevel.ERROR, 'CRITICAL: Failed to create Enquiry Source (' + config.Related_Object_API_Name__c + '): ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            System.debug(LoggingLevel.ERROR, 'Lead ID used: ' + leadToUse + ', Enquiry Type: ' + enquiryType);
            System.debug(LoggingLevel.ERROR, 'Mappings count: ' + (mappings != null ? mappings.size() : 0));

            // Log to error object so admins can see failures without checking debug logs
            try {
                Field_Mapping_Error_Log__c errorLog = new Field_Mapping_Error_Log__c();
                errorLog.Error_Message__c = 'Failed to create Enquiry Source: ' + e.getMessage();
                errorLog.Operation_Type__c = 'Insert';
                errorLog.Source_Record_Id__c = String.valueOf(leadToUse);
                errorLog.Error_Timestamp__c = DateTime.now();
                insert errorLog;
            } catch (Exception logEx) {
                System.debug(LoggingLevel.ERROR, 'Failed to log error: ' + logEx.getMessage());
            }

            return null;
        }
    }

    // ============================================================================
    // FIELD MAPPING & TRANSFORMATION
    // ============================================================================
    private static Object mapFieldValue(SObject record,String fieldName,String mappingType,Field_Mapping__c mapping) {
        if (mappingType == 'field') {
            return getFieldValue(record, fieldName);
        }
        else if (mappingType == 'manual') {
            return mapping.Primary_Object_Field_value__c;  // Static value
        }
        return null;
    }

    private static Object getFieldValue(SObject record, String fieldName) {
        try {
            if (fieldName.contains('.')) {
                List<String> parts = fieldName.split('\\.');
                SObject current = record;
                for (Integer i = 0; i < parts.size() - 1; i++) {
                    current = current.getSObject(parts[i]);
                    if (current == null) return null;
                }
                return current.get(parts[parts.size() - 1]);
            }
            return record.get(fieldName);
        } catch (Exception e) {
            System.debug('Error getting field value: ' + e.getMessage());
            return null;
        }
    }

    private static void setFieldValue(SObject record, String fieldName, Object value) {
        try {
            record.put(fieldName, value);
        } catch (Exception e) {
            System.debug('Error setting field value: ' + e.getMessage());
        }
    }

    private static void setIfBlank(SObject record, String fieldName, Object value) {
        if (value == null) return;
        try {
            if (record.get(fieldName) == null) {
                record.put(fieldName, value);
            }
        } catch (Exception e) {
            System.debug('Error in setIfBlank for ' + fieldName + ': ' + e.getMessage());
        }
    }

    // ============================================================================
    // ADVANCED MAPPING TYPES
    // ============================================================================
    private static Object evaluateFormula(SObject record, String formulaExpression) {
        System.debug('Evaluating formula: ' + formulaExpression);
        return formulaExpression; // Placeholder
    }

    private static Object handleLookupMapping(Object sourceValue, Field_Mapping__c mapping) {
        System.debug('Handling lookup mapping for value: ' + sourceValue);
        return sourceValue; // Placeholder
    }

    // ============================================================================
    // LINKING PRIMARY TO RELATED
    // ============================================================================
    private static void linkPrimaryToRelated(
        SObject relatedRecord,
        SObject primaryRecord,
        Duplication_Configuration__c config
    ) {
        try {
            if (primaryRecord.Id == null) {
                return;
            }

            String lookupFieldName = config.Primary_Object_API_Name__c;

            if (String.isNotBlank(lookupFieldName)) {
                relatedRecord.put(lookupFieldName, primaryRecord.Id);
            }

        } catch (Exception e) {
            System.debug('Error linking records dynamically: ' + e.getMessage());
        }
    }

    // ============================================================================
    // CONFIGURATION & METADATA RETRIEVAL
    // ============================================================================
    private static Duplication_Configuration__c getConfiguration(String objectApiName) {
        try {
            List<Duplication_Configuration__c> configs = [
                SELECT Id,
                Primary_Object_API_Name__c,
                Primary_Expression__c,
                Related_Object_API_Name__c,
                Related_Expression__c
                FROM Duplication_Configuration__c
                WHERE Primary_Object_API_Name__c = :objectApiName
                AND Active__c = true
                LIMIT 1
            ];

            return configs.isEmpty() ? null : configs[0];
        } catch (Exception e) {
            System.debug('Error retrieving configuration: ' + e.getMessage());
            return null;
        }
    }

    private static List<Field_Mapping__c> getFieldMappings(Id configId) {
        try {
            return [
                SELECT Id,
                Primary_Object_Field_value__c,
                Related_object_field__c,
                Mapping_Type__c,
                Sequence__c
                FROM Field_Mapping__c
                WHERE Duplication_Configuration__c = :configId
                AND Active__c = true
                ORDER BY Sequence__c ASC
            ];
        } catch (Exception e) {
            System.debug('Error retrieving field mappings: ' + e.getMessage());
            return new List<Field_Mapping__c>();
        }
    }

    private static SObject createDynamicObject(String objectApiName) {
        return (SObject) Type.forName(objectApiName).newInstance();
    }
}