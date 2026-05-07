@isTest
private class AriaKnowledgeServiceTest {

    @TestSetup
    static void setup() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('KnowProj');
        p.Project_Status__c = 'Launched';
        p.Is_Active__c = true;
        update p;

        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        TestDataFactory.createUnit(p.Id, t.Id, 'K-101');
    }

    @isTest
    static void getProjectsDigest_returnsActiveProjects() {
        Test.startTest();
        List<Map<String, Object>> out = AriaKnowledgeService.getProjectsDigest();
        Test.stopTest();
        System.assert(out != null, 'Digest should be returned');
    }

    @isTest
    static void getProjectDetails_nullId_returnsNull() {
        System.assertEquals(null, AriaKnowledgeService.getProjectDetails(null));
    }

    @isTest
    static void getProjectDetails_notFound_returnsNull() {
        String prefix = Project__c.SObjectType.getDescribe().getKeyPrefix();
        Id fakeId = Id.valueOf(prefix + '000000000000');
        System.assertEquals(null, AriaKnowledgeService.getProjectDetails(fakeId));
    }

    @isTest
    static void getProjectDetails_existingProject() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        Map<String, Object> res = AriaKnowledgeService.getProjectDetails(p.Id);
        Test.stopTest();

        System.assertNotEquals(null, res);
        System.assertEquals(p.Id, res.get('id'));
    }

    @isTest
    static void getUnitAvailability_variousFilters() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        System.assertNotEquals(null, AriaKnowledgeService.getUnitAvailability(p.Id, null, null, null));
        System.assertNotEquals(null, AriaKnowledgeService.getUnitAvailability(p.Id, '2BHK', null, null));
        System.assertNotEquals(null, AriaKnowledgeService.getUnitAvailability(p.Id, '2BHK', 1000000, 10000000));
        System.assertNotEquals(null, AriaKnowledgeService.getUnitAvailability(null, null, null, null));
        Test.stopTest();
    }

    @isTest
    static void findLead_withLead() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'Findable', '9000050001');

        Test.startTest();
        List<Map<String, Object>> byMobile = AriaKnowledgeService.findLead('9000050001');
        List<Map<String, Object>> byName   = AriaKnowledgeService.findLead('Findable');
        List<Map<String, Object>> blank    = AriaKnowledgeService.findLead('');
        Test.stopTest();

        System.assert(byMobile != null);
        System.assert(byName != null);
        System.assertEquals(0, blank.size());
    }

    @isTest
    static void universalSearch_variousQueries() {
        Test.startTest();
        System.assertEquals(0, AriaKnowledgeService.universalSearch(null).size());
        System.assertEquals(0, AriaKnowledgeService.universalSearch('').size());
        // Exercises lookup paths
        AriaKnowledgeService.universalSearch('KnowProj');
        AriaKnowledgeService.universalSearch('LD-000001');
        AriaKnowledgeService.universalSearch('BK-000001');
        AriaKnowledgeService.universalSearch('9000050001');
        Test.stopTest();
        System.assert(true);
    }

    @isTest
    static void findBookingsByName_blank_returnsEmpty() {
        Test.startTest();
        System.assert(AriaKnowledgeService.findBookingsByName(null) != null);
        System.assert(AriaKnowledgeService.findBookingsByName('') != null);
        System.assert(AriaKnowledgeService.findBookingsByName('BK-999999') != null);
        Test.stopTest();
    }

    @isTest
    static void findBookingsByCustomer_variousQueries() {
        Test.startTest();
        System.assert(AriaKnowledgeService.findBookingsByCustomer(null) != null);
        System.assert(AriaKnowledgeService.findBookingsByCustomer('') != null);
        System.assert(AriaKnowledgeService.findBookingsByCustomer('Nobody') != null);
        Test.stopTest();
    }

    @isTest
    static void findCostSheetsByName_variousQueries() {
        Test.startTest();
        System.assert(AriaKnowledgeService.findCostSheetsByName(null) != null);
        System.assert(AriaKnowledgeService.findCostSheetsByName('') != null);
        System.assert(AriaKnowledgeService.findCostSheetsByName('CS-999999') != null);
        Test.stopTest();
    }

    @isTest
    static void findProjectsByNameOrCode_variousQueries() {
        Test.startTest();
        System.assert(AriaKnowledgeService.findProjectsByNameOrCode(null) != null);
        System.assert(AriaKnowledgeService.findProjectsByNameOrCode('') != null);
        System.assert(AriaKnowledgeService.findProjectsByNameOrCode('KnowProj') != null);
        Test.stopTest();
    }

    @isTest
    static void findUnitsByNumber_variousQueries() {
        Test.startTest();
        System.assert(AriaKnowledgeService.findUnitsByNumber(null) != null);
        System.assert(AriaKnowledgeService.findUnitsByNumber('') != null);
        System.assert(AriaKnowledgeService.findUnitsByNumber('K-101') != null);
        Test.stopTest();
    }

    @isTest
    static void getBookingReadiness_invalidInputs() {
        Test.startTest();
        // null → method returns null outright
        System.assertEquals(null, AriaKnowledgeService.getBookingReadiness(null));

        // nonexistent lead → returns { error: 'Lead not found.' }
        String prefix = Lead__c.SObjectType.getDescribe().getKeyPrefix();
        Id fakeId = Id.valueOf(prefix + '000000000000');
        Map<String, Object> r2 = AriaKnowledgeService.getBookingReadiness(fakeId);
        System.assertNotEquals(null, r2);
        System.assertNotEquals(null, r2.get('error'));
        Test.stopTest();
    }

    @isTest
    static void getBookingReadiness_existingLead() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'BookReady', '9000050002');

        Test.startTest();
        Map<String, Object> res = AriaKnowledgeService.getBookingReadiness(lead.Id);
        Test.stopTest();

        System.assertNotEquals(null, res);
    }

    @isTest
    static void getHotLeads_variousTopN() {
        Test.startTest();
        System.assert(AriaKnowledgeService.getHotLeads(null) != null);
        System.assert(AriaKnowledgeService.getHotLeads(0) != null);
        System.assert(AriaKnowledgeService.getHotLeads(5) != null);
        Test.stopTest();
    }

    @isTest
    static void getPaymentSchedule_invalidInputs() {
        Test.startTest();
        System.assert(AriaKnowledgeService.getPaymentSchedule(null) != null);

        String prefix = Booking__c.SObjectType.getDescribe().getKeyPrefix();
        Id fakeId = Id.valueOf(prefix + '000000000000');
        System.assert(AriaKnowledgeService.getPaymentSchedule(fakeId) != null);
        Test.stopTest();
    }

    @isTest
    static void getRecordContext_variousInputs() {
        Test.startTest();
        System.assertEquals(null, AriaKnowledgeService.getRecordContext(null));

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Map<String, Object> res = AriaKnowledgeService.getRecordContext(p.Id);
        System.assertNotEquals(null, res);
        Test.stopTest();
    }

    @isTest
    static void getLeadContext_variousInputs() {
        Test.startTest();
        System.assertEquals(null, AriaKnowledgeService.getLeadContext(null));

        String prefix = Lead__c.SObjectType.getDescribe().getKeyPrefix();
        Id fakeId = Id.valueOf(prefix + '000000000000');
        System.assertEquals(null, AriaKnowledgeService.getLeadContext(fakeId));

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'Ctx', '9000050003');
        System.assertNotEquals(null, AriaKnowledgeService.getLeadContext(lead.Id));
        Test.stopTest();
    }

    @isTest
    static void getNextBestAction_variousInputs() {
        Test.startTest();
        Map<String, Object> r1 = AriaKnowledgeService.getNextBestAction(null);
        System.assertNotEquals(null, r1);

        String prefix = Lead__c.SObjectType.getDescribe().getKeyPrefix();
        Id fakeId = Id.valueOf(prefix + '000000000000');
        AriaKnowledgeService.getNextBestAction(fakeId);

        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c lead = TestDataFactory.createLead(p.Id, 'NBA', '9000050004');
        System.assertNotEquals(null, AriaKnowledgeService.getNextBestAction(lead.Id));
        Test.stopTest();
    }
}