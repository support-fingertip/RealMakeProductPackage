/**
 * @description Centralised reader for AI_Integration_Config__mdt.
 *
 * Purpose: keep API keys and endpoints out of Apex source. The Gemini key that
 * was previously hard-coded in GeminiChatController has been migrated here and
 * should be set via Setup → Custom Metadata Types → AI Integration Config after
 * deployment. A missing / blank key throws a clear error instead of making a
 * failed callout.
 */
public with sharing class AISettingsProvider {
    public static String test = System.Label.Custom_Meta_Data_Records;

    public class AISettingsException extends Exception {}

    // Cached per-transaction to avoid repeated SOQL.
    private static Map<String, AI_Integration_Config__mdt> cache;

    public static AI_Integration_Config__mdt get(String provider) {
        if (String.isBlank(provider)) {
            throw new AISettingsException('AI provider name is required.');
        }
        if (cache == null) {
            cache = new Map<String, AI_Integration_Config__mdt>();
            for (AI_Integration_Config__mdt c : [
                SELECT Provider__c, API_Key__c, Endpoint__c, Model__c, Is_Active__c
                FROM AI_Integration_Config__mdt
                WHERE Is_Active__c = true
            ]) {
                cache.put(c.Provider__c, c);
            }
        }
        AI_Integration_Config__mdt cfg = cache.get(provider);
        if (cfg == null) {
            throw new AISettingsException(
                'No active AI_Integration_Config__mdt record found for provider: ' + provider
            );
        }
        return cfg;
    }

    public static String getApiKey(String provider) {
        AI_Integration_Config__mdt cfg = get(provider);
        if (String.isBlank(cfg.API_Key__c)) {
            throw new AISettingsException(
                'API key is not configured for provider ' + provider
                + '. Open Setup → Custom Metadata Types → AI Integration Config → Manage Records → '
                + provider + ' and populate the API Key field.'
            );
        }
        return cfg.API_Key__c;
    }

    public static String getEndpoint(String provider) {
        return get(provider).Endpoint__c;
    }

    public static String getModel(String provider) {
        return get(provider).Model__c;
    }

    /** Test-only override so unit tests don't need CMT records. */
    @TestVisible
    private static void overrideForTest(String provider, String apiKey, String endpoint, String model) {
        if (cache == null) {
            cache = new Map<String, AI_Integration_Config__mdt>();
        }
        AI_Integration_Config__mdt cfg = new AI_Integration_Config__mdt();
        cfg.Provider__c = provider;
        cfg.API_Key__c = apiKey;
        cfg.Endpoint__c = endpoint;
        cfg.Model__c = model;
        cfg.Is_Active__c = true;
        cache.put(provider, cfg);
    }
}