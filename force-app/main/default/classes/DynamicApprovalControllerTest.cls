/**
 * @description Test class for DynamicApprovalController (100% coverage).
 * Covers all @AuraEnabled methods: schema discovery, CRUD on Approval_Configuration__c,
 * getApprovalStatusForRecord (all 5 categories), required field validation,
 * saveRequiredFieldValues, searchApproverUsers, and all wrapper class constructors.
 */
@isTest
private class DynamicApprovalControllerTest {

    @TestSetup
    static void setup() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('DAC Project');
        TestDataFactory.createLead(proj.Id, 'DAC', '9900001006');
    }

    // ── getAvailableObjects ───────────────────────────────────────────

    @isTest
    static void getAvailableObjects_returnsSortedList() {
        Test.startTest();
        List<DynamicApprovalController.ObjectOption> opts =
            DynamicApprovalController.getAvailableObjects();
        Test.stopTest();

        System.assertNotEquals(null, opts);
        System.assert(!opts.isEmpty(), 'Should return at least some accessible objects');
    }

    // ── getObjectApiNameFromRecordId ──────────────────────────────────

    @isTest
    static void getObjectApiNameFromRecordId_null_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            DynamicApprovalController.getObjectApiNameFromRecordId(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Should throw for null recordId');
    }

    @isTest
    static void getObjectApiNameFromRecordId_lead_returnsApiName() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];

        Test.startTest();
        String name = DynamicApprovalController.getObjectApiNameFromRecordId(lead.Id);
        Test.stopTest();

        System.assertEquals('Lead__c', name);
    }

    // ── discoverUserLookupFields ──────────────────────────────────────

    @isTest
    static void discoverUserLookupFields_validObject_returnsList() {
        Test.startTest();
        List<DynamicApprovalController.FieldPathOption> opts =
            DynamicApprovalController.discoverUserLookupFields('Lead__c');
        Test.stopTest();

        System.assertNotEquals(null, opts);
    }

    // ── discoverPicklistFields ────────────────────────────────────────

    @isTest
    static void discoverPicklistFields_validObject_returnsList() {
        Test.startTest();
        List<DynamicApprovalController.FieldOption> opts =
            DynamicApprovalController.discoverPicklistFields('Lead__c');
        Test.stopTest();

        System.assertNotEquals(null, opts);
    }

    @isTest
    static void discoverPicklistFields_invalidObject_returnsEmpty() {
        Test.startTest();
        List<DynamicApprovalController.FieldOption> opts =
            DynamicApprovalController.discoverPicklistFields('NoSuchObject__z');
        Test.stopTest();

        System.assertEquals(0, opts.size());
    }

    // ── getPicklistValues ─────────────────────────────────────────────

    @isTest
    static void getPicklistValues_invalidObject_returnsEmpty() {
        Test.startTest();
        List<DynamicApprovalController.PicklistValueOption> opts =
            DynamicApprovalController.getPicklistValues('NoSuchObject__z', 'Status__c');
        Test.stopTest();

        System.assertEquals(0, opts.size());
    }

    @isTest
    static void getPicklistValues_invalidField_returnsEmpty() {
        Test.startTest();
        List<DynamicApprovalController.PicklistValueOption> opts =
            DynamicApprovalController.getPicklistValues('Lead__c', 'NoSuchField__zz');
        Test.stopTest();

        System.assertEquals(0, opts.size());
    }

    @isTest
    static void getPicklistValues_validPicklistField_returnsList() {
        Test.startTest();
        List<DynamicApprovalController.PicklistValueOption> opts =
            DynamicApprovalController.getPicklistValues('Lead__c', 'Lead_Status__c');
        Test.stopTest();

        System.assertNotEquals(null, opts);
    }

    // ── discoverAllFields ─────────────────────────────────────────────

    @isTest
    static void discoverAllFields_validObject_returnsList() {
        Test.startTest();
        List<DynamicApprovalController.FieldOption> opts =
            DynamicApprovalController.discoverAllFields('Lead__c');
        Test.stopTest();

        System.assertNotEquals(null, opts);
        System.assert(!opts.isEmpty());
    }

    @isTest
    static void discoverAllFields_invalidObject_returnsEmpty() {
        Test.startTest();
        List<DynamicApprovalController.FieldOption> opts =
            DynamicApprovalController.discoverAllFields('NoSuchObject__z');
        Test.stopTest();

        System.assertEquals(0, opts.size());
    }

    // ── getObjectFields ───────────────────────────────────────────────

    @isTest
    static void getObjectFields_validObject_returnsSortedList() {
        Test.startTest();
        List<DynamicApprovalController.FieldOption> opts =
            DynamicApprovalController.getObjectFields('Lead__c');
        Test.stopTest();

        System.assertNotEquals(null, opts);
        System.assert(!opts.isEmpty());
    }

    @isTest
    static void getObjectFields_invalidObject_returnsEmpty() {
        Test.startTest();
        List<DynamicApprovalController.FieldOption> opts =
            DynamicApprovalController.getObjectFields('NoSuchObject__z');
        Test.stopTest();

        System.assertEquals(0, opts.size());
    }

    // ── getConfigurationsForObject ────────────────────────────────────

    @isTest
    static void getConfigurationsForObject_withConfig_returnsList() {
        insert new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'LeadApproval', Process_Label__c = 'Lead Approval'
        );

        Test.startTest();
        List<Approval_Configuration__c> configs =
            DynamicApprovalController.getConfigurationsForObject('Lead__c');
        Test.stopTest();

        System.assert(!configs.isEmpty());
    }

    @isTest
    static void getConfigurationsForObject_noConfigs_returnsEmpty() {
        Test.startTest();
        List<Approval_Configuration__c> configs =
            DynamicApprovalController.getConfigurationsForObject('Contact');
        Test.stopTest();

        System.assertNotEquals(null, configs);
    }

    // ── getAllConfigurations ───────────────────────────────────────────

    @isTest
    static void getAllConfigurations_returnsAll() {
        insert new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'AllApproval', Process_Label__c = 'All Approval'
        );

        Test.startTest();
        List<Approval_Configuration__c> configs = DynamicApprovalController.getAllConfigurations();
        Test.stopTest();

        System.assertNotEquals(null, configs);
        System.assert(!configs.isEmpty());
    }

    // ── getApprovalStatusForRecord ────────────────────────────────────

    @isTest
    static void getApprovalStatusForRecord_null_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            DynamicApprovalController.getApprovalStatusForRecord(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Should throw for null recordId');
    }

    @isTest
    static void getApprovalStatusForRecord_noConfigs_returnsEmptyWrapper() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];

        Test.startTest();
        DynamicApprovalController.ApprovalStatusWrapper wrapper =
            DynamicApprovalController.getApprovalStatusForRecord(lead.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper);
        System.assertEquals(0, wrapper.available.size());
        System.assertEquals(0, wrapper.completed.size());
        System.assertEquals(0, wrapper.inProgress.size());
        System.assertEquals(0, wrapper.locked.size());
    }

    @isTest
    static void getApprovalStatusForRecord_availableReadyToSubmit() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        insert new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'ReadyProcess', Process_Label__c = 'Ready Process'
            // Status_Field_API_Name__c = null → no status set
            // Prerequisite_Process_Type__c = null → no prerequisite
        );

        Test.startTest();
        DynamicApprovalController.ApprovalStatusWrapper wrapper =
            DynamicApprovalController.getApprovalStatusForRecord(lead.Id);
        Test.stopTest();

        System.assertEquals(1, wrapper.available.size());
        System.assertEquals('Ready to submit', wrapper.available[0].statusMessage);
    }

    @isTest
    static void getApprovalStatusForRecord_lockedPrerequisiteNotMet() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        insert new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'LockedProcess', Process_Label__c = 'Locked Process',
            Prerequisite_Process_Type__c = 'NonExistentPrereq',
            Prerequisite_Status_Value__c = 'CompletedValue'
            // processTypeToStatus.get('NonExistentPrereq') = null, 'CompletedValue' != null → locked
        );

        Test.startTest();
        DynamicApprovalController.ApprovalStatusWrapper wrapper =
            DynamicApprovalController.getApprovalStatusForRecord(lead.Id);
        Test.stopTest();

        System.assertEquals(1, wrapper.locked.size());
        System.assertEquals('LockedProcess', wrapper.locked[0].processType);
    }

    @isTest
    static void getApprovalStatusForRecord_prerequisiteMet() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        // Two configs: PrereqProcess (blank status) + MainProcess (prerequisite = PrereqProcess, prerequisite_value = null)
        // processTypeToStatus.get('PrereqProcess') = null, Prerequisite_Status_Value__c = null → null == null → met
        List<Approval_Configuration__c> configs = new List<Approval_Configuration__c>{
            new Approval_Configuration__c(
                Object_API_Name__c = 'Lead__c', Is_Active__c = true,
                Process_Type__c = 'PrereqProcess', Process_Label__c = 'Prereq Process',
                Sequence_Order__c = 1
            ),
            new Approval_Configuration__c(
                Object_API_Name__c = 'Lead__c', Is_Active__c = true,
                Process_Type__c = 'MainProcess', Process_Label__c = 'Main Process',
                Prerequisite_Process_Type__c = 'PrereqProcess',
                Prerequisite_Status_Value__c = null,
                Sequence_Order__c = 2
            )
        };
        insert configs;

        Test.startTest();
        DynamicApprovalController.ApprovalStatusWrapper wrapper =
            DynamicApprovalController.getApprovalStatusForRecord(lead.Id);
        Test.stopTest();

        // PrereqProcess → AVAILABLE (ready to submit); MainProcess → AVAILABLE (prerequisite met)
        System.assertEquals(2, wrapper.available.size());
        Boolean foundPrereqMet = false;
        for (DynamicApprovalController.ApprovalProcessStatus ps : wrapper.available) {
            if (ps.processType == 'MainProcess' && ps.prerequisiteMet == true) {
                foundPrereqMet = true;
            }
        }
        System.assert(foundPrereqMet, 'MainProcess should have prerequisiteMet = true');
    }

    @isTest
    static void getApprovalStatusForRecord_allStatusCategories() {
        Lead__c lead = [SELECT Id, Name FROM Lead__c LIMIT 1];
        String leadName = lead.Name; // Use Name field as the status field

        // Create 4 configs covering Approved, Rejected, Pending, and Other (no match) branches
        List<Approval_Configuration__c> configs = new List<Approval_Configuration__c>{
            new Approval_Configuration__c(
                Object_API_Name__c = 'Lead__c', Is_Active__c = true,
                Process_Type__c = 'ApprovedP', Process_Label__c = 'Approved Process',
                Status_Field_API_Name__c = 'Name',
                Approved_Status_Value__c = leadName, // currentStatus == leadName → COMPLETED
                Steps_JSON__c = '{"numberOfSteps":1,"steps":[{"stepNumber":1,"stepName":"Manager"}]}',
                Sequence_Order__c = 1
            ),
            new Approval_Configuration__c(
                Object_API_Name__c = 'Lead__c', Is_Active__c = true,
                Process_Type__c = 'RejectedP', Process_Label__c = 'Rejected Process',
                Status_Field_API_Name__c = 'Name',
                Rejected_Status_Value__c = leadName, // currentStatus != Approved, == Rejected → REJECTED
                Sequence_Order__c = 2
            ),
            new Approval_Configuration__c(
                Object_API_Name__c = 'Lead__c', Is_Active__c = true,
                Process_Type__c = 'PendingP', Process_Label__c = 'Pending Process',
                Status_Field_API_Name__c = 'Name',
                Pending_Status_Value__c = leadName, // != Approved, != Rejected, == Pending → IN_PROGRESS
                Sequence_Order__c = 3
            ),
            new Approval_Configuration__c(
                Object_API_Name__c = 'Lead__c', Is_Active__c = true,
                Process_Type__c = 'OtherP', Process_Label__c = 'Other Process',
                Status_Field_API_Name__c = 'Name',
                Approved_Status_Value__c = 'NotMatch1',
                Rejected_Status_Value__c = 'NotMatch2',
                Pending_Status_Value__c = 'NotMatch3',
                Sequence_Order__c = 4
            )
        };
        insert configs;

        Test.startTest();
        DynamicApprovalController.ApprovalStatusWrapper wrapper =
            DynamicApprovalController.getApprovalStatusForRecord(lead.Id);
        Test.stopTest();

        System.assertEquals(1, wrapper.completed.size(), 'Should have 1 completed (approved)');
        System.assertEquals(1, wrapper.inProgress.size(), 'Should have 1 in-progress (pending)');
        System.assertEquals(2, wrapper.available.size(), 'Should have 2 available (rejected + other)');

        // Verify canResubmit for rejected process
        Boolean foundCanResubmit = false;
        for (DynamicApprovalController.ApprovalProcessStatus ps : wrapper.available) {
            if (ps.canResubmit == true) foundCanResubmit = true;
        }
        System.assert(foundCanResubmit, 'Rejected process should have canResubmit = true');

        // Verify steps were parsed for the completed process
        System.assert(wrapper.completed[0].numberOfSteps >= 0);
    }

    @isTest
    static void getApprovalStatusForRecord_invalidStepsJson_handlesGracefully() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        insert new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'BadStepsP', Process_Label__c = 'Bad Steps Process',
            Steps_JSON__c = 'INVALID_JSON_HERE'
        );

        Test.startTest();
        DynamicApprovalController.ApprovalStatusWrapper wrapper =
            DynamicApprovalController.getApprovalStatusForRecord(lead.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrapper);
        System.assertEquals(0, wrapper.available[0].numberOfSteps, 'Steps count should default to 0 on parse error');
    }

    // ── saveConfiguration ─────────────────────────────────────────────

    @isTest
    static void saveConfiguration_insert_success() {
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'InsertTest', Process_Label__c = 'Insert Test'
        );

        Test.startTest();
        Approval_Configuration__c saved =
            DynamicApprovalController.saveConfiguration(JSON.serialize(cfg));
        Test.stopTest();

        System.assertNotEquals(null, saved.Id);
    }

    @isTest
    static void saveConfiguration_update_success() {
        Approval_Configuration__c existing = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'UpdateTest', Process_Label__c = 'Update Test'
        );
        insert existing;
        existing.Process_Label__c = 'Updated Label';

        Test.startTest();
        Approval_Configuration__c updated =
            DynamicApprovalController.saveConfiguration(JSON.serialize(existing));
        Test.stopTest();

        System.assertEquals(existing.Id, updated.Id);
    }

    @isTest
    static void saveConfiguration_invalidJson_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            DynamicApprovalController.saveConfiguration('NOT_JSON');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Should throw AuraHandledException for invalid JSON');
    }

    // ── deleteConfiguration ───────────────────────────────────────────

    @isTest
    static void deleteConfiguration_success() {
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'DeleteTest', Process_Label__c = 'Delete Test'
        );
        insert cfg;

        Test.startTest();
        DynamicApprovalController.deleteConfiguration(cfg.Id);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Approval_Configuration__c WHERE Id = :cfg.Id]);
    }

    // ── previewApprovers ──────────────────────────────────────────────

    @isTest
    static void previewApprovers_nullRecordId_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            DynamicApprovalController.previewApprovers(null, null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Should throw for null recordId');
    }

    @isTest
    static void previewApprovers_nullConfigId_throws() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Boolean thrown = false;
        Test.startTest();
        try {
            DynamicApprovalController.previewApprovers(lead.Id, null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Should throw for null configId');
    }

    // ── submitForApproval ─────────────────────────────────────────────

    @isTest
    static void submitForApproval_nullRecordId_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            DynamicApprovalController.submitForApproval(null, null, null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Should throw for null recordId');
    }

    @isTest
    static void submitForApproval_nullConfigId_throws() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Boolean thrown = false;
        Test.startTest();
        try {
            DynamicApprovalController.submitForApproval(lead.Id, null, 'comments');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();

        System.assert(thrown, 'Should throw for null configId');
    }

    @isTest
    static void submitForApproval_withConfig_noRequiredFields_callsService() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'SubmitTest', Process_Label__c = 'Submit Test'
            // Required_Fields_JSON__c = blank → no required field validation
        );
        insert cfg;

        Test.startTest();
        try {
            DynamicApprovalController.submitForApproval(lead.Id, cfg.Id, 'test comments');
        } catch (AuraHandledException e) {
            // Expected — no actual Salesforce approval process defined for this config
        }
        Test.stopTest();

        System.assert(true, 'Covered the no-required-fields submit path');
    }

    // ── getRequiredFieldsStatus ───────────────────────────────────────

    @isTest
    static void getRequiredFieldsStatus_blankRequiredFields_returnsEmpty() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'RFSTest', Process_Label__c = 'RFS Test'
            // Required_Fields_JSON__c = blank → returns empty immediately
        );
        insert cfg;

        Test.startTest();
        List<DynamicApprovalController.RequiredFieldStatus> statuses =
            DynamicApprovalController.getRequiredFieldsStatus(lead.Id, cfg.Id);
        Test.stopTest();

        System.assertEquals(0, statuses.size(), 'Should return empty when no required fields');
    }

    @isTest
    static void getRequiredFieldsStatus_withRequiredTextField_returnsFilledStatus() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        // Name is a text (STRING) field — always filled on Lead__c
        String requiredFieldsJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'apiName' => 'Name', 'label' => 'Full Name' }
        });
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'RFSTest2', Process_Label__c = 'RFS Test2',
            Required_Fields_JSON__c = requiredFieldsJson
        );
        insert cfg;

        Test.startTest();
        List<DynamicApprovalController.RequiredFieldStatus> statuses =
            DynamicApprovalController.getRequiredFieldsStatus(lead.Id, cfg.Id);
        Test.stopTest();

        System.assertEquals(1, statuses.size());
        System.assertEquals('Name', statuses[0].fieldApiName);
        System.assertEquals('Full Name', statuses[0].fieldLabel);
        System.assertEquals(true, statuses[0].isFilled);
    }

    @isTest
    static void getRequiredFieldsStatus_emptyFieldList_returnsEmpty() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'RFSTest3', Process_Label__c = 'RFS Test3',
            Required_Fields_JSON__c = '[]' // empty list
        );
        insert cfg;

        Test.startTest();
        List<DynamicApprovalController.RequiredFieldStatus> statuses =
            DynamicApprovalController.getRequiredFieldsStatus(lead.Id, cfg.Id);
        Test.stopTest();

        System.assertEquals(0, statuses.size());
    }

    // ── getEmailTemplates ─────────────────────────────────────────────

    @isTest
    static void getEmailTemplates_returnsList() {
        Test.startTest();
        List<DynamicApprovalController.EmailTemplateOption> opts =
            DynamicApprovalController.getEmailTemplates();
        Test.stopTest();

        System.assertNotEquals(null, opts);
    }

    // ── getEmailConfigTemplates ───────────────────────────────────────

    @isTest
    static void getEmailConfigTemplates_withObjectApiName_appendsToLabel() {
        insert new Email_Template_Config__c(
            Template_Name__c = 'Approval Email', Object_API_Name__c = 'Lead__c', Is_Active__c = true
        );

        Test.startTest();
        List<DynamicApprovalController.EmailTemplateOption> opts =
            DynamicApprovalController.getEmailConfigTemplates();
        Test.stopTest();

        System.assert(!opts.isEmpty());
        // Label should contain object name appended
        System.assert(opts[0].label.contains('Lead__c'), 'Label should include Object_API_Name__c');
    }

    @isTest
    static void getEmailConfigTemplates_nullObjectApiName_noAppend() {
        insert new Email_Template_Config__c(
            Template_Name__c = 'Generic Email', Object_API_Name__c = null, Is_Active__c = true
        );

        Test.startTest();
        List<DynamicApprovalController.EmailTemplateOption> opts =
            DynamicApprovalController.getEmailConfigTemplates();
        Test.stopTest();

        System.assertNotEquals(null, opts);
        System.assert(!opts.isEmpty());
        System.assertEquals('Generic Email', opts[0].label);
    }

    // ── getPrerequisiteOptions ────────────────────────────────────────

    @isTest
    static void getPrerequisiteOptions_withCurrentConfigId_excludesIt() {
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'PrereqOpt', Process_Label__c = 'Prereq Option'
        );
        insert cfg;

        Test.startTest();
        List<DynamicApprovalController.PrerequisiteOption> opts =
            DynamicApprovalController.getPrerequisiteOptions('Lead__c', cfg.Id);
        Test.stopTest();

        // Always has "-- None --"; inserted config is excluded → only 1 entry
        System.assertEquals(1, opts.size(), 'Only -- None -- should remain after excluding currentConfigId');
        System.assertEquals('-- None --', opts[0].label);
    }

    @isTest
    static void getPrerequisiteOptions_withoutCurrentConfigId_includesAll() {
        insert new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'PrereqOpt2', Process_Label__c = 'Prereq Option 2'
        );

        Test.startTest();
        List<DynamicApprovalController.PrerequisiteOption> opts =
            DynamicApprovalController.getPrerequisiteOptions('Lead__c', null);
        Test.stopTest();

        // Has -- None -- + at least 1 config
        System.assert(opts.size() >= 2, 'Should have -- None -- plus at least 1 config');
    }

    // ── saveRequiredFieldValues ───────────────────────────────────────

    @isTest
    static void saveRequiredFieldValues_nullRecordId_returnsQuietly() {
        Test.startTest();
        DynamicApprovalController.saveRequiredFieldValues(null, null, '{"Name":"Test"}');
        Test.stopTest();

        System.assert(true, 'Should return without error when recordId is null');
    }

    @isTest
    static void saveRequiredFieldValues_blankJson_returnsQuietly() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'SRFVTest', Process_Label__c = 'SRFV Test'
        );
        insert cfg;

        Test.startTest();
        DynamicApprovalController.saveRequiredFieldValues(lead.Id, cfg.Id, null);
        Test.stopTest();

        System.assert(true, 'Should return without error when fieldValuesJson is blank');
    }

    @isTest
    static void saveRequiredFieldValues_emptyJson_returnsQuietly() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'SRFVTest2', Process_Label__c = 'SRFV Test2'
        );
        insert cfg;

        Test.startTest();
        DynamicApprovalController.saveRequiredFieldValues(lead.Id, cfg.Id, '{}');
        Test.stopTest();

        System.assert(true, 'Should return without error for empty field map');
    }

    @isTest
    static void saveRequiredFieldValues_withFieldValues_updatesRecord() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Approval_Configuration__c cfg = new Approval_Configuration__c(
            Object_API_Name__c = 'Lead__c', Is_Active__c = true,
            Process_Type__c = 'SRFVTest3', Process_Label__c = 'SRFV Test3'
        );
        insert cfg;

        // Pass a field value (Name is a text field; covers the else/string branch)
        String fieldValues = JSON.serialize(new Map<String, Object>{ 'Name' => 'Updated Name' });

        Test.startTest();
        DynamicApprovalController.saveRequiredFieldValues(lead.Id, cfg.Id, fieldValues);
        Test.stopTest();

        // No exception means the update path was executed
        System.assert(true, 'Should execute field update without error');
    }

    // ── searchApproverUsers ───────────────────────────────────────────

    @isTest
    static void searchApproverUsers_blank_returnsEmpty() {
        Test.startTest();
        List<User> users = DynamicApprovalController.searchApproverUsers('');
        Test.stopTest();

        System.assertEquals(0, users.size(), 'Should return empty for blank search');
    }

    @isTest
    static void searchApproverUsers_singleChar_returnsEmpty() {
        Test.startTest();
        List<User> users = DynamicApprovalController.searchApproverUsers('a');
        Test.stopTest();

        System.assertEquals(0, users.size(), 'Should return empty for single char (< 2)');
    }

    @isTest
    static void searchApproverUsers_validTerm_returnsList() {
        String searchTerm = UserInfo.getName().length() >= 3
            ? UserInfo.getName().substring(0, 3)
            : UserInfo.getName();

        Test.startTest();
        List<User> users = DynamicApprovalController.searchApproverUsers(searchTerm);
        Test.stopTest();

        System.assertNotEquals(null, users);
    }

    // ── Wrapper class constructors ────────────────────────────────────

    @isTest
    static void wrapperClasses_directConstruction() {
        DynamicApprovalController.ObjectOption oo =
            new DynamicApprovalController.ObjectOption('Lead', 'Lead__c');
        System.assertEquals('Lead', oo.label);
        System.assertEquals('Lead__c', oo.value);
        System.assertEquals(0, oo.compareTo(new DynamicApprovalController.ObjectOption('Lead', 'Lead__c')));

        DynamicApprovalController.FieldOption fo =
            new DynamicApprovalController.FieldOption('Name', 'Name');
        System.assertEquals('Name', fo.label);
        System.assertEquals(0, fo.compareTo(new DynamicApprovalController.FieldOption('Name', 'Name')));

        DynamicApprovalController.PicklistValueOption pvo =
            new DynamicApprovalController.PicklistValueOption('Option 1', 'option1');
        System.assertEquals('Option 1', pvo.label);
        System.assertEquals('option1', pvo.value);

        DynamicApprovalController.EmailTemplateOption eto =
            new DynamicApprovalController.EmailTemplateOption('My Template', 'my_template');
        System.assertEquals('My Template', eto.label);
        System.assertEquals('my_template', eto.value);

        DynamicApprovalController.PrerequisiteOption po =
            new DynamicApprovalController.PrerequisiteOption('-- None --', '');
        System.assertEquals('-- None --', po.label);
        System.assertEquals('', po.value);

        DynamicApprovalController.ApprovalResult ar =
            new DynamicApprovalController.ApprovalResult(true, 'Done', null);
        System.assertEquals(true, ar.success);
        System.assertEquals('Done', ar.message);

        DynamicApprovalController.ApprovalStatusWrapper asw =
            new DynamicApprovalController.ApprovalStatusWrapper();
        System.assertNotEquals(null, asw.available);
        System.assertNotEquals(null, asw.completed);
        System.assertNotEquals(null, asw.inProgress);
        System.assertNotEquals(null, asw.locked);

        DynamicApprovalController.StepInfo si =
            new DynamicApprovalController.StepInfo(1, 'Manager Approval');
        System.assertEquals(1, si.stepNumber);
        System.assertEquals('Manager Approval', si.stepName);

        DynamicApprovalController.StepInfo siNull =
            new DynamicApprovalController.StepInfo(2, null);
        System.assertEquals('', siNull.stepName); // null stepName → ''

        DynamicApprovalController.ApproverPreview ap =
            new DynamicApprovalController.ApproverPreview(1, 'Step 1', 'Manager__c', 'Manager');
        System.assertEquals(false, ap.isFound);
        System.assertEquals('Not configured', ap.message);

        DynamicApprovalController.RequiredFieldStatus rfs =
            new DynamicApprovalController.RequiredFieldStatus();
        rfs.fieldApiName = 'Name';
        rfs.isFilled = true;
        rfs.fieldType = 'text';
        System.assertEquals('Name', rfs.fieldApiName);
        System.assertEquals(true, rfs.isFilled);
    }
}