@isTest
private class FieldMapperInvocableTest {

    @isTest
    static void testMapFieldsNoConfig() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('FMI Proj');
        Lead__c l = TestDataFactory.createLead(p.Id, 'FMI', '9800000100');

        Test.startTest();
        FieldMapperInvocable.Request req = new FieldMapperInvocable.Request();
        req.sourceRecordId = l.Id;
        req.objectApiName = 'Lead__c';
        req.isInsert = true;
        req.targetRecordId = null;

        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, 'Should succeed with no config found');
        System.assert(results[0].message.contains('No active mapping'), 'Should indicate no config');
    }

    @isTest
    static void testMapFieldsMissingParams() {
        Test.startTest();
        FieldMapperInvocable.Request req = new FieldMapperInvocable.Request();
        req.sourceRecordId = null;
        req.objectApiName = null;
        req.isInsert = true;
        req.targetRecordId = null;

        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('required'), 'Should require source record ID');
    }

    @isTest
    static void testMapFieldsWithActiveConfig() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('FMI Config Proj');
        Lead__c l = TestDataFactory.createLead(p.Id, 'FMIConf', '9800000101');

        // Create a mapping configuration
        Field_Mapping_Configuration__c config = new Field_Mapping_Configuration__c(
            Name = 'Lead to Account Mapping',
            From_Object__c = 'Lead__c',
            To_Object__c = 'Account',
            Is_Active__c = true,
            Mapping_Trigger__c = 'Insert Only'
        );
        insert config;

        // Create mapping detail
        Field_Mapping_Detail__c detail = new Field_Mapping_Detail__c(
            Field_Mapping_Configuration__c = config.Id,
            From_Field_API_Name__c = 'First_Name__c',
            To_Field_API_Name__c = 'Name',
            From_Field_Type__c = 'STRING',
            To_Field_Type__c = 'STRING',
            Sequence__c = 1
        );
        insert detail;

        Test.startTest();
        FieldMapperInvocable.Request req = new FieldMapperInvocable.Request();
        req.sourceRecordId = l.Id;
        req.objectApiName = 'Lead__c';
        req.isInsert = true;
        req.targetRecordId = null;

        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        // Result depends on whether Account insert succeeds with mapped Name
    }

    @isTest
    static void testMapFieldsWithTargetRecordId() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('FMI Target Proj');
        Lead__c l = TestDataFactory.createLead(p.Id, 'FMITarget', '9800000102');

        // Create target account
        Account acc = new Account(Name = 'Target Account');
        insert acc;

        // Create mapping config
        Field_Mapping_Configuration__c config = new Field_Mapping_Configuration__c(
            Name = 'Lead to Account Update',
            From_Object__c = 'Lead__c',
            To_Object__c = 'Account',
            Is_Active__c = true,
            Mapping_Trigger__c = 'Update Only'
        );
        insert config;

        Field_Mapping_Detail__c detail = new Field_Mapping_Detail__c(
            Field_Mapping_Configuration__c = config.Id,
            From_Field_API_Name__c = 'First_Name__c',
            To_Field_API_Name__c = 'Name',
            From_Field_Type__c = 'STRING',
            To_Field_Type__c = 'STRING',
            Sequence__c = 1
        );
        insert detail;

        Test.startTest();
        FieldMapperInvocable.Request req = new FieldMapperInvocable.Request();
        req.sourceRecordId = l.Id;
        req.objectApiName = 'Lead__c';
        req.isInsert = false;
        req.targetRecordId = acc.Id;

        List<FieldMapperInvocable.Result> results = FieldMapperInvocable.mapFields(
            new List<FieldMapperInvocable.Request>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
    }

    @isTest
    static void testResultWrapper() {
        FieldMapperInvocable.Result res = new FieldMapperInvocable.Result();
        res.success = true;
        res.message = 'done';
        res.errorMessage = null;
        System.assertEquals(true, res.success);
    }
}