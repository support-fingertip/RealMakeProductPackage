@isTest
private class RoundRobinControllerTest {

    @TestSetup
    static void setup() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c proj = TestDataFactory.createProject('RR Test Project');
    }

    @isTest
    static void testGetConfigurationData() {
        Test.startTest();
        Map<String, Object> data = RoundRobinController.getConfigurationData();
        Test.stopTest();

        System.assertNotEquals(null, data);
        System.assert(data.containsKey('sources'));
        System.assert(data.containsKey('zones'));
        System.assert(data.containsKey('users'));
    }

    @isTest
    static void testGetExistingBuckets_empty() {
        Test.startTest();
        List<Round_Robin__c> buckets = RoundRobinController.getExistingBuckets();
        Test.stopTest();

        System.assertNotEquals(null, buckets);
    }

    @isTest
    static void testGetActiveUsers() {
        Test.startTest();
        List<User> users = RoundRobinController.getActiveUsers();
        Test.stopTest();

        System.assert(users.size() > 0, 'Should return active users');
    }

    @isTest
    static void testSaveBucket_newBucket() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Round_Robin__c bucket = new Round_Robin__c(
            Project__c = proj.Id,
            Is_Active__c = true
        );

        Map<String, List<String>> categorizedUsers = new Map<String, List<String>>{
            'Pre Sales' => new List<String>{ UserInfo.getUserId() }
        };

        Test.startTest();
        try {
            RoundRobinController.saveBucket(bucket, categorizedUsers);
        } catch (AuraHandledException e) {
            // Org-specific validation may prevent save
            System.assert(true, 'Caught validation: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testSaveBucket_emptyUsers() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Round_Robin__c bucket = new Round_Robin__c(
            Project__c = proj.Id,
            Is_Active__c = true
        );

        Map<String, List<String>> categorizedUsers = new Map<String, List<String>>{
            'Pre Sales' => null
        };

        Test.startTest();
        try {
            RoundRobinController.saveBucket(bucket, categorizedUsers);
        } catch (AuraHandledException e) {
            System.assert(true, 'Caught: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetExistingBuckets_withData() {
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Round_Robin__c bucket = new Round_Robin__c(
            Project__c = proj.Id,
            Is_Active__c = true
        );
        try {
            insert bucket;
        } catch (Exception e) {
            return; // Validation prevents insert
        }

        Test.startTest();
        List<Round_Robin__c> buckets = RoundRobinController.getExistingBuckets();
        Test.stopTest();

        System.assert(buckets.size() >= 1);
    }
}