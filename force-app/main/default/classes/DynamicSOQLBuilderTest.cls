/**
 * @description Test class for DynamicSOQLBuilder -- dynamic SOQL query building.
 *              Covers simple query generation, custom filters, relationship fields,
 *              and null input handling.
 * @author Integration Platform
 */
@IsTest
private class DynamicSOQLBuilderTest {

    /**
     * @description Verifies that a basic query is generated correctly with object name,
     *              field list, and a record ID filter.
     */
    @IsTest
    static void testBuildSimpleQuery() {
        // Arrange
        Account testAcc = new Account(Name = 'SOQL Test');
        insert testAcc;

        // Act
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', null, testAcc.Id);
        Test.stopTest();

        // Assert
        System.assert(query.contains('SELECT'), 'Query should start with SELECT');
        System.assert(query.contains('Name'), 'Query should contain requested fields');
        System.assert(query.contains('FROM Account'), 'Query should contain FROM clause');
        System.assert(query.contains('WHERE'), 'Query should contain WHERE clause for record ID');
        System.assert(query.contains(String.valueOf(testAcc.Id)), 'Query should reference the record Id');

        // Verify the query is executable
        List<SObject> results = Database.query(query);
        System.assertEquals(1, results.size(), 'Query should return the test account');
    }

    /**
     * @description Verifies that a custom filter clause is correctly incorporated into the query.
     */
    @IsTest
    static void testBuildQueryWithFilter() {
        // Arrange
        Account testAcc = new Account(Name = 'Filter Test', Industry = 'Technology');
        insert testAcc;

        // Act
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery(
            'Account', 'Id, Name, Industry', 'Industry = \'Technology\'', null
        );
        Test.stopTest();

        // Assert
        System.assert(query.contains('WHERE'), 'Query should contain WHERE clause');
        System.assert(query.contains('Technology'), 'Filter should be included');

        // Verify executable
        List<SObject> results = Database.query(query);
        System.assert(results.size() >= 1, 'Query should return filtered results');
    }

    /**
     * @description Verifies that relationship fields (e.g., Account.Name from Contact)
     *              are handled correctly in the field list.
     */
    @IsTest
    static void testBuildQueryWithRelationship() {
        // Act
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery(
            'Contact', 'Id, FirstName, LastName, Account.Name', null, null
        );
        Test.stopTest();

        // Assert
        System.assert(query.contains('Account.Name'), 'Query should contain relationship field');
        System.assert(query.contains('FROM Contact'), 'Query should target Contact object');
    }

    /**
     * @description Verifies that null or blank object name throws DynamicSOQLException.
     */
    @IsTest
    static void testNullInputs() {
        // Act & Assert -- null object name
        Test.startTest();
        try {
            DynamicSOQLBuilder.buildQuery(null, 'Id, Name', null, null);
            System.assert(false, 'Should have thrown DynamicSOQLException for null object');
        } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
            System.assert(e.getMessage().contains('required'),
                'Exception should mention required object name');
        }

        // Blank object name
        try {
            DynamicSOQLBuilder.buildQuery('', 'Id, Name', null, null);
            System.assert(false, 'Should have thrown DynamicSOQLException for blank object');
        } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
            System.assert(e.getMessage().contains('required'),
                'Exception should mention required object name');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies that blank fields default to Id only.
     */
    @IsTest
    static void testBlankFieldsDefaultsToId() {
        // Act
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery('Account', null, null, null);
        Test.stopTest();

        // Assert
        System.assert(query.contains('SELECT Id'), 'Query should default to Id field');
    }

    /**
     * @description Verifies the extended buildQuery overload with ORDER BY and LIMIT.
     */
    @IsTest
    static void testBuildQueryWithOrderAndLimit() {
        // Act
        Test.startTest();
        String query = DynamicSOQLBuilder.buildQuery(
            'Account', 'Id, Name', null, null, 'Name', true, 10
        );
        Test.stopTest();

        // Assert
        System.assert(query.contains('ORDER BY Name ASC'), 'Query should contain ORDER BY');
        System.assert(query.contains('LIMIT 10'), 'Query should contain LIMIT');
    }

    /**
     * @description Verifies that dangerous filter patterns are rejected.
     */
    @IsTest
    static void testDangerousFilterRejected() {
        Test.startTest();
        try {
            DynamicSOQLBuilder.buildQuery('Account', 'Id, Name', 'Name = \'test\'; DELETE', null);
            System.assert(false, 'Should have thrown DynamicSOQLException for dangerous pattern');
        } catch (DynamicSOQLBuilder.DynamicSOQLException e) {
            System.assert(e.getMessage().contains('dangerous'),
                'Exception should mention dangerous pattern');
        }
        Test.stopTest();
    }

    /**
     * @description Verifies buildRelatedQuery creates a proper relationship query.
     */
    @IsTest
    static void testBuildRelatedQuery() {
        // Arrange
        Account parentAcc = new Account(Name = 'Parent Account');
        insert parentAcc;

        // Act
        Test.startTest();
        String query = DynamicSOQLBuilder.buildRelatedQuery(
            'Contact', 'Id, FirstName, LastName', 'AccountId', parentAcc.Id
        );
        Test.stopTest();

        // Assert
        System.assert(query.contains('AccountId'), 'Should reference relationship field');
        System.assert(query.contains('FROM Contact'), 'Should target Contact object');
    }
}