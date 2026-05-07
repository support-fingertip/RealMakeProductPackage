@isTest
private class ApprovalActionHandlerTest {

    // ==================== TEST DATA SETUP ====================

    @TestSetup
    static void setupTestData() {
        Approval_Configuration__c config1 = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'Account Approval',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = '{"actions":[{"actionType":"FIELD_UPDATE","fieldUpdates":[{"fieldName":"Description","value":"Approved"}]}]}',
            On_Rejection_JSON__c = '{"actions":[{"actionType":"FIELD_UPDATE","fieldUpdates":[{"fieldName":"Description","value":"Rejected"}]}]}'
        );
        insert config1;
    }

    // ==================== TESTS ====================

    @isTest
    static void testProcessApprovalNotifications_NullRecordId() {
        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = null;
        req.priorValuesJson = null;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Record ID is required'));
    }

    @isTest
    static void testProcessApprovalNotifications_NoConfig() {
        Contact c = new Contact(LastName = 'TestContact');
        insert c;

        delete [SELECT Id FROM Approval_Configuration__c WHERE Object_API_Name__c = 'Contact'];

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = c.Id;
        req.priorValuesJson = null;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
    }

    @isTest
    static void testProcessApprovalNotifications_ApprovalDetected() {
        Account acc = new Account(
            Name = 'Test Account',
            AccountSource = 'Web'
        );
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assert(results[0].message.contains('APPROVAL'));
    }

    @isTest
    static void testProcessApprovalNotifications_RejectionDetected() {
        Account acc = new Account(
            Name = 'Test Account Rejected',
            AccountSource = 'Phone'
        );
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Web"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assert(results[0].message.contains('REJECTION'));
    }

    @isTest
    static void testProcessApprovalNotifications_NoChange() {
        Account acc = new Account(
            Name = 'No Change Account',
            AccountSource = 'Web'
        );
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Web"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('No final approval'));
    }

    @isTest
    static void testProcessApprovalNotifications_NoPriorValues() {
        Account acc = new Account(
            Name = 'Test No Prior',
            AccountSource = 'Web'
        );
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = null;

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
    }

    @isTest
    static void testFieldUpdate_SpecialValues() {
        Approval_Configuration__c config = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'Special Value Test',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = '{"actions":[{"actionType":"FIELD_UPDATE","fieldUpdates":[{"fieldName":"OwnerId","value":"$USER_ID"}]}]}'
        );
        insert config;

        Account acc = new Account(Name = 'Special Value Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
    }

    @isTest
    static void testChatterPost_Action() {
        Approval_Configuration__c config = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'Chatter Test',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = '{"actions":[{"actionType":"CHATTER_POST","chatterMessage":"Record has been approved!"}]}'
        );
        insert config;

        Account acc = new Account(Name = 'Chatter Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
    }

    @isTest
    static void testChatterPost_BlankMessage() {
        Approval_Configuration__c config = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'Chatter Blank Test',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = '{"actions":[{"actionType":"CHATTER_POST","chatterMessage":""}]}'
        );
        insert config;

        Account acc = new Account(Name = 'Chatter Blank Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
    }

    @isTest
    static void testEmailNotification_AdditionalEmails() {
        Approval_Configuration__c config = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'Email Test',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = '{"actions":[{"actionType":"EMAIL_NOTIFICATION","emailConfig":{"additionalEmails":["test@example.com"]}}]}'
        );
        insert config;

        Account acc = new Account(Name = 'Email Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
    }

    @isTest
    static void testEmailNotification_RecipientFieldPath() {
        Approval_Configuration__c config = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'Email Field Path Test',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = '{"actions":[{"actionType":"EMAIL_NOTIFICATION","emailConfig":{"recipientFieldPaths":["OwnerId"]}}]}'
        );
        insert config;

        Account acc = new Account(Name = 'Email Field Path Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
    }

    @isTest
    static void testEmailNotification_WithTemplate() {
        Approval_Configuration__c config = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'Email Template Test',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = '{"actions":[{"actionType":"EMAIL_NOTIFICATION","emailConfig":{"additionalEmails":["test@example.com"],"templateDeveloperName":"NonExistentTemplate"}}]}'
        );
        insert config;

        Account acc = new Account(Name = 'Email Template Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
    }

    @isTest
    static void testBellNotification_BlankTitleOrBody() {
        Approval_Configuration__c config = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'Bell Blank Test',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = '{"actions":[{"actionType":"BELL_NOTIFICATION","bellConfig":{"title":"","body":"","recipientFieldPaths":[]}}]}'
        );
        insert config;

        Account acc = new Account(Name = 'Bell Blank Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
    }

    @isTest
    static void testBellNotification_WithMergeFields() {
        Approval_Configuration__c config = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'Bell Merge Test',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = '{"actions":[{"actionType":"BELL_NOTIFICATION","bellConfig":{"title":"Approved: {Name}","body":"Record {Name} has been approved","recipientFieldPaths":["OwnerId"]}}]}'
        );
        insert config;

        Account acc = new Account(Name = 'Bell Merge Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
    }

    @isTest
    static void testInvalidPriorValuesJson() {
        Account acc = new Account(Name = 'Invalid JSON Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = 'not-valid-json{{}}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size());
    }

    @isTest
    static void testNoActionsJson_OnApproval() {
        Approval_Configuration__c config = new Approval_Configuration__c(
            Object_API_Name__c = 'Account',
            Process_Type__c = 'Standard',
            Process_Label__c = 'No Action JSON',
            Status_Field_API_Name__c = 'AccountSource',
            Approved_Status_Value__c = 'Web',
            Rejected_Status_Value__c = 'Phone',
            Is_Active__c = true,
            On_Approval_JSON__c = null
        );
        insert config;

        Account acc = new Account(Name = 'No Action Account', AccountSource = 'Web');
        insert acc;

        ApprovalActionHandler.NotificationRequest req = new ApprovalActionHandler.NotificationRequest();
        req.recordId = acc.Id;
        req.priorValuesJson = '{"AccountSource":"Phone"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
    }

    @isTest
    static void testMultipleRequests() {
        Account acc1 = new Account(Name = 'Bulk Account 1', AccountSource = 'Web');
        Account acc2 = new Account(Name = 'Bulk Account 2', AccountSource = 'Phone');
        insert new List<Account>{ acc1, acc2 };

        ApprovalActionHandler.NotificationRequest req1 = new ApprovalActionHandler.NotificationRequest();
        req1.recordId = acc1.Id;
        req1.priorValuesJson = '{"AccountSource":"Phone"}';

        ApprovalActionHandler.NotificationRequest req2 = new ApprovalActionHandler.NotificationRequest();
        req2.recordId = acc2.Id;
        req2.priorValuesJson = '{"AccountSource":"Web"}';

        Test.startTest();
        List<ApprovalActionHandler.NotificationResult> results =
            ApprovalActionHandler.processApprovalNotifications(
                new List<ApprovalActionHandler.NotificationRequest>{ req1, req2 }
            );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[1].success);
    }

    @isTest
    static void testInnerClassInstantiation() {
        ApprovalActionHandler.ActionConfig ac = new ApprovalActionHandler.ActionConfig();
        ApprovalActionHandler.ActionItem ai = new ApprovalActionHandler.ActionItem();
        ApprovalActionHandler.EmailConfig ec = new ApprovalActionHandler.EmailConfig();
        ApprovalActionHandler.BellConfig bc = new ApprovalActionHandler.BellConfig();
        ApprovalActionHandler.FieldUpdate fu = new ApprovalActionHandler.FieldUpdate();
        ApprovalActionHandler.NotificationRequest nr = new ApprovalActionHandler.NotificationRequest();
        ApprovalActionHandler.NotificationResult nres = new ApprovalActionHandler.NotificationResult();

        System.assertNotEquals(null, ac);
        System.assertNotEquals(null, ai);
        System.assertNotEquals(null, ec);
        System.assertNotEquals(null, bc);
        System.assertNotEquals(null, fu);
        System.assertNotEquals(null, nr);
        System.assertNotEquals(null, nres);
    }

}