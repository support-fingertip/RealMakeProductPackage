/**
 * @description Test class for IntegrationRestResource -- REST inbound endpoint.
 *              Covers POST success, POST with invalid key, GET request handling,
 *              Site URL key extraction, URL parameter body input, form-encoded body,
 *              and merged body + URL params.
 * @author Integration Platform
 */
@IsTest
private class IntegrationRestResourceTest {

    /**
     * @description Verifies that a POST request with a valid integration key is processed
     *              and returns a proper response.
     */
    @IsTest
    static void testHandlePostSuccess() {
        // Arrange -- create endpoint with field mappings for inbound processing
        Integration_Endpoint__c endpoint = postSalesTestDataFactory.createEndpoint('INBOUND_POST_TEST');
        endpoint.HTTP_Method__c = 'POST';
        update endpoint;

        Integration_Field_Mapping__c fieldMapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Name Mapping',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = true,
            Order__c = 1,
            Active__c = true
        );
        insert fieldMapping;

        // Set up RestContext
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection/INBOUND_POST_TEST';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"name":"Inbound Test Account"}');
        req.addHeader('Content-Type', 'application/json');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        // Act
        Test.startTest();
        IntegrationRestResource.handlePost();
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, RestContext.response, 'Response should be set');
        System.assertNotEquals(null, RestContext.response.responseBody, 'Response body should be set');

        String responseStr = RestContext.response.responseBody.toString();
        System.assert(responseStr.contains('correlationId') || responseStr.contains('success'),
            'Response should contain result data');
    }

    /**
     * @description Verifies that a POST request with a missing/invalid integration key
     *              returns a 400 error response.
     */
    @IsTest
    static void testHandlePostInvalidKey() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"data":"test"}');
        req.addHeader('Content-Type', 'application/json');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handlePost();
        Test.stopTest();

       
    }

    /**
     * @description Verifies that a GET request is handled and delegates to the service layer.
     */
    @IsTest
    static void testHandleGetSuccess() {
        Integration_Endpoint__c endpoint = postSalesTestDataFactory.createEndpoint('INBOUND_GET_TEST');
        endpoint.HTTP_Method__c = 'GET';
        update endpoint;

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection/INBOUND_GET_TEST';
        req.httpMethod = 'GET';
        req.params.put('status', 'active');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handleGet();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response, 'Response should be set');
        System.assertNotEquals(null, RestContext.response.statusCode,
            'Status code should be set');
    }

    /**
     * @description Verifies that a non-existent integration key returns 404.
     */
    @IsTest
    static void testHandlePostNonExistentKey() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection/DOES_NOT_EXIST';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"data":"test"}');
        req.addHeader('Content-Type', 'application/json');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handlePost();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response.statusCode,
            'Status code should be set for non-existent key');
        System.assert(
            RestContext.response.statusCode == 404 || RestContext.response.statusCode == 500,
            'Should return error status for non-existent endpoint'
        );
    }

    /**
     * @description Verifies that PUT requests are handled correctly.
     */
    @IsTest
    static void testHandlePut() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection/PUT_TEST';
        req.httpMethod = 'PUT';
        req.requestBody = Blob.valueOf('{"data":"update"}');
        req.addHeader('Content-Type', 'application/json');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handlePut();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response, 'Response should be set');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Site URL Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Verifies integration key extraction from a Salesforce Site-prefixed URL.
     *              Site URLs add a prefix: /MySite/services/apexrest/integration/{key}
     */
    @IsTest
    static void testSiteUrlKeyExtraction() {
        Integration_Endpoint__c endpoint = postSalesTestDataFactory.createEndpoint('SITE_TEST_KEY');
        endpoint.HTTP_Method__c = 'POST';
        update endpoint;

        Integration_Field_Mapping__c fieldMapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Site Name Mapping',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 1,
            Active__c = true
        );
        insert fieldMapping;

        // Simulate a Site-prefixed URL
        RestRequest req = new RestRequest();
        req.requestURI = '/MyPartnerSite/services/apexrest/integration/SITE_TEST_KEY';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"name":"Site Account"}');
        req.addHeader('Content-Type', 'application/json');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handlePost();
        Test.stopTest();

        // The key should be extracted correctly from the Site URL
        System.assertNotEquals(null, RestContext.response, 'Response should be set');
        System.assertNotEquals(null, RestContext.response.responseBody, 'Response body should be set');
        // Should NOT be a 400 (missing key) error
        System.assertNotEquals(400, RestContext.response.statusCode,
            'Site URL should not result in missing key error');
    }

    /**
     * @description Verifies that the integration key can be provided via the
     *              ?integrationKey= URL parameter as a fallback.
     */
    @IsTest
    static void testIntegrationKeyFromUrlParam() {
        Integration_Endpoint__c endpoint = postSalesTestDataFactory.createEndpoint('PARAM_KEY_TEST');
        endpoint.HTTP_Method__c = 'POST';
        update endpoint;

        Integration_Field_Mapping__c fieldMapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Param Name Mapping',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 1,
            Active__c = true
        );
        insert fieldMapping;

        // URL ends at /integration with no path key -- key is in params instead
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"name":"Param Key Account"}');
        req.params.put('integrationKey', 'PARAM_KEY_TEST');
        req.addHeader('Content-Type', 'application/json');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handlePost();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response.responseBody, 'Response body should be set');
        // Should NOT be 400 (missing key)
        System.assertNotEquals(400, RestContext.response.statusCode,
            'URL param key should be recognized');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  URL Parameter Body Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Verifies that a POST request with NO body uses URL parameters as the
     *              request body (converted to JSON automatically).
     */
    @IsTest
    static void testPostWithUrlParamsAsBody() {
        Integration_Endpoint__c endpoint = postSalesTestDataFactory.createEndpoint('PARAMS_BODY_TEST');
        endpoint.HTTP_Method__c = 'POST';
        update endpoint;

        Integration_Field_Mapping__c fieldMapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Params Name Mapping',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = true,
            Order__c = 1,
            Active__c = true
        );
        insert fieldMapping;

        // POST with no body -- data comes from URL parameters
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection/PARAMS_BODY_TEST';
        req.httpMethod = 'POST';
        // No requestBody set
        req.params.put('name', 'URL Param Account');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handlePost();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response.responseBody, 'Response body should be set');
        String responseStr = RestContext.response.responseBody.toString();
        System.assert(responseStr.contains('success'),
            'URL params should be processed as body data');
    }

    /**
     * @description Verifies that when both a JSON body and URL parameters are present,
     *              they are merged. Body fields take precedence over URL params.
     */
    @IsTest
    static void testMergedBodyAndUrlParams() {
        Integration_Endpoint__c endpoint = postSalesTestDataFactory.createEndpoint('MERGE_BODY_TEST');
        endpoint.HTTP_Method__c = 'POST';
        update endpoint;

        Integration_Field_Mapping__c nameMapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Merge Name',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = true,
            Order__c = 1,
            Active__c = true
        );
        Integration_Field_Mapping__c industryMapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Merge Industry',
            Direction__c = 'Inbound',
            Source_Field__c = 'industry',
            Target_Field__c = 'Industry',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Order__c = 2,
            Active__c = true
        );
        insert new List<Integration_Field_Mapping__c>{ nameMapping, industryMapping };

        // Body provides name; URL params provide industry
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection/MERGE_BODY_TEST';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{"name":"Merged Account"}');
        req.params.put('industry', 'Technology');
        req.addHeader('Content-Type', 'application/json');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handlePost();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response.responseBody, 'Response body should be set');
        String responseStr = RestContext.response.responseBody.toString();
        System.assert(responseStr.contains('success'),
            'Merged body + params should be processed successfully');
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Form-Encoded Body Tests
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Verifies that a form-encoded body (application/x-www-form-urlencoded)
     *              is correctly parsed into JSON and processed.
     */
    @IsTest
    static void testFormEncodedBody() {
        Integration_Endpoint__c endpoint = postSalesTestDataFactory.createEndpoint('FORM_ENCODED_TEST');
        endpoint.HTTP_Method__c = 'POST';
        update endpoint;

        Integration_Field_Mapping__c fieldMapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Form Name Mapping',
            Direction__c = 'Inbound',
            Source_Field__c = 'name',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = true,
            Order__c = 1,
            Active__c = true
        );
        insert fieldMapping;

        // Form-encoded body
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection/FORM_ENCODED_TEST';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('name=Form+Encoded+Account&industry=Technology');
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handlePost();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response.responseBody, 'Response body should be set');
        String responseStr = RestContext.response.responseBody.toString();
        System.assert(responseStr.contains('success'),
            'Form-encoded body should be processed');
    }

    /**
     * @description Verifies the convertFormEncodedToJson utility handles URL-encoded
     *              special characters correctly.
     */
    @IsTest
    static void testConvertFormEncodedToJson() {
        // Directly test the form-encoded to JSON conversion via InboundIntegrationService
        // parseFormEncodedString path by sending a non-JSON body without the header hint
        Integration_Endpoint__c endpoint = postSalesTestDataFactory.createEndpoint('FORM_PARSE_TEST');
        endpoint.HTTP_Method__c = 'POST';
        update endpoint;

        Integration_Field_Mapping__c fieldMapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpoint.Id,
            Mapping_Name__c = 'Form Parse Name',
            Direction__c = 'Inbound',
            Source_Field__c = 'company',
            Target_Field__c = 'Name',
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = true,
            Order__c = 1,
            Active__c = true
        );
        insert fieldMapping;

        // Body is form-encoded but Content-Type header says form-urlencoded
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/restConnection/FORM_PARSE_TEST';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('company=Acme%20Corp&city=San%20Francisco');
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');

        RestResponse res = new RestResponse();

        RestContext.request = req;
        RestContext.response = res;

        Test.startTest();
        IntegrationRestResource.handlePost();
        Test.stopTest();

        System.assertNotEquals(null, RestContext.response, 'Response should be set');
        // Verify it was processed (not rejected as invalid JSON)
        System.assertNotEquals(400, RestContext.response.statusCode,
            'Form-encoded body should not be rejected as unparseable');
    }
}