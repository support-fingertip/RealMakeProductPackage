/**
 * @description VF Page Controller for DynamicDocumentPDF.
 * Reads the Document_Template__c by the templateId URL parameter,
 * resolves it against the record identified by the id parameter,
 * and exposes the resulting HTML to the VF page.
 */
public with sharing class DynamicDocumentPDFController {

    // Configurable PDF defaults
    private static final String DEFAULT_PAGE_SIZE = 'A4';
    private static final String DEFAULT_ORIENTATION = 'portrait';
    private static final String DEFAULT_MARGIN_TOP = '20';
    private static final String DEFAULT_MARGIN_RIGHT = '15';
    private static final String DEFAULT_MARGIN_BOTTOM = '20';
    private static final String DEFAULT_MARGIN_LEFT = '15';
    private static final String DEFAULT_FONT_FAMILY = 'Arial, Helvetica, sans-serif';

    public String renderedHtml { get; set; }
    public String pageSize { get; set; }
    public String pageOrientation { get; set; }
    public String documentTitle { get; set; }
    public String marginTop { get; set; }
    public String marginRight { get; set; }
    public String marginBottom { get; set; }
    public String marginLeft { get; set; }
    public String fontFamily { get; set; }

    private void setDefaults() {
        pageSize = DEFAULT_PAGE_SIZE;
        pageOrientation = DEFAULT_ORIENTATION;
        marginTop = DEFAULT_MARGIN_TOP;
        marginRight = DEFAULT_MARGIN_RIGHT;
        marginBottom = DEFAULT_MARGIN_BOTTOM;
        marginLeft = DEFAULT_MARGIN_LEFT;
        fontFamily = DEFAULT_FONT_FAMILY;
    }

    public DynamicDocumentPDFController() {
        setDefaults();
        try {
            String templateId = ApexPages.currentPage().getParameters().get('templateId');
            String recordId   = ApexPages.currentPage().getParameters().get('id');

            if (String.isBlank(templateId)) {
                renderedHtml = '<p style="color:red;">Missing templateId parameter.</p>';
                documentTitle = 'Document';
                return;
            }

            // Fetch template
            List<Document_Template__c> templates = [
                SELECT Id, Name, Object_API_Name__c, Template_JSON__c,
                       Template_Content_Document_Id__c,
                       Page_Size__c, Page_Orientation__c, Logo_URL__c
                FROM Document_Template__c
                WHERE Id = :templateId
                LIMIT 1
            ];

            if (templates.isEmpty()) {
                renderedHtml = '<p style="color:red;">Template not found.</p>';
                documentTitle = 'Document';
                return;
            }

            Document_Template__c template = templates[0];
            documentTitle = template.Name;
            pageSize = String.isNotBlank(template.Page_Size__c) ? template.Page_Size__c : DEFAULT_PAGE_SIZE;
            pageOrientation = String.isNotBlank(template.Page_Orientation__c) ? template.Page_Orientation__c : DEFAULT_ORIENTATION;

            // Load template JSON from ContentVersion (primary) or field (legacy)
            String templateJsonStr = TemplateJsonStorageService.loadTemplateJson(template);
            if (String.isNotBlank(templateJsonStr)) {
                Map<String, Object> tJson = (Map<String, Object>) JSON.deserializeUntyped(templateJsonStr);

                // Inject logo URL if set at template level
                if (String.isNotBlank(template.Logo_URL__c) && tJson.containsKey('header')) {
                    Map<String, Object> header = (Map<String, Object>) tJson.get('header');
                    if (String.isBlank((String) header.get('logoUrl'))) {
                        header.put('logoUrl', template.Logo_URL__c);
                        header.put('showLogo', true);
                        // Try to extract ContentVersion ID from URL for base64 conversion
                        if (String.isBlank((String) header.get('logoContentVersionId'))) {
                            String extractedCvId = extractContentVersionIdFromUrl(template.Logo_URL__c);
                            if (String.isNotBlank(extractedCvId)) {
                                header.put('logoContentVersionId', extractedCvId);
                            }
                        }
                    }
                    tJson.put('header', header);
                    templateJsonStr = JSON.serialize(tJson);
                }

                // ---- Collect all ContentVersion IDs for bulk base64 conversion ----
                // (single SOQL query instead of multiple queries in loops)
                Set<String> allCvIds = new Set<String>();

                if (tJson.containsKey('header')) {
                    Map<String, Object> hdr = (Map<String, Object>) tJson.get('header');

                    // Legacy single-column header logo
                    String cvId = (String) hdr.get('logoContentVersionId');
                    if (String.isBlank(cvId)) {
                        cvId = extractContentVersionIdFromUrl((String) hdr.get('logoUrl'));
                    }
                    if (String.isNotBlank(cvId)) allCvIds.add(cvId);

                    // 3-column header logos (left, center, right)
                    for (String colKey : new List<String>{'left', 'center', 'right'}) {
                        if (hdr.containsKey(colKey) && hdr.get(colKey) instanceof Map<String, Object>) {
                            Map<String, Object> col = (Map<String, Object>) hdr.get(colKey);
                            if ((String) col.get('type') == 'image') {
                                String colCvId = (String) col.get('logoContentVersionId');
                                if (String.isBlank(colCvId)) {
                                    colCvId = extractContentVersionIdFromUrl((String) col.get('logoUrl'));
                                    if (String.isNotBlank(colCvId)) col.put('logoContentVersionId', colCvId);
                                }
                                if (String.isNotBlank(colCvId)) allCvIds.add(colCvId);
                            }
                            hdr.put(colKey, col);
                        }
                    }
                    tJson.put('header', hdr);
                }

                // Section images
                if (tJson.containsKey('sections')) {
                    List<Object> sections = (List<Object>) tJson.get('sections');
                    for (Object sectionObj : sections) {
                        Map<String, Object> section = (Map<String, Object>) sectionObj;
                        if ((String) section.get('type') == 'image') {
                            String imgCvId = (String) section.get('imageContentVersionId');
                            if (String.isBlank(imgCvId)) {
                                imgCvId = extractContentVersionIdFromUrl((String) section.get('imageUrl'));
                                if (String.isNotBlank(imgCvId)) section.put('imageContentVersionId', imgCvId);
                            }
                            if (String.isNotBlank(imgCvId)) allCvIds.add(imgCvId);
                        }
                    }
                    tJson.put('sections', sections);
                }

                // ---- Bulk convert all collected ContentVersion IDs to base64 ----
                Map<String, String> base64Map = bulkConvertToBase64(allCvIds);

                // Apply base64 data URIs to header
                if (tJson.containsKey('header')) {
                    Map<String, Object> hdr = (Map<String, Object>) tJson.get('header');

                    // Legacy single-column header logo
                    String cvId = (String) hdr.get('logoContentVersionId');
                    if (String.isNotBlank(cvId) && base64Map.containsKey(cvId)) {
                        hdr.put('logoUrl', base64Map.get(cvId));
                        hdr.put('showLogo', true);
                    }

                    // 3-column header logos
                    for (String colKey : new List<String>{'left', 'center', 'right'}) {
                        if (hdr.containsKey(colKey) && hdr.get(colKey) instanceof Map<String, Object>) {
                            Map<String, Object> col = (Map<String, Object>) hdr.get(colKey);
                            if ((String) col.get('type') == 'image') {
                                String colCvId = (String) col.get('logoContentVersionId');
                                if (String.isNotBlank(colCvId) && base64Map.containsKey(colCvId)) {
                                    col.put('logoUrl', base64Map.get(colCvId));
                                }
                            }
                            hdr.put(colKey, col);
                        }
                    }
                    tJson.put('header', hdr);
                }

                // Apply base64 data URIs to section images
                if (tJson.containsKey('sections')) {
                    List<Object> sections = (List<Object>) tJson.get('sections');
                    for (Object sectionObj : sections) {
                        Map<String, Object> section = (Map<String, Object>) sectionObj;
                        if ((String) section.get('type') == 'image') {
                            String imgCvId = (String) section.get('imageContentVersionId');
                            if (String.isNotBlank(imgCvId) && base64Map.containsKey(imgCvId)) {
                                section.put('imageUrl', base64Map.get(imgCvId));
                            }
                        }
                    }
                    tJson.put('sections', sections);
                }

                templateJsonStr = JSON.serialize(tJson);

                // Extract page margins and font from styles
                if (tJson.containsKey('styles')) {
                    Map<String, Object> styles = (Map<String, Object>) tJson.get('styles');
                    if (styles.get('marginTop') != null) marginTop = String.valueOf(styles.get('marginTop'));
                    if (styles.get('marginRight') != null) marginRight = String.valueOf(styles.get('marginRight'));
                    if (styles.get('marginBottom') != null) marginBottom = String.valueOf(styles.get('marginBottom'));
                    if (styles.get('marginLeft') != null) marginLeft = String.valueOf(styles.get('marginLeft'));
                    if (styles.get('fontFamily') != null) {
                        String ff = String.valueOf(styles.get('fontFamily'));
                        if (String.isNotBlank(ff)) fontFamily = ff;
                    }
                }
            }

            if (String.isNotBlank(recordId)) {
                renderedHtml = DynamicDocumentRenderer.renderDocument(
                    templateJsonStr, recordId, template.Object_API_Name__c
                );
            } else {
                renderedHtml = DynamicDocumentRenderer.renderDocument(
                    templateJsonStr, null, template.Object_API_Name__c
                );
            }
        } catch (Exception e) {
            renderedHtml = '<p style="color:red;">Error rendering document: ' +
                           String.valueOf(e.getMessage()) + '</p>';
            documentTitle = 'Error';
        }
    }

    /**
     * @description Bulk-converts a set of ContentVersion IDs to base64 data URIs.
     * Returns a map of ContentVersion ID -> data URI string.
     * Uses a single SOQL query to avoid governor limit issues.
     */
    private static Map<String, String> bulkConvertToBase64(Set<String> contentVersionIds) {
        return new ImageBase64Helper().convertForPdf(contentVersionIds);
    }

    /**
     * Inner class that runs without sharing to ensure ContentVersion images
     * are accessible regardless of which user uploaded them.
     */
    private without sharing class ImageBase64Helper {
        public Map<String, String> convertForPdf(Set<String> contentVersionIds) {
            Map<String, String> result = new Map<String, String>();
            if (contentVersionIds == null || contentVersionIds.isEmpty()) return result;

            contentVersionIds.remove(null);
            contentVersionIds.remove('');
            if (contentVersionIds.isEmpty()) return result;

            try {
                List<ContentVersion> versions = [
                    SELECT Id, VersionData, FileExtension
                    FROM ContentVersion
                    WHERE Id IN :contentVersionIds
                ];
                for (ContentVersion cv : versions) {
                    if (cv.VersionData == null) continue;
                    String ext = (cv.FileExtension != null) ? cv.FileExtension.toLowerCase() : 'png';
                    String mimeType = 'image/png';
                    if (ext == 'jpg' || ext == 'jpeg') mimeType = 'image/jpeg';
                    else if (ext == 'gif') mimeType = 'image/gif';
                    else if (ext == 'svg') mimeType = 'image/svg+xml';
                    result.put(cv.Id, 'data:' + mimeType + ';base64,' + EncodingUtil.base64Encode(cv.VersionData));
                }
            } catch (Exception e) {
                System.debug('Error converting images to base64: ' + e.getMessage());
            }
            return result;
        }
    }

    /**
     * @description Converts a ContentVersion logo to a base64 data URI
     * for reliable embedding in PDF output (avoids external URL fetching issues).
     */
    private static String convertLogoToBase64(String contentVersionId) {
        Set<String> ids = new Set<String>{ contentVersionId };
        Map<String, String> results = bulkConvertToBase64(ids);
        return results.get(contentVersionId);
    }

    /**
     * @description Extracts a ContentVersion ID from a Salesforce content URL.
     * Handles patterns like /sfc/servlet.shepherd/version/download/068...
     * Returns null if the URL is not a recognizable Salesforce content URL.
     */
    private static String extractContentVersionIdFromUrl(String url) {
        if (String.isBlank(url)) return null;
        String marker = '/sfc/servlet.shepherd/version/download/';
        Integer idx = url.indexOf(marker);
        if (idx >= 0) {
            String cvId = url.substring(idx + marker.length());
            if (cvId.contains('?')) cvId = cvId.substringBefore('?');
            if (cvId.contains('/')) cvId = cvId.substringBefore('/');
            if (String.isNotBlank(cvId) && cvId.length() >= 15) return cvId;
        }
        return null;
    }
}