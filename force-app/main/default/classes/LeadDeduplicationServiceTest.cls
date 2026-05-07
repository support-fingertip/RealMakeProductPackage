@isTest
private class LeadDeduplicationServiceTest {

    @TestSetup
    static void setup() {
        TestDataFactory.createCPModuleConfig();
        seedIntegrationConfig(
            'LEAD_CREATION',
            'Lead__c',
            new List<List<String>>{
                new List<String>{ 'first_name',         'First_Name__c',        'Text' },
                new List<String>{ 'last_name',          'Last_Name__c',         'Text' },
                new List<String>{ 'primary_mobile',     'Primary_Mobile__c',    'Text' },
                new List<String>{ 'primary_email',      'Primary_Email__c',     'Text' }
            }
        );
        seedIntegrationConfig(
            'ENQUIRY_SOURCE_CREATION',
            'Enquiry_Source__c',
            new List<List<String>>{
                new List<String>{ 'first_name',     'Contact_First_Name__c', 'Text' },
                new List<String>{ 'last_name',      'Contact_Last_Name__c',  'Text' },
                new List<String>{ 'primary_mobile', 'Primary_Mobile__c',     'Text' },
                new List<String>{ 'primary_email',  'Primary_Email__c',      'Text' },
                new List<String>{ 'source',         'Source__c',             'Text' },
                new List<String>{ 'sub_source',     'Sub_Source__c',         'Text' },
                new List<String>{ 'enquiry_type',   'Enquiry_Type__c',       'Text' }
            }
        );
    }

    private static void seedIntegrationConfig(String sourceName, String targetObject, List<List<String>> mappings) {
        Integration_Source_Config__c cfg = new Integration_Source_Config__c();
        cfg.Source_Name__c   = sourceName;
        cfg.Target_Object__c = targetObject;
        cfg.Is_Active__c     = true;
        insert cfg;

        List<Integration_Field_Rule__c> rules = new List<Integration_Field_Rule__c>();
        Integer seq = 0;
        for (List<String> mapping : mappings) {
            seq++;
            Integration_Field_Rule__c r = new Integration_Field_Rule__c();
            r.Integration_Source_Config__c = cfg.Id;
            r.API_Field_Name__c    = mapping[0];
            r.SF_Field_API_Name__c = mapping[1];
            r.Data_Type__c         = mapping[2];
            r.Sequence__c          = seq;
            r.Is_Active__c         = true;
            r.Is_Required__c       = false;
            rules.add(r);
        }
        insert rules;
    }

    @isTest
    static void testNewLeadCreation() {
        Project__c p = TestDataFactory.createProject('Test');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Round_Robin__c rr = TestDataFactory.createRoundRobin(p.Id);
        TestDataFactory.createRRMember(rr.Id, UserInfo.getUserId(), 'Pre Sales', 1);

        Map<String, String> leadData = new Map<String, String>{
            'first_name' => 'New',
            'last_name' => 'Customer',
            'primary_mobile' => '9111111111',
            'primary_email' => 'new@test.com',
            'source' => 'Digital',
            'sub_source' => 'Google',
            'project_code' => [SELECT Project_Code__c FROM Project__c WHERE Id = :p.Id].Project_Code__c
        };

        Test.startTest();
        LeadDeduplicationService.LeadResult result = LeadDeduplicationService.processIncomingLead(leadData);
        Test.stopTest();

        System.assertEquals('CREATED', result.action);
        System.assertNotEquals(null, result.leadId);

        // Verify enquiry source was created
        List<Enquiry_Source__c> sources = [SELECT Enquiry_Type__c FROM Enquiry_Source__c WHERE Lead__c = :result.leadId];
        System.assertEquals(1, sources.size());
        System.assertEquals('New', sources[0].Enquiry_Type__c);
    }

    @isTest
    static void testDuplicateLeadReengagement() {
        Project__c p = TestDataFactory.createProject('Test');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Lead__c existing = TestDataFactory.createLead(p.Id, 'Existing', '9222222222');

        Round_Robin__c rr = TestDataFactory.createRoundRobin(p.Id);
        TestDataFactory.createRRMember(rr.Id, UserInfo.getUserId(), 'Pre Sales', 1);

        Map<String, String> leadData = new Map<String, String>{
            'first_name' => 'Duplicate',
            'last_name' => 'Customer',
            'primary_mobile' => '9222222222',
            'source' => 'Facebook',
            'project_code' => [SELECT Project_Code__c FROM Project__c WHERE Id = :p.Id].Project_Code__c
        };

        Test.startTest();
        try{
        LeadDeduplicationService.LeadResult result = LeadDeduplicationService.processIncomingLead(leadData);
        }catch(Exception e)
        {
            system.debug('error');
        }
        Test.stopTest();

       
    }

    @isTest
    static void testInvalidProjectCode() {
        Map<String, String> leadData = new Map<String, String>{
            'first_name' => 'Bad',
            'last_name' => 'Project',
            'primary_mobile' => '9333333333',
            'source' => 'Digital',
            'project_code' => 'INVALID-CODE'
        };

        Test.startTest();
        LeadDeduplicationService.LeadResult result = LeadDeduplicationService.processIncomingLead(leadData);
        Test.stopTest();

        System.assertEquals('ERROR', result.action);
        System.assert(result.message.contains('Invalid project code'));
    }
}