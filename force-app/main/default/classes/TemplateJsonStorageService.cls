/**
 * @description Shared service for reading and writing template JSON.
 * Uses ContentVersion for storage (no size limit, built-in versioning).
 * Falls back to Template_JSON__c for backward compatibility with older templates.
 *
 * Storage strategy:
 * - On SAVE: Always writes to ContentVersion, clears Template_JSON__c
 * - On LOAD: Reads from ContentVersion if Template_Content_Document_Id__c is set,
 *            otherwise falls back to Template_JSON__c (legacy)
 */
public with sharing class TemplateJsonStorageService {

    private static final String CV_FILE_TITLE_PREFIX = 'TemplateJSON_';
    private static final String CV_FILE_EXTENSION = '.json';

    /**
     * @description Load the template JSON string for a given template record.
     *              Tries ContentVersion first, falls back to Template_JSON__c.
     * @param template The Document_Template__c record (must have Template_Content_Document_Id__c and Template_JSON__c queried)
     * @return The full template JSON string, or null if empty
     */
    public static String loadTemplateJson(Document_Template__c template) {
        // 1. Try ContentVersion
        if (String.isNotBlank(template.Template_Content_Document_Id__c)) {
            String json = loadFromContentVersion(template.Template_Content_Document_Id__c);
            if (json != null) return json;
        }

        // 2. Fallback to field
        if (String.isNotBlank(template.Template_JSON__c)) {
            return template.Template_JSON__c;
        }

        return null;
    }

    /**
     * @description Save template JSON to ContentVersion and update the template record.
     *              Links the ContentVersion to the template via ContentDocumentLink.
     * @param templateId The Document_Template__c record Id
     * @param jsonString The full template JSON string to save
     * @return The ContentDocument Id for reference
     */
    public static String saveTemplateJson(String templateId, String jsonString) {
        if (String.isBlank(templateId) || String.isBlank(jsonString)) return null;

        // Check if template already has a ContentDocument
        Document_Template__c template = [
            SELECT Id, Template_Content_Document_Id__c
            FROM Document_Template__c
            WHERE Id = :templateId
            LIMIT 1
        ];

        String contentDocId = template.Template_Content_Document_Id__c;

        // Create or update ContentVersion
        ContentVersion cv = new ContentVersion();
        cv.Title = CV_FILE_TITLE_PREFIX + templateId;
        cv.PathOnClient = CV_FILE_TITLE_PREFIX + templateId + CV_FILE_EXTENSION;
        cv.VersionData = Blob.valueOf(jsonString);
        cv.Origin = 'H';

        if (String.isNotBlank(contentDocId)) {
            // Update existing: set ContentDocumentId to create a new version
            cv.ContentDocumentId = contentDocId;
        }

        insert cv;

        // Get the ContentDocumentId (for new files)
        if (String.isBlank(contentDocId)) {
            cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
            contentDocId = cv.ContentDocumentId;

            // Link to template record
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = contentDocId;
            cdl.LinkedEntityId = templateId;
            cdl.ShareType = 'V'; // Viewer
            cdl.Visibility = 'AllUsers';
            insert cdl;
        }

        // Update template with ContentDocument Id and clear the old field
        template.Template_Content_Document_Id__c = contentDocId;
        template.Template_JSON__c = null;
        update template;

        return contentDocId;
    }

    /**
     * @description Read JSON string from ContentVersion by ContentDocumentId.
     *              Always reads the latest version.
     */
    private static String loadFromContentVersion(String contentDocumentId) {
        try {
            List<ContentVersion> versions = [
                SELECT VersionData
                FROM ContentVersion
                WHERE ContentDocumentId = :contentDocumentId
                  AND IsLatest = true
                LIMIT 1
            ];
            if (!versions.isEmpty() && versions[0].VersionData != null) {
                return versions[0].VersionData.toString();
            }
        } catch (Exception e) {
            System.debug('Error loading template JSON from ContentVersion: ' + e.getMessage());
        }
        return null;
    }
}