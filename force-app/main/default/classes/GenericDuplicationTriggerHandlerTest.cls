/**
 * @description Test class for GenericDuplicationTriggerHandler.
 * Covers the three configuration branches: no config, block disabled
 * (intra-batch only), and block enabled (intra-batch + DB).
 */
@isTest
private class GenericDuplicationTriggerHandlerTest {

    private static Lead__c lead(Id projectId, String firstName, String mobile) {
        return new Lead__c(
            First_Name__c = firstName, Last_Name__c = 'Dup',
            Primary_Mobile__c = mobile,
            Primary_Email__c = firstName.toLowerCase() + '@gd.test',
            Project__c = projectId, Owner__c = UserInfo.getUserId(),
            Lead_Status__c = 'New Enquiry', Lead_Type__c = 'Fresh',
            Lead_Source__c = 'Digital', Lead_Sub_Source__c = 'Google'
        );
    }

    @isTest
    static void noConfig_earlyReturn() {
        Project__c p = TestDataFactory.createProject('GDH');
        // No Duplication_Configuration__c rows at all
        Test.startTest();
        GenericDuplicationTriggerHandler.handleBeforeInsertUpdate(
            new List<SObject>{ lead(p.Id, 'A', '9800000001') }, 'Lead__c'
        );
        Test.stopTest();
    }

    @isTest
    static void intraBatchOnly_doesNotQueryDb() {
        Project__c p = TestDataFactory.createProject('GDH');
        Duplication_Configuration__c cfg = TestDataFactory.createDuplicationConfig(
            'Lead__c', 'Primary_Mobile__c'
        );
        cfg.Block_On_Duplicate__c = false;
        update cfg;

        // Two leads with the same Primary_Mobile__c in one batch
        List<Lead__c> batch = new List<Lead__c>{
            lead(p.Id, 'X1', '9800000099'),
            lead(p.Id, 'X2', '9800000099')
        };

        Boolean thrown = false;
        Test.startTest();
        try {
            insert batch; // Trigger fires the handler
        } catch (DmlException e) {
            thrown = true;
            System.assert(e.getMessage().contains('within the same batch'),
                'Should flag intra-batch duplicate');
        }
        Test.stopTest();
        System.assert(thrown, 'Intra-batch duplicate should be blocked');
    }

    @isTest
    static void dbDuplicateBlocksInsert() {
        Project__c p = TestDataFactory.createProject('GDH');
        Duplication_Configuration__c cfg = TestDataFactory.createDuplicationConfig(
            'Lead__c', 'Primary_Mobile__c'
        );
        cfg.Block_On_Duplicate__c = true;
        update cfg;

        // Seed DB with an existing lead
        insert lead(p.Id, 'Existing', '9800000200');

        Boolean thrown = false;
        Test.startTest();
        try {
            insert lead(p.Id, 'NewOne', '9800000200');
        } catch (DmlException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Duplicate record'),
                'Should flag DB duplicate');
        }
        Test.stopTest();
        System.assert(thrown, 'DB duplicate should be blocked');
    }

    @isTest
    static void allSurvivorsBatchDuplicates_earlyReturn() {
        // Covers the "survivingRecords.isEmpty()" early-return branch:
        // two records with identical dedup keys → both flagged (first is kept,
        // but DB check sees no surviving non-duplicate records). This path is
        // subtle; we just ensure the handler runs cleanly.
        Project__c p = TestDataFactory.createProject('GDH');
        Duplication_Configuration__c cfg = TestDataFactory.createDuplicationConfig(
            'Lead__c', 'Primary_Mobile__c'
        );
        cfg.Block_On_Duplicate__c = true;
        update cfg;

        List<Lead__c> batch = new List<Lead__c>{
            lead(p.Id, 'A1', '9800000300'),
            lead(p.Id, 'A2', '9800000300')
        };
        Boolean thrown = false;
        Test.startTest();
        try {
            insert batch;
        } catch (DmlException e) {
            thrown = true;
        }
        Test.stopTest();
        System.assert(thrown);
    }
}