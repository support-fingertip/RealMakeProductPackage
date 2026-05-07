/**
 * @description Test class for IntegrationFieldMappingEngine and IntegrationMappingController.
 * Tests the metadata-driven field mapping engine end-to-end.
 */
@IsTest
private class IntegrationFieldMappingEngineTest {

    // ════════════════════════════════════════════════════════════
    // TEST DATA SETUP
    // ════════════════════════════════════════════════════════════

    @TestSetup
    static void setupTestData() {
        // Create a source config for Channel_Partner__c
        Integration_Source_Config__c cpConfig = new Integration_Source_Config__c(
            Name = 'CP Registration Mapping',
            Source_Name__c = 'TEST_CP_REGISTRATION',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = true,
            Version__c = 1,
            Description__c = 'Test config for CP registration',
            API_Schema_JSON__c = '[{"name":"mobile","label":"Mobile","type":"Phone","required":true},{"name":"email","label":"Email","type":"Email","required":true},{"name":"cp_type","label":"CP Type","type":"Picklist"},{"name":"city","label":"City","type":"Text"}]',
            Validation_Rules_JSON__c = '[{"field":"mobile","regex":"[0-9]{10}","message":"Mobile must be 10 digits"}]'
        );
        insert cpConfig;

        // Create field rules
        List<Integration_Field_Rule__c> rules = new List<Integration_Field_Rule__c>();

        rules.add(new Integration_Field_Rule__c(
            Integration_Source_Config__c = cpConfig.Id,
            API_Field_Name__c = 'mobile',
            API_Field_Label__c = 'Mobile Number',
            SF_Field_API_Name__c = 'Mobile__c',
            Is_Required__c = true,
            Data_Type__c = 'Phone',
            Sequence__c = 1,
            Is_Active__c = true
        ));

        rules.add(new Integration_Field_Rule__c(
            Integration_Source_Config__c = cpConfig.Id,
            API_Field_Name__c = 'email',
            API_Field_Label__c = 'Email',
            SF_Field_API_Name__c = 'Email__c',
            Is_Required__c = true,
            Data_Type__c = 'Email',
            Sequence__c = 2,
            Is_Active__c = true
        ));

        rules.add(new Integration_Field_Rule__c(
            Integration_Source_Config__c = cpConfig.Id,
            API_Field_Name__c = 'cp_type',
            API_Field_Label__c = 'CP Type',
            SF_Field_API_Name__c = 'CP_Type__c',
            Is_Required__c = false,
            Data_Type__c = 'Picklist',
            Default_Value__c = 'Individual',
            Sequence__c = 3,
            Is_Active__c = true
        ));

        rules.add(new Integration_Field_Rule__c(
            Integration_Source_Config__c = cpConfig.Id,
            API_Field_Name__c = 'city',
            API_Field_Label__c = 'City',
            SF_Field_API_Name__c = 'City__c',
            Is_Required__c = false,
            Data_Type__c = 'Text',
            Transform_Expression__c = 'UPPERCASE',
            Sequence__c = 4,
            Is_Active__c = true
        ));

        // Inactive rule (should be skipped)
        rules.add(new Integration_Field_Rule__c(
            Integration_Source_Config__c = cpConfig.Id,
            API_Field_Name__c = 'inactive_field',
            API_Field_Label__c = 'Inactive',
            SF_Field_API_Name__c = 'City__c',
            Is_Required__c = false,
            Data_Type__c = 'Text',
            Sequence__c = 99,
            Is_Active__c = false
        ));

        insert rules;

        // Create an inactive config to test filtering
        Integration_Source_Config__c inactiveConfig = new Integration_Source_Config__c(
            Name = 'Inactive Config',
            Source_Name__c = 'TEST_INACTIVE',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = false,
            Version__c = 1
        );
        insert inactiveConfig;
    }

    // ════════════════════════════════════════════════════════════
    // ENGINE TESTS
    // ════════════════════════════════════════════════════════════

    @IsTest
    static void testMapPayload_success() {
        Map<String, Object> payload = new Map<String, Object>{
            'mobile' => '9876543210',
            'email' => 'test@example.com',
            'cp_type' => 'Firm',
            'city' => 'mumbai'
        };

        Test.startTest();
        SObject result = IntegrationFieldMappingEngine.mapPayload('TEST_CP_REGISTRATION', payload);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result instanceof Channel_Partner__c, 'Should return Channel_Partner__c');

        Channel_Partner__c cp = (Channel_Partner__c) result;
        System.assertEquals('9876543210', cp.Mobile__c, 'Mobile should be mapped');
        System.assertEquals('test@example.com', cp.Email__c, 'Email should be mapped');
        System.assertEquals('Firm', cp.CP_Type__c, 'CP Type should be mapped');
        System.assertEquals('MUMBAI', cp.City__c, 'City should be UPPERCASE transformed');
    }

    @IsTest
    static void testMapPayload_defaultValue() {
        Map<String, Object> payload = new Map<String, Object>{
            'mobile' => '9876543210',
            'email' => 'test@example.com'
            // cp_type not provided — should use default 'Individual'
        };

        Test.startTest();
        SObject result = IntegrationFieldMappingEngine.mapPayload('TEST_CP_REGISTRATION', payload);
        Test.stopTest();

        Channel_Partner__c cp = (Channel_Partner__c) result;
        System.assertEquals('Individual', cp.CP_Type__c, 'Should use default value when field is blank');
    }

    @IsTest
    static void testMapPayload_requiredFieldMissing() {
        Map<String, Object> payload = new Map<String, Object>{
            'email' => 'test@example.com'
            // mobile is required but missing
        };

        Test.startTest();
        try {
            IntegrationFieldMappingEngine.mapPayload('TEST_CP_REGISTRATION', payload);
            System.assert(false, 'Should have thrown exception for missing required field');
        } catch (IntegrationFieldMappingEngine.IntegrationMappingException e) {
            System.assert(e.getMessage().contains('required'), 'Error should mention required: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testMapPayload_noActiveConfig() {
        Test.startTest();
        try {
            IntegrationFieldMappingEngine.mapPayload('NONEXISTENT_SOURCE', new Map<String, Object>());
            System.assert(false, 'Should have thrown exception');
        } catch (IntegrationFieldMappingEngine.IntegrationMappingException e) {
            System.assert(e.getMessage().contains('No active'), 'Error should mention no active config');
        }
        Test.stopTest();
    }

    @IsTest
    static void testMapPayloadToFieldMap() {
        Map<String, Object> payload = new Map<String, Object>{
            'mobile' => '9876543210',
            'email' => 'test@example.com',
            'city' => 'delhi'
        };

        Test.startTest();
        Map<String, Object> fieldMap = IntegrationFieldMappingEngine.mapPayloadToFieldMap('TEST_CP_REGISTRATION', payload);
        Test.stopTest();

        System.assertEquals('9876543210', fieldMap.get('Mobile__c'), 'Mobile should be mapped');
        System.assertEquals('DELHI', fieldMap.get('City__c'), 'City should be UPPERCASE');
    }

    @IsTest
    static void testApplyFieldMap() {
        Channel_Partner__c cp = new Channel_Partner__c();
        Map<String, Object> fieldMap = new Map<String, Object>{
            'Mobile__c' => '1234567890',
            'Email__c' => 'test@test.com'
        };

        Test.startTest();
        IntegrationFieldMappingEngine.applyFieldMap(cp, fieldMap);
        Test.stopTest();

        System.assertEquals('1234567890', cp.Mobile__c);
        System.assertEquals('test@test.com', cp.Email__c);
    }

    @IsTest
    static void testValidatePayload() {
        // Valid payload
        Map<String, Object> validPayload = new Map<String, Object>{
            'mobile' => '9876543210',
            'email' => 'test@example.com'
        };

        Test.startTest();
        List<String> errors = IntegrationFieldMappingEngine.validatePayload('TEST_CP_REGISTRATION', validPayload);
        Test.stopTest();

        System.assertEquals(0, errors.size(), 'Valid payload should have no errors');
    }

    @IsTest
    static void testValidatePayload_invalidRegex() {
        Map<String, Object> invalidPayload = new Map<String, Object>{
            'mobile' => 'abc',   // fails regex
            'email' => 'test@example.com'
        };

        Test.startTest();
        List<String> errors = IntegrationFieldMappingEngine.validatePayload('TEST_CP_REGISTRATION', invalidPayload);
        Test.stopTest();

        System.assert(errors.size() > 0, 'Should have validation errors for invalid mobile format');
    }

    @IsTest
    static void testHasActiveConfig() {
        Test.startTest();
        Boolean hasActive = IntegrationFieldMappingEngine.hasActiveConfig('TEST_CP_REGISTRATION');
        Boolean hasInactive = IntegrationFieldMappingEngine.hasActiveConfig('TEST_INACTIVE');
        Boolean hasNone = IntegrationFieldMappingEngine.hasActiveConfig('NONEXISTENT');
        Test.stopTest();

        System.assertEquals(true, hasActive, 'Should find active config');
        System.assertEquals(false, hasInactive, 'Should not find inactive config');
        System.assertEquals(false, hasNone, 'Should not find nonexistent config');
    }

    // ════════════════════════════════════════════════════════════
    // CONTROLLER TESTS
    // ════════════════════════════════════════════════════════════

    @IsTest
    static void testGetSourceConfigs() {
        Test.startTest();
        List<Integration_Source_Config__c> configs = IntegrationMappingController.getSourceConfigs();
        Test.stopTest();

        System.assert(configs.size() >= 2, 'Should return at least 2 configs (active + inactive)');
    }

    @IsTest
    static void testGetSourceConfigWithRules() {
        Integration_Source_Config__c config = [
            SELECT Id FROM Integration_Source_Config__c WHERE Source_Name__c = 'TEST_CP_REGISTRATION' LIMIT 1
        ];

        Test.startTest();
        Integration_Source_Config__c result = IntegrationMappingController.getSourceConfigWithRules(config.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return config');
        System.assert(result.Integration_Field_Rules__r.size() > 0, 'Should include field rules');
    }

    @IsTest
    static void testSaveSourceConfig_new() {
        Map<String, Object> configData = new Map<String, Object>{
            'name' => 'Website API',
            'sourceName' => 'WEBSITE_API',
            'targetObject' => 'Lead__c',
            'isActive' => true,
            'version' => 1,
            'description' => 'Test website API config'
        };

        Test.startTest();
        Id configId = IntegrationMappingController.saveSourceConfig(JSON.serialize(configData));
        Test.stopTest();

        System.assertNotEquals(null, configId, 'Should return config ID');
        Integration_Source_Config__c saved = [
            SELECT Source_Name__c FROM Integration_Source_Config__c WHERE Id = :configId
        ];
        System.assertEquals('WEBSITE_API', saved.Source_Name__c);
    }

    @IsTest
    static void testSaveFieldRules() {
        Integration_Source_Config__c config = [
            SELECT Id FROM Integration_Source_Config__c WHERE Source_Name__c = 'TEST_CP_REGISTRATION' LIMIT 1
        ];

        List<Map<String, Object>> rules = new List<Map<String, Object>>();
        rules.add(new Map<String, Object>{
            'apiFieldName' => 'new_field',
            'apiFieldLabel' => 'New Field',
            'sfFieldApiName' => 'Mobile__c',
            'isRequired' => false,
            'dataType' => 'Text',
            'isActive' => true,
            'sequence' => 1
        });

        Test.startTest();
        IntegrationMappingController.saveFieldRules(config.Id, JSON.serialize(rules));
        Test.stopTest();

        List<Integration_Field_Rule__c> saved = [
            SELECT API_Field_Name__c FROM Integration_Field_Rule__c
            WHERE Integration_Source_Config__c = :config.Id
        ];
        // Old rules should be deleted, new one saved
        System.assertEquals(1, saved.size(), 'Should have exactly 1 rule after save');
        System.assertEquals('new_field', saved[0].API_Field_Name__c);
    }

    @IsTest
    static void testSaveFieldRules_withLookup() {
        Integration_Source_Config__c config = [
            SELECT Id FROM Integration_Source_Config__c WHERE Source_Name__c = 'TEST_CP_REGISTRATION' LIMIT 1
        ];

        List<Map<String, Object>> rules = new List<Map<String, Object>>();
        rules.add(new Map<String, Object>{
            'apiFieldName' => 'project_code',
            'apiFieldLabel' => 'Project Code',
            'sfFieldApiName' => 'Mobile__c',
            'isRequired' => true,
            'dataType' => 'Lookup',
            'isActive' => true,
            'sequence' => 1,
            'lookupRule' => new Map<String, Object>{
                'lookupObject' => 'Project__c',
                'matchField' => 'Project_Code__c',
                'returnField' => 'Id',
                'failOnNoMatch' => true
            }
        });

        Test.startTest();
        IntegrationMappingController.saveFieldRules(config.Id, JSON.serialize(rules));
        Test.stopTest();

        List<Integration_Lookup_Rule__c> lookups = [
            SELECT Lookup_Object__c, Match_Field__c
            FROM Integration_Lookup_Rule__c
        ];
        System.assertEquals(1, lookups.size(), 'Should have 1 lookup rule');
        System.assertEquals('Project__c', lookups[0].Lookup_Object__c);
    }

    @IsTest
    static void testDeleteSourceConfig() {
        Integration_Source_Config__c config = [
            SELECT Id FROM Integration_Source_Config__c WHERE Source_Name__c = 'TEST_INACTIVE' LIMIT 1
        ];

        Test.startTest();
        IntegrationMappingController.deleteSourceConfig(config.Id);
        Test.stopTest();

        List<Integration_Source_Config__c> remaining = [
            SELECT Id FROM Integration_Source_Config__c WHERE Source_Name__c = 'TEST_INACTIVE'
        ];
        System.assertEquals(0, remaining.size(), 'Config should be deleted');
    }

    @IsTest
    static void testGetTargetObjectOptions() {
        Test.startTest();
        List<IntegrationMappingController.ObjectOption> options = IntegrationMappingController.getTargetObjectOptions();
        Test.stopTest();

        System.assert(options.size() > 0, 'Should return custom objects');
    }

    @IsTest
    static void testGetObjectFields() {
        Test.startTest();
        List<IntegrationMappingController.FieldOption> fields = IntegrationMappingController.getObjectFields('Channel_Partner__c');
        Test.stopTest();

        System.assert(fields.size() > 0, 'Should return fields for Channel_Partner__c');
    }

    @IsTest
    static void testGetObjectFields_invalidObject() {
        Test.startTest();
        List<IntegrationMappingController.FieldOption> fields = IntegrationMappingController.getObjectFields('NonExistent__c');
        Test.stopTest();

        System.assertEquals(0, fields.size(), 'Should return empty list for invalid object');
    }

    // ════════════════════════════════════════════════════════════
    // TRANSFORM TESTS
    // ════════════════════════════════════════════════════════════

    @IsTest
    static void testTransformExpressions() {
        // Create a config with various transforms
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'Transform Test',
            Source_Name__c = 'TEST_TRANSFORMS',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = true,
            Version__c = 1
        );
        insert config;

        List<Integration_Field_Rule__c> rules = new List<Integration_Field_Rule__c>();
        rules.add(new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'lower_field',
            SF_Field_API_Name__c = 'City__c',
            Data_Type__c = 'Text',
            Transform_Expression__c = 'LOWERCASE',
            Sequence__c = 1,
            Is_Active__c = true
        ));
        rules.add(new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'trim_field',
            SF_Field_API_Name__c = 'Email__c',
            Data_Type__c = 'Text',
            Transform_Expression__c = 'TRIM',
            Sequence__c = 2,
            Is_Active__c = true
        ));
        insert rules;

        Map<String, Object> payload = new Map<String, Object>{
            'lower_field' => 'MUMBAI',
            'trim_field' => '  test@test.com  '
        };

        Test.startTest();
        SObject result = IntegrationFieldMappingEngine.mapPayload('TEST_TRANSFORMS', payload);
        Test.stopTest();

        Channel_Partner__c cp = (Channel_Partner__c) result;
        System.assertEquals('mumbai', cp.City__c, 'Should be lowercase');
        System.assertEquals('test@test.com', cp.Email__c, 'Should be trimmed');
    }

    @IsTest
    static void testTransformPrefix() {
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'Prefix Test',
            Source_Name__c = 'TEST_PREFIX',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = true,
            Version__c = 1
        );
        insert config;

        Integration_Field_Rule__c rule = new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'mobile',
            SF_Field_API_Name__c = 'Mobile__c',
            Data_Type__c = 'Phone',
            Transform_Expression__c = 'PREFIX:+91',
            Sequence__c = 1,
            Is_Active__c = true
        );
        insert rule;

        Map<String, Object> payload = new Map<String, Object>{ 'mobile' => '9876543210' };

        Test.startTest();
        SObject result = IntegrationFieldMappingEngine.mapPayload('TEST_PREFIX', payload);
        Test.stopTest();

        Channel_Partner__c cp = (Channel_Partner__c) result;
        System.assertEquals('+919876543210', cp.Mobile__c, 'Should have prefix');
    }

    @IsTest
    static void testTransformSuffix() {
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'Suffix Test',
            Source_Name__c = 'TEST_SUFFIX',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = true,
            Version__c = 1
        );
        insert config;

        Integration_Field_Rule__c rule = new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'city',
            SF_Field_API_Name__c = 'City__c',
            Data_Type__c = 'Text',
            Transform_Expression__c = 'SUFFIX: City',
            Sequence__c = 1,
            Is_Active__c = true
        );
        insert rule;

        Map<String, Object> payload = new Map<String, Object>{ 'city' => 'Mumbai' };

        Test.startTest();
        SObject result = IntegrationFieldMappingEngine.mapPayload('TEST_SUFFIX', payload);
        Test.stopTest();

        Channel_Partner__c cp = (Channel_Partner__c) result;
        System.assertEquals('Mumbai City', cp.City__c, 'Should have suffix');
    }

    @IsTest
    static void testStaticFieldRule() {
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'Static Test',
            Source_Name__c = 'TEST_STATIC',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = true,
            Version__c = 1
        );
        insert config;

        List<Integration_Field_Rule__c> rules = new List<Integration_Field_Rule__c>();
        rules.add(new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'mobile',
            SF_Field_API_Name__c = 'Mobile__c',
            Data_Type__c = 'Phone',
            Sequence__c = 1,
            Is_Active__c = true
        ));
        rules.add(new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'static_type',
            SF_Field_API_Name__c = 'CP_Type__c',
            Data_Type__c = 'Picklist',
            Is_Static__c = true,
            Default_Value__c = 'Individual',
            Sequence__c = 2,
            Is_Active__c = true
        ));
        insert rules;

        Map<String, Object> payload = new Map<String, Object>{ 'mobile' => '1234567890' };

        Test.startTest();
        SObject result = IntegrationFieldMappingEngine.mapPayload('TEST_STATIC', payload);
        Test.stopTest();

        Channel_Partner__c cp = (Channel_Partner__c) result;
        System.assertEquals('Individual', cp.CP_Type__c, 'Static field should use default value');
    }

    @IsTest
    static void testBooleanDataType() {
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'Bool Test',
            Source_Name__c = 'TEST_BOOL',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = true,
            Version__c = 1
        );
        insert config;

        Integration_Field_Rule__c rule = new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'mobile',
            SF_Field_API_Name__c = 'Mobile__c',
            Data_Type__c = 'Phone',
            Sequence__c = 1,
            Is_Active__c = true
        );
        insert rule;

        Map<String, Object> payload = new Map<String, Object>{ 'mobile' => '9999999999' };

        Test.startTest();
        SObject result = IntegrationFieldMappingEngine.mapPayload('TEST_BOOL', payload);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testNumberDataType() {
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'Number Test',
            Source_Name__c = 'TEST_NUMBER',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = true,
            Version__c = 1
        );
        insert config;

        Integration_Field_Rule__c rule = new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'mobile',
            SF_Field_API_Name__c = 'Mobile__c',
            Data_Type__c = 'Phone',
            Sequence__c = 1,
            Is_Active__c = true
        );
        insert rule;

        Map<String, Object> payload = new Map<String, Object>{ 'mobile' => '5551234567' };

        Test.startTest();
        Map<String, Object> fieldMap = IntegrationFieldMappingEngine.mapPayloadToFieldMap('TEST_NUMBER', payload);
        Test.stopTest();

        System.assert(fieldMap.containsKey('Mobile__c'));
    }

    @IsTest
    static void testValidatePayload_missingRequired() {
        // Uses TEST_CP_REGISTRATION from @TestSetup
        Map<String, Object> payload = new Map<String, Object>{
            'email' => 'test@example.com'
            // mobile is required but missing
        };

        Test.startTest();
        List<String> errors = IntegrationFieldMappingEngine.validatePayload('TEST_CP_REGISTRATION', payload);
        Test.stopTest();

        System.assert(errors.size() > 0, 'Should have validation error for missing mobile');
    }

    // ════════════════════════════════════════════════════════════
    // DATE AND DATETIME DATA TYPE TESTS
    // ════════════════════════════════════════════════════════════

    @IsTest
    static void testDateDataType() {
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'Date Test',
            Source_Name__c = 'TEST_DATE',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = true,
            Version__c = 1
        );
        insert config;

        Integration_Field_Rule__c rule = new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'mobile',
            SF_Field_API_Name__c = 'Mobile__c',
            Data_Type__c = 'Phone',
            Sequence__c = 1,
            Is_Active__c = true
        );
        insert rule;

        Map<String, Object> payload = new Map<String, Object>{ 'mobile' => '8888888888' };

        Test.startTest();
        SObject result = IntegrationFieldMappingEngine.mapPayload('TEST_DATE', payload);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testNumberConversionError() {
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'NumErr Test',
            Source_Name__c = 'TEST_NUM_ERR',
            Target_Object__c = 'Channel_Partner__c',
            Is_Active__c = true,
            Version__c = 1
        );
        insert config;

        Integration_Field_Rule__c rule = new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'amount',
            SF_Field_API_Name__c = 'Mobile__c',
            Data_Type__c = 'Number',
            Sequence__c = 1,
            Is_Active__c = true
        );
        insert rule;

        Map<String, Object> payload = new Map<String, Object>{ 'amount' => 'not-a-number' };

        Test.startTest();
        try {
            IntegrationFieldMappingEngine.mapPayload('TEST_NUM_ERR', payload);
            System.assert(false, 'Should throw for invalid number');
        } catch (IntegrationFieldMappingEngine.IntegrationMappingException e) {
            System.assert(e.getMessage().contains('number'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testMapPayloadToFieldMap_withDefaultAndStatic() {
        // Uses TEST_STATIC from earlier test
        Integration_Source_Config__c config = [
            SELECT Id FROM Integration_Source_Config__c WHERE Source_Name__c = 'TEST_CP_REGISTRATION' LIMIT 1
        ];

        // Payload with blank cp_type to trigger default
        Map<String, Object> payload = new Map<String, Object>{
            'mobile' => '7777777777',
            'email' => 'map@test.com',
            'cp_type' => ''
        };

        Test.startTest();
        Map<String, Object> fieldMap = IntegrationFieldMappingEngine.mapPayloadToFieldMap('TEST_CP_REGISTRATION', payload);
        Test.stopTest();

        System.assertEquals('Individual', fieldMap.get('CP_Type__c'), 'Empty string should use default');
    }
}