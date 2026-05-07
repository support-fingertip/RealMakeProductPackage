/**
 * @description Test class for LeadScoringDesignerController (100% coverage).
 */
@isTest
private class LeadScoringDesignerControllerTest {

    @isTest
    static void getLeadFields_returnsList() {
        Test.startTest();
        List<LeadScoringDesignerController.FieldInfo> fields =
            LeadScoringDesignerController.getLeadFields();
        Test.stopTest();
        System.assert(fields.size() >= 1);
    }

    @isTest
    static void getPicklistValues_branches() {
        System.assertEquals(0, LeadScoringDesignerController.getPicklistValues('').size());
        System.assertEquals(0, LeadScoringDesignerController.getPicklistValues('NoSuchField__x').size());
        // Non-picklist (text) field
        System.assertEquals(0, LeadScoringDesignerController.getPicklistValues('First_Name__c').size());
        // Valid picklist
        System.assert(LeadScoringDesignerController.getPicklistValues('Lead_Status__c').size() >= 1);
    }

    @isTest
    static void getRelatedObjects_returnsList() {
        Test.startTest();
        List<LeadScoringDesignerController.RelatedObjectInfo> related =
            LeadScoringDesignerController.getRelatedObjects();
        Test.stopTest();
        System.assertNotEquals(null, related);
    }

    @isTest
    static void getRelatedObjectFields_branches() {
        System.assertEquals(0, LeadScoringDesignerController.getRelatedObjectFields('').size());
        System.assertEquals(0, LeadScoringDesignerController.getRelatedObjectFields('NoSuchObj__x').size());
        System.assert(LeadScoringDesignerController.getRelatedObjectFields('Enquiry_Source__c').size() >= 1);
    }

    @isTest
    static void getRelatedObjectPicklistValues_branches() {
        System.assertEquals(0,
            LeadScoringDesignerController.getRelatedObjectPicklistValues('', '').size());
        System.assertEquals(0,
            LeadScoringDesignerController.getRelatedObjectPicklistValues('NoSuchObj__x', 'x').size());
        System.assertEquals(0,
            LeadScoringDesignerController.getRelatedObjectPicklistValues('Lead__c', 'NoSuchField__x').size());
        System.assertEquals(0,
            LeadScoringDesignerController.getRelatedObjectPicklistValues('Lead__c', 'First_Name__c').size());
        System.assert(
            LeadScoringDesignerController.getRelatedObjectPicklistValues('Lead__c', 'Lead_Status__c').size() >= 1);
    }

    @isTest
    static void getLookupRecords_branches() {
        System.assertEquals(0, LeadScoringDesignerController.getLookupRecords('').size());
        System.assertEquals(0, LeadScoringDesignerController.getLookupRecords('NoSuchObj__x').size());
        // Object with Name field
        Project__c p = TestDataFactory.createProject('LSDC');
        System.assert(LeadScoringDesignerController.getLookupRecords('Project__c').size() >= 1);
    }

    @isTest
    static void rulesCrud() {
        Test.startTest();
        System.assertNotEquals(null, LeadScoringDesignerController.getRules());

        // Save rules
        Lead_Score_Rule__c r1 = new Lead_Score_Rule__c(
            Rule_Type__c = 'Field', Operator__c = 'equals',
            Field_API_Name__c = 'First_Name__c', Field_Value__c = 'X',
            Points__c = 5, Is_Active__c = true
        );
        String rulesJson = JSON.serialize(new List<Lead_Score_Rule__c>{ r1 });
        List<Lead_Score_Rule__c> saved = LeadScoringDesignerController.saveRules(rulesJson);
        System.assertEquals(1, saved.size());

        // Delete
        LeadScoringDesignerController.deleteRule(saved[0].Id);
        LeadScoringDesignerController.deleteRule(null); // null branch
        Test.stopTest();
    }

    @isTest
    static void tiersCrud() {
        Test.startTest();
        System.assertNotEquals(null, LeadScoringDesignerController.getTiers());

        Lead_Score_Tier__c t = new Lead_Score_Tier__c(
            Name = 'Hot', Min_Score__c = 0, Max_Score__c = 100
        );
        String tiersJson = JSON.serialize(new List<Lead_Score_Tier__c>{ t });
        List<Lead_Score_Tier__c> saved = LeadScoringDesignerController.saveTiers(tiersJson);
        System.assertEquals(1, saved.size());

        LeadScoringDesignerController.deleteTier(saved[0].Id);
        LeadScoringDesignerController.deleteTier(null);
        Test.stopTest();
    }

    @isTest
    static void wrappers_instantiate() {
        LeadScoringDesignerController.FieldInfo a = new LeadScoringDesignerController.FieldInfo();
        a.apiName = ''; a.label = 'A'; a.fieldType = 'STRING';
        a.isPicklist = false; a.isLookup = true; a.referenceTo = 'User';
        LeadScoringDesignerController.FieldInfo b = new LeadScoringDesignerController.FieldInfo();
        b.label = 'B';
        System.assert(a.compareTo(b) < 0);

        LeadScoringDesignerController.PicklistOption po = new LeadScoringDesignerController.PicklistOption();
        po.label = 'L'; po.value = 'V';
        System.assertEquals('L', po.label);

        LeadScoringDesignerController.RelatedObjectInfo ri = new LeadScoringDesignerController.RelatedObjectInfo();
        ri.objectApiName = ''; ri.objectLabel = ''; ri.lookupField = '';
        System.assertEquals('', ri.objectApiName);
    }
}