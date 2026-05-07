/**
 * @description Test class for EmailPdfGenerator (100% coverage).
 * Covers PDF generation, attachment creation, static document retrieval,
 * related file attachment listing, attachment info parsing, and all
 * getContentType extension branches.
 */
@isTest
private class EmailPdfGeneratorTest {

    @TestSetup
    static void setup() {
        // ContentVersion with pdf extension (known content type)
        ContentVersion cv1 = new ContentVersion(
            Title       = 'Test PDF Doc',
            PathOnClient = 'testpdf.pdf',
            VersionData  = Blob.valueOf('PDF Content'),
            IsMajorVersion = true
        );
        insert cv1;

        // ContentVersion with unknown extension
        ContentVersion cv2 = new ContentVersion(
            Title       = 'Unknown Ext Doc',
            PathOnClient = 'testfile.xyz',
            VersionData  = Blob.valueOf('XYZ Content'),
            IsMajorVersion = true
        );
        insert cv2;

        // ContentVersion with no extension (blank extension branch)
        ContentVersion cv3 = new ContentVersion(
            Title       = 'NoExtFile',
            PathOnClient = 'noext',
            VersionData  = Blob.valueOf('NoExt Content'),
            IsMajorVersion = true
        );
        insert cv3;
    }

    // ── generatePdfFromVfPage (3-arg overload) ────────────────────────

    @isTest
    static void generatePdfFromVfPage_threeArg_success() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG', '9700000001');

        Test.startTest();
        Blob result = EmailPdfGenerator.generatePdfFromVfPage('TestPage', lead.Id, 'id');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals('Test PDF Content', result.toString());
    }

    // ── generatePdfFromVfPage (4-arg overload) branches ─────────────

    @isTest
    static void generatePdfFromVfPage_blankVfPageName_throws() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG1', '9700000002');

        Boolean thrown = false;
        Test.startTest();
        try {
            EmailPdfGenerator.generatePdfFromVfPage('', lead.Id, 'id');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Should throw AuraHandledException for blank vfPageName');
    }

    @isTest
    static void generatePdfFromVfPage_nullRecordId_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            EmailPdfGenerator.generatePdfFromVfPage('MyPage', null, 'id');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Should throw AuraHandledException for null recordId');
    }

    @isTest
    static void generatePdfFromVfPage_blankParamName_defaultsToId() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG2', '9700000003');

        Test.startTest();
        // blank paramName → defaults to 'id'
        Blob result = EmailPdfGenerator.generatePdfFromVfPage('TestPage', lead.Id, null, null);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void generatePdfFromVfPage_extraParamsWithBlankValue() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG3', '9700000004');

        // Extra params: one non-blank (added), one blank (skipped)
        Map<String, String> extraParams = new Map<String, String>{
            'templateId' => 'tmpl123',
            'emptyKey'   => ''
        };

        Test.startTest();
        Blob result = EmailPdfGenerator.generatePdfFromVfPage(
            'TestPage', lead.Id, 'id', extraParams
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void generatePdfFromVfPage_nullExtraParams() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG4', '9700000005');

        Test.startTest();
        Blob result = EmailPdfGenerator.generatePdfFromVfPage(
            'TestPage', lead.Id, 'id', null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    // ── generatePdfAttachment ─────────────────────────────────────────

    @isTest
    static void generatePdfAttachment_fourArg_success() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG5', '9700000006');

        Test.startTest();
        Messaging.EmailFileAttachment att = EmailPdfGenerator.generatePdfAttachment(
            'TestPage', lead.Id, 'myfile.pdf', 'id'
        );
        Test.stopTest();

        System.assertNotEquals(null, att);
        System.assertEquals('myfile.pdf', att.getFileName());
        System.assertEquals('application/pdf', att.getContentType());
    }

    @isTest
    static void generatePdfAttachment_fiveArg_withExtraParams() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG6', '9700000007');

        Map<String, String> extra = new Map<String, String>{ 'templateId' => 'T1' };

        Test.startTest();
        Messaging.EmailFileAttachment att = EmailPdfGenerator.generatePdfAttachment(
            'TestPage', lead.Id, 'file.pdf', 'id', extra
        );
        Test.stopTest();

        System.assertNotEquals(null, att);
        System.assertEquals('application/pdf', att.getContentType());
    }

    // ── getStaticDocumentAttachment ───────────────────────────────────

    @isTest
    static void getStaticDocumentAttachment_contentDocument_success() {
        // Get ContentDocumentId from the setup ContentVersion (.pdf)
        ContentVersion cv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE PathOnClient = 'testpdf.pdf'
            LIMIT 1
        ];

        Test.startTest();
        Messaging.EmailFileAttachment att =
            EmailPdfGenerator.getStaticDocumentAttachment(cv.ContentDocumentId);
        Test.stopTest();

        System.assertNotEquals(null, att);
        System.assertEquals('application/pdf', att.getContentType());
    }

    @isTest
    static void getStaticDocumentAttachment_contentDocument_unknownExtension() {
        // Get ContentDocumentId from the setup ContentVersion (.xyz)
        ContentVersion cv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE PathOnClient = 'testfile.xyz'
            LIMIT 1
        ];

        Test.startTest();
        Messaging.EmailFileAttachment att =
            EmailPdfGenerator.getStaticDocumentAttachment(cv.ContentDocumentId);
        Test.stopTest();

        System.assertNotEquals(null, att);
        // Unknown extension → application/octet-stream
        System.assertEquals('application/octet-stream', att.getContentType());
    }

    @isTest
    static void getStaticDocumentAttachment_contentDocument_noExtension() {
        // Get ContentDocumentId from the setup ContentVersion (no extension)
        ContentVersion cv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE PathOnClient = 'noext'
            LIMIT 1
        ];

        Test.startTest();
        Messaging.EmailFileAttachment att =
            EmailPdfGenerator.getStaticDocumentAttachment(cv.ContentDocumentId);
        Test.stopTest();

        // Blank extension → application/octet-stream
        System.assertEquals('application/octet-stream', att.getContentType());
    }

    @isTest
    static void getStaticDocumentAttachment_document_success() {
        // Insert a legacy Document record to cover the Document branch
        Document doc = new Document(
            Name        = 'Test Legacy Doc',
            Body        = Blob.valueOf('Legacy Content'),
            FolderId    = UserInfo.getUserId(),
            ContentType = 'text/plain'
        );
        insert doc;

        Test.startTest();
        Messaging.EmailFileAttachment att =
            EmailPdfGenerator.getStaticDocumentAttachment(doc.Id);
        Test.stopTest();

        System.assertNotEquals(null, att);
        System.assertEquals('Test Legacy Doc', att.getFileName());
    }

    @isTest
    static void getStaticDocumentAttachment_nullId_throws() {
        Boolean thrown = false;
        Test.startTest();
        try {
            EmailPdfGenerator.getStaticDocumentAttachment(null);
        } catch (AuraHandledException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown, 'Should throw AuraHandledException for null documentId');
    }

    // ── getRelatedFilesAttachments ────────────────────────────────────

    @isTest
    static void getRelatedFilesAttachments_noFiles_returnsEmpty() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG7', '9700000008');

        Test.startTest();
        List<Messaging.EmailFileAttachment> atts =
            EmailPdfGenerator.getRelatedFilesAttachments(lead.Id);
        Test.stopTest();

        System.assertEquals(0, atts.size());
    }

    @isTest
    static void getRelatedFilesAttachments_withFiles_returnsAttachments() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG8', '9700000009');

        ContentVersion cv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE PathOnClient = 'testpdf.pdf'
            LIMIT 1
        ];

        ContentDocumentLink link = new ContentDocumentLink(
            ContentDocumentId = cv.ContentDocumentId,
            LinkedEntityId    = lead.Id,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        insert link;

        Test.startTest();
        List<Messaging.EmailFileAttachment> atts =
            EmailPdfGenerator.getRelatedFilesAttachments(lead.Id);
        Test.stopTest();

        System.assertEquals(1, atts.size());
        System.assertEquals('application/pdf', atts[0].getContentType());
    }

    // ── getAttachmentInfoList ─────────────────────────────────────────

    @isTest
    static void getAttachmentInfoList_blankJson_returnsEmpty() {
        Test.startTest();
        List<EmailPdfGenerator.AttachmentInfo> result =
            EmailPdfGenerator.getAttachmentInfoList('', null, null);
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @isTest
    static void getAttachmentInfoList_noAttachmentsKey_returnsEmpty() {
        Test.startTest();
        List<EmailPdfGenerator.AttachmentInfo> result =
            EmailPdfGenerator.getAttachmentInfoList('{}', null, null);
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @isTest
    static void getAttachmentInfoList_vfPageType_required() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG9', '9700000010');

        // VFPage type, required, with documentTemplateId
        String configJson = '{"attachments":[{'
            + '"id":"att1","name":"My PDF","type":"VFPage",'
            + '"vfPageName":"QuotePage","vfPageParam":"id",'
            + '"isRequired":true,"isDefaultChecked":false,'
            + '"documentTemplateId":"tmpl001",'
            + '"singleChildLimit":1,"maxChildRecords":5'
            + '}]}';

        Test.startTest();
        List<EmailPdfGenerator.AttachmentInfo> result =
            EmailPdfGenerator.getAttachmentInfoList(configJson, lead.Id, 'Lead__c');
        Test.stopTest();

        System.assertEquals(1, result.size());
        EmailPdfGenerator.AttachmentInfo info = result[0];
        System.assertEquals('application/pdf', info.contentType);
        System.assertEquals('QuotePage', info.VFPageName);
        System.assertEquals('id', info.VFParamName);
        System.assertEquals(true, info.isRequired);
        System.assertEquals(true, info.isSelected);  // required → always selected
        System.assertEquals('tmpl001', info.documentTemplateId);
        System.assertEquals(1, info.singleChildLimit);
        System.assertEquals(5, info.maxChildRecords);
    }

    @isTest
    static void getAttachmentInfoList_vfPageType_withFileName() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('EPG');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'EPG10', '9700000011');

        // VFPage type with explicit fileName (no fileNamePattern)
        String configJson = '{"attachments":[{'
            + '"id":"att2","name":"Named","type":"VFPage",'
            + '"vfPageName":"MyPage",'
            + '"fileName":"custom_output.pdf",'
            + '"isRequired":false,"isDefaultChecked":true'
            + '}]}';

        Test.startTest();
        List<EmailPdfGenerator.AttachmentInfo> result =
            EmailPdfGenerator.getAttachmentInfoList(configJson, lead.Id, 'Lead__c');
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('custom_output.pdf', result[0].fileName);
        System.assertEquals(true, result[0].isSelected); // isDefaultChecked = true
    }

    @isTest
    static void getAttachmentInfoList_vfPageType_fallbackFileName() {
        // No fileName, no fileNamePattern → uses name + '.pdf'
        String configJson = '{"attachments":[{'
            + '"id":"att3","name":"FallbackDoc","type":"VFPage",'
            + '"vfPageName":"SomePage",'
            + '"isRequired":false,"isDefaultChecked":false'
            + '}]}';

        Test.startTest();
        List<EmailPdfGenerator.AttachmentInfo> result =
            EmailPdfGenerator.getAttachmentInfoList(configJson, null, null);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('FallbackDoc.pdf', result[0].fileName);
        System.assertEquals(false, result[0].isSelected);
    }

    @isTest
    static void getAttachmentInfoList_staticDocumentType() {
        String configJson = '{"attachments":[{'
            + '"id":"att4","name":"Static","type":"StaticDocument",'
            + '"documentId":"doc001",'
            + '"isRequired":false,"isDefaultChecked":true'
            + '}]}';

        Test.startTest();
        List<EmailPdfGenerator.AttachmentInfo> result =
            EmailPdfGenerator.getAttachmentInfoList(configJson, null, null);
        Test.stopTest();

        System.assertEquals(1, result.size());
        EmailPdfGenerator.AttachmentInfo info = result[0];
        System.assertEquals('doc001', info.documentId);
        System.assertEquals(true, info.isSelected);
        System.assert(info.previewUrl.contains('doc001'));
    }

    @isTest
    static void getAttachmentInfoList_multipleAttachments() {
        String configJson = '{"attachments":['
            + '{"id":"a1","name":"PDF1","type":"VFPage","vfPageName":"P1","isRequired":true,"isDefaultChecked":false},'
            + '{"id":"a2","name":"Doc1","type":"StaticDocument","documentId":"dId1","isRequired":false,"isDefaultChecked":false}'
            + ']}';

        Test.startTest();
        List<EmailPdfGenerator.AttachmentInfo> result =
            EmailPdfGenerator.getAttachmentInfoList(configJson, null, null);
        Test.stopTest();

        System.assertEquals(2, result.size());
    }

    @isTest
    static void getAttachmentInfoList_relatedRecordFields_parsed() {
        // Cover the related record attachment fields branch
        String configJson = '{"attachments":[{'
            + '"id":"att5","name":"Related","type":"VFPage","vfPageName":"P2",'
            + '"recordSourceType":"child","selectedRelationship":"rel",'
            + '"relationshipType":"lookup","relationshipName":"Bookings",'
            + '"relatedObjectApi":"Booking__c","childRecordType":"Standard",'
            + '"filterConditionsJson":"{}","orderByField":"Name",'
            + '"orderByDirection":"ASC",'
            + '"singleChildLimit":2,"maxChildRecords":10,'
            + '"isRequired":false,"isDefaultChecked":false'
            + '}]}';

        Test.startTest();
        List<EmailPdfGenerator.AttachmentInfo> result =
            EmailPdfGenerator.getAttachmentInfoList(configJson, null, null);
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assertEquals('child', result[0].recordSourceType);
        System.assertEquals('rel', result[0].selectedRelationship);
        System.assertEquals(2, result[0].singleChildLimit);
        System.assertEquals(10, result[0].maxChildRecords);
    }

    // ── AttachmentInfo inner class construction ───────────────────────

    @isTest
    static void attachmentInfo_directConstruction() {
        EmailPdfGenerator.AttachmentInfo info = new EmailPdfGenerator.AttachmentInfo();
        info.id = 'x1';
        info.name = 'Test';
        info.fileName = 'test.pdf';
        info.type = 'VFPage';
        info.contentType = 'application/pdf';
        info.isRequired = true;
        info.isSelected = true;
        System.assertEquals('x1', info.id);
        System.assertEquals('application/pdf', info.contentType);
    }
}