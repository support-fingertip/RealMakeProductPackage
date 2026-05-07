@isTest
private class DynamicDocumentPDFControllerTest {

    @isTest
    static void testConstructorNoParams() {
        Test.startTest();
        // No parameters set - should show missing templateId error
        PageReference pageRef = Page.DynamicDocumentPDF;
        Test.setCurrentPage(pageRef);
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.renderedHtml, 'Should have rendered HTML');
        System.assert(ctrl.renderedHtml.contains('Missing templateId') || ctrl.renderedHtml.contains('Error'),
                       'Should show error for missing templateId');
        System.assertEquals('A4', ctrl.pageSize, 'Default page size should be A4');
        System.assertEquals('portrait', ctrl.pageOrientation, 'Default orientation should be portrait');
        System.assertNotEquals(null, ctrl.marginTop);
        System.assertNotEquals(null, ctrl.marginRight);
        System.assertNotEquals(null, ctrl.marginBottom);
        System.assertNotEquals(null, ctrl.marginLeft);
        System.assertNotEquals(null, ctrl.fontFamily);
    }

    @isTest
    static void testConstructorWithInvalidTemplateId() {
        Test.startTest();
        PageReference pageRef = Page.DynamicDocumentPDF;
        pageRef.getParameters().put('templateId', 'invalidId12345');
        Test.setCurrentPage(pageRef);
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();

        // Should show "Template not found" or error
        System.assertNotEquals(null, ctrl.renderedHtml);
    }

    @isTest
    static void testConstructorWithTemplate() {
        // Create a document template
        Document_Template__c template = new Document_Template__c(
            Name = 'Test Template',
            Object_API_Name__c = 'Booking__c',
            Template_JSON__c = '{"header":{"title":"Test"},"sections":[{"type":"text","content":"Hello"}],"styles":{"marginTop":"25","marginRight":"20","marginBottom":"25","marginLeft":"20","fontFamily":"Courier"}}',
            Page_Size__c = 'Letter',
            Page_Orientation__c = 'landscape'
        );
        insert template;

        Test.startTest();
        PageReference pageRef = Page.DynamicDocumentPDF;
        pageRef.getParameters().put('templateId', template.Id);
        Test.setCurrentPage(pageRef);
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.renderedHtml);
        System.assertEquals('Test Template', ctrl.documentTitle);
        System.assertEquals('Letter', ctrl.pageSize);
        System.assertEquals('landscape', ctrl.pageOrientation);
    }

    @isTest
    static void testConstructorWithTemplateAndRecordId() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('DDPdf Proj');
        Booking__c bk = new Booking__c(
            Project__c = p.Id, Booking_Date__c = Date.today(),
            Status__c = 'Approved, Active', Owner__c = UserInfo.getUserId()
        );
        insert bk;

        Document_Template__c template = new Document_Template__c(
            Name = 'Booking Template',
            Object_API_Name__c = 'Booking__c',
            Template_JSON__c = '{"header":{"title":"Booking"},"sections":[]}'
        );
        insert template;

        Test.startTest();
        PageReference pageRef = Page.DynamicDocumentPDF;
        pageRef.getParameters().put('templateId', template.Id);
        pageRef.getParameters().put('id', bk.Id);
        Test.setCurrentPage(pageRef);
        DynamicDocumentPDFController ctrl = new DynamicDocumentPDFController();
        Test.stopTest();

        System.assertNotEquals(null, ctrl.renderedHtml);
    }
}