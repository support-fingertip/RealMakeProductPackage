/**
 * @description Test class for DiscountNotificationQueueable.
 * Target: 100% coverage — execute(), createTasks(), sendEmailToApprovers(),
 * including null/blank comments, no recipients, and submitter-name extraction.
 */
@isTest
private class DiscountNotificationQueueableTest {

    private static Cost_Sheet__c newCostSheet() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('DNQ Proj');
        Lead__c l = new Lead__c(
            First_Name__c = 'Disc',
            Last_Name__c = 'Notify',
            Primary_Mobile__c = '9911112222',
            Primary_Email__c = 'disc.notify@test.com',
            Project__c = p.Id,
            Lead_Status__c = 'New Enquiry',
            Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Digital',
            Lead_Sub_Source__c = 'Google',
            Owner__c = UserInfo.getUserId()
        );
        insert l;
        DuplicateConversionEngine.skipProcessing = false;

        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = l.Id);
        insert cs;
        return cs;
    }

    @isTest
    static void execute_createsTasksForSingleRecipient() {
        Cost_Sheet__c cs = newCostSheet();
        Set<Id> recipients = new Set<Id>{ UserInfo.getUserId() };

        DiscountNotificationQueueable job = new DiscountNotificationQueueable(
            cs.Id, 'CS-001', recipients, 'Please review',
            'Approval Required', 'Alice submitted CS-001 for approval'
        );

        Test.startTest();
        System.enqueueJob(job);
        Test.stopTest();

        List<Task> tasks = [
            SELECT Id, Subject, Description, Priority, Status, OwnerId, WhatId
            FROM Task
            WHERE OwnerId = :UserInfo.getUserId() AND WhatId = :cs.Id
        ];
        System.assertEquals(1, tasks.size(), 'One Task should be created');
        System.assert(tasks[0].Subject.contains('CS-001'));
        System.assert(tasks[0].Description.contains('Please review'));
        System.assertEquals('High', tasks[0].Priority);
        System.assertEquals('Not Started', tasks[0].Status);
    }

    @isTest
    static void execute_emptyRecipients_noTasksNoError() {
        Cost_Sheet__c cs = newCostSheet();

        DiscountNotificationQueueable job = new DiscountNotificationQueueable(
            cs.Id, 'CS-002', new Set<Id>(), null, 'Title', null
        );

        Test.startTest();
        System.enqueueJob(job);
        Test.stopTest();

        Integer taskCount = [SELECT COUNT() FROM Task WHERE WhatId = :cs.Id];
        System.assertEquals(0, taskCount, 'No recipients → no tasks');
    }

    @isTest
    static void execute_nullCommentsAndBody_usesDefaults() {
        Cost_Sheet__c cs = newCostSheet();

        DiscountNotificationQueueable job = new DiscountNotificationQueueable(
            cs.Id, 'CS-003', new Set<Id>{ UserInfo.getUserId() },
            null, 'Title', null
        );
        Test.startTest();
        System.enqueueJob(job);
        Test.stopTest();

        Task t = [SELECT Id, Description FROM Task WHERE WhatId = :cs.Id LIMIT 1];
        System.assert(t.Description.contains('Comments: None'),
            'Null comments should render as "None"');
    }

    @isTest
    static void execute_bodyWithoutSubmittedPhrase() {
        Cost_Sheet__c cs = newCostSheet();

        DiscountNotificationQueueable job = new DiscountNotificationQueueable(
            cs.Id, 'CS-004', new Set<Id>{ UserInfo.getUserId() },
            'any comment', 'Title', 'No phrase here'
        );
        Test.startTest();
        System.enqueueJob(job);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Task WHERE WhatId = :cs.Id];
        System.assertEquals(1, count);
    }

    @isTest
    static void execute_multipleRecipients_createsTaskEach() {
        Cost_Sheet__c cs = newCostSheet();

        // Create a second active user for the recipient set
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User extra = new User(
            Alias = 'dnq',
            Email = 'dnq.extra@test.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'dnq.extra' + DateTime.now().getTime() + '@test.com'
        );
        insert extra;

        Set<Id> recipients = new Set<Id>{ UserInfo.getUserId(), extra.Id };
        DiscountNotificationQueueable job = new DiscountNotificationQueueable(
            cs.Id, 'CS-005', recipients, 'bulk', 'Title',
            'Bob submitted CS-005 for approval'
        );

        Test.startTest();
        System.enqueueJob(job);
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Task WHERE WhatId = :cs.Id];
        System.assertEquals(2, count, 'One Task per recipient');
    }
}