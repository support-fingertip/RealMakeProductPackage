@isTest
private class CampaignTriggerHandlerTest {

    // ==================== HELPER ====================

    private static Id getTestProjectId() {
        Project__c proj = new Project__c(
            Name = 'Test Project',
            Allowed_BHK_Types__c = '1BHK',
            Max_Block_Days__c = 30,
            Min_Booking_Amount__c = 10000,
            Property_Types__c = 'Apartment'
        );
        insert proj;
        return proj.Id;
    }

    private static Campaign__c createCampaign(String status) {
        Campaign__c camp = new Campaign__c(
            Status__c = status,
            Campaign_Name__c = 'Test Campaign ' + status + ' ' + DateTime.now().getTime(),
            Campaign_Type__c = 'Digital',
            Source__c = 'Google',
            Start_Date__c = Date.today(),
            Target_Project__c = getTestProjectId()
        );
        insert camp;
        return camp;
    }

    // ==================== VALID TRANSITION TESTS ====================

    @isTest
    static void testPlannedToStarted() {
        Campaign__c camp = createCampaign('Planned');

        Test.startTest();
        camp.Status__c = 'Started';
        update camp;
        Test.stopTest();
    }

    @isTest
    static void testPlannedToCancelled() {
        Campaign__c camp = createCampaign('Planned');

        Test.startTest();
        camp.Status__c = 'Cancelled';
        update camp;
        Test.stopTest();
    }

    @isTest
    static void testStartedToHold() {
        Campaign__c camp = createCampaign('Started');

        Test.startTest();
        camp.Status__c = 'Hold';
        update camp;
        Test.stopTest();
    }

    @isTest
    static void testStartedToCompleted() {
        Campaign__c camp = createCampaign('Started');

        Test.startTest();
        camp.Status__c = 'Completed';
        update camp;
        Test.stopTest();
    }

    @isTest
    static void testStartedToCancelled() {
        Campaign__c camp = createCampaign('Started');

        Test.startTest();
        camp.Status__c = 'Cancelled';
        update camp;
        Test.stopTest();
    }

    @isTest
    static void testHoldToStarted() {
        Campaign__c camp = createCampaign('Hold');

        Test.startTest();
        camp.Status__c = 'Started';
        update camp;
        Test.stopTest();
    }

    @isTest
    static void testHoldToCancelled() {
        Campaign__c camp = createCampaign('Hold');

        Test.startTest();
        camp.Status__c = 'Cancelled';
        update camp;
        Test.stopTest();
    }

    // ==================== INVALID TRANSITION TESTS ====================

    @isTest
    static void testPlannedToCompleted_Invalid() {
        Campaign__c camp = createCampaign('Planned');
        Boolean errorThrown = false;

        Test.startTest();
        try {
            camp.Status__c = 'Completed';
            update camp;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    @isTest
    static void testPlannedToHold_Invalid() {
        Campaign__c camp = createCampaign('Planned');
        Boolean errorThrown = false;

        Test.startTest();
        try {
            camp.Status__c = 'Hold';
            update camp;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    @isTest
    static void testStartedToPlanned_Invalid() {
        Campaign__c camp = createCampaign('Started');
        Boolean errorThrown = false;

        Test.startTest();
        try {
            camp.Status__c = 'Planned';
            update camp;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    @isTest
    static void testHoldToCompleted_Invalid() {
        Campaign__c camp = createCampaign('Hold');
        Boolean errorThrown = false;

        Test.startTest();
        try {
            camp.Status__c = 'Completed';
            update camp;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    @isTest
    static void testHoldToPlanned_Invalid() {
        Campaign__c camp = createCampaign('Hold');
        Boolean errorThrown = false;

        Test.startTest();
        try {
            camp.Status__c = 'Planned';
            update camp;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    @isTest
    static void testCompletedToStarted_TerminalState() {
        Campaign__c camp = createCampaign('Completed');
        Boolean errorThrown = false;

        Test.startTest();
        try {
            camp.Status__c = 'Started';
            update camp;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    @isTest
    static void testCompletedToCancelled_TerminalState() {
        Campaign__c camp = createCampaign('Completed');
        Boolean errorThrown = false;

        Test.startTest();
        try {
            camp.Status__c = 'Cancelled';
            update camp;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    @isTest
    static void testCancelledToStarted_TerminalState() {
        Campaign__c camp = createCampaign('Cancelled');
        Boolean errorThrown = false;

        Test.startTest();
        try {
            camp.Status__c = 'Started';
            update camp;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    @isTest
    static void testCancelledToPlanned_TerminalState() {
        Campaign__c camp = createCampaign('Cancelled');
        Boolean errorThrown = false;

        Test.startTest();
        try {
            camp.Status__c = 'Planned';
            update camp;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    // ==================== NO CHANGE TEST ====================

    @isTest
    static void testNoStatusChange_NoError() {
        Campaign__c camp = createCampaign('Planned');

        Test.startTest();
        update camp;
        Test.stopTest();
    }

    // ==================== BULK TESTS ====================

    @isTest
    static void testBulkValidTransitions() {
        Id projectId = getTestProjectId();

        List<Campaign__c> camps = new List<Campaign__c>();
        for (Integer i = 0; i < 20; i++) {
            camps.add(new Campaign__c(
                Status__c = 'Planned',
                Campaign_Name__c = 'Bulk Campaign ' + i,
                Campaign_Type__c = 'Digital',
                Source__c = 'Google',
                Start_Date__c = Date.today(),
                Target_Project__c = projectId
            ));
        }
        insert camps;

        for (Campaign__c c : camps) {
            c.Status__c = 'Started';
        }

        Test.startTest();
        update camps;
        Test.stopTest();
    }

    @isTest
    static void testBulkInvalidTransitions() {
        Id projectId = getTestProjectId();

        List<Campaign__c> camps = new List<Campaign__c>();
        for (Integer i = 0; i < 20; i++) {
            camps.add(new Campaign__c(
                Status__c = 'Completed',
                Campaign_Name__c = 'Bulk Invalid Campaign ' + i,
                Campaign_Type__c = 'Digital',
                Source__c = 'Google',
                Start_Date__c = Date.today(),
                Target_Project__c = projectId
            ));
        }
        insert camps;

        for (Campaign__c c : camps) {
            c.Status__c = 'Started';
        }

        Boolean errorThrown = false;

        Test.startTest();
        try {
            update camps;
        } catch (DmlException e) {
            errorThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, errorThrown);
    }

    // ==================== DIRECT HANDLER TESTS ====================

    @isTest
    static void testDirectHandlerCall_ValidTransition() {
        Campaign__c camp = createCampaign('Planned');
        Campaign__c updatedCamp = camp.clone(true, true, false, false);
        updatedCamp.Status__c = 'Started';

        Map<Id, Campaign__c> oldMap = new Map<Id, Campaign__c>{ camp.Id => camp };

        Test.startTest();
        CampaignTriggerHandler.validateStatusTransitions(
            new List<Campaign__c>{ updatedCamp },
            oldMap
        );
        Test.stopTest();
    }

    @isTest
    static void testDirectHandlerCall_InvalidTransition() {
        Campaign__c camp = createCampaign('Completed');
        Campaign__c updatedCamp = camp.clone(true, true, false, false);
        updatedCamp.Status__c = 'Planned';

        Map<Id, Campaign__c> oldMap = new Map<Id, Campaign__c>{ camp.Id => camp };

        Test.startTest();
        CampaignTriggerHandler.validateStatusTransitions(
            new List<Campaign__c>{ updatedCamp },
            oldMap
        );
        Test.stopTest();
    }

    @isTest
    static void testDirectHandlerCall_NoStatusChange() {
        Campaign__c camp = createCampaign('Planned');
        Campaign__c updatedCamp = camp.clone(true, true, false, false);
        updatedCamp.Status__c = 'Planned';

        Map<Id, Campaign__c> oldMap = new Map<Id, Campaign__c>{ camp.Id => camp };

        Test.startTest();
        CampaignTriggerHandler.validateStatusTransitions(
            new List<Campaign__c>{ updatedCamp },
            oldMap
        );
        Test.stopTest();
    }

    @isTest
    static void testDirectHandlerCall_UnknownOldStatus() {
        Campaign__c camp = createCampaign('Planned');
        Campaign__c oldCamp = camp.clone(true, true, false, false);
        oldCamp.Status__c = 'UnknownStatus';

        Campaign__c updatedCamp = camp.clone(true, true, false, false);
        updatedCamp.Status__c = 'Started';

        Map<Id, Campaign__c> oldMap = new Map<Id, Campaign__c>{ camp.Id => oldCamp };

        Test.startTest();
        CampaignTriggerHandler.validateStatusTransitions(
            new List<Campaign__c>{ updatedCamp },
            oldMap
        );
        Test.stopTest();
    }

}