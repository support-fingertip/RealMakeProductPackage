@isTest
private class AriaAgentMetricsServiceTest {

    @TestSetup
    static void setup() {
        Project__c p = TestDataFactory.createProject('Metrics Test');
        Lead__c l = TestDataFactory.createLead(p.Id, 'Agent', '9888899999');
        TestDataFactory.createFollowup(l.Id, UserInfo.getUserId());
    }

    @isTest
    static void myPerformance_returns_counts() {
        Map<String, Object> r = AriaAgentMetricsService.myPerformance(30);
        System.assertNotEquals(null, r.get('leads_created'));
        System.assertNotEquals(null, r.get('conversion_rate_pct'));
    }

    @isTest
    static void getOverdueFollowups_returns_list() {
        // The TestDataFactory follow-up is due tomorrow — not overdue. So we
        // expect 0 overdue, but the method should still succeed.
        Map<String, Object> r = AriaAgentMetricsService.getOverdueFollowups();
        System.assertNotEquals(null, r.get('count'));
    }

    @isTest
    static void getStaleLeads_returns_list() {
        Map<String, Object> r = AriaAgentMetricsService.getStaleLeads(0);
        // days=0 means "stale if modified before right now" — our test lead was
        // just created, so it may or may not qualify. Just verify no exception.
        System.assertNotEquals(null, r.get('count'));
    }

    @isTest
    static void explainLeadScore_happy_path() {
        Lead__c l = [SELECT Id FROM Lead__c LIMIT 1];
        Map<String, Object> r = AriaAgentMetricsService.explainLeadScore(l.Id);
        System.assertNotEquals(null, r.get('lead_id'));
        System.assertNotEquals(null, r.get('rules'));
        System.assertNotEquals(null, r.get('tiers'));
    }

    @isTest
    static void explainLeadScore_missing_lead() {
        Map<String, Object> r = AriaAgentMetricsService.explainLeadScore(null);
        System.assertEquals('lead_id is required', r.get('error'));
    }

    @isTest
    static void getWelcomeMetrics_returns_all_keys() {
        Map<String, Object> r = AriaAgentMetricsService.getWelcomeMetrics();
        System.assert(r.containsKey('overdue_followups'));
        System.assert(r.containsKey('site_visits_today'));
        System.assert(r.containsKey('new_leads_today'));
        System.assert(r.containsKey('stale_leads_7d'));
    }

    @isTest
    static void getLeadMetrics_returns_null_for_null_id() {
        System.assertEquals(null, AriaAgentMetricsService.getLeadMetrics(null));
    }

    @isTest
    static void getLeadMetrics_returns_null_for_non_lead_id() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        System.assertEquals(null, AriaAgentMetricsService.getLeadMetrics(p.Id),
            'Non-Lead recordIds should return null so the LWC falls back to welcome metrics');
    }

    @isTest
    static void getLeadMetrics_counts_children_and_includes_greeting() {
        Lead__c l = [SELECT Id FROM Lead__c LIMIT 1];
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        TestDataFactory.createSiteVisit(l.Id, p.Id, UserInfo.getUserId());

        Test.startTest();
        Map<String, Object> r = AriaAgentMetricsService.getLeadMetrics(l.Id);
        Test.stopTest();

        System.assertNotEquals(null, r);
        System.assertEquals(l.Id, (Id) r.get('lead_id'));
        System.assert((Integer) r.get('followups') >= 1,
            'Test setup created 1 follow-up');
        System.assert((Integer) r.get('site_visits') >= 1,
            'Test added 1 site visit');
        System.assertEquals(0, (Integer) r.get('cost_sheets'));
        System.assertEquals(0, (Integer) r.get('bookings'));
        System.assert(r.containsKey('readiness'),
            'Readiness hint should be present for the proactive greeting');
    }
}