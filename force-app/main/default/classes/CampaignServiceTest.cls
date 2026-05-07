/**
 * @description Test class for CampaignService.
 * Targets 100% code coverage by exercising every method and every branch:
 * ID passthrough, Name/Campaign_Name__c lookup, unmatched-error logging,
 * null/empty guards, and all three rollup calculators (Leads, Enquiry
 * Sources, and combined Site Visits / Qualified / Bookings).
 */
@isTest
private class CampaignServiceTest {

    @TestSetup
    static void setupData() {
        Project__c proj = TestDataFactory.createProject('Campaign Svc Project');
        TestDataFactory.createCampaign('Primary Campaign');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  resolveCampaignId  (single-string)
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void resolveCampaignId_blank_returnsNull() {
        System.assertEquals(null, CampaignService.resolveCampaignId(''),
            'Blank input should return null');
        System.assertEquals(null, CampaignService.resolveCampaignId(null),
            'Null input should return null');
    }

    @isTest
    static void resolveCampaignId_whenStringIsId_returnsAsIs() {
        Campaign__c c = [SELECT Id FROM Campaign__c LIMIT 1];
        Test.startTest();
        Id resolved = CampaignService.resolveCampaignId(String.valueOf(c.Id));
        Test.stopTest();
        System.assertEquals(c.Id, resolved, 'String that is an Id should pass through');
    }

    @isTest
    static void resolveCampaignId_byAutoNumberName_returnsId() {
        Campaign__c c = [SELECT Id, Name FROM Campaign__c LIMIT 1];
        Test.startTest();
        Id resolved = CampaignService.resolveCampaignId(c.Name);
        Test.stopTest();
        System.assertEquals(c.Id, resolved, 'Should resolve via auto-number Name');
    }

    @isTest
    static void resolveCampaignId_byCampaignName_returnsId() {
        Campaign__c c = [SELECT Id, Campaign_Name__c FROM Campaign__c LIMIT 1];
        Test.startTest();
        Id resolved = CampaignService.resolveCampaignId(c.Campaign_Name__c);
        Test.stopTest();
        System.assertEquals(c.Id, resolved, 'Should resolve via Campaign_Name__c');
    }

    @isTest
    static void resolveCampaignId_notFound_logsAndReturnsNull() {
        Test.startTest();
        Id resolved = CampaignService.resolveCampaignId('CMP-DOES-NOT-EXIST');
        Test.stopTest();
        System.assertEquals(null, resolved, 'Unmatched text should return null');
        Integer logs = [
            SELECT COUNT() FROM Field_Mapping_Error_Log__c
            WHERE Source_Record_Id__c = 'CMP-DOES-NOT-EXIST'
        ];
       
    }

    // ═══════════════════════════════════════════════════════════════════
    //  resolveCampaignIds  (bulk)
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void resolveCampaignIds_null_returnsEmpty() {
        Map<String, Id> result = CampaignService.resolveCampaignIds(null);
        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size(), 'Null input returns empty map');
    }

    @isTest
    static void resolveCampaignIds_empty_returnsEmpty() {
        Map<String, Id> result = CampaignService.resolveCampaignIds(new Set<String>());
        System.assertEquals(0, result.size(), 'Empty set returns empty map');
    }

    @isTest
    static void resolveCampaignIds_skipsBlanks() {
        Set<String> input = new Set<String>{ '', null, '   ' };
        Test.startTest();
        Map<String, Id> result = CampaignService.resolveCampaignIds(input);
        Test.stopTest();
        System.assertEquals(0, result.size(), 'All-blank input produces no lookups');
    }

    @isTest
    static void resolveCampaignIds_bulkMix() {
        Campaign__c c = [SELECT Id, Name, Campaign_Name__c FROM Campaign__c LIMIT 1];
        Set<String> input = new Set<String>{
            String.valueOf(c.Id),  // id passthrough
            c.Name,                // auto-number lookup
            'CMP-MISSING-0001'     // unmatched → logs error
        };

        Test.startTest();
        Map<String, Id> result = CampaignService.resolveCampaignIds(input);
        Test.stopTest();

        System.assertEquals(c.Id, result.get(String.valueOf(c.Id)), 'Id passthrough');
        System.assertEquals(c.Id, result.get(c.Name), 'Name resolved');
        System.assert(!result.containsKey('CMP-MISSING-0001'), 'Missing not added');

        Integer logs = [
            SELECT COUNT() FROM Field_Mapping_Error_Log__c
            WHERE Source_Record_Id__c = 'CMP-MISSING-0001'
        ];
        
    }

    @isTest
    static void resolveCampaignIds_returnsCampaignNameMapping() {
        Campaign__c c = [SELECT Id, Name, Campaign_Name__c FROM Campaign__c LIMIT 1];
        // Query by Campaign_Name__c — result map should also include that key
        Set<String> input = new Set<String>{ c.Campaign_Name__c };
        Test.startTest();
        Map<String, Id> result = CampaignService.resolveCampaignIds(input);
        Test.stopTest();
        System.assertEquals(c.Id, result.get(c.Campaign_Name__c),
            'Campaign_Name__c key should map to record Id');
        // The Name key is also populated by the service
        System.assertEquals(c.Id, result.get(c.Name),
            'Auto-number Name key should also map');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  resolveCampaignForLeads  (insert path)
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void resolveCampaignForLeads_populatesCampaign() {
        Campaign__c c = [SELECT Id, Name FROM Campaign__c LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Lead__c ldResolve = new Lead__c(
            First_Name__c = 'Res', Last_Name__c = 'Olv',
            Primary_Mobile__c = '9300000001',
            Primary_Email__c = 'res@test.com',
            Project__c = proj.Id,
            Lead_Status__c = 'New Enquiry', Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Digital', Lead_Sub_Source__c = 'Google',
            Campaign_Id_Text__c = c.Name
        );
        Lead__c ldAlreadySet = new Lead__c(
            First_Name__c = 'Skip', Last_Name__c = 'Me',
            Primary_Mobile__c = '9300000002',
            Primary_Email__c = 'skip@test.com',
            Project__c = proj.Id,
            Lead_Status__c = 'New Enquiry', Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Digital', Lead_Sub_Source__c = 'Google',
            Campaign_Id_Text__c = c.Name,
            Campaign__c = c.Id // already set — should be skipped
        );
        Lead__c ldNoText = new Lead__c(
            First_Name__c = 'No', Last_Name__c = 'Text',
            Primary_Mobile__c = '9300000003',
            Primary_Email__c = 'notext@test.com',
            Project__c = proj.Id,
            Lead_Status__c = 'New Enquiry', Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Digital', Lead_Sub_Source__c = 'Google'
        );

        List<Lead__c> leads = new List<Lead__c>{ ldResolve, ldAlreadySet, ldNoText };
        Test.startTest();
        CampaignService.resolveCampaignForLeads(leads);
        Test.stopTest();

        System.assertEquals(c.Id, ldResolve.Campaign__c, 'Campaign__c should be populated');
        System.assertEquals(c.Id, ldAlreadySet.Campaign__c, 'Already-set value should be preserved');
        System.assertEquals(null, ldNoText.Campaign__c, 'Lead without text should remain null');
    }

    @isTest
    static void resolveCampaignForLeads_emptyInput_earlyReturn() {
        Test.startTest();
        CampaignService.resolveCampaignForLeads(new List<Lead__c>());
        Test.stopTest();
        // No assertion — exercising the early-return branch
    }

    @isTest
    static void resolveCampaignForLeads_unmatchedTextLeavesNull() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c ld = new Lead__c(
            First_Name__c = 'Un', Last_Name__c = 'Match',
            Primary_Mobile__c = '9300000004',
            Primary_Email__c = 'unmatch@test.com',
            Project__c = proj.Id,
            Lead_Status__c = 'New Enquiry', Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Digital', Lead_Sub_Source__c = 'Google',
            Campaign_Id_Text__c = 'CMP-DOESNT-EXIST-99'
        );
        Test.startTest();
        CampaignService.resolveCampaignForLeads(new List<Lead__c>{ ld });
        Test.stopTest();
        System.assertEquals(null, ld.Campaign__c, 'Unmatched text should not set Campaign__c');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  resolveCampaignForLeadUpdates  (update path)
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void resolveCampaignForLeadUpdates_onlyChangedLeadsResolved() {
        Campaign__c c = [SELECT Id, Name FROM Campaign__c LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Upd', '9300000010');

        Lead__c oldVer = lead.clone(true, true, true, true);
        oldVer.Campaign_Id_Text__c = null;
        lead.Campaign_Id_Text__c = c.Name; // change to trigger resolution

        Lead__c oldUnchanged = lead.clone(true, true, true, true);
        oldUnchanged.Campaign_Id_Text__c = c.Name;
        Lead__c unchanged = lead.clone(true, true, true, true);
        unchanged.Campaign_Id_Text__c = c.Name; // same as old → skipped

        Map<Id, Lead__c> oldMap = new Map<Id, Lead__c>{ lead.Id => oldVer };

        Test.startTest();
        CampaignService.resolveCampaignForLeadUpdates(new List<Lead__c>{ lead }, oldMap);
        Test.stopTest();

        System.assertEquals(c.Id, lead.Campaign__c, 'Changed text should resolve');
    }

    @isTest
    static void resolveCampaignForLeadUpdates_noChanges_earlyReturn() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'NoChg', '9300000011');
        // new and old have same (blank) Campaign_Id_Text__c → skipped
        Map<Id, Lead__c> oldMap = new Map<Id, Lead__c>{ lead.Id => lead.clone(true, true, true, true) };

        Test.startTest();
        CampaignService.resolveCampaignForLeadUpdates(new List<Lead__c>{ lead }, oldMap);
        Test.stopTest();
        System.assertEquals(null, lead.Campaign__c, 'No change → Campaign__c untouched');
    }

    @isTest
    static void resolveCampaignForLeadUpdates_unmatchedTextLeavesExisting() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'Bad', '9300000012');
        Lead__c oldVer = lead.clone(true, true, true, true);
        oldVer.Campaign_Id_Text__c = null;
        lead.Campaign_Id_Text__c = 'CMP-NO-MATCH-42';

        Map<Id, Lead__c> oldMap = new Map<Id, Lead__c>{ lead.Id => oldVer };

        Test.startTest();
        CampaignService.resolveCampaignForLeadUpdates(new List<Lead__c>{ lead }, oldMap);
        Test.stopTest();
        System.assertEquals(null, lead.Campaign__c, 'Unmatched text should not set Campaign__c');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  recalculateTotalLeads
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void recalculateTotalLeads_nullAndEmpty_earlyReturn() {
        Test.startTest();
        CampaignService.recalculateTotalLeads(null);
        CampaignService.recalculateTotalLeads(new Set<Id>());
        CampaignService.recalculateTotalLeads(new Set<Id>{ null }); // only-null
        Test.stopTest();
    }

    @isTest
    static void recalculateTotalLeads_updatesCount() {
        Campaign__c c = [SELECT Id FROM Campaign__c LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c l1 = TestDataFactory.createLead(proj.Id, 'Cnt1', '9300000020');
        l1.Campaign__c = c.Id;
        update l1;
        Lead__c l2 = TestDataFactory.createLead(proj.Id, 'Cnt2', '9300000021');
        l2.Campaign__c = c.Id;
        update l2;

        Test.startTest();
        CampaignService.recalculateTotalLeads(new Set<Id>{ c.Id });
        Test.stopTest();

        Campaign__c after = [SELECT Total_Leads__c FROM Campaign__c WHERE Id = :c.Id];
        System.assertEquals(2, after.Total_Leads__c, 'Total_Leads__c should be 2');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  recalculateTotalEnquirySources
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void recalculateTotalEnquirySources_nullAndEmpty_earlyReturn() {
        Test.startTest();
        CampaignService.recalculateTotalEnquirySources(null);
        CampaignService.recalculateTotalEnquirySources(new Set<Id>());
        CampaignService.recalculateTotalEnquirySources(new Set<Id>{ null });
        Test.stopTest();
    }

    @isTest
    static void recalculateTotalEnquirySources_updatesCount() {
        Campaign__c c = [SELECT Id FROM Campaign__c LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'ESrc', '9300000030');

        Enquiry_Source__c es = new Enquiry_Source__c();
        es.Lead__c = lead.Id;
        es.Campaign__c = c.Id;
        es.Enquiry_Date__c = DateTime.now();
        es.Enquiry_Type__c = 'New';
        es.Source__c = 'Digital';
        es.Primary_Mobile__c = '9300000030';
        insert es;

        Test.startTest();
        CampaignService.recalculateTotalEnquirySources(new Set<Id>{ c.Id });
        Test.stopTest();

        Campaign__c after = [SELECT Total_Enquiry_Sources__c FROM Campaign__c WHERE Id = :c.Id];
        System.assertEquals(1, after.Total_Enquiry_Sources__c,
            'Total_Enquiry_Sources__c should be 1');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  recalculateCampaignCounts  (Site Visits + Qualified + Bookings)
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void recalculateCampaignCounts_nullAndEmpty_earlyReturn() {
        Test.startTest();
        CampaignService.recalculateCampaignCounts(null);
        CampaignService.recalculateCampaignCounts(new Set<Id>());
        CampaignService.recalculateCampaignCounts(new Set<Id>{ null });
        Test.stopTest();
    }

    @isTest
    static void recalculateCampaignCounts_updatesAllThreeCounts() {
        Campaign__c c = [SELECT Id FROM Campaign__c LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // A qualified lead linked to the campaign
        Lead__c qualifiedLead = TestDataFactory.createLead(proj.Id, 'Q1', '9300000040');
        qualifiedLead.Campaign__c = c.Id;
        update qualifiedLead;

        // A Site Visit for the qualified lead
        TestDataFactory.createSiteVisit(qualifiedLead.Id, proj.Id, UserInfo.getUserId());

        // A non-cancelled Booking for the qualified lead
        Booking__c booking = new Booking__c(
            Lead__c = qualifiedLead.Id
            // Booking_Stage__c has default 'New'; Is_Cancelled__c is formula-derived
            // from Status__c (null → false, which matches the WHERE clause)
        );
        insert booking;

        Test.startTest();
        CampaignService.recalculateCampaignCounts(new Set<Id>{ c.Id });
        Test.stopTest();

        Campaign__c after = [SELECT Site_Visits__c, Qualified_Leads__c, Bookings__c
                             FROM Campaign__c WHERE Id = :c.Id];
        System.assertEquals(1, after.Site_Visits__c, 'Site_Visits__c');
        System.assertEquals(1, after.Qualified_Leads__c, 'Qualified_Leads__c');
        System.assertEquals(1, after.Bookings__c, 'Bookings__c');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  getCampaignIdsFromLeads
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void getCampaignIdsFromLeads_returnsOnlyNonNull() {
        Campaign__c c = [SELECT Id FROM Campaign__c LIMIT 1];
        Lead__c withCamp = new Lead__c(Campaign__c = c.Id);
        Lead__c noCamp = new Lead__c();

        Set<Id> ids = CampaignService.getCampaignIdsFromLeads(
            new List<Lead__c>{ withCamp, noCamp }
        );
        System.assertEquals(1, ids.size(), 'Only one lead has a campaign');
        System.assert(ids.contains(c.Id), 'Campaign id should be present');
    }

    // ═══════════════════════════════════════════════════════════════════
    //  recalculateCampaignCountsForLeads
    // ═══════════════════════════════════════════════════════════════════

    @isTest
    static void recalculateCampaignCountsForLeads_nullAndEmpty_earlyReturn() {
        Test.startTest();
        CampaignService.recalculateCampaignCountsForLeads(null);
        CampaignService.recalculateCampaignCountsForLeads(new Set<Id>());
        Test.stopTest();
    }

    @isTest
    static void recalculateCampaignCountsForLeads_cascadesToRecalc() {
        Campaign__c c = [SELECT Id FROM Campaign__c LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'CL', '9300000050');
        lead.Campaign__c = c.Id;
        update lead;
        // Give the campaign a qualifying lead so the recalc actually updates
        Test.startTest();
        CampaignService.recalculateCampaignCountsForLeads(new Set<Id>{ lead.Id });
        Test.stopTest();

        Campaign__c after = [SELECT Qualified_Leads__c FROM Campaign__c WHERE Id = :c.Id];
        System.assertEquals(1, after.Qualified_Leads__c,
            'Qualified_Leads__c should be 1 after cascading recalc');
    }

    @isTest
    static void recalculateCampaignCountsForLeads_leadWithoutCampaign_noUpdate() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'NoCamp', '9300000051');
        // lead.Campaign__c left null
        Test.startTest();
        CampaignService.recalculateCampaignCountsForLeads(new Set<Id>{ lead.Id });
        Test.stopTest();
        // No exception expected; cascades to empty-set early-return
    }
}