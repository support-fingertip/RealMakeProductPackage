/**
 * @description Test class for LeadDuplicateController (100% coverage).
 */
@isTest
private class LeadDuplicateControllerTest {

    @isTest
    static void getDuplicateOfId_found() {
        Project__c p = TestDataFactory.createProject('LDC');
        Lead__c original = TestDataFactory.createLead(p.Id, 'Orig', '9900001101');
        Lead__c dup = TestDataFactory.createLead(p.Id, 'Dup', '9900001102');
        dup.Duplicate_Of__c = original.Id;
        update dup;

        Test.startTest();
        Id result = LeadDuplicateController.getDuplicateOfId(dup.Id);
        Test.stopTest();
        System.assertEquals(original.Id, result);
    }

    @isTest
    static void getDuplicateOfId_notFound_returnsNull() {
        // Empty query result → returns null
        Test.startTest();
        Id result = LeadDuplicateController.getDuplicateOfId('a0W000000000001');
        Test.stopTest();
        System.assertEquals(null, result);
    }

    @isTest
    static void deleteDuplicateLead_deletesWhenMatchExists() {
        Project__c p = TestDataFactory.createProject('LDC');
        Lead__c original = TestDataFactory.createLead(p.Id, 'Orig', '9900001103');
        Lead__c dup = TestDataFactory.createLead(p.Id, 'Dup', '9900001104');
        dup.Duplicate_Of__c = original.Id;
        update dup;

        Test.startTest();
        LeadDuplicateController.deleteDuplicateLead(dup.Id);
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Lead__c WHERE Id = :dup.Id]);
    }

    @isTest
    static void deleteDuplicateLead_noMatch_noop() {
        Project__c p = TestDataFactory.createProject('LDC');
        Lead__c lead = TestDataFactory.createLead(p.Id, 'NotDup', '9900001105');
        // Duplicate_Of__c is null → query returns empty → no delete

        Test.startTest();
        LeadDuplicateController.deleteDuplicateLead(lead.Id);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Lead__c WHERE Id = :lead.Id]);
    }
}