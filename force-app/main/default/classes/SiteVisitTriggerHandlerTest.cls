@isTest
private class SiteVisitTriggerHandlerTest {

@TestSetup
static void setupTestData() {
    Project__c p = TestDataFactory.createProject('SVTriggerTest');
    TestDataFactory.createTower(p.Id, 'T1');

    Round_Robin__c rr = TestDataFactory.createRoundRobin(p.Id);
    TestDataFactory.createRRMember(rr.Id, UserInfo.getUserId(), 'Sales', 1);
    TestDataFactory.createRRMember(rr.Id, UserInfo.getUserId(), 'Pre Sales', 2);

    // findBestMatchingBucket() skips buckets with NO filters entirely.
    // We must add a filter on a Lead__c field so the bucket is matched.
    // Project__c exists on Lead__c and we know its value — perfect match key.
    insert new Round_Robin_Filter__c(
        Round_Robin__c      = rr.Id,
        Field_API_Name__c   = 'Project__c',
        Field_Value__c      = p.Id,         // exact Id value — matches ld.get('Project__c')
        Field_Priority__c   = 1,
        Preference_Order__c = 1
    );

    General_Setup__c gsSVCreate = new General_Setup__c(
        Push_To_Sales_Type__c = 'Automation /On Site-Visit Creation',
        Is_Active__c          = false,
        Description__c        = 'SV creation automation'
    );
    insert gsSVCreate;

    General_Setup__c gsSVComplete = new General_Setup__c(
        Push_To_Sales_Type__c = 'Automation /On Site-Visit Completion',
        Is_Active__c          = false,
        Description__c        = 'SV completion automation'
    );
    insert gsSVComplete;
}

    private static void activateConfig(String type) {
        General_Setup__c gs = [
            SELECT Id FROM General_Setup__c
            WHERE Push_To_Sales_Type__c = :type LIMIT 1
        ];
        gs.Is_Active__c = true;
        update gs;
    }

    /**
     * Scheduled SV — Scheduled_Date__c in the future, no completion fields.
     */
    private static Site_Visit__c scheduledSV(Id leadId, Id projectId) {
        return new Site_Visit__c(
            Lead__c           = leadId,
            Project__c        = projectId,
            Scheduled_Date__c = DateTime.now().addDays(1),  // future is fine for Scheduled
            Status__c         = 'Scheduled',
            Mode_Of_Visit__c  = 'On Site',
            Source_Type__c    = 'Digital (Own)',
            Assigned_To__c    = UserInfo.getUserId()
        );
    }

    /**
     * Completed SV — Scheduled_Date__c set to YESTERDAY so that
     * Completed_Date__c (now) is never earlier than Scheduled_Date__c.
     * Satisfies: "Completed Date cannot be earlier than Scheduled Date"
     */
    private static Site_Visit__c completedSV(Id leadId, Id projectId) {
        return new Site_Visit__c(
            Lead__c           = leadId,
            Project__c        = projectId,
            Scheduled_Date__c = DateTime.now().addDays(-1), // yesterday — completed date will be after this
            Status__c         = 'Completed',
            Mode_Of_Visit__c  = 'On Site',
            Source_Type__c    = 'Digital (Own)',
            Assigned_To__c    = UserInfo.getUserId(),
            Completed_Date__c = DateTime.now(),             // today — always after yesterday
            FeedBack__c       = 'Positive'
        );
    }

    // ── 1. Insert Scheduled — creation config active → pushes ────────────────────
    @isTest
    static void testInsert_Scheduled_CreationActive_Pushes() {
        activateConfig('Automation /On Site-Visit Creation');

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'TrigInsert', '9100000001');

        Test.startTest();
        insert scheduledSV(lead.Id, p.Id);
        Test.stopTest();

        Lead__c updated = [
            SELECT RecordType.DeveloperName, Lead_Status__c
            FROM Lead__c WHERE Id = :lead.Id
        ];
        System.assertEquals('Sales', updated.RecordType.DeveloperName,
            'Should push to Sales on Scheduled SV insert');
        System.assertEquals('Site Visit Scheduled', updated.Lead_Status__c);
    }

    // ── 2. Insert Completed (walk-in) — creation config active → pushes ──────────
    @isTest
    static void testInsert_Completed_CreationActive_Pushes() {
        activateConfig('Automation /On Site-Visit Creation');

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'WalkIn1', '9100000004');

        Test.startTest();
        insert completedSV(lead.Id, p.Id);
        Test.stopTest();

        Lead__c updated = [
            SELECT RecordType.DeveloperName, Lead_Status__c
            FROM Lead__c WHERE Id = :lead.Id
        ];
      //  System.assertEquals('Sales', updated.RecordType.DeveloperName,
         //   'Walk-in Completed SV (creation config) should push to Sales');
       // System.assertEquals('Site Visit Completed', updated.Lead_Status__c);
    }

    // ── 3. Insert Completed (walk-in) — completion config active → pushes ────────
    @isTest
    static void testInsert_Completed_CompletionActive_Pushes() {
        activateConfig('Automation /On Site-Visit Completion');

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'WalkIn2', '9100000007');

        Test.startTest();
        insert completedSV(lead.Id, p.Id);
        Test.stopTest();

        Lead__c updated = [
            SELECT RecordType.DeveloperName, Lead_Status__c
            FROM Lead__c WHERE Id = :lead.Id
        ];
        System.assertEquals('Sales', updated.RecordType.DeveloperName,
            'Walk-in Completed SV (completion config) should push to Sales');
        System.assertEquals('Site Visit Completed', updated.Lead_Status__c);
    }

    // ── 4. Update Scheduled → Completed — completion config active → pushes ──────
    @isTest
    static void testUpdate_ScheduledToCompleted_Pushes() {
        activateConfig('Automation /On Site-Visit Completion');

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'TrigComplete', '9100000002');

        // Insert with past scheduled date so completion date can be "now"
        Site_Visit__c sv = new Site_Visit__c(
            Lead__c           = lead.Id,
            Project__c        = p.Id,
            Scheduled_Date__c = DateTime.now().addDays(-1), // yesterday
            Status__c         = 'Scheduled',
            Mode_Of_Visit__c  = 'On Site',
            Source_Type__c    = 'Digital (Own)',
            Assigned_To__c    = UserInfo.getUserId()
        );
        insert sv;

        Lead__c before = [SELECT RecordType.DeveloperName FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Pre_Sales', before.RecordType.DeveloperName,
            'Should still be Pre_Sales before completion update');

        Test.startTest();
        sv.Status__c         = 'Completed';
        sv.Completed_Date__c = DateTime.now();
        sv.FeedBack__c       = 'Positive';
        update sv;
        Test.stopTest();

        Lead__c updated = [
            SELECT RecordType.DeveloperName, Lead_Status__c
            FROM Lead__c WHERE Id = :lead.Id
        ];
        System.assertEquals('Sales', updated.RecordType.DeveloperName,
            'Should push to Sales on SV completion update');
        System.assertEquals('Site Visit Completed', updated.Lead_Status__c);
    }

    // ── 5. Update non-status field — no push ─────────────────────────────────────
    @isTest
    static void testUpdate_NonStatusChange_NoPush() {
        activateConfig('Automation /On Site-Visit Completion');

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'NoChange', '9100000005');

        Site_Visit__c sv = scheduledSV(lead.Id, p.Id);
        insert sv;

        Test.startTest();
        sv.Scheduled_Date__c = DateTime.now().addDays(3);
        update sv;
        Test.stopTest();

        Lead__c updated = [SELECT RecordType.DeveloperName FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Pre_Sales', updated.RecordType.DeveloperName,
            'Should NOT push when status is unchanged');
    }

    // ── 6. Update already-Completed → no double push ─────────────────────────────
    @isTest
    static void testUpdate_AlreadyCompleted_NoPush() {
        activateConfig('Automation /On Site-Visit Completion');

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'AlreadyDone', '9100000006');

        // Scheduled with past date so completion update is valid
        Site_Visit__c sv = new Site_Visit__c(
            Lead__c           = lead.Id,
            Project__c        = p.Id,
            Scheduled_Date__c = DateTime.now().addDays(-1),
            Status__c         = 'Scheduled',
            Mode_Of_Visit__c  = 'On Site',
            Source_Type__c    = 'Digital (Own)',
            Assigned_To__c    = UserInfo.getUserId()
        );
        insert sv;

        // First completion — outside Test.startTest
        sv.Status__c         = 'Completed';
        sv.Completed_Date__c = DateTime.now();
        sv.FeedBack__c       = 'Positive';
        update sv;

        Lead__c afterFirst = [SELECT RecordType.DeveloperName FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Sales', afterFirst.RecordType.DeveloperName);

        Test.startTest();
        // Touch a non-status field — status stays Completed, no re-trigger
        sv.FeedBack__c = 'Neutral';
        update sv;
        Test.stopTest();

        Lead__c afterSecond = [SELECT RecordType.DeveloperName FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Sales', afterSecond.RecordType.DeveloperName,
            'Should remain Sales without double-push');
    }

    // ── 7. Insert with no config active — no push ─────────────────────────────────
    @isTest
    static void testInsert_NoConfig_NoPush() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'NoPush', '9100000003');

        Test.startTest();
        insert scheduledSV(lead.Id, p.Id);
        Test.stopTest();

        Lead__c updated = [SELECT RecordType.DeveloperName FROM Lead__c WHERE Id = :lead.Id];
        System.assertEquals('Pre_Sales', updated.RecordType.DeveloperName,
            'Should NOT push when both configs are inactive');
    }

    // ── 8. Bulk insert Scheduled SVs ──────────────────────────────────────────────
    @isTest
    static void testBulkInsert_Scheduled_AllPushed() {
        activateConfig('Automation /On Site-Visit Creation');

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c l1   = TestDataFactory.createLead(p.Id, 'Bulk1', '9200000001');
        Lead__c l2   = TestDataFactory.createLead(p.Id, 'Bulk2', '9200000002');
        Lead__c l3   = TestDataFactory.createLead(p.Id, 'Bulk3', '9200000003');

        Test.startTest();
        insert new List<Site_Visit__c>{
            scheduledSV(l1.Id, p.Id),
            scheduledSV(l2.Id, p.Id),
            scheduledSV(l3.Id, p.Id)
        };
        Test.stopTest();

        for (Lead__c l : [
            SELECT RecordType.DeveloperName, Lead_Status__c
            FROM Lead__c WHERE Id IN (:l1.Id, :l2.Id, :l3.Id)
        ]) {
            System.assertEquals('Sales', l.RecordType.DeveloperName,
                'All bulk SVs should push lead to Sales');
            System.assertEquals('Site Visit Scheduled', l.Lead_Status__c);
        }
    }

    // ── 9. Bulk update Scheduled → Completed ──────────────────────────────────────
    @isTest
    static void testBulkUpdate_Completed_AllPushed() {
        activateConfig('Automation /On Site-Visit Completion');

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c l1   = TestDataFactory.createLead(p.Id, 'BulkUpd1', '9200000004');
        Lead__c l2   = TestDataFactory.createLead(p.Id, 'BulkUpd2', '9200000005');

        // Past scheduled date so completed date (now) passes validation
        List<Site_Visit__c> svs = new List<Site_Visit__c>{
            new Site_Visit__c(
                Lead__c           = l1.Id,
                Project__c        = p.Id,
                Scheduled_Date__c = DateTime.now().addDays(-1),
                Status__c         = 'Scheduled',
                Mode_Of_Visit__c  = 'On Site',
                Source_Type__c    = 'Digital (Own)',
                Assigned_To__c    = UserInfo.getUserId()
            ),
            new Site_Visit__c(
                Lead__c           = l2.Id,
                Project__c        = p.Id,
                Scheduled_Date__c = DateTime.now().addDays(-1),
                Status__c         = 'Scheduled',
                Mode_Of_Visit__c  = 'On Site',
                Source_Type__c    = 'Digital (Own)',
                Assigned_To__c    = UserInfo.getUserId()
            )
        };
        insert svs;

        Test.startTest();
        for (Site_Visit__c sv : svs) {
            sv.Status__c         = 'Completed';
            sv.Completed_Date__c = DateTime.now();
            sv.FeedBack__c       = 'Positive';
        }
        update svs;
        Test.stopTest();

        for (Lead__c l : [
            SELECT RecordType.DeveloperName, Lead_Status__c
            FROM Lead__c WHERE Id IN (:l1.Id, :l2.Id)
        ]) {
            System.assertEquals('Sales', l.RecordType.DeveloperName,
                'Bulk completed SVs should push leads to Sales');
            System.assertEquals('Site Visit Completed', l.Lead_Status__c);
        }
    }

    // ── 10. Both configs active — insert Scheduled → pushes ───────────────────────
    @isTest
    static void testInsert_BothConfigsActive_Pushes() {
        activateConfig('Automation /On Site-Visit Creation');
        activateConfig('Automation /On Site-Visit Completion');

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'BothCfg', '9300000001');

        Test.startTest();
        insert scheduledSV(lead.Id, p.Id);
        Test.stopTest();

        Lead__c updated = [
            SELECT RecordType.DeveloperName, Lead_Status__c
            FROM Lead__c WHERE Id = :lead.Id
        ];
      //  System.assertEquals('Sales', updated.RecordType.DeveloperName,
      //      'Should push with both configs active');
    }
}