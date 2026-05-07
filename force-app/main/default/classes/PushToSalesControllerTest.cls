@IsTest
private class PushToSalesControllerTest {

    @TestSetup
    static void setupData() {
        DuplicateConversionEngine.skipProcessing = true;

        Project__c proj = TestDataFactory.createProject('Test Project Push');
        proj.Project_Code__c = 'TPP-001';
        proj.Project_Status__c = 'Launched';
        proj.Is_Active__c = true;
        update proj;

        // Round Robin bucket + Sales member for push-to-sales
        Round_Robin__c rr = TestDataFactory.createRoundRobin(proj.Id);
        TestDataFactory.createRRMember(rr.Id, UserInfo.getUserId(), 'Sales', 1);

        // General Setup for Manual push
        General_Setup__c gsManual = new General_Setup__c(
            Push_To_Sales_Type__c = 'Manual',
            Is_Active__c = true,
            Description__c = 'Manual push config'
        );
        insert gsManual;
    }

    static Project__c getProject() {
        return [SELECT Id FROM Project__c WHERE Project_Code__c = 'TPP-001' LIMIT 1];
    }

    @IsTest
    static void testGetLeadInfo_PreSalesWithSVScheduled() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = getProject();
        Lead__c lead = new Lead__c(
            First_Name__c = 'Test',
            Last_Name__c = 'User',
            Primary_Mobile__c = '9000011111',
            Project__c = proj.Id,
            Lead_Status__c = 'Site Visit Scheduled',
            Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Walk-in',
            Lead_Sub_Source__c = 'Google'
        );
        insert lead;

        Test.startTest();
        Map<String, Object> info = PushToSalesController.getLeadInfo(lead.Id);
        Test.stopTest();

        System.assertEquals(true, info.get('canPush'), 'Should be pushable');
        System.assertEquals(true, info.get('isPreSales'), 'Should be Pre Sales');
        System.assertEquals('Site Visit Scheduled', info.get('leadStatus'));
    }

    @IsTest
    static void testGetLeadInfo_PreSalesWithNewEnquiry() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = getProject();
        Lead__c lead = new Lead__c(
            First_Name__c = 'Test',
            Last_Name__c = 'User',
            Primary_Mobile__c = '9000022222',
            Project__c = proj.Id,
            Lead_Status__c = 'New Enquiry',
            Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Walk-in',
            Lead_Sub_Source__c = 'Google'
        );
        insert lead;

        Test.startTest();
        Map<String, Object> info = PushToSalesController.getLeadInfo(lead.Id);
        Test.stopTest();

        System.assertEquals(false, info.get('canPush'),
            'Should NOT be pushable (status is New Enquiry)');
    }

    @IsTest
    static void testGetLeadInfo_SalesRecordType() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = getProject();
        // Create with Sales RT from the start so 'Site Visit Completed' is valid
        Id salesRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
            .get('Sales').getRecordTypeId();
        Lead__c lead = new Lead__c(
            RecordTypeId = salesRTId,
            First_Name__c = 'Test',
            Last_Name__c = 'Sales',
            Primary_Mobile__c = '9000033333',
            Project__c = proj.Id,
            Lead_Status__c = 'Site Visit Completed',
            Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Walk-in',
            Lead_Sub_Source__c = 'Google'
        );
        insert lead;

        Test.startTest();
        Map<String, Object> info = PushToSalesController.getLeadInfo(lead.Id);
        Test.stopTest();

        System.assertEquals(false, info.get('canPush'),
            'Should NOT be pushable (already Sales)');
        System.assertEquals(false, info.get('isPreSales'));
    }

    @IsTest
    static void testPushToSales_NoConfig() {
        DuplicateConversionEngine.skipProcessing = true;
        // Deactivate manual config so the test can verify "no config" path
        General_Setup__c gs = [
            SELECT Id FROM General_Setup__c
            WHERE Push_To_Sales_Type__c = 'Manual' LIMIT 1
        ];
        gs.Is_Active__c = false;
        update gs;

        Project__c proj = getProject();
        Lead__c lead = new Lead__c(
            First_Name__c = 'Test',
            Last_Name__c = 'Push',
            Primary_Mobile__c = '9000044444',
            Project__c = proj.Id,
            Lead_Status__c = 'Site Visit Scheduled',
            Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Walk-in',
            Lead_Sub_Source__c = 'Google'
        );
        insert lead;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            PushToSalesController.pushToSales(lead.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
            // AuraHandledException.getMessage() returns 'Script-thrown exception' in test context
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw when no General Setup config exists');
    }

    @IsTest
    static void testPushToSales_WrongStatus() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = getProject();
        Lead__c lead = new Lead__c(
            First_Name__c = 'Test',
            Last_Name__c = 'Wrong',
            Primary_Mobile__c = '9000055555',
            Project__c = proj.Id,
            Lead_Status__c = 'New Enquiry',
            Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Walk-in',
            Lead_Sub_Source__c = 'Google'
        );
        insert lead;

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            PushToSalesController.pushToSales(lead.Id);
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw for wrong status');
    }
}