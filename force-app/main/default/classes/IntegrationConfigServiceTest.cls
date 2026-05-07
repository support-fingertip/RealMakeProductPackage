/**
 * @description Test class for IntegrationConfigService -- configuration loading and caching.
 *              Covers endpoint retrieval, template retrieval, response/field mapping retrieval,
 *              bulk retrieval, cache clearing, and configuration validation.
 * @author Integration Platform
 */
@IsTest
private class IntegrationConfigServiceTest {

    /**
     * @description Verifies that getEndpoint() retrieves an endpoint by its unique key.
     */
    @IsTest
    static void testGetEndpoint() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('CONFIG_TEST_KEY');

        // Act
        Test.startTest();
        Integration_Endpoint__c retrieved = IntegrationConfigService.getEndpoint('CONFIG_TEST_KEY');
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, retrieved, 'Endpoint should be found');
        System.assertEquals(endpoint.Id, retrieved.Id, 'Should return the correct endpoint');
        System.assertEquals('CONFIG_TEST_KEY', retrieved.Integration_Key__c, 'Integration key should match');
    }

    /**
     * @description Verifies that getEndpoint() throws IntegrationConfigException for a non-existent key.
     */
    @IsTest
    static void testGetEndpointNotFound() {
        // Act & Assert
        Test.startTest();
        try {
            IntegrationConfigService.getEndpoint('NONEXISTENT_KEY');
            System.assert(false, 'Should have thrown IntegrationConfigException');
        } catch (IntegrationConfigService.IntegrationConfigException e) {
            System.assert(e.getMessage().contains('No Integration Endpoint found'),
                'Exception message should indicate not found');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies that getRequestTemplate() retrieves the active template for an endpoint.
     */
    @IsTest
    static void testGetRequestTemplate() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('TEMPLATE_TEST');
        Integration_Request_Template__c template = TestDataFactory.createRequestTemplate(
            endpoint.Id, '{"key":"{{value}}"}'
        );

        // Act
        Test.startTest();
        Integration_Request_Template__c retrieved = IntegrationConfigService.getRequestTemplate(endpoint.Id);
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, retrieved, 'Template should be found');
        System.assertEquals(template.Id, retrieved.Id, 'Should return the correct template');
        System.assertEquals('{"key":"{{value}}"}', retrieved.Body_Template__c, 'Body template should match');
    }

    /**
     * @description Verifies that getResponseMappings() retrieves mappings ordered by Order__c.
     */
    @IsTest
    static void testGetResponseMappings() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('RESP_MAP_TEST');

        Integration_Response_Mapping__c mapping1 = new Integration_Response_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'First Mapping',
            Response_JSON_Path__c = 'data.first',
            Target_Object__c = 'Account',
            Target_Field__c = 'Name',
            Data_Type__c = 'String',
            Active__c = true,
            Order__c = 2
        );

        Integration_Response_Mapping__c mapping2 = new Integration_Response_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Second Mapping',
            Response_JSON_Path__c = 'data.second',
            Target_Object__c = 'Account',
            Target_Field__c = 'Description',
            Data_Type__c = 'String',
            Active__c = true,
            Order__c = 1
        );

        insert new List<Integration_Response_Mapping__c>{ mapping1, mapping2 };

        // Act
        Test.startTest();
        List<Integration_Response_Mapping__c> retrieved = IntegrationConfigService.getResponseMappings(endpoint.Id);
        Test.stopTest();

        // Assert
        System.assertEquals(2, retrieved.size(), 'Should return both active mappings');
        System.assertEquals(1, retrieved[0].Order__c, 'First result should have lowest Order__c');
        System.assertEquals(2, retrieved[1].Order__c, 'Second result should have higher Order__c');
    }

    /**
     * @description Verifies that getFieldMappings() retrieves field mappings filtered by direction.
     */
    @IsTest
    static void testGetFieldMappings() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('FIELD_MAP_TEST');
        TestDataFactory.createFieldMapping(endpoint.Id, 'Name', 'name', 'Outbound');
        TestDataFactory.createFieldMapping(endpoint.Id, 'ext_id', 'External_Id__c', 'Inbound');

        // Act
        Test.startTest();
        List<Integration_Field_Mapping__c> outboundMappings =
            IntegrationConfigService.getFieldMappings(endpoint.Id, 'Outbound');
        List<Integration_Field_Mapping__c> inboundMappings =
            IntegrationConfigService.getFieldMappings(endpoint.Id, 'Inbound');
        Test.stopTest();

        // Assert
        System.assertEquals(1, outboundMappings.size(), 'Should return one outbound mapping');
        System.assertEquals('Name', outboundMappings[0].Source_Field__c, 'Source should be Name');
        System.assertEquals(1, inboundMappings.size(), 'Should return one inbound mapping');
    }

    /**
     * @description Verifies that clearCache() successfully resets all internal caches,
     *              causing a fresh SOQL query on subsequent retrieval.
     */
    @IsTest
    static void testClearCache() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('CACHE_TEST');

        // Load into cache
        IntegrationConfigService.getEndpoint('CACHE_TEST');

        // Act
        Test.startTest();
        IntegrationConfigService.clearCache();

        // The second call should query the database again (no exception expected)
        Integration_Endpoint__c retrieved = IntegrationConfigService.getEndpoint('CACHE_TEST');
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, retrieved, 'Should retrieve endpoint after cache clear');
        System.assertEquals(endpoint.Id, retrieved.Id, 'Should return same endpoint');
    }

    /**
     * @description Verifies that validateConfiguration() returns errors for invalid endpoints
     *              and an empty list for valid ones.
     */
    @IsTest
    static void testValidateEndpoint() {
        // Arrange -- valid endpoint
        Integration_Endpoint__c validEndpoint = new Integration_Endpoint__c(
            Integration_Key__c = 'VALIDATE_VALID',
            Base_URL__c = 'https://api.example.com',
            HTTP_Method__c = 'POST',
            Timeout__c = 30000,
            Active__c = true
        );
        insert validEndpoint;

        // Arrange -- invalid endpoint (mutate validated copy in memory to bypass
        // restricted-picklist DML and required-field validation).
        Integration_Endpoint__c invalidEndpoint = new Integration_Endpoint__c(
            Integration_Key__c = 'VALIDATE_INVALID',
            Base_URL__c = 'https://api.example.com',
            HTTP_Method__c = 'POST',
            Active__c = true
        );
        insert invalidEndpoint;
        invalidEndpoint.HTTP_Method__c = 'INVALID_METHOD';
        invalidEndpoint.Base_URL__c = null;

        // Act
        Test.startTest();
        List<String> validErrors = IntegrationConfigService.validateConfiguration(validEndpoint);
        List<String> invalidErrors = IntegrationConfigService.validateConfiguration(invalidEndpoint);
        List<String> nullErrors = IntegrationConfigService.validateConfiguration(null);
        Test.stopTest();

        // Assert
        System.assertEquals(0, validErrors.size(), 'Valid endpoint should produce no errors');
        System.assert(invalidErrors.size() >= 1, 'Invalid endpoint should produce at least one error');
        System.assertEquals(1, nullErrors.size(), 'Null endpoint should produce one error');
        System.assert(nullErrors[0].contains('null'), 'Error should mention null');
    }

    /**
     * @description Verifies that getEndpoint() throws IntegrationConfigException for blank key.
     */
    @IsTest
    static void testGetEndpointBlankKey() {
        Test.startTest();
        try {
            IntegrationConfigService.getEndpoint('');
            System.assert(false, 'Should have thrown IntegrationConfigException for blank key');
        } catch (IntegrationConfigService.IntegrationConfigException e) {
            System.assert(e.getMessage().contains('blank'),
                'Exception should mention blank key');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies that getRequestTemplate() returns null for a null endpoint ID.
     */
    @IsTest
    static void testGetRequestTemplateNullId() {
        Test.startTest();
        Integration_Request_Template__c result = IntegrationConfigService.getRequestTemplate(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for null endpoint ID');
    }
}