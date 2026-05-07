@isTest
private class CleanupDuplicateLeadsBatchTest {

    @isTest
    static void testBatchDeletesDuplicateLeads() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('CleanupProj');

        // Create a master lead
        Lead__c masterLead = TestDataFactory.createLead(p.Id, 'Master', '9800000080');

        // Create duplicate leads with Duplicate_Of__c set
        List<Lead__c> dupLeads = new List<Lead__c>();
        for (Integer i = 0; i < 3; i++) {
            Lead__c dup = new Lead__c(
                First_Name__c = 'Dup',
                Last_Name__c = 'Lead' + i,
                Primary_Mobile__c = '980000100' + i,
                Project__c = p.Id,
                Duplicate_Of__c = masterLead.Id,
                Owner__c = UserInfo.getUserId(),
                Lead_Source__c = 'Website'
            );
            dupLeads.add(dup);
        }
        insert dupLeads;

        Integer countBefore = [SELECT COUNT() FROM Lead__c WHERE Duplicate_Of__c != null];
        System.assertEquals(3, countBefore, 'Should have 3 duplicate leads');

        Test.startTest();
        Database.executeBatch(new CleanupDuplicateLeadsBatch(), 200);
        Test.stopTest();

        Integer countAfter = [SELECT COUNT() FROM Lead__c WHERE Duplicate_Of__c != null];
        System.assertEquals(0, countAfter, 'All duplicate leads should be deleted');

        // Master lead should still exist
        List<Lead__c> masters = [SELECT Id FROM Lead__c WHERE Id = :masterLead.Id];
        System.assertEquals(1, masters.size(), 'Master lead should not be deleted');
    }

    @isTest
    static void testBatchNoDuplicates() {
        Test.startTest();
        Database.executeBatch(new CleanupDuplicateLeadsBatch(), 200);
        Test.stopTest();
        System.assert(true, 'Batch should complete with no duplicates');
    }

    @isTest
    static void testSchedulable() {
        Test.startTest();
        CleanupDuplicateLeadsBatch batch = new CleanupDuplicateLeadsBatch();
        String jobId = System.schedule('Test Cleanup Dups', '0 0 * * * ?', batch);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }
}