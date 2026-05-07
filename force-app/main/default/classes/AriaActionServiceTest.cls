/**
 * @description Unit tests for AriaActionService.
 *
 * We focus on the thin routing / validation layer here. Exhaustive tests of
 * downstream services (LeadDeduplicationService, SiteVisitCreationService,
 * CostSheetController) live with those services — re-testing them here would
 * require rebuilding their full config surface (integration mappings,
 * calculation templates, etc.) in every test.
 */
@isTest
private class AriaActionServiceTest {

    @TestSetup
    static void setup() {
        Project__c p = TestDataFactory.createProject('Aria Action Test');
        // AriaKnowledgeService.getProjectsDigest() filters on Is_Active__c
        // + Project_Status__c — set both so the test project shows up.
        p.Is_Active__c = true;
        p.Project_Status__c = 'Launched';
        update p;

        Tower__c t = TestDataFactory.createTower(p.Id, 'TowerA');
        TestDataFactory.createUnit(p.Id, t.Id, 'A-101');
        TestDataFactory.createLead(p.Id, 'Ravi', '9888800001');
    }

    // ────────────────────────────────────────────────────────────
    // Router
    // ────────────────────────────────────────────────────────────

    @isTest
    static void dispatch_unknown_tool_throws() {
        try {
            AriaActionService.dispatch('not_a_real_tool', new Map<String, Object>());
            System.assert(false, 'Should have thrown');
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('Unknown'));
        }
    }

    @isTest
    static void dispatch_blank_tool_throws() {
        try {
            AriaActionService.dispatch(null, null);
            System.assert(false, 'Should have thrown');
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('required'));
        }
    }

    // ────────────────────────────────────────────────────────────
    // Read actions
    // ────────────────────────────────────────────────────────────

    @isTest
    static void searchProjects_returns_payload() {
        Map<String, Object> out = (Map<String, Object>) AriaActionService.dispatch(
            'search_projects', new Map<String, Object>()
        );
        List<Map<String, Object>> projects = (List<Map<String, Object>>) out.get('projects');
        System.assert(!projects.isEmpty());
    }

    @isTest
    static void checkUnitAvailability_returns_count() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Map<String, Object> out = (Map<String, Object>) AriaActionService.dispatch(
            'check_unit_availability',
            new Map<String, Object>{ 'project_id' => p.Id, 'bhk_type' => '2BHK' }
        );
        System.assertNotEquals(null, out.get('count'));
    }

    @isTest
    static void getLeadHistory_hydrates_context() {
        Lead__c l = [SELECT Id FROM Lead__c LIMIT 1];
        Map<String, Object> out = AriaActionService.dispatch(
            'get_lead_history', new Map<String, Object>{ 'lead_id' => l.Id }
        );
        System.assertEquals(l.Id, out.get('id'));
    }

    @isTest
    static void getLeadHistory_missing_id_throws() {
        try {
            AriaActionService.dispatch('get_lead_history', new Map<String, Object>());
            System.assert(false, 'Should have thrown');
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('lead_id'));
        }
    }

    @isTest
    static void getProjectDetails_with_code_resolves() {
        Project__c p = [SELECT Project_Code__c FROM Project__c LIMIT 1];
        Map<String, Object> out = AriaActionService.dispatch(
            'get_project_details',
            new Map<String, Object>{ 'project_code' => p.Project_Code__c }
        );
        System.assertEquals('Aria Action Test', out.get('name'));
    }

    // ────────────────────────────────────────────────────────────
    // Write actions — happy path for follow-up (simplest)
    // ────────────────────────────────────────────────────────────

    @isTest
    static void scheduleFollowup_creates_record() {
        Lead__c l = [SELECT Id FROM Lead__c LIMIT 1];

        // Dynamic future date — a hardcoded literal would expire once it
        // drifts into the past and AriaActionService.rejectIfPast() fires.
        // ISO date — parseDate in AriaActionService does Date.valueOf(s)
        Date d = Date.today().addDays(7);
        String futureDate = String.valueOf(d.year()) + '-'
            + String.valueOf(d.month()).leftPad(2, '0') + '-'
            + String.valueOf(d.day()).leftPad(2, '0');

        Test.startTest();
        Map<String, Object> out = AriaActionService.dispatch(
            'schedule_followup',
            new Map<String, Object>{
                'lead_id'  => l.Id,
                'due_date' => futureDate,
                'subject'  => 'Test follow-up from Aria',
                'notes'    => 'Ask about budget'
            }
        );
        Test.stopTest();

        Id followupId = (Id) out.get('followup_id');
        Followup__c f = [SELECT Lead__c, Subject__c, Status__c FROM Followup__c WHERE Id = :followupId];
        System.assertEquals(l.Id, f.Lead__c);
        System.assertEquals('Test follow-up from Aria', f.Subject__c);
    }

    @isTest
    static void scheduleFollowup_missing_lead_throws() {
        // ISO date — parseDate in AriaActionService does Date.valueOf(s)
        Date d = Date.today().addDays(7);
        String futureDate = String.valueOf(d.year()) + '-'
            + String.valueOf(d.month()).leftPad(2, '0') + '-'
            + String.valueOf(d.day()).leftPad(2, '0');
        try {
            AriaActionService.dispatch(
                'schedule_followup',
                new Map<String, Object>{ 'due_date' => futureDate }
            );
            System.assert(false, 'Should have thrown');
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('lead_id'));
        }
    }

    @isTest
    static void scheduleFollowup_missing_due_date_throws() {
        Lead__c l = [SELECT Id FROM Lead__c LIMIT 1];
        try {
            AriaActionService.dispatch(
                'schedule_followup',
                new Map<String, Object>{ 'lead_id' => l.Id }
            );
            System.assert(false, 'Should have thrown');
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('due_date'));
        }
    }

    @isTest
    static void createLead_validates_required_args() {
        try {
            AriaActionService.dispatch('create_lead', new Map<String, Object>{
                'first_name' => 'Test'
            });
            System.assert(false, 'Should have thrown');
        } catch (AriaActionService.AriaActionException e) {
            // Expect failure on missing mobile or project_code
            System.assert(
                e.getMessage().contains('mobile') || e.getMessage().contains('project_code'),
                'Expected validation error, got: ' + e.getMessage()
            );
        }
    }

    @isTest
    static void scheduleSiteVisit_validates_required_args() {
        try {
            AriaActionService.dispatch('schedule_site_visit', new Map<String, Object>());
            System.assert(false, 'Should have thrown');
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('lead_id'));
        }
    }

    @isTest
    static void generateCostSheet_validates_required_args() {
        try {
            AriaActionService.dispatch('generate_cost_sheet', new Map<String, Object>());
            System.assert(false, 'Should have thrown');
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('lead_id') || e.getMessage().contains('unit_id'));
        }
    }

    // ════════════════════════════════════════════════════════════
    // Search / find dispatch
    // ════════════════════════════════════════════════════════════

    @isTest
    static void searchEverything_requires_query() {
        try {
            AriaActionService.dispatch('search_everything', new Map<String, Object>());
            System.assert(false);
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('query'));
        }
    }

    @isTest
    static void searchEverything_returns_results() {
        Lead__c l = [SELECT Primary_Mobile__c FROM Lead__c LIMIT 1];
        Map<String, Object> out = AriaActionService.dispatch(
            'search_everything',
            new Map<String, Object>{ 'query' => l.Primary_Mobile__c }
        );
        System.assertNotEquals(null, out.get('results'));
        System.assert(((Integer) out.get('count')) > 0);
    }

    @isTest
    static void findLead_dispatch_happy_path() {
        Lead__c l = [SELECT Name FROM Lead__c LIMIT 1];
        Map<String, Object> out = AriaActionService.dispatch(
            'find_lead', new Map<String, Object>{ 'query' => l.Name }
        );
        System.assertEquals(1, out.get('count'));
    }

    @isTest
    static void findLead_missing_query_throws() {
        try {
            AriaActionService.dispatch('find_lead', new Map<String, Object>());
            System.assert(false);
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('query'));
        }
    }

    // ════════════════════════════════════════════════════════════
    // Booking flow validation
    // ════════════════════════════════════════════════════════════

    @isTest
    static void getBookingStatus_routes_to_knowledge() {
        Lead__c l = [SELECT Id FROM Lead__c LIMIT 1];
        Map<String, Object> res = AriaActionService.dispatch(
            'get_booking_status', new Map<String, Object>{ 'lead_id' => l.Id }
        );
        System.assertEquals('needs_cost_sheet', res.get('status'));
    }

    @isTest
    static void initiateBooking_missing_cost_sheet_throws() {
        try {
            AriaActionService.dispatch('initiate_booking', new Map<String, Object>{
                'booking_amount' => 100000
            });
            System.assert(false);
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('cost_sheet_id'));
        }
    }

    @isTest
    static void initiateBooking_missing_amount_throws() {
        try {
            AriaActionService.dispatch('initiate_booking', new Map<String, Object>{
                'cost_sheet_id' => 'a00000000000000AAA'
            });
            System.assert(false);
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('booking_amount'));
        }
    }

    @isTest
    static void getPaymentSchedule_missing_booking_throws() {
        try {
            AriaActionService.dispatch('get_payment_schedule', new Map<String, Object>());
            System.assert(false);
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('booking_id'));
        }
    }

    @isTest
    static void blockUnit_validates_required_args() {
        try {
            AriaActionService.dispatch('block_unit', new Map<String, Object>());
            System.assert(false);
        } catch (AriaActionService.AriaActionException e) {
            System.assert(e.getMessage().contains('lead_id') || e.getMessage().contains('unit_id'));
        }
    }

    // ════════════════════════════════════════════════════════════
    // Auto-seed integration configs + CP module config on create_lead
    // ════════════════════════════════════════════════════════════

    @isTest
    static void createLead_seeds_missing_configs() {
        // Verify the auto-seed helpers run when a lead is submitted on a
        // fresh org — neither LEAD_CREATION / ENQUIRY_SOURCE_CREATION nor
        // an active CP_Module_Config__c existed before this call.
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Integration_Source_Config__c
             WHERE Source_Name__c IN ('LEAD_CREATION', 'ENQUIRY_SOURCE_CREATION')]
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM CP_Module_Config__c WHERE Is_Active__c = true]
        );

        // Call createLead with deliberately missing fields to fail fast AFTER
        // the seed runs but BEFORE the downstream LeadDeduplicationService
        // touches data that requires additional fixtures.
        try {
            AriaActionService.dispatch('create_lead', new Map<String, Object>());
            System.assert(false, 'Should have thrown on missing fields');
        } catch (AriaActionService.AriaActionException e) {
            // expected — validation guard
        }

        // Now call with valid inputs — seed runs, then downstream service.
        // We're not asserting on the final insert (fixtures for dedup /
        // round-robin are covered by LeadDeduplicationServiceTest); we're
        // asserting the seed ran regardless of downstream success.
        Project__c p = [SELECT Project_Code__c FROM Project__c LIMIT 1];
        try {
            AriaActionService.dispatch('create_lead', new Map<String, Object>{
                'first_name'   => 'Seed',
                'last_name'    => 'Check',
                'mobile'       => '9888833333',
                'project_code' => p.Project_Code__c
            });
        } catch (Exception ignored) {
            // Downstream fixtures (round-robin) may reject — seed assertion
            // below is what we care about.
        }

        System.assertEquals(
            2,
            [SELECT COUNT() FROM Integration_Source_Config__c
             WHERE Source_Name__c IN ('LEAD_CREATION', 'ENQUIRY_SOURCE_CREATION')
               AND Is_Active__c = true],
            'Both integration configs should be auto-seeded'
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM CP_Module_Config__c WHERE Is_Active__c = true],
            'CP Module Config should be auto-seeded'
        );
    }

    @isTest
    static void getHotLeads_dispatch_returns_leads_key() {
        Map<String, Object> out = AriaActionService.dispatch(
            'get_hot_leads', new Map<String, Object>{ 'top_n' => 3 }
        );
        System.assertNotEquals(null, out.get('leads'),
            'get_hot_leads dispatch should return a leads key');
    }
}