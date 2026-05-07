@isTest
private class LeadReopenServiceTest {

    @TestSetup
    static void setup() {
        TestDataFactory.createCPModuleConfig();
        Project__c proj = TestDataFactory.createProject('Test Project');

        // Create Round Robin bucket with filter and member
        Round_Robin__c rr = new Round_Robin__c(Is_Active__c = true);
        insert rr;

        Round_Robin_Filter__c filter = new Round_Robin_Filter__c(
            Round_Robin__c = rr.Id,
            Field_API_Name__c = 'Project__c',
            Field_Value__c = proj.Id,
            Field_Priority__c = 1,
            Preference_Order__c = 1
        );
        insert filter;

        Round_Robin_Member__c member = new Round_Robin_Member__c(
            Round_Robin__c = rr.Id,
            User__c = UserInfo.getUserId(),
            Assignment_Type__c = 'Pre Sales',
            Is_Active__c = true,
            Order__c = 1
        );
        insert member;
    }

    @isTest
    static void testReopenInactiveLead() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Reopen', '9000000001');

        // Make lead inactive
        lead.Lead_Status__c = 'Unqualified';
        lead.Lost_Reason__c = 'Budget';
        update lead;

        Test.startTest();
        LeadReopenService.ReopenResult result = LeadReopenService.reopenLead(
            lead.Id, 'Manual', 'Quick Action'
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(lead.Id, result.leadId, 'Lead ID should match');
        System.assertNotEquals(null, result.newStatus, 'New status should be set');

        // Verify lead was updated
        Lead__c updated = [SELECT Lead_Status__c, Lead_Type__c, Last_Reopened_Date__c
                           FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Re-opened', updated.Lead_Type__c);
        System.assertEquals(Date.today(), updated.Last_Reopened_Date__c);

        // Verify Enquiry Source was created
        List<Enquiry_Source__c> sources = [SELECT Id, Enquiry_Type__c, Source__c
                                            FROM Enquiry_Source__c WHERE Lead__c = :lead.Id];
        System.assert(!sources.isEmpty(), 'Enquiry Source should be created');
        System.assertEquals('Re-opened', sources[0].Enquiry_Type__c);
    }

    @isTest
    static void testReopenWithOverrides() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Override', '9000000002');

        lead.Lead_Status__c = 'Unqualified';
        lead.Lost_Reason__c = 'Budget';
        update lead;

        Test.startTest();
        LeadReopenService.ReopenResult result = LeadReopenService.reopenLead(
            lead.Id, 'Walk-in', null,
            UserInfo.getUserId(), 'Site Visit Scheduled'
        );
        Test.stopTest();

        Lead__c updated = [SELECT Lead_Status__c, Owner__c FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Site Visit Scheduled', updated.Lead_Status__c);
        System.assertEquals(UserInfo.getUserId(), updated.Owner__c);
    }

    @isTest
    static void testReopenActiveLeadThrowsError() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Active', '9000000003');

        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            LeadReopenService.reopenLead(lead.Id, 'Manual', null);
        } catch (LeadReopenService.LeadReopenException e) {
            exceptionThrown = true;
            System.assert(e.getMessage().contains('already active'));
        }
        Test.stopTest();

        System.assert(exceptionThrown, 'Should throw exception for active lead');
    }

    @isTest
    static void testReopenNullLeadThrowsError() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            LeadReopenService.reopenLead(null, 'Manual', null);
        } catch (LeadReopenService.LeadReopenException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
        System.assert(exceptionThrown, 'Should throw exception for null lead ID');
    }
}