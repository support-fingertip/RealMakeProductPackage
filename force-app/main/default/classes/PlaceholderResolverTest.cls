/**
 * @description Test class for PlaceholderResolver -- template placeholder resolution.
 *              Covers simple placeholders, nested dot-notation paths, missing placeholders,
 *              null/empty inputs, and multiple placeholder replacement.
 * @author Integration Platform
 */
@IsTest
private class PlaceholderResolverTest {

    /**
     * @description Verifies that a simple {{name}} placeholder is replaced with the
     *              corresponding value from the data map.
     */
    @IsTest
    static void testSimplePlaceholder() {
        // Arrange
        String template = 'Hello, {{name}}!';
        Map<String, Object> data = new Map<String, Object>{ 'name' => 'World' };

        // Act
        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        // Assert
        System.assertEquals('Hello, World!', result, 'Simple placeholder should be resolved');
    }

    /**
     * @description Verifies that nested dot-notation placeholders like {{account.name}} are
     *              resolved by traversing nested maps.
     */
    @IsTest
    static void testNestedPlaceholder() {
        // Arrange
        String template = 'Account: {{account.name}}';
        Map<String, Object> nestedData = new Map<String, Object>{ 'name' => 'Acme Corp' };
        Map<String, Object> data = new Map<String, Object>{ 'account' => nestedData };

        // Act
        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        // Assert
        System.assertEquals('Account: Acme Corp', result, 'Nested placeholder should be resolved');
    }

    /**
     * @description Verifies that a missing placeholder key resolves to an empty string
     *              (the default behavior).
     */
    @IsTest
    static void testMissingPlaceholder() {
        // Arrange
        String template = 'Value: {{missing}}';
        Map<String, Object> data = new Map<String, Object>{ 'present' => 'here' };

        // Act
        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        // Assert
        System.assertEquals('Value: ', result, 'Missing placeholder should resolve to empty string');
    }

    /**
     * @description Verifies that null template input is returned as-is (null).
     */
    @IsTest
    static void testNullTemplate() {
        // Arrange
        Map<String, Object> data = new Map<String, Object>{ 'key' => 'value' };

        // Act
        Test.startTest();
        String result = PlaceholderResolver.resolve(null, data);
        Test.stopTest();

        // Assert
        System.assertEquals(null, result, 'Null template should return null');
    }

    /**
     * @description Verifies that an empty data map causes placeholders to resolve
     *              to empty strings (default behavior).
     */
    @IsTest
    static void testEmptyData() {
        // Arrange
        String template = 'Name: {{name}}';
        Map<String, Object> data = new Map<String, Object>();

        // Act
        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        // Assert
        System.assertEquals('Name: ', result, 'Placeholder with empty data should resolve to empty');
    }

    /**
     * @description Verifies that multiple placeholders in a single template are all replaced.
     */
    @IsTest
    static void testMultiplePlaceholders() {
        // Arrange
        String template = '{{first}} {{last}} - {{email}}';
        Map<String, Object> data = new Map<String, Object>{
            'first' => 'John',
            'last' => 'Doe',
            'email' => 'john@example.com'
        };

        // Act
        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        // Assert
        System.assertEquals('John Doe - john@example.com', result,
            'All placeholders should be resolved');
    }

    /**
     * @description Verifies that the default value syntax {{field:default}} works correctly
     *              when the field is missing from the data map.
     */
    @IsTest
    static void testDefaultValueSyntax() {
        // Arrange
        String template = 'Status: {{status:unknown}}';
        Map<String, Object> data = new Map<String, Object>();

        // Act
        Test.startTest();
        String result = PlaceholderResolver.resolve(template, data);
        Test.stopTest();

        // Assert
        System.assertEquals('Status: unknown', result,
            'Default value should be used when field is missing');
    }

    /**
     * @description Verifies that resolveNestedPath handles array index notation.
     */
    @IsTest
    static void testArrayIndexAccess() {
        // Arrange
        List<Object> items = new List<Object>{ 'first', 'second', 'third' };
        Map<String, Object> data = new Map<String, Object>{ 'items' => items };

        // Act
        Test.startTest();
        Object result = PlaceholderResolver.resolveNestedPath('items[0]', data);
        Test.stopTest();

        // Assert
        System.assertEquals('first', result, 'Should resolve array index 0');
    }

    /**
     * @description Verifies conditional block resolution with {{#if field}}...{{/if}}.
     */
    @IsTest
    static void testConditionalBlock() {
        // Arrange
        String template = 'Hello{{#if showGreeting}}, World{{/if}}!';
        Map<String, Object> dataTrue = new Map<String, Object>{ 'showGreeting' => true };
        Map<String, Object> dataFalse = new Map<String, Object>{ 'showGreeting' => false };

        // Act
        Test.startTest();
        String resultTrue = PlaceholderResolver.resolve(template, dataTrue);
        String resultFalse = PlaceholderResolver.resolve(template, dataFalse);
        Test.stopTest();

        // Assert
        System.assertEquals('Hello, World!', resultTrue, 'True condition should include content');
        System.assertEquals('Hello!', resultFalse, 'False condition should exclude content');
    }
}