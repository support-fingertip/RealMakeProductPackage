@isTest
private class DeleteNewLeadsAsyncTest {

    @isTest
    static void testExecuteWithEmptyList() {
        Test.startTest();
        DeleteNewLeadsAsync job = new DeleteNewLeadsAsync(new List<Id>());
        job.execute(null);
        Test.stopTest();
        System.assert(true, 'Empty list should complete without error');
    }

    @isTest
    static void testExecuteWithNullList() {
        Test.startTest();
        DeleteNewLeadsAsync job = new DeleteNewLeadsAsync(null);
        job.execute(null);
        Test.stopTest();
        System.assert(true, 'Null list should complete without error');
    }

    @isTest
    static void testExecuteWithValidLeadIds() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('DeleteAsyncProj');
        Lead__c l1 = TestDataFactory.createLead(p.Id, 'Del1', '9800000090');
        Lead__c l2 = TestDataFactory.createLead(p.Id, 'Del2', '9800000091');

        List<Id> leadIds = new List<Id>{ l1.Id, l2.Id };

        Test.startTest();
        DeleteNewLeadsAsync job = new DeleteNewLeadsAsync(leadIds);
        job.execute(null);
        Test.stopTest();

        // Verify leads are deleted
        List<Lead__c> remaining = [SELECT Id FROM Lead__c WHERE Id IN :leadIds];
        System.assertEquals(0, remaining.size(), 'Leads should be deleted');
    }

    @isTest
    static void testExecuteAsQueueable() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('QueueDelProj');
        Lead__c l = TestDataFactory.createLead(p.Id, 'QDel', '9800000092');

        Test.startTest();
        System.enqueueJob(new DeleteNewLeadsAsync(new List<Id>{ l.Id }));
        Test.stopTest();

        List<Lead__c> remaining = [SELECT Id FROM Lead__c WHERE Id = :l.Id];
        System.assertEquals(0, remaining.size(), 'Lead should be deleted via queueable');
    }
}