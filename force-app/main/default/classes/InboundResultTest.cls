/**
 * @description Test class for InboundResult wrapper.
 *              Covers default constructor, success factory, failure factory,
 *              partial factory, toResponseMap, and all field accessors.
 */
@IsTest
private class InboundResultTest {

    @IsTest
    static void testDefaultConstructor() {
        Test.startTest();
        InboundResult result = new InboundResult();
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(200, result.statusCode);
        System.assertNotEquals(null, result.recordIds);
        System.assertEquals(0, result.recordIds.size());
        System.assertEquals('', result.errorMessage);
        System.assertNotEquals(null, result.correlationId);
        System.assert(result.correlationId.length() > 0);
        System.assertEquals(0, result.recordsProcessed);
        System.assertEquals(0, result.recordsFailed);
        System.assertNotEquals(null, result.errors);
    }

    @IsTest
    static void testSuccessFactory() {
        Account acc = new Account(Name = 'InboundResultTest');
        insert acc;

        Test.startTest();
        InboundResult result = InboundResult.success(new List<Id>{ acc.Id }, 1);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(200, result.statusCode);
        System.assertEquals(1, result.recordIds.size());
        System.assertEquals(acc.Id, result.recordIds[0]);
        System.assertEquals(1, result.recordsProcessed);
        System.assertEquals(0, result.recordsFailed);
    }

    @IsTest
    static void testSuccessFactoryNullInputs() {
        Test.startTest();
        InboundResult result = InboundResult.success(null, null);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(0, result.recordIds.size());
        System.assertEquals(0, result.recordsProcessed);
    }

    @IsTest
    static void testFailureFactory() {
        Test.startTest();
        InboundResult result = InboundResult.failure(400, 'Bad request data');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(400, result.statusCode);
        System.assertEquals('Bad request data', result.errorMessage);
    }

    @IsTest
    static void testFailureFactory404() {
        Test.startTest();
        InboundResult result = InboundResult.failure(404, 'Not found');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(404, result.statusCode);
    }

    @IsTest
    static void testFailureFactory500() {
        Test.startTest();
        InboundResult result = InboundResult.failure(500, 'Internal server error');
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(500, result.statusCode);
    }

    @IsTest
    static void testPartialFactory_allSuccess() {
        Account acc = new Account(Name = 'Partial1');
        insert acc;

        Test.startTest();
        InboundResult result = InboundResult.partial(
            new List<Id>{ acc.Id }, 1, 0, new List<String>()
        );
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(200, result.statusCode);
        System.assertEquals(1, result.recordsProcessed);
        System.assertEquals(0, result.recordsFailed);
    }

    @IsTest
    static void testPartialFactory_withFailures() {
        Test.startTest();
        InboundResult result = InboundResult.partial(
            new List<Id>(), 3, 2, new List<String>{ 'Error 1', 'Error 2' }
        );
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(207, result.statusCode);
        System.assertEquals(3, result.recordsProcessed);
        System.assertEquals(2, result.recordsFailed);
        System.assertEquals(2, result.errors.size());
    }

    @IsTest
    static void testPartialFactory_nullInputs() {
        Test.startTest();
        InboundResult result = InboundResult.partial(null, null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(200, result.statusCode);
        System.assertEquals(0, result.recordIds.size());
        System.assertEquals(0, result.recordsProcessed);
        System.assertEquals(0, result.recordsFailed);
        System.assertEquals(0, result.errors.size());
    }

    @IsTest
    static void testToResponseMap_success() {
        Account acc = new Account(Name = 'ResponseMap1');
        insert acc;

        InboundResult result = InboundResult.success(new List<Id>{ acc.Id }, 1);

        Test.startTest();
        Map<String, Object> responseMap = result.toResponseMap();
        Test.stopTest();

        System.assertEquals(true, responseMap.get('success'));
        System.assertNotEquals(null, responseMap.get('correlationId'));
        System.assertEquals(1, responseMap.get('recordsProcessed'));
        System.assertEquals(0, responseMap.get('recordsFailed'));
        System.assert(responseMap.containsKey('recordIds'));
    }

    @IsTest
    static void testToResponseMap_failure() {
        InboundResult result = InboundResult.failure(500, 'Something broke');

        Test.startTest();
        Map<String, Object> responseMap = result.toResponseMap();
        Test.stopTest();

        System.assertEquals(false, responseMap.get('success'));
        System.assertEquals('Something broke', responseMap.get('errorMessage'));
    }

    @IsTest
    static void testToResponseMap_withErrors() {
        InboundResult result = InboundResult.partial(
            new List<Id>(), 1, 1, new List<String>{ 'Record 1 failed' }
        );

        Test.startTest();
        Map<String, Object> responseMap = result.toResponseMap();
        Test.stopTest();

        System.assert(responseMap.containsKey('errors'));
    }

    @IsTest
    static void testToResponseMap_noErrorsNoRecords() {
        InboundResult result = new InboundResult();

        Test.startTest();
        Map<String, Object> responseMap = result.toResponseMap();
        Test.stopTest();

        System.assertNotEquals(null, responseMap);
        System.assertEquals(false, responseMap.containsKey('recordIds'));
        System.assertEquals(false, responseMap.containsKey('errorMessage'));
    }

    @IsTest
    static void testCorrelationIdUniqueness() {
        Test.startTest();
        InboundResult r1 = new InboundResult();
        InboundResult r2 = new InboundResult();
        Test.stopTest();

        System.assertNotEquals(r1.correlationId, r2.correlationId,
            'Two results should have different correlation IDs');
    }
}