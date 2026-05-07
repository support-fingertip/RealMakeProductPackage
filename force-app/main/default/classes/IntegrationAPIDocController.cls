/**
 * @description Controller for the IntegrationAPIDoc Visualforce page.
 * Queries integration source config with all field rules and lookup rules,
 * parses JSON schemas, reads doc settings from Custom Metadata, and
 * exposes structured data for rendering a professional API documentation PDF.
 * Supports both HTML preview and PDF download via dynamic renderAs.
 */
public with sharing class IntegrationAPIDocController {

    // ════════════════════════════════════════════
    // CONFIG DATA
    // ════════════════════════════════════════════
    public Integration_Source_Config__c config { get; set; }
    public List<FieldMappingInfo> mappingRows { get; set; }
    public List<ApiFieldInfo> apiSchemaFields { get; set; }
    public List<ValidationRuleInfo> validationRules { get; set; }
    public String sampleRequestJson { get; set; }
    public String sampleResponseJson { get; set; }
    public String generatedDate { get; set; }
    public String endpointUrl { get; set; }

    // ════════════════════════════════════════════
    // DOC SETTINGS (from CMT)
    // ════════════════════════════════════════════
    public String watermarkText { get; set; }
    public String companyName { get; set; }
    public String headerColor { get; set; }
    public String logoDataUrl { get; set; }
    public Boolean hasLogo { get; set; }
    public Boolean hasWatermark { get; set; }

    public IntegrationAPIDocController() {
        mappingRows = new List<FieldMappingInfo>();
        apiSchemaFields = new List<ApiFieldInfo>();
        validationRules = new List<ValidationRuleInfo>();
        sampleRequestJson = '';
        sampleResponseJson = '';
        watermarkText = '';
        companyName = '';
        headerColor = '#1B2A4A';
        logoDataUrl = '';
        hasLogo = false;
        hasWatermark = false;

        loadDocSettings();

        String configId = ApexPages.currentPage().getParameters().get('id');
        if (String.isNotBlank(configId)) {
            loadData((Id) configId);
        }
    }

    /**
     * @description Dynamic renderAs value. Returns 'pdf' when format=pdf URL param is set.
     */
    public String getRenderFormat() {
        String fmt = ApexPages.currentPage().getParameters().get('format');
        return (fmt != null && fmt.equalsIgnoreCase('pdf')) ? 'pdf' : null;
    }

    // ════════════════════════════════════════════
    // COMPUTED PROPERTIES
    // ════════════════════════════════════════════

    public Boolean getHasConfig() {
        return config != null;
    }

    public Boolean getHasFieldRules() {
        return mappingRows != null && !mappingRows.isEmpty();
    }

    public Boolean getHasApiSchema() {
        return apiSchemaFields != null && !apiSchemaFields.isEmpty();
    }

    public Boolean getHasValidationRules() {
        return validationRules != null && !validationRules.isEmpty();
    }

    public Boolean getHasLookupRules() {
        if (mappingRows == null) return false;
        for (FieldMappingInfo m : mappingRows) {
            if (m.hasLookup) return true;
        }
        return false;
    }

    public String getVersionDisplay() {
        if (config == null || config.Version__c == null) return '';
        return 'v' + String.valueOf(config.Version__c.intValue());
    }

    // ════════════════════════════════════════════
    // DOC SETTINGS FROM CMT
    // ════════════════════════════════════════════

    private void loadDocSettings() {
        List<Integration_Doc_Setting__mdt> settings = [
            SELECT Watermark_Text__c, Company_Name__c, Logo_Document_Id__c,
                   Header_Color__c
            FROM Integration_Doc_Setting__mdt
            WHERE Is_Active__c = true
            LIMIT 1
        ];

        if (settings.isEmpty()) return;

        Integration_Doc_Setting__mdt s = settings[0];

        if (String.isNotBlank(s.Watermark_Text__c)) {
            watermarkText = s.Watermark_Text__c;
            hasWatermark = true;
        }
        if (String.isNotBlank(s.Company_Name__c)) {
            companyName = s.Company_Name__c;
        }
        if (String.isNotBlank(s.Header_Color__c)) {
            headerColor = s.Header_Color__c;
        }

        // Load logo as base64 data URL for PDF compatibility
        if (String.isNotBlank(s.Logo_Document_Id__c)) {
            loadLogoAsDataUrl(s.Logo_Document_Id__c.trim());
        }
    }

    private void loadLogoAsDataUrl(String docId) {
        try {
            // 1) Try as ContentDocumentId -> get ContentVersion
            List<ContentVersion> cvList = [
                SELECT VersionData, FileExtension
                FROM ContentVersion
                WHERE ContentDocumentId = :docId AND IsLatest = true
                LIMIT 1
            ];
            if (!cvList.isEmpty()) {
                setLogoFromBlob(cvList[0].VersionData, cvList[0].FileExtension);
                return;
            }
        } catch (Exception e) {
            System.debug('Logo ContentDocumentId lookup: ' + e.getMessage());
        }

        try {
            // 2) Try as ContentVersion Id directly
            List<ContentVersion> cvById = [
                SELECT VersionData, FileExtension
                FROM ContentVersion
                WHERE Id = :docId
                LIMIT 1
            ];
            if (!cvById.isEmpty()) {
                setLogoFromBlob(cvById[0].VersionData, cvById[0].FileExtension);
                return;
            }
        } catch (Exception e) {
            System.debug('Logo ContentVersion Id lookup: ' + e.getMessage());
        }

        try {
            // 3) Try as classic Document Id
            List<Document> docs = [
                SELECT Body, ContentType
                FROM Document
                WHERE Id = :docId
                LIMIT 1
            ];
            if (!docs.isEmpty()) {
                logoDataUrl = 'data:' + docs[0].ContentType + ';base64,'
                    + EncodingUtil.base64Encode(docs[0].Body);
                hasLogo = true;
                return;
            }
        } catch (Exception e) {
            System.debug('Logo Document Id lookup: ' + e.getMessage());
        }

        try {
            // 4) Try as Attachment Id
            List<Attachment> atts = [
                SELECT Body, ContentType
                FROM Attachment
                WHERE Id = :docId
                LIMIT 1
            ];
            if (!atts.isEmpty()) {
                logoDataUrl = 'data:' + atts[0].ContentType + ';base64,'
                    + EncodingUtil.base64Encode(atts[0].Body);
                hasLogo = true;
                return;
            }
        } catch (Exception e) {
            System.debug('Logo Attachment Id lookup: ' + e.getMessage());
        }

        // 5) Try as Static Resource name
        try {
            List<StaticResource> srs = [
                SELECT Body, ContentType
                FROM StaticResource
                WHERE Name = :docId
                LIMIT 1
            ];
            if (!srs.isEmpty()) {
                logoDataUrl = 'data:' + srs[0].ContentType + ';base64,'
                    + EncodingUtil.base64Encode(srs[0].Body);
                hasLogo = true;
                return;
            }
        } catch (Exception e) {
            System.debug('Logo StaticResource lookup: ' + e.getMessage());
        }

        // 6) Fallback: search ContentVersion by Title (file name)
        try {
            String searchTitle = docId.trim();
            List<ContentVersion> cvByTitle = [
                SELECT VersionData, FileExtension
                FROM ContentVersion
                WHERE Title = :searchTitle AND IsLatest = true
                LIMIT 1
            ];
            if (!cvByTitle.isEmpty()) {
                setLogoFromBlob(cvByTitle[0].VersionData, cvByTitle[0].FileExtension);
                return;
            }
        } catch (Exception e) {
            System.debug('Logo title search: ' + e.getMessage());
        }
    }

    private void setLogoFromBlob(Blob body, String fileExt) {
        String ext = fileExt != null ? fileExt.toLowerCase() : 'png';
        String mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/' + ext;
        logoDataUrl = 'data:' + mime + ';base64,' + EncodingUtil.base64Encode(body);
        hasLogo = true;
    }

    // ════════════════════════════════════════════
    // DATA LOADING
    // ════════════════════════════════════════════

    private void loadData(Id configId) {
        List<Integration_Source_Config__c> configs = [
            SELECT Id, Name, Source_Name__c, Target_Object__c, Is_Active__c,
                   Version__c, Description__c, API_Schema_JSON__c,
                   Validation_Rules_JSON__c, Endpoint_URL__c,
                   Enable_Duplicate_Check__c, CreatedDate, LastModifiedDate,
                   (SELECT Id, API_Field_Name__c, API_Field_Label__c,
                           SF_Field_API_Name__c, Is_Required__c, Default_Value__c,
                           Data_Type__c, Transform_Expression__c, Is_Active__c,
                           Is_Static__c, Sequence__c,
                           (SELECT Id, Lookup_Object__c, Match_Field__c,
                                   Return_Field__c, Fail_On_No_Match__c,
                                   Additional_Filter__c
                            FROM Integration_Lookup_Rules__r)
                    FROM Integration_Field_Rules__r
                    WHERE Is_Active__c = true
                    ORDER BY Sequence__c ASC NULLS LAST)
            FROM Integration_Source_Config__c
            WHERE Id = :configId
            LIMIT 1
        ];

        if (configs.isEmpty()) return;

        config = configs[0];
        generatedDate = DateTime.now().format('MMMM d, yyyy \'at\' h:mm a');
		  String baseUrl = System.Url.getOrgDomainUrl().toExternalForm();
        endpointUrl = baseUrl + config.Endpoint_URL__c;
        if (String.isBlank(endpointUrl)) {
            // Use the new method for API v58.0+
            baseUrl = System.Url.getOrgDomainUrl().toExternalForm();
            system.debug('baseUrl' + baseUrl);
            endpointUrl = baseUrl + '/services/apexrest/integration/' + config.Source_Name__c;
        }

        buildMappingRows();
        parseApiSchema();
        parseValidationRules();
        buildSampleRequest();
        buildSampleResponse();
    }

    private void buildMappingRows() {
        Integer seq = 1;
        for (Integration_Field_Rule__c r : config.Integration_Field_Rules__r) {
            FieldMappingInfo row = new FieldMappingInfo();
            row.sequence = seq++;
            row.apiFieldName = r.API_Field_Name__c;
            row.apiFieldLabel = r.API_Field_Label__c;
            row.sfFieldApiName = r.SF_Field_API_Name__c;
            row.dataType = r.Data_Type__c;
            row.isRequired = r.Is_Required__c;
            row.defaultValue = r.Default_Value__c;
            row.transformExpression = r.Transform_Expression__c;
            row.isStatic = r.Is_Static__c;

            // Lookup info
            if (r.Integration_Lookup_Rules__r != null && !r.Integration_Lookup_Rules__r.isEmpty()) {
                Integration_Lookup_Rule__c lk = r.Integration_Lookup_Rules__r[0];
                row.hasLookup = true;
                row.lookupObject = lk.Lookup_Object__c;
                row.matchField = lk.Match_Field__c;
                row.returnField = lk.Return_Field__c;
                row.failOnNoMatch = lk.Fail_On_No_Match__c;
                row.additionalFilter = lk.Additional_Filter__c;
            } else {
                row.hasLookup = false;
            }

            mappingRows.add(row);
        }
    }

    private void parseApiSchema() {
        if (String.isBlank(config.API_Schema_JSON__c)) return;
        try {
            List<Object> fields = (List<Object>) JSON.deserializeUntyped(config.API_Schema_JSON__c);
            for (Object obj : fields) {
                Map<String, Object> f = (Map<String, Object>) obj;
                ApiFieldInfo info = new ApiFieldInfo();
                info.name = (String) f.get('name');
                info.label = (String) f.get('label');
                info.fieldType = (String) f.get('type');
                info.isRequired = f.get('required') == true;
                info.sampleValue = getSampleValue(info.fieldType, info.name);
                apiSchemaFields.add(info);
            }
        } catch (Exception e) {
            System.debug('Error parsing API schema: ' + e.getMessage());
        }
    }

    private void parseValidationRules() {
        if (String.isBlank(config.Validation_Rules_JSON__c)) return;
        try {
            List<Object> rules = (List<Object>) JSON.deserializeUntyped(config.Validation_Rules_JSON__c);
            for (Object obj : rules) {
                Map<String, Object> r = (Map<String, Object>) obj;
                ValidationRuleInfo info = new ValidationRuleInfo();
                info.field = (String) r.get('field');
                info.regex = (String) r.get('regex');
                info.message = (String) r.get('message');
                validationRules.add(info);
            }
        } catch (Exception e) {
            System.debug('Error parsing validation rules: ' + e.getMessage());
        }
    }

    private void buildSampleRequest() {
        if (apiSchemaFields.isEmpty() && mappingRows.isEmpty()) {
            sampleRequestJson = '{ }';
            return;
        }

        List<String> lines = new List<String>();
        if (!apiSchemaFields.isEmpty()) {
            for (ApiFieldInfo f : apiSchemaFields) {
                lines.add('    ' + colorKey(f.name) + ': ' + colorValue(f.sampleValue));
            }
        } else {
            for (FieldMappingInfo r : mappingRows) {
                if (!r.isStatic && String.isNotBlank(r.apiFieldName)) {
                    String val = getSampleValue(r.dataType, r.apiFieldName);
                    lines.add('    ' + colorKey(r.apiFieldName) + ': ' + colorValue(val));
                }
            }
        }

        sampleRequestJson = '{\n' + String.join(lines, ',\n') + '\n}';
    }

    private String getSampleValue(String dataType, String fieldName) {
        if (String.isBlank(dataType)) dataType = 'Text';
        String dt = dataType.toLowerCase();

        if (dt == 'number' || dt == 'currency') return '12345';
        if (dt == 'boolean') return 'true';
        if (dt == 'date') return '"2025-01-15"';
        if (dt == 'datetime') return '"2025-01-15T10:30:00Z"';
        if (dt == 'email') return '"user@example.com"';
        if (dt == 'phone') return '"9876543210"';

        String fn = (fieldName != null) ? fieldName.toLowerCase() : '';
        if (fn.contains('name')) return '"John Doe"';
        if (fn.contains('email')) return '"user@example.com"';
        if (fn.contains('mobile') || fn.contains('phone')) return '"9876543210"';

        return '"sample_value"';
    }

    private void buildSampleResponse() {
        sampleResponseJson =
            '<span class="json-comment">// Success (HTTP 200)</span>\n'
            + '{\n'
            + '    ' + colorKey('status') + ': ' + colorStr('SUCCESS') + ',\n'
            + '    ' + colorKey('recordId') + ': ' + colorStr('a0B5g00000XXXXXX') + ',\n'
            + '    ' + colorKey('message') + ': ' + colorStr('Record created successfully.') + '\n'
            + '}\n\n'
            + '<span class="json-comment">// Validation Error (HTTP 400)</span>\n'
            + '{\n'
            + '    ' + colorKey('status') + ': ' + colorStr('VALIDATION_ERROR') + ',\n'
            + '    ' + colorKey('recordId') + ': <span class="json-null">null</span>,\n'
            + '    ' + colorKey('message') + ': ' + colorStr('Required field missing: mobile') + '\n'
            + '}\n\n'
            + '<span class="json-comment">// Duplicate (HTTP 409)</span>\n'
            + '{\n'
            + '    ' + colorKey('status') + ': ' + colorStr('DUPLICATE') + ',\n'
            + '    ' + colorKey('recordId') + ': ' + colorStr('a0B5g00000YYYYYY') + ',\n'
            + '    ' + colorKey('message') + ': ' + colorStr('Duplicate record found.') + '\n'
            + '}';
    }

    private String colorKey(String key) {
        return '<span class="json-key">"' + key.escapeHtml4() + '"</span>';
    }

    private String colorStr(String val) {
        return '<span class="json-string">"' + val.escapeHtml4() + '"</span>';
    }

    private String colorValue(String rawVal) {
        if (rawVal == null) return '<span class="json-null">null</span>';
        String trimmed = rawVal.trim();
        if (trimmed == 'null') return '<span class="json-null">null</span>';
        if (trimmed == 'true' || trimmed == 'false') return '<span class="json-bool">' + trimmed + '</span>';
        if (trimmed.startsWith('"')) return '<span class="json-string">' + trimmed.escapeHtml4() + '</span>';
        return '<span class="json-number">' + trimmed.escapeHtml4() + '</span>';
    }

    // ════════════════════════════════════════════
    // INNER CLASSES
    // ════════════════════════════════════════════

    public class ApiFieldInfo {
        public String name { get; set; }
        public String label { get; set; }
        public String fieldType { get; set; }
        public Boolean isRequired { get; set; }
        public String sampleValue { get; set; }
    }

    public class ValidationRuleInfo {
        public String field { get; set; }
        public String regex { get; set; }
        public String message { get; set; }
    }

    public class FieldMappingInfo {
        public Integer sequence { get; set; }
        public String apiFieldName { get; set; }
        public String apiFieldLabel { get; set; }
        public String sfFieldApiName { get; set; }
        public String dataType { get; set; }
        public Boolean isRequired { get; set; }
        public String defaultValue { get; set; }
        public String transformExpression { get; set; }
        public Boolean isStatic { get; set; }
        // Lookup
        public Boolean hasLookup { get; set; }
        public String lookupObject { get; set; }
        public String matchField { get; set; }
        public String returnField { get; set; }
        public Boolean failOnNoMatch { get; set; }
        public String additionalFilter { get; set; }
    }
}