/**
 * @description Test class for EnquirySourceTrigger (100% coverage).
 * Covers before insert (campaign inherit), after insert/update/delete/
 * undelete (Trigger.new loop + Trigger.old loop for rollup).
 */
@isTest
private class EnquirySourceTriggerTest {
    @isTest
    static void allBranches() {
        Project__c p = TestDataFactory.createProject('EST');
        Campaign__c c = TestDataFactory.createCampaign('EST Campaign');
        Lead__c lead = TestDataFactory.createLead(p.Id, 'EST', '9200000001');
        lead.Campaign__c = c.Id;
        update lead;

        Test.startTest();
        Enquiry_Source__c es = new Enquiry_Source__c(
            Lead__c = lead.Id,
            Enquiry_Date__c = DateTime.now(),
            Enquiry_Type__c = 'New',
            Source__c = 'Digital',
            Primary_Mobile__c = '9200000001'
        );
        insert es;          // before insert + after insert
        es.Source__c = 'Google';
        update es;          // after update (new + old campaign loops)
        delete es;          // after delete (old campaign loop)
        undelete es;        // after undelete (new campaign loop)
        Test.stopTest();
    }
}