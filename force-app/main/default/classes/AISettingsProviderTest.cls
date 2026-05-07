@isTest
private class AISettingsProviderTest {

    @isTest
    static void overrideForTest_provides_values() {
        AISettingsProvider.overrideForTest('Gemini', 'fake-key', 'https://example.com', 'gemini-test');

        System.assertEquals('fake-key', AISettingsProvider.getApiKey('Gemini'));
        System.assertEquals('https://example.com', AISettingsProvider.getEndpoint('Gemini'));
        System.assertEquals('gemini-test', AISettingsProvider.getModel('Gemini'));
    }

    @isTest
    static void blank_provider_throws() {
        try {
            AISettingsProvider.get(null);
            System.assert(false, 'Should have thrown');
        } catch (AISettingsProvider.AISettingsException e) {
            System.assert(e.getMessage().contains('provider'));
        }
    }

    @isTest
    static void missing_api_key_throws_helpful_message() {
        AISettingsProvider.overrideForTest('Gemini', null, 'https://example.com', 'gemini-test');
        try {
            AISettingsProvider.getApiKey('Gemini');
            System.assert(false, 'Should have thrown');
        } catch (AISettingsProvider.AISettingsException e) {
            System.assert(e.getMessage().contains('Setup'), 'Error should guide admin to setup');
        }
    }

    @isTest
    static void unknown_provider_throws() {
        try {
            AISettingsProvider.get('Unknown');
            System.assert(false, 'Should have thrown');
        } catch (AISettingsProvider.AISettingsException e) {
            System.assert(e.getMessage().contains('Unknown'));
        }
    }
}