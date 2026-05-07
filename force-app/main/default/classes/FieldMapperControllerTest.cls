@isTest
private class FieldMapperControllerTest {

    @isTest
    static void testGetObjectList() {
        Test.startTest();
        List<FieldMapperController.ObjectInfo> objects = FieldMapperController.getObjectList();
        Test.stopTest();

        System.assertNotEquals(null, objects, 'Should return object list');
        System.assert(objects.size() > 0, 'Should have at least one object');
        // Verify ObjectInfo properties
        FieldMapperController.ObjectInfo first = objects[0];
        System.assertNotEquals(null, first.label);
        System.assertNotEquals(null, first.apiName);
    }

    @isTest
    static void testGetFieldList() {
        Test.startTest();
        List<FieldMapperController.FieldInfo> fields = FieldMapperController.getFieldList('Account');
        Test.stopTest();

        System.assertNotEquals(null, fields, 'Should return field list');
        System.assert(fields.size() > 0, 'Account should have fields');
    }

    @isTest
    static void testGetFieldListInvalidObject() {
        Test.startTest();
        List<FieldMapperController.FieldInfo> fields = FieldMapperController.getFieldList('NonExistentObject__c');
        Test.stopTest();

        System.assertEquals(0, fields.size(), 'Should return empty list for invalid object');
    }

    @isTest
    static void testGetCompatibleFields() {
        Test.startTest();
        List<FieldMapperController.FieldInfo> fields = FieldMapperController.getCompatibleFields('Account', 'STRING');
        Test.stopTest();

        System.assertNotEquals(null, fields);
        System.assert(fields.size() > 0, 'Should have compatible STRING fields on Account');
    }

    @isTest
    static void testGetCompatibleFieldsInvalidObject() {
        Test.startTest();
        List<FieldMapperController.FieldInfo> fields = FieldMapperController.getCompatibleFields('NonExistentObject__c', 'STRING');
        Test.stopTest();

        System.assertEquals(0, fields.size());
    }

    @isTest
    static void testGetAllMappingConfigurations() {
        Test.startTest();
        List<FieldMapperController.MappingConfigWrapper> configs = FieldMapperController.getAllMappingConfigurations();
        Test.stopTest();

        System.assertNotEquals(null, configs, 'Should return list even if empty');
    }

    @isTest
    static void testSaveMappingConfiguration() {
        Map<String, Object> configData = new Map<String, Object>{
            'mappingName' => 'Test Mapping',
            'fromObject' => 'Lead__c',
            'toObject' => 'Account',
            'lookupField' => null,
            'isActive' => false,
            'mappingTrigger' => 'Insert Only',
            'mappingDetails' => '[{"fromField":"First_Name__c","toField":"Name","fromFieldType":"STRING","toFieldType":"STRING","sequence":1}]'
        };

        Test.startTest();
        FieldMapperController.saveMappingConfiguration(JSON.serialize(configData));
        Test.stopTest();

        List<Field_Mapping_Configuration__c> configs = [SELECT Id, Name FROM Field_Mapping_Configuration__c WHERE Name = 'Test Mapping'];
        System.assertEquals(1, configs.size(), 'Configuration should be saved');

        List<Field_Mapping_Detail__c> details = [SELECT Id FROM Field_Mapping_Detail__c WHERE Field_Mapping_Configuration__c = :configs[0].Id];
        System.assertEquals(1, details.size(), 'Detail should be saved');
    }

    @isTest
    static void testDeleteMappingConfiguration() {
        Field_Mapping_Configuration__c config = new Field_Mapping_Configuration__c(
            Name = 'To Delete',
            From_Object__c = 'Lead__c',
            To_Object__c = 'Account',
            Is_Active__c = false
        );
        insert config;

        Test.startTest();
        FieldMapperController.deleteMappingConfiguration(config.Id);
        Test.stopTest();

        List<Field_Mapping_Configuration__c> remaining = [SELECT Id FROM Field_Mapping_Configuration__c WHERE Id = :config.Id];
        System.assertEquals(0, remaining.size(), 'Config should be deleted');
    }

    @isTest
    static void testDeleteMappingConfigurationBlankId() {
        Boolean thrown = false;
        Test.startTest();
        try {
            FieldMapperController.deleteMappingConfiguration('');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Should throw for blank ID');
    }

    @isTest
    static void testObjectInfoCompareTo() {
        FieldMapperController.ObjectInfo a = new FieldMapperController.ObjectInfo('Account', 'Account');
        FieldMapperController.ObjectInfo b = new FieldMapperController.ObjectInfo('Booking', 'Booking__c');
        System.assert(a.compareTo(b) < 0, 'Account should sort before Booking');
    }

    @isTest
    static void testFieldInfoCompareTo() {
        FieldMapperController.FieldInfo a = new FieldMapperController.FieldInfo('Amount', 'Amount__c', 'CURRENCY', null);
        FieldMapperController.FieldInfo b = new FieldMapperController.FieldInfo('Name', 'Name', 'STRING', null);
        System.assert(a.compareTo(b) < 0, 'Amount should sort before Name');
    }

    @isTest
    static void testMappingConfigWrapper() {
        FieldMapperController.MappingConfigWrapper w = new FieldMapperController.MappingConfigWrapper();
        w.id = null;
        w.name = 'Test';
        w.fromObject = 'A';
        w.toObject = 'B';
        w.isActive = true;
        w.mappingTrigger = 'On Create';
        w.fieldCount = 5;
        System.assertEquals(5, w.fieldCount);
    }
}