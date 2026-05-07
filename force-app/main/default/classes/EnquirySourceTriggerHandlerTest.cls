/**
 * @description Test class for EnquirySourceTriggerHandler.
 * Covers Campaign inheritance from the parent Lead — including the
 * "already set", "no lead", "lead without campaign", and happy paths.
 */
@isTest
private class EnquirySourceTriggerHandlerTest {

    @TestSetup
    static void setup() {
        Project__c proj = TestDataFactory.createProject('ESH Project');
        TestDataFactory.createCampaign('ESH Campaign 1');
        TestDataFactory.createCampaign('ESH Campaign 2');
        TestDataFactory.createLead(proj.Id, 'Alice', '9200000001');
        TestDataFactory.createLead(proj.Id, 'Bob',   '9200000002');
    }

    private static Enquiry_Source__c newEs(Id leadId, Id campaignId, String mobile) {
        return new Enquiry_Source__c(
            Lead__c = leadId,
            Campaign__c = campaignId,
            Enquiry_Date__c = DateTime.now(),
            Enquiry_Type__c = 'New',
            Source__c = 'Digital',
            Primary_Mobile__c = mobile
        );
    }

    @isTest
    static void inheritsCampaignFromLead() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Campaign__c camp = [SELECT Id FROM Campaign__c WHERE Campaign_Name__c = 'ESH Campaign 1' LIMIT 1];
        lead.Campaign__c = camp.Id;
        update lead;

        Enquiry_Source__c es = newEs(lead.Id, null, '9200000001');
        Test.startTest();
        insert es;
        Test.stopTest();

        es = [SELECT Campaign__c FROM Enquiry_Source__c WHERE Id = :es.Id];
        System.assertEquals(camp.Id, es.Campaign__c,
            'Campaign should inherit from lead');
    }

    @isTest
    static void campaignAlreadySetIsKept() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Campaign__c c1 = [SELECT Id FROM Campaign__c WHERE Campaign_Name__c = 'ESH Campaign 1' LIMIT 1];
        Campaign__c c2 = [SELECT Id FROM Campaign__c WHERE Campaign_Name__c = 'ESH Campaign 2' LIMIT 1];
        lead.Campaign__c = c1.Id;
        update lead;

        Enquiry_Source__c es = newEs(lead.Id, c2.Id, '9200000001');
        Test.startTest();
        insert es;
        Test.stopTest();

        es = [SELECT Campaign__c FROM Enquiry_Source__c WHERE Id = :es.Id];
        System.assertEquals(c2.Id, es.Campaign__c,
            'Already-set campaign should be preserved');
    }

    @isTest
    static void leadWithoutCampaignLeavesNull() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Bob' LIMIT 1];
        // Lead has no Campaign__c
        Enquiry_Source__c es = newEs(lead.Id, null, '9200000002');
        Test.startTest();
        insert es;
        Test.stopTest();

        es = [SELECT Campaign__c FROM Enquiry_Source__c WHERE Id = :es.Id];
        System.assertEquals(null, es.Campaign__c);
    }

    @isTest
    static void noLeadEarlyReturn() {
        // Exercises "leadIds.isEmpty()" early-return branch.
        Enquiry_Source__c es = newEs(null, null, '9200000099');
        Test.startTest();
        insert es;
        Test.stopTest();

        es = [SELECT Campaign__c FROM Enquiry_Source__c WHERE Id = :es.Id];
        System.assertEquals(null, es.Campaign__c);
    }
}