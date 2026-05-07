/**
 * @description Test class for ResponseMapper -- JSON response path mapping.
 *              Covers simple mapping, nested paths, array access, default values,
 *              type conversion, and empty/null response handling.
 * @author Integration Platform
 */
@IsTest
private class ResponseMapperTest {

    /**
     * @description Verifies that a simple JSON path like "data.name" is correctly mapped.
     */
    @IsTest
    static void testSimpleMapping() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('RESP_SIMPLE');
        Integration_Response_Mapping__c mapping = new Integration_Response_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name Mapping',
            Response_JSON_Path__c = 'data.name',
            Target_Object__c = 'Account',
            Target_Field__c = 'Name',
            Data_Type__c = 'String',
            Active__c = true,
            Order__c = 1
        );
        insert mapping;

        String responseBody = '{"data":{"name":"Test Account"}}';
        List<Integration_Response_Mapping__c> mappings = new List<Integration_Response_Mapping__c>{ mapping };

        // Act
        Test.startTest();
        Map<String, Object> result = ResponseMapper.mapResponse(responseBody, mappings);
        Test.stopTest();

        // Assert
        System.assertEquals('Test Account', result.get('Account.Name'),
            'Simple path should map correctly');
    }

    /**
     * @description Verifies that deeply nested JSON paths are correctly resolved.
     */
    @IsTest
    static void testNestedMapping() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('RESP_NESTED');
        Integration_Response_Mapping__c mapping = new Integration_Response_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Deep Mapping',
            Response_JSON_Path__c = 'response.data.details.city',
            Target_Object__c = 'Account',
            Target_Field__c = 'BillingCity',
            Data_Type__c = 'String',
            Active__c = true,
            Order__c = 1
        );
        insert mapping;

        String responseBody = '{"response":{"data":{"details":{"city":"San Francisco"}}}}';
        List<Integration_Response_Mapping__c> mappings = new List<Integration_Response_Mapping__c>{ mapping };

        // Act
        Test.startTest();
        Map<String, Object> result = ResponseMapper.mapResponse(responseBody, mappings);
        Test.stopTest();

        // Assert
        System.assertEquals('San Francisco', result.get('Account.BillingCity'),
            'Nested path should resolve correctly');
    }

    /**
     * @description Verifies that array index access in paths (e.g., "items[0].name") works.
     */
    @IsTest
    static void testArrayAccess() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('RESP_ARRAY');
        Integration_Response_Mapping__c mapping = new Integration_Response_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Array Mapping',
            Response_JSON_Path__c = 'items[0].name',
            Target_Object__c = 'Account',
            Target_Field__c = 'Name',
            Data_Type__c = 'String',
            Active__c = true,
            Order__c = 1
        );
        insert mapping;

        String responseBody = '{"items":[{"name":"First Item"},{"name":"Second Item"}]}';
        List<Integration_Response_Mapping__c> mappings = new List<Integration_Response_Mapping__c>{ mapping };

        // Act
        Test.startTest();
        Map<String, Object> result = ResponseMapper.mapResponse(responseBody, mappings);
        Test.stopTest();

        // Assert
        System.assertEquals('First Item', result.get('Account.Name'),
            'Array index access should resolve first item');
    }

    /**
     * @description Verifies that the default value is used when a JSON path is not found.
     */
    @IsTest
    static void testDefaultValue() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('RESP_DEFAULT');
        Integration_Response_Mapping__c mapping = new Integration_Response_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Default Mapping',
            Response_JSON_Path__c = 'nonexistent.path',
            Target_Object__c = 'Account',
            Target_Field__c = 'Industry',
            Data_Type__c = 'String',
            Default_Value__c = 'Technology',
            Active__c = true,
            Order__c = 1
        );
        insert mapping;

        String responseBody = '{"data":"something"}';
        List<Integration_Response_Mapping__c> mappings = new List<Integration_Response_Mapping__c>{ mapping };

        // Act
        Test.startTest();
        Map<String, Object> result = ResponseMapper.mapResponse(responseBody, mappings);
        Test.stopTest();

        // Assert
        System.assertEquals('Technology', result.get('Account.Industry'),
            'Default value should be used when path is not found');
    }

    /**
     * @description Verifies type conversion for Integer, Decimal, Boolean, and String types.
     */
    @IsTest
    static void testTypeConversion() {
        // Act
        Test.startTest();
        Object intResult = ResponseMapper.convertType('42', 'Integer');
        Object decResult = ResponseMapper.convertType('3.14', 'Decimal');
        Object boolResult = ResponseMapper.convertType('true', 'Boolean');
        Object strResult = ResponseMapper.convertType(42, 'String');
        Object nullResult = ResponseMapper.convertType(null, 'String');
        Test.stopTest();

        // Assert
        System.assertEquals(42, intResult, 'Should convert string to Integer');
        System.assertEquals(3.14, (Decimal) decResult, 'Should convert string to Decimal');
        System.assertEquals(true, boolResult, 'Should convert string to Boolean');
        System.assertEquals('42', strResult, 'Should convert Integer to String');
        System.assertEquals(null, nullResult, 'Null input should return null');
    }

    /**
     * @description Verifies that empty or null response body returns an empty result map.
     */
    @IsTest
    static void testEmptyResponse() {
        // Arrange
        Integration_Endpoint__c endpoint = TestDataFactory.createEndpoint('RESP_EMPTY');
        Integration_Response_Mapping__c mapping = new Integration_Response_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Empty Mapping',
            Response_JSON_Path__c = 'data.name',
            Target_Object__c = 'Account',
            Target_Field__c = 'Name',
            Data_Type__c = 'String',
            Active__c = true,
            Order__c = 1
        );
        insert mapping;

        List<Integration_Response_Mapping__c> mappings = new List<Integration_Response_Mapping__c>{ mapping };

        // Act
        Test.startTest();
        Map<String, Object> resultNull = ResponseMapper.mapResponse(null, mappings);
        Map<String, Object> resultEmpty = ResponseMapper.mapResponse('', mappings);
        Map<String, Object> resultNullMappings = ResponseMapper.mapResponse('{"data":"test"}', null);
        Test.stopTest();

        // Assert
        System.assertEquals(0, resultNull.size(), 'Null response should return empty map');
        System.assertEquals(0, resultEmpty.size(), 'Empty response should return empty map');
        System.assertEquals(0, resultNullMappings.size(), 'Null mappings should return empty map');
    }

    /**
     * @description Verifies that resolveJsonPath works directly with a parsed JSON object.
     */
    @IsTest
    static void testResolveJsonPathDirect() {
        // Arrange
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
            '{"level1":{"level2":{"value":"deep"}}}'
        );

        // Act
        Test.startTest();
        Object result = ResponseMapper.resolveJsonPath(parsed, 'level1.level2.value');
        Object nullResult = ResponseMapper.resolveJsonPath(parsed, 'nonexistent');
        Object nullObj = ResponseMapper.resolveJsonPath(null, 'any.path');
        Test.stopTest();

        // Assert
        System.assertEquals('deep', result, 'Should resolve deep nested path');
        System.assertEquals(null, nullResult, 'Non-existent path should return null');
        System.assertEquals(null, nullObj, 'Null object should return null');
    }
}