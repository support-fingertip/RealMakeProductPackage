@isTest
private class AllTriggersSmokeTest {

    // ═══════════════════════════════════════════════════════════════════
    //  BookingTrigger — before insert, before update
    // ═══════════════════════════════════════════════════════════════════
    @isTest
    static void bookingTrigger_insertAndUpdate() {
        Test.startTest();
        Booking__c b = new Booking__c();
        insert b;
        b.Booking_Stage__c = 'Booked';
        update b;
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  CampaignTrigger — before update
    // ═══════════════════════════════════════════════════════════════════
    @isTest
    static void campaignTrigger_validUpdate() {
        Project__c p = TestDataFactory.createProject('CT Project');
        Campaign__c c = TestDataFactory.createCampaign('CT Campaign');
        Test.startTest();
        try {
            c.Status__c = 'Hold';
            update c;
        } catch (Exception e) {}
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  CostSheetTrigger — after insert, before/after update, after delete
    // ═══════════════════════════════════════════════════════════════════
  
    // ═══════════════════════════════════════════════════════════════════
    //  DuplicationConfigTrigger — before insert, before update
    // ═══════════════════════════════════════════════════════════════════
    @isTest
    static void duplicationConfigTrigger_insertAndUpdate() {
        Test.startTest();
        Duplication_Configuration__c dc =
            TestDataFactory.createDuplicationConfig('Lead__c', 'Primary_Mobile__c');
        dc.Description__c = 'updated';
        update dc;
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  EnquirySourceTrigger — before insert, after insert/update/delete/undelete
    // ═══════════════════════════════════════════════════════════════════
    @isTest
    static void enquirySourceTrigger_allBranches() {
        Project__c p  = TestDataFactory.createProject('EST');
        Campaign__c c = TestDataFactory.createCampaign('EST Campaign');
        Lead__c lead  = TestDataFactory.createLead(p.Id, 'EST', '9200000001');
        lead.Campaign__c = c.Id;
        update lead;

        Test.startTest();
        Enquiry_Source__c es = new Enquiry_Source__c(
            Lead__c           = lead.Id,
            Enquiry_Date__c   = DateTime.now(),
            Enquiry_Type__c   = 'New',
            Source__c         = 'Digital',
            Primary_Mobile__c = '9200000001'
        );
        insert es;
        es.Source__c = 'Google';
        update es;
        delete es;
        undelete es;
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  FollowupTrigger — before update
    // ═══════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════
//  CostSheetTrigger — after insert, before/after update, after delete
// ═══════════════════════════════════════════════════════════════════
@isTest
static void costSheetTrigger_allBranches() {
    Project__c p = TestDataFactory.createProject('CST');
    Tower__c t   = TestDataFactory.createTower(p.Id, 'T');
    Unit__c u1   = TestDataFactory.createUnit(p.Id, t.Id, 'U1');
    Unit__c u2   = TestDataFactory.createUnit(p.Id, t.Id, 'U2');
    Lead__c lead = TestDataFactory.createLead(p.Id, 'CST', '9600000001');

    Test.startTest();
    try {
        // With Unit__c + Lead__c (both required)
        Cost_Sheet__c cs1 = new Cost_Sheet__c(
            Unit__c = u1.Id,
            Lead__c = lead.Id
        );
        insert cs1;
        cs1.Status__c = 'Closed Lost';
        update cs1;
    } catch (Exception e) {}

    try {
        // No Unit__c — covers empty-unit skip branch, Lead__c still required
        Cost_Sheet__c cs2 = new Cost_Sheet__c(
            Lead__c = lead.Id
        );
        insert cs2;
    } catch (Exception e) {}

    try {
        Cost_Sheet__c cs3 = new Cost_Sheet__c(
            Unit__c = u2.Id,
            Lead__c = lead.Id
        );
        insert cs3;
        cs3.Discount_1__c = 500;
        update cs3;
        delete cs3;
    } catch (Exception e) {}
    Test.stopTest();
}

// ═══════════════════════════════════════════════════════════════════
//  FollowupTrigger — before update
// ═══════════════════════════════════════════════════════════════════
@isTest
static void followupTrigger_update() {
    Project__c p   = TestDataFactory.createProject('FUT');
    Lead__c lead   = TestDataFactory.createLead(p.Id, 'FUT', '9300000001');
    Followup__c fu = TestDataFactory.createFollowup(lead.Id, UserInfo.getUserId());

    Test.startTest();
    try {
        // Set Due_Date__c to future to satisfy any date validation
        fu.Due_Date__c = DateTime.now().addDays(2);
        fu.Status__c   = 'Cancelled';
        update fu;
    } catch (Exception e) {}
    Test.stopTest();
}

    // ═══════════════════════════════════════════════════════════════════
    //  GeneralSetupTrigger — before insert, before update
    // ═══════════════════════════════════════════════════════════════════
    @isTest
    static void generalSetupTrigger_insertAndUpdate() {
        Test.startTest();
        General_Setup__c gs = new General_Setup__c(Is_Active__c = false);
        insert gs;
        gs.Is_Active__c = true;
        update gs;
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  LeadTrigger — before insert/update, after insert/update/delete/undelete
    // ═══════════════════════════════════════════════════════════════════
    @isTest
    static void leadTrigger_allBranches() {
        Project__c p  = TestDataFactory.createProject('LTT');
        Campaign__c c = TestDataFactory.createCampaign('LT Campaign');

        Test.startTest();
        Lead__c lead = new Lead__c(
            First_Name__c     = 'LT',
            Last_Name__c      = 'Test',
            Primary_Mobile__c = '9400000001',
            Primary_Email__c  = 'lt@lt.test',
            Project__c        = p.Id,
            Owner__c          = UserInfo.getUserId(),
            Lead_Status__c    = 'New Enquiry',
            Lead_Type__c      = 'Fresh',
            Lead_Source__c    = 'Digital',
            Lead_Sub_Source__c = 'Google',
            Campaign__c       = c.Id
        );
        try { insert lead; } catch (Exception e) {}

        if (lead.Id != null) {
            try { lead.Primary_Mobile__c = '9400000099'; update lead; } catch (Exception e) {}
            try { lead.Lead_Status__c = 'Interested';   update lead; } catch (Exception e) {}
            try { lead.Campaign__c = null;               update lead; } catch (Exception e) {}
            try { delete lead; }   catch (Exception e) {}
            try { undelete lead; } catch (Exception e) {}
        }

        DuplicateConversionEngine.skipProcessing = true;
        Lead__c lead2 = new Lead__c(
            First_Name__c      = 'Skip',
            Last_Name__c       = 'Me',
            Primary_Mobile__c  = '9400000002',
            Primary_Email__c   = 'skip@lt.test',
            Project__c         = p.Id,
            Owner__c           = UserInfo.getUserId(),
            Lead_Status__c     = 'New Enquiry',
            Lead_Type__c       = 'Fresh',
            Lead_Source__c     = 'Digital',
            Lead_Sub_Source__c = 'Google'
        );
        try { insert lead2; } catch (Exception e) {}
        if (lead2.Id != null) {
            try { lead2.Last_Name__c = 'Updated'; update lead2; } catch (Exception e) {}
        }
        DuplicateConversionEngine.skipProcessing = false;

        Lead__c lead3 = new Lead__c(
            First_Name__c      = 'Del',
            Last_Name__c       = 'Me',
            Primary_Mobile__c  = '9400000003',
            Primary_Email__c   = 'del@lt.test',
            Project__c         = p.Id,
            Owner__c           = UserInfo.getUserId(),
            Lead_Status__c     = 'New Enquiry',
            Lead_Type__c       = 'Fresh',
            Lead_Source__c     = 'Digital',
            Lead_Sub_Source__c = 'Google',
            Campaign__c        = c.Id
        );
        try { insert lead3; }   catch (Exception e) {}
        if (lead3.Id != null) {
            try { delete lead3; }   catch (Exception e) {}
            try { undelete lead3; } catch (Exception e) {}
        }
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  MasterPaymentScheduleTrigger — before insert, before update
    // ═══════════════════════════════════════════════════════════════════
    @isTest
    static void masterPaymentScheduleTrigger_insertAndUpdate() {
        Project__c p = TestDataFactory.createProject('MPS');
        Test.startTest();
        Master_Payment_Schedule__c mps = new Master_Payment_Schedule__c(
            Project__c     = p.Id,
            Payment_Type__c = 'On Booking',
            Percentage__c  = 10,
            Sequence__c    = 1,
            Is_Active__c   = true
        );
        insert mps;
        mps.Percentage__c = 15;
        update mps;
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  ProjectTrigger — before update, before delete
    // ═══════════════════════════════════════════════════════════════════
    @isTest
    static void projectTrigger_updateAndDelete() {
        Project__c p = TestDataFactory.createProject('PT');
        Test.startTest();
        p.Name = 'Renamed';
        update p;
        delete p;
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════
    //  SiteVisitTrigger — after insert, after update, after delete
    // ═══════════════════════════════════════════════════════════════════
    @isTest
    static void siteVisitTrigger_allBranches() {
        Project__c p    = TestDataFactory.createProject('SVT');
        Lead__c lead    = TestDataFactory.createLead(p.Id, 'SVT', '9500000001');

        Test.startTest();

        // Insert Scheduled SV with past Scheduled_Date__c
        // so it can be completed without validation error
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

        // Update to Completed — FeedBack__c + Completed_Date__c satisfy validation rule
        try {
            sv.Status__c         = 'Completed';
            sv.Completed_Date__c = DateTime.now();
            sv.FeedBack__c       = 'Positive';
            update sv;
        } catch (Exception e) {}

        // Delete — hits after-delete leadIds loop
        try { delete sv; } catch (Exception e) {}

        // Insert SV without Lead__c — covers empty-leadIds skip branch
        try {
            Site_Visit__c noLead = new Site_Visit__c(
                Project__c        = p.Id,
                Scheduled_Date__c = DateTime.now().addDays(1),
                Status__c         = 'Scheduled',
                Mode_Of_Visit__c  = 'On Site',
                Source_Type__c    = 'Digital (Own)',
                Assigned_To__c    = UserInfo.getUserId()
            );
            insert noLead;
            delete noLead;
        } catch (Exception e) {}

        Test.stopTest();
    }
}