/**
 * @description Test class for TemplateJsonStorageService.
 * Covers save → load round-trip, legacy field fallback, and null/blank guards.
 */
@isTest
private class TemplateJsonStorageServiceTest {

    @isTest
    static void saveTemplateJson_nullAndBlank_returnsNull() {
        System.assertEquals(null, TemplateJsonStorageService.saveTemplateJson(null, 'x'));
        System.assertEquals(null, TemplateJsonStorageService.saveTemplateJson('abc', null));
        System.assertEquals(null, TemplateJsonStorageService.saveTemplateJson('', ''));
    }

    @isTest
    static void save_then_load_roundTripViaContentVersion() {
        Document_Template__c tmpl = new Document_Template__c();
        insert tmpl;

        String json = '{"hello":"world"}';

        Test.startTest();
        String docId = TemplateJsonStorageService.saveTemplateJson(tmpl.Id, json);
        Test.stopTest();
        System.assertNotEquals(null, docId);

        // Reload via the service
        Document_Template__c reloaded = [
            SELECT Id, Template_Content_Document_Id__c, Template_JSON__c
            FROM Document_Template__c WHERE Id = :tmpl.Id
        ];
        System.assertEquals(docId, reloaded.Template_Content_Document_Id__c,
            'Doc id should be persisted on the template');
        System.assertEquals(null, reloaded.Template_JSON__c,
            'Legacy field should be cleared after save');

        String loaded = TemplateJsonStorageService.loadTemplateJson(reloaded);
        System.assertEquals(json, loaded, 'Round-tripped JSON should match');
    }

    @isTest
    static void save_updateExistingDocumentCreatesNewVersion() {
        Document_Template__c tmpl = new Document_Template__c();
        insert tmpl;

        String firstDocId = TemplateJsonStorageService.saveTemplateJson(tmpl.Id, '{"v":1}');

        Test.startTest();
        String secondDocId = TemplateJsonStorageService.saveTemplateJson(tmpl.Id, '{"v":2}');
        Test.stopTest();
        System.assertEquals(firstDocId, secondDocId,
            'Second save should reuse the same ContentDocumentId');

        Document_Template__c reloaded = [
            SELECT Template_Content_Document_Id__c FROM Document_Template__c WHERE Id = :tmpl.Id
        ];
        String loaded = TemplateJsonStorageService.loadTemplateJson(reloaded);
        System.assertEquals('{"v":2}', loaded, 'Should load latest version');
    }

    @isTest
    static void load_fallbackToLegacyField() {
        // Template with no ContentDocument but with legacy JSON
        Document_Template__c tmpl = new Document_Template__c(Template_JSON__c = '{"legacy":true}');
        insert tmpl;

        Document_Template__c reloaded = [
            SELECT Id, Template_Content_Document_Id__c, Template_JSON__c
            FROM Document_Template__c WHERE Id = :tmpl.Id
        ];
        System.assertEquals('{"legacy":true}',
            TemplateJsonStorageService.loadTemplateJson(reloaded));
    }

    @isTest
    static void load_nothingSetReturnsNull() {
        Document_Template__c tmpl = new Document_Template__c();
        insert tmpl;

        Document_Template__c reloaded = [
            SELECT Id, Template_Content_Document_Id__c, Template_JSON__c
            FROM Document_Template__c WHERE Id = :tmpl.Id
        ];
        System.assertEquals(null, TemplateJsonStorageService.loadTemplateJson(reloaded));
    }

    @isTest
    static void load_withBogusContentDocumentId_catchAndFallback() {
        // Template with a non-existent ContentDocumentId value. ContentVersion
        // query returns empty → loadFromContentVersion returns null → falls
        // back to Template_JSON__c.
        Document_Template__c tmpl = new Document_Template__c(
            Template_Content_Document_Id__c = '069000000000000',
            Template_JSON__c = '{"fallback":true}'
        );
        insert tmpl;

        Document_Template__c reloaded = [
            SELECT Id, Template_Content_Document_Id__c, Template_JSON__c
            FROM Document_Template__c WHERE Id = :tmpl.Id
        ];
        System.assertEquals('{"fallback":true}',
            TemplateJsonStorageService.loadTemplateJson(reloaded));
    }
}