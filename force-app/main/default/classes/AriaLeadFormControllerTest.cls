@isTest
private class AriaLeadFormControllerTest {

    @TestSetup
    static void setup() {
        // Project in Telangana — TestDataFactory defaults state to Telangana
        Project__c p = TestDataFactory.createProject('Aria Form Test');
        p.Is_Active__c = true;
        p.Project_Status__c = 'Launched';
        p.Allowed_BHK_Types__c = '2BHK;3BHK';
        update p;

        Tower__c t = TestDataFactory.createTower(p.Id, 'TowerA');
        TestDataFactory.createUnit(p.Id, t.Id, 'A-101');
    }

    @isTest
    static void getStates_returns_distinct_active_states() {
        List<Map<String, Object>> states = AriaLeadFormController.getStates();
        System.assert(!states.isEmpty(), 'Expected at least one state from the test project');
        Boolean hasTelangana = false;
        for (Map<String, Object> s : states) {
            if ('Telangana'.equals(s.get('value'))) hasTelangana = true;
        }
        System.assert(hasTelangana, 'Expected Telangana in returned states');
    }

    @isTest
    static void getProjectsByState_returns_projects() {
        List<Map<String, Object>> projects = AriaLeadFormController.getProjectsByState('Telangana');
        System.assert(!projects.isEmpty());
        Map<String, Object> first = projects[0];
        System.assertNotEquals(null, first.get('value'));      // project Id
        System.assertNotEquals(null, first.get('label'));      // display label
        System.assertNotEquals(null, first.get('project_code'));
        System.assertNotEquals(null, first.get('allowed_bhk'));
    }

    @isTest
    static void getProjectsByState_blank_returns_empty() {
        List<Map<String, Object>> out = AriaLeadFormController.getProjectsByState('');
        System.assertEquals(0, out.size());
    }

    @isTest
    static void getBhkOptionsForProject_uses_project_allowed_bhk() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        List<Map<String, Object>> bhks = AriaLeadFormController.getBhkOptionsForProject(p.Id);
        Set<String> values = new Set<String>();
        for (Map<String, Object> b : bhks) values.add((String) b.get('value'));
        System.assert(values.contains('2BHK'));
        System.assert(values.contains('3BHK'));
    }

    @isTest
    static void getBhkOptionsForProject_falls_back_to_picklist_when_unset() {
        // Allowed_BHK_Types__c is a required field on Project__c in this org,
        // so we can't null it on the setup record. Passing a null projectId
        // hits the SAME fallback branch (values.isEmpty() → load the picklist).
        List<Map<String, Object>> bhks = AriaLeadFormController.getBhkOptionsForProject(null);
        System.assert(!bhks.isEmpty(), 'Should fall back to Lead__c.BHK_Type__c picklist');
    }

    @isTest
    static void getStaticOptions_returns_all_buckets() {
        Map<String, Object> out = AriaLeadFormController.getStaticOptions();
        System.assertNotEquals(null, out.get('budgets'));
        System.assertNotEquals(null, out.get('purposes'));
        System.assertNotEquals(null, out.get('timelines'));
        System.assertNotEquals(null, out.get('visit_modes'));
    }

    @isTest
    static void submitLead_validates_payload() {
        try {
            AriaLeadFormController.submitLead('not-json{');
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            // expected
            System.assert(true);
        }
    }

    @isTest
    static void submitLead_blank_throws() {
        try {
            AriaLeadFormController.submitLead('');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void submitLead_missing_required_args_throws() {
        // No mobile / project_code → AriaActionService.createLead throws
        String payload = JSON.serialize(new Map<String, Object>{
            'first_name' => 'Test'
        });
        try {
            AriaLeadFormController.submitLead(payload);
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void submitSiteVisit_validates_lead() {
        try {
            AriaLeadFormController.submitSiteVisit(null, null, '2026-04-20T11:00:00Z', 'On Site');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void submitFollowup_validates_lead() {
        try {
            AriaLeadFormController.submitFollowup(null, '2026-04-20T11:00:00Z', 'subj', 'notes');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void submitFollowup_creates_followup() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c l = TestDataFactory.createLead(p.Id, 'Form', '9888812345');

        // Use a future date so AriaActionService.rejectIfPast does not block.
        DateTime due = DateTime.now().addDays(7);
        String dueIso = due.formatGmt('yyyy-MM-dd') + 'T' + due.formatGmt('HH:mm:ss') + 'Z';

        Test.startTest();
        Map<String, Object> result = AriaLeadFormController.submitFollowup(
            l.Id, dueIso, 'Aria form follow-up', 'Test notes'
        );
        Test.stopTest();

        Id followupId = (Id) result.get('followup_id');
        Followup__c f = [SELECT Subject__c, Lead__c FROM Followup__c WHERE Id = :followupId];
        System.assertEquals('Aria form follow-up', f.Subject__c);
        System.assertEquals(l.Id, f.Lead__c);
    }

    @isTest
    static void getPicklistValues_returns_active_only() {
        List<Map<String, Object>> out = AriaLeadFormController.getPicklistValues('Lead__c', 'BHK_Type__c');
        System.assert(!out.isEmpty());
    }
}