/**
 * @description Test class for ConfigMatchingService.
 * Covers JSON criteria evaluation, field/profile/role conditions,
 * operator branches, utility lookup methods, and email-template resolution.
 */
@isTest
private class ConfigMatchingServiceTest {

    @isTest
    static void evaluateCriteria_blankJson_returnsTrue() {
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(null, null, null));
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria('', null, null));
    }

    @isTest
    static void evaluateCriteria_noConditions_returnsTrue() {
        String json = '{"conditions":[], "matchLogic":"AND"}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(json, null, null));
    }

    @isTest
    static void evaluateCriteria_profileAndRoleConditions_AND() {
        // Current user's profile always matches itself — this exercises
        // the profile condition + AND logic + true result path.
        User cu = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String json = '{"matchLogic":"AND","conditions":[' +
            '{"type":"profile","operator":"in","values":["' + cu.Profile.Name + '"]},' +
            '{"type":"role","operator":"in","values":["Any Role"]}' +
            ']}';
        Boolean result = ConfigMatchingService.evaluateCriteria(json, null, null);
        // Role check likely fails (AND path short-circuits to false)
        System.assertEquals(false, result);
    }

    @isTest
    static void evaluateCriteria_orLogicShortCircuitsOnMatch() {
        User cu = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String json = '{"matchLogic":"OR","conditions":[' +
            '{"type":"profile","operator":"in","values":["NonExistent"]},' +
            '{"type":"profile","operator":"in","values":["' + cu.Profile.Name + '"]}' +
            ']}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(json, null, null));
    }

    @isTest
    static void evaluateCriteria_notInOperator() {
        String json = '{"matchLogic":"AND","conditions":[' +
            '{"type":"profile","operator":"notIn","values":["NonExistentProfile"]}' +
            ']}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(json, null, null));
    }

    @isTest
    static void evaluateCriteria_emptyValuesReturnsTrue() {
        String json = '{"matchLogic":"AND","conditions":[' +
            '{"type":"profile","operator":"in","values":[]}' +
            ']}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(json, null, null));
    }

    @isTest
    static void evaluateCriteria_fieldConditionsAllOperators() {
        Project__c proj = TestDataFactory.createProject('CMS P');
        Lead__c lead = TestDataFactory.createLead(proj.Id, 'CM', '9700000001');

        // equals
        String j = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","operator":"equals","fieldPath":"First_Name__c","value":"CM"}]}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, lead.Id, 'Lead__c'));

        // notEquals
        j = '{"matchLogic":"AND","conditions":[{"type":"field","operator":"notEquals","fieldPath":"First_Name__c","value":"Other"}]}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, lead.Id, 'Lead__c'));

        // contains
        j = '{"matchLogic":"AND","conditions":[{"type":"field","operator":"contains","fieldPath":"First_Name__c","value":"cm"}]}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, lead.Id, 'Lead__c'));

        // startsWith
        j = '{"matchLogic":"AND","conditions":[{"type":"field","operator":"startsWith","fieldPath":"First_Name__c","value":"C"}]}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, lead.Id, 'Lead__c'));

        // isNotNull / isNull
        j = '{"matchLogic":"AND","conditions":[{"type":"field","operator":"isNotNull","fieldPath":"First_Name__c"}]}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, lead.Id, 'Lead__c'));
        j = '{"matchLogic":"AND","conditions":[{"type":"field","operator":"isNull","fieldPath":"Transferred_On__c"}]}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, lead.Id, 'Lead__c'));
    }

    @isTest
    static void evaluateCriteria_fieldConditions_numericOperators() {
        Project__c proj = TestDataFactory.createProject('CMS N');
        proj.Max_Block_Days__c = 7;
        update proj;

        String j = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","operator":"greaterThan","fieldPath":"Max_Block_Days__c","value":"5"}]}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, proj.Id, 'Project__c'));

        j = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","operator":"lessThan","fieldPath":"Max_Block_Days__c","value":"10"}]}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, proj.Id, 'Project__c'));

        // greaterThan with non-numeric → catch branch → false
        j = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","operator":"greaterThan","fieldPath":"Name","value":"abc"}]}';
        System.assertEquals(false,
            ConfigMatchingService.evaluateCriteria(j, proj.Id, 'Project__c'));

        // lessThan non-numeric
        j = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","operator":"lessThan","fieldPath":"Name","value":"abc"}]}';
        System.assertEquals(false,
            ConfigMatchingService.evaluateCriteria(j, proj.Id, 'Project__c'));
    }

    @isTest
    static void evaluateCriteria_unknownOperatorReturnsTrue() {
        // Unknown operator falls through to the default "return true" branch.
        String j = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","operator":"fooBar","fieldPath":"Name","value":"X"}]}';
        Project__c proj = TestDataFactory.createProject('CMS U');
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, proj.Id, 'Project__c'));
    }

    @isTest
    static void evaluateCriteria_unknownConditionType_defaultsTrue() {
        String j = '{"matchLogic":"AND","conditions":[' +
            '{"type":"mysteryType","operator":"equals","values":[]}]}';
        System.assertEquals(true,
            ConfigMatchingService.evaluateCriteria(j, null, null));
    }

    @isTest
    static void filterMatchingConfigs_returnsMatchingIds() {
        String configs = '[' +
            '{"id":"cfg1","matchingCriteria":""},' +
            '{"id":"cfg2","matchingCriteria":"{\\"matchLogic\\":\\"AND\\",\\"conditions\\":[]}"}' +
            ']';
        Test.startTest();
        List<String> ids = ConfigMatchingService.filterMatchingConfigs(configs, null, null);
        Test.stopTest();
        System.assertEquals(2, ids.size(), 'Both blank/empty-cond configs match');
    }

    @isTest
    static void utilityLookups_returnLists() {
        Test.startTest();
        System.assert(ConfigMatchingService.getAllProfiles().size() >= 1);
        System.assert(ConfigMatchingService.getAllRoles() != null);
        System.assert(ConfigMatchingService.searchUsers('a') != null);
        System.assert(ConfigMatchingService.getFieldsForObject('Lead__c').size() >= 1);
        System.assert(ConfigMatchingService.getFieldsForObject('NoSuchObj__x').isEmpty());
        System.assert(ConfigMatchingService.getFieldsForObject('').isEmpty());
        System.assert(ConfigMatchingService.getPicklistValues('Lead__c', 'Lead_Status__c').size() >= 1);
        System.assert(ConfigMatchingService.getPicklistValues('', 'x').isEmpty());
        System.assert(ConfigMatchingService.getPicklistValues('NoSuchObj__x', 'x').isEmpty());
        System.assert(ConfigMatchingService.getPicklistValues('Lead__c', 'NoSuchField__x').isEmpty());
        Test.stopTest();
    }

    @isTest
    static void resolveEmailTemplateForAction_noMatch_returnsNull() {
        Test.startTest();
        String id = ConfigMatchingService.resolveEmailTemplateForAction(
            'NonExistent', null, 'Lead__c'
        );
        Test.stopTest();
        System.assertEquals(null, id);
    }

    @isTest
    static void fieldCondition_invalidObjectApiName_catchesError() {
        // Exercises queryFieldValues' try/catch branch via an invalid object.
        Project__c proj = TestDataFactory.createProject('CMS E');
        String j = '{"matchLogic":"AND","conditions":[' +
            '{"type":"field","operator":"equals","fieldPath":"Name","value":"X"}]}';
        Boolean result = ConfigMatchingService.evaluateCriteria(j, proj.Id, 'NoSuchObj__x');
        // No-op query → fieldValues empty → actual=null, expected="X", equals=false
        System.assertEquals(false, result);
    }
}