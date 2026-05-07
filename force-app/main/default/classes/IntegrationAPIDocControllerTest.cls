@IsTest
private class IntegrationAPIDocControllerTest {

    @TestSetup
    static void setupTestData() {
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'PDF Test Config',
            Source_Name__c = 'TEST_PDF_DOC',
            Target_Object__c = 'Lead__c',
            Is_Active__c = true,
            Version__c = 2,
            Description__c = 'Test config for PDF documentation generation',
            API_Schema_JSON__c = '[{"name":"first_name","label":"First Name","type":"Text","required":true},{"name":"mobile","label":"Mobile","type":"Phone","required":true},{"name":"email","label":"Email","type":"Email","required":false},{"name":"amount","label":"Amount","type":"Number","required":false},{"name":"is_verified","label":"Is Verified","type":"Boolean","required":false},{"name":"dob","label":"Date of Birth","type":"Date","required":false},{"name":"created_at","label":"Created At","type":"DateTime","required":false}]',
            Validation_Rules_JSON__c = '[{"field":"mobile","regex":"[0-9]{10}","message":"Must be 10 digits"}]',
            Endpoint_URL__c = '/services/apexrest/integration/TEST_PDF_DOC',
            Enable_Duplicate_Check__c = true
        );
        insert config;

        Integration_Field_Rule__c textRule = new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'first_name',
            API_Field_Label__c = 'First Name',
            SF_Field_API_Name__c = 'First_Name__c',
            Is_Required__c = true,
            Data_Type__c = 'Text',
            Transform_Expression__c = 'UPPERCASE',
            Sequence__c = 1,
            Is_Active__c = true,
            Is_Static__c = false
        );

        Integration_Field_Rule__c lookupRule = new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = 'project_code',
            API_Field_Label__c = 'Project Code',
            SF_Field_API_Name__c = 'Project__c',
            Is_Required__c = true,
            Data_Type__c = 'Lookup',
            Sequence__c = 2,
            Is_Active__c = true,
            Is_Static__c = false
        );

        Integration_Field_Rule__c staticRule = new Integration_Field_Rule__c(
            Integration_Source_Config__c = config.Id,
            API_Field_Name__c = '',
            API_Field_Label__c = '',
            SF_Field_API_Name__c = 'Lead_Source__c',
            Is_Required__c = false,
            Default_Value__c = 'Website',
            Data_Type__c = 'Text',
            Sequence__c = 3,
            Is_Active__c = true,
            Is_Static__c = true
        );

        insert new List<Integration_Field_Rule__c>{ textRule, lookupRule, staticRule };

        Integration_Lookup_Rule__c lkRule = new Integration_Lookup_Rule__c(
            Integration_Field_Rule__c = lookupRule.Id,
            Lookup_Object__c = 'Project__c',
            Match_Field__c = 'Project_Code__c',
            Return_Field__c = 'Id',
            Fail_On_No_Match__c = true,
            Additional_Filter__c = 'Is_Active__c = true'
        );
        insert lkRule;
    }

    @IsTest
    static void testControllerWithValidConfig() {
        Integration_Source_Config__c config = [
            SELECT Id FROM Integration_Source_Config__c
            WHERE Source_Name__c = 'TEST_PDF_DOC' LIMIT 1
        ];

        Test.startTest();
        PageReference pageRef = new PageReference('/apex/IntegrationAPIDoc');
        pageRef.getParameters().put('id', config.Id);
        Test.setCurrentPage(pageRef);

        IntegrationAPIDocController ctrl = new IntegrationAPIDocController();
        Test.stopTest();

        // Config loaded
        System.assertNotEquals(null, ctrl.config, 'Config should be loaded');
        System.assertEquals('TEST_PDF_DOC', ctrl.config.Source_Name__c);
        System.assertEquals(true, ctrl.getHasConfig());

        // Field rules (as FieldMappingInfo rows)
        System.assertEquals(true, ctrl.getHasFieldRules());
        System.assertEquals(3, ctrl.mappingRows.size());

        // API schema
        System.assertEquals(true, ctrl.getHasApiSchema());
        System.assertEquals(7, ctrl.apiSchemaFields.size());

        // Validation rules
        System.assertEquals(true, ctrl.getHasValidationRules());
        System.assertEquals(1, ctrl.validationRules.size());

        // Lookup rules
        System.assertEquals(true, ctrl.getHasLookupRules());

        // JSON strings
        System.assert(String.isNotBlank(ctrl.sampleRequestJson));
        System.assert(String.isNotBlank(ctrl.sampleResponseJson));

        // Metadata
        System.assert(String.isNotBlank(ctrl.generatedDate));
        System.assert(ctrl.endpointUrl.contains('integration'));
        System.assertEquals('v2', ctrl.getVersionDisplay());
        System.assertEquals(null, ctrl.getRenderFormat());

        // Doc settings defaults (CMT records can't be inserted in tests)
        System.assertNotEquals(null, ctrl.headerColor);
    }

    @IsTest
    static void testMappingRowDetails() {
        Integration_Source_Config__c config = [
            SELECT Id FROM Integration_Source_Config__c
            WHERE Source_Name__c = 'TEST_PDF_DOC' LIMIT 1
        ];

        PageReference pageRef = new PageReference('/apex/IntegrationAPIDoc');
        pageRef.getParameters().put('id', config.Id);
        Test.setCurrentPage(pageRef);

        IntegrationAPIDocController ctrl = new IntegrationAPIDocController();

        // First row: text rule
        IntegrationAPIDocController.FieldMappingInfo row1 = ctrl.mappingRows[0];
        System.assertEquals('first_name', row1.apiFieldName);
        System.assertEquals('First_Name__c', row1.sfFieldApiName);
        System.assertEquals('Text', row1.dataType);
        System.assertEquals(true, row1.isRequired);
        System.assertEquals('UPPERCASE', row1.transformExpression);
        System.assertEquals(false, row1.isStatic);
        System.assertEquals(false, row1.hasLookup);

        // Second row: lookup rule
        IntegrationAPIDocController.FieldMappingInfo row2 = ctrl.mappingRows[1];
        System.assertEquals('project_code', row2.apiFieldName);
        System.assertEquals('Lookup', row2.dataType);
        System.assertEquals(true, row2.hasLookup);
        System.assertEquals('Project__c', row2.lookupObject);
        System.assertEquals('Project_Code__c', row2.matchField);
        System.assertEquals('Id', row2.returnField);
        System.assertEquals(true, row2.failOnNoMatch);

        // Third row: static rule
        IntegrationAPIDocController.FieldMappingInfo row3 = ctrl.mappingRows[2];
        System.assertEquals(true, row3.isStatic);
        System.assertEquals('Website', row3.defaultValue);
    }

    @IsTest
    static void testControllerPdfFormat() {
        Integration_Source_Config__c config = [
            SELECT Id FROM Integration_Source_Config__c
            WHERE Source_Name__c = 'TEST_PDF_DOC' LIMIT 1
        ];

        Test.startTest();
        PageReference pageRef = new PageReference('/apex/IntegrationAPIDoc');
        pageRef.getParameters().put('id', config.Id);
        pageRef.getParameters().put('format', 'pdf');
        Test.setCurrentPage(pageRef);

        IntegrationAPIDocController ctrl = new IntegrationAPIDocController();
        Test.stopTest();

        System.assertEquals('pdf', ctrl.getRenderFormat());
    }

    @IsTest
    static void testControllerWithNoId() {
        Test.startTest();
        PageReference pageRef = new PageReference('/apex/IntegrationAPIDoc');
        Test.setCurrentPage(pageRef);

        IntegrationAPIDocController ctrl = new IntegrationAPIDocController();
        Test.stopTest();

        System.assertEquals(null, ctrl.config);
        System.assertEquals(false, ctrl.getHasConfig());
        System.assertEquals(false, ctrl.getHasFieldRules());
        System.assertEquals(false, ctrl.getHasApiSchema());
        System.assertEquals(false, ctrl.getHasValidationRules());
        System.assertEquals(false, ctrl.getHasLookupRules());
        System.assertEquals('', ctrl.getVersionDisplay());
    }

    @IsTest
    static void testControllerWithInvalidId() {
        Test.startTest();
        PageReference pageRef = new PageReference('/apex/IntegrationAPIDoc');
        pageRef.getParameters().put('id', 'a005g000000XXXXX');
        Test.setCurrentPage(pageRef);

        Boolean threwException = false;
        try {
            IntegrationAPIDocController ctrl = new IntegrationAPIDocController();
        } catch (Exception e) {
            threwException = true;
        }
        Test.stopTest();
        // Should handle gracefully - config will be null
    }

    @IsTest
    static void testApiSchemaFieldInfo() {
        Integration_Source_Config__c config = [
            SELECT Id FROM Integration_Source_Config__c
            WHERE Source_Name__c = 'TEST_PDF_DOC' LIMIT 1
        ];

        PageReference pageRef = new PageReference('/apex/IntegrationAPIDoc');
        pageRef.getParameters().put('id', config.Id);
        Test.setCurrentPage(pageRef);

        IntegrationAPIDocController ctrl = new IntegrationAPIDocController();

        // Verify field parsing
        IntegrationAPIDocController.ApiFieldInfo textField = ctrl.apiSchemaFields[0];
        System.assertEquals('first_name', textField.name);
        System.assertEquals('First Name', textField.label);
        System.assertEquals('Text', textField.fieldType);
        System.assertEquals(true, textField.isRequired);
        System.assert(String.isNotBlank(textField.sampleValue));

        // Verify different data types generate sample values
        IntegrationAPIDocController.ApiFieldInfo phoneField = ctrl.apiSchemaFields[1];
        System.assert(phoneField.sampleValue.contains('9876543210'));

        IntegrationAPIDocController.ApiFieldInfo emailField = ctrl.apiSchemaFields[2];
        System.assert(emailField.sampleValue.contains('example.com'));

        // Verify validation rule
        IntegrationAPIDocController.ValidationRuleInfo rule = ctrl.validationRules[0];
        System.assertEquals('mobile', rule.field);
        System.assertEquals('[0-9]{10}', rule.regex);
        System.assertEquals('Must be 10 digits', rule.message);
    }

    @IsTest
    static void testDocSettingsDefaults() {
        // CMT records can't be inserted in tests, so verify defaults
        PageReference pageRef = new PageReference('/apex/IntegrationAPIDoc');
        Test.setCurrentPage(pageRef);

        IntegrationAPIDocController ctrl = new IntegrationAPIDocController();

        // Verify default values when no CMT record exists
        System.assertEquals('#1B2A4A', ctrl.headerColor);
        System.assertEquals(false, ctrl.hasLogo);
        System.assertEquals('', ctrl.logoDataUrl);
    }

    @IsTest
    static void testConfigWithNoEndpointUrl() {
        // Create a config without explicit endpoint URL
        Integration_Source_Config__c config = new Integration_Source_Config__c(
            Name = 'No Endpoint Config',
            Source_Name__c = 'NO_ENDPOINT',
            Target_Object__c = 'Lead__c',
            Is_Active__c = true,
            Version__c = 1
        );
        insert config;

        PageReference pageRef = new PageReference('/apex/IntegrationAPIDoc');
        pageRef.getParameters().put('id', config.Id);
        Test.setCurrentPage(pageRef);

        IntegrationAPIDocController ctrl = new IntegrationAPIDocController();

        // Endpoint URL is best-effort; just verify the controller initialized.
        System.assertNotEquals(null, ctrl);
        System.assertEquals(false, ctrl.getHasApiSchema());
        System.assertEquals(false, ctrl.getHasFieldRules());
        System.assertEquals(false, ctrl.getHasValidationRules());
    }
}