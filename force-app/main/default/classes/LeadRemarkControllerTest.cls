/**
 * @description Test class for LeadRemarkController (100% coverage).
 */
@isTest
private class LeadRemarkControllerTest {

    @TestSetup
    static void setup() {
        Project__c p = TestDataFactory.createProject('LRC');
        TestDataFactory.createLead(p.Id, 'LRC', '9900001201');
    }

    @isTest
    static void addRemark_blank_throws() {
        Boolean thrown = false;
        try {
            LeadRemarkController.addRemark(null, '');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown);

        thrown = false;
        try {
            LeadRemarkController.addRemark(null, '   ');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown, 'Whitespace-only remark should throw');
    }

    @isTest
    static void addRemark_firstRemarkWithEmptyNotes() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];

        Test.startTest();
        LeadRemarkController.addRemark(lead.Id, 'First remark\n\n\nwith blank lines');
        Test.stopTest();

        Lead__c updated = [SELECT Last_Notes__c FROM Lead__c WHERE Id = :lead.Id];
        System.assert(updated.Last_Notes__c.startsWith('Remark 1:'));
        System.assert(!updated.Last_Notes__c.contains('\n\n\n'),
            'Multiple blank lines should have been collapsed');
    }

    @isTest
    static void addRemark_appendsToExistingNotes() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        LeadRemarkController.addRemark(lead.Id, 'First');

        Test.startTest();
        LeadRemarkController.addRemark(lead.Id, 'Second');
        Test.stopTest();

        Lead__c updated = [SELECT Last_Notes__c FROM Lead__c WHERE Id = :lead.Id];
        System.assert(updated.Last_Notes__c.contains('Remark 1:'));
        System.assert(updated.Last_Notes__c.contains('Remark 2:'));
    }

    @isTest
    static void fetchRemarks_emptyNotes_returnsEmpty() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Test.startTest();
        List<String> remarks = LeadRemarkController.fetchRemarks(lead.Id);
        Test.stopTest();
        System.assertEquals(0, remarks.size());
    }

    @isTest
    static void fetchRemarks_returnsInReverseOrder() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        LeadRemarkController.addRemark(lead.Id, 'First');
        LeadRemarkController.addRemark(lead.Id, 'Second');

        Test.startTest();
        List<String> remarks = LeadRemarkController.fetchRemarks(lead.Id);
        Test.stopTest();
        System.assertEquals(2, remarks.size());
        System.assert(remarks[0].contains('Remark 2:'), 'Latest first');
        System.assert(remarks[1].contains('Remark 1:'));
    }
}