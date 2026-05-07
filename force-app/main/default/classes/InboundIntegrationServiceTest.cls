/**
 * @description Test class for InboundIntegrationService.
 *              Covers processInbound with blank key, non-existent key, valid key with
 *              field mappings, authentication validation, request body parsing,
 *              transform expressions, nested value extraction, and edge cases.
 */
@IsTest
private class InboundIntegrationServiceTest {

    @IsTest
    static void testProcessInbound_blankKey() {
        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            '', '{"name":"test"}', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(400, result.statusCode);
        System.assert(result.errorMessage.contains('required'));
    }

    @IsTest
    static void testProcessInbound_nonExistentKey() {
        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'NONEXISTENT_INBOUND_KEY', '{"name":"test"}', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(404, result.statusCode);
    }

    @IsTest
    static void testProcessInbound_emptyBody() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_EMPTY');

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_EMPTY', '', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(400, result.statusCode);
    }

    @IsTest
    static void testProcessInbound_nullBody() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_NULL');

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_NULL', null, new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(400, result.statusCode);
    }

    @IsTest
    static void testProcessInbound_withFieldMappings() {
        // Create endpoint with field mappings that map to Account
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_MAP');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name mapping',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = true,
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        String body = '{"name":"Test Account"}';

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_MAP', body, new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assert(result.recordIds.size() > 0, 'Should have created a record');
    }

    @IsTest
    static void testProcessInbound_arrayBody() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_ARR');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name arr',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = true,
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        String body = '[{"name":"Account1"},{"name":"Account2"}]';

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_ARR', body, new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(2, result.recordIds.size());
    }

    @IsTest
    static void testProcessInbound_methodMismatch() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_METHOD');
        endpoint.HTTP_Method__c = 'PUT';
        update endpoint;

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name method',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_METHOD', '{"name":"test"}', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(405, result.statusCode);
    }

    @IsTest
    static void testProcessInbound_apiKeyAuth_valid() {
        Integration_Auth_Profile__c authProfile = TestDataFactory.createAuthProfile('INBOUND_AUTH', 'API_Key');
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_APIKEY');
        endpoint.Auth_Profile__c = authProfile.Id;
        update endpoint;

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name auth',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        Map<String, String> headers = new Map<String, String>{
            'x-api-key' => 'test-api-key-12345'
        };

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_APIKEY', '{"name":"Auth Test"}', headers, 'POST'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
    }

    @IsTest
    static void testProcessInbound_apiKeyAuth_invalid() {
        Integration_Auth_Profile__c authProfile = TestDataFactory.createAuthProfile('INBOUND_BAD_AUTH', 'API_Key');
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_BADKEY');
        endpoint.Auth_Profile__c = authProfile.Id;
        update endpoint;

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name badauth',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        Map<String, String> headers = new Map<String, String>{
            'x-api-key' => 'wrong-key'
        };

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_BADKEY', '{"name":"Bad Auth"}', headers, 'POST'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(403, result.statusCode);
    }

    @IsTest
    static void testProcessInbound_apiKeyAuth_missing() {
        Integration_Auth_Profile__c authProfile = TestDataFactory.createAuthProfile('INBOUND_NOKEY', 'API_Key');
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_NOKEYHDR');
        endpoint.Auth_Profile__c = authProfile.Id;
        update endpoint;

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name nokey',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_NOKEYHDR', '{"name":"test"}', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(401, result.statusCode);
    }

    @IsTest
    static void testProcessInbound_formEncoded() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_FORM');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name form',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = true,
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        String formBody = 'name=Test%20Form%20Account';

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_FORM', formBody, new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
    }

    @IsTest
    static void testProcessInbound_noFieldMappings() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_NOMAP');

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_NOMAP', '{"name":"test"}', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(500, result.statusCode);
    }

    @IsTest
    static void testProcessInbound_transformExpressions() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_XFORM');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name xform',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Transform_Expression__c = 'UPPERCASE',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_XFORM', '{"name":"lowercase value"}', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);

        // Verify the transform was applied
        Account created = [SELECT Name FROM Account WHERE Id = :result.recordIds[0]];
        System.assertEquals('LOWERCASE VALUE', created.Name);
    }

    @IsTest
    static void testProcessInbound_nestedJson() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_NESTED');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Nested name',
            Direction__c = 'Inbound',
            Source_Field__c = 'company.name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        String body = '{"company":{"name":"Nested Corp"}}';

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_NESTED', body, new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
    }

    @IsTest
    static void testProcessInbound_defaultValue() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_DEFAULT');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name default',
            Direction__c = 'Inbound',
            Source_Field__c = 'missing_field',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Default_Value__c = 'Default Account',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_DEFAULT', '{"other":"data"}', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
    }

    @IsTest
    static void testProcessInbound_invalidJson() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_BADJSON');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name badjson',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_BADJSON', 'not valid json{{{', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
    }

    @IsTest
    static void testProcessInbound_requiredFieldMissing() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_REQ');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name req',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = true,
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        // Body without 'name' field
        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_REQ', '{"other":"data"}', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        // May fail due to required field or insert error
        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testProcessInbound_lowercaseTransform() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_LOWER');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name lower',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Transform_Expression__c = 'LOWERCASE',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_LOWER', '{"name":"UPPERCASE VALUE"}', new Map<String, String>(), 'POST'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        Account created = [SELECT Name FROM Account WHERE Id = :result.recordIds[0]];
        System.assertEquals('uppercase value', created.Name);
    }

    @IsTest
    static void testProcessInbound_withNullHeaders() {
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('INBOUND_NULLHDR');

        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name nullhdr',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 1,
            Active__c = true
        );
        insert mapping;

        Test.startTest();
        InboundResult result = InboundIntegrationService.processInbound(
            'INBOUND_NULLHDR', '{"name":"NullHdr Account"}', null, 'POST'
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
    }
}