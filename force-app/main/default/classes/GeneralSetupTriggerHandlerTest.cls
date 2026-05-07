/**
 * @description Test class for GeneralSetupTriggerHandler.
 * Covers the "only one active at a time" enforcement on insert and update,
 * including multi-activation batch errors and no-op paths.
 */
@isTest
private class GeneralSetupTriggerHandlerTest {

    @isTest
    static void insertInactiveIsNoop() {
        // Exercises the empty-activating early-return branch.
        General_Setup__c gs = new General_Setup__c(Is_Active__c = false);
        Test.startTest();
        insert gs;
        Test.stopTest();
        System.assertEquals(false,
            [SELECT Is_Active__c FROM General_Setup__c WHERE Id = :gs.Id].Is_Active__c);
    }

    @isTest
    static void insertSingleActiveWhenNoOthersExist() {
        General_Setup__c gs = new General_Setup__c(Is_Active__c = true);
        Test.startTest();
        insert gs;
        Test.stopTest();
        System.assertEquals(true,
            [SELECT Is_Active__c FROM General_Setup__c WHERE Id = :gs.Id].Is_Active__c);
    }

    @isTest
    static void insertActiveDeactivatesExistingActive() {
        General_Setup__c first = new General_Setup__c(Is_Active__c = true);
        insert first;

        General_Setup__c second = new General_Setup__c(Is_Active__c = true);
        Test.startTest();
        insert second;
        Test.stopTest();

        first = [SELECT Is_Active__c FROM General_Setup__c WHERE Id = :first.Id];
        second = [SELECT Is_Active__c FROM General_Setup__c WHERE Id = :second.Id];
        System.assertEquals(false, first.Is_Active__c, 'Prior active deactivated');
        System.assertEquals(true,  second.Is_Active__c, 'New record stays active');
    }

    @isTest
    static void multipleActivatingInSameBatchFails() {
        List<General_Setup__c> batch = new List<General_Setup__c>{
            new General_Setup__c(Is_Active__c = true),
            new General_Setup__c(Is_Active__c = true)
        };
        Boolean thrown = false;
        Test.startTest();
        try {
            insert batch;
        } catch (DmlException e) {
            thrown = true;
            System.assert(e.getMessage().contains('Only one General Setup'),
                'Expected multi-active error, got: ' + e.getMessage());
        }
        Test.stopTest();
        System.assert(thrown, 'Two active records in one batch must be blocked');
    }

    @isTest
    static void updateActivationDeactivatesOthers() {
        General_Setup__c active = new General_Setup__c(Is_Active__c = true);
        insert active;
        General_Setup__c inactive = new General_Setup__c(Is_Active__c = false);
        insert inactive;

        Test.startTest();
        inactive.Is_Active__c = true;
        update inactive;
        Test.stopTest();

        active = [SELECT Is_Active__c FROM General_Setup__c WHERE Id = :active.Id];
        inactive = [SELECT Is_Active__c FROM General_Setup__c WHERE Id = :inactive.Id];
        System.assertEquals(false, active.Is_Active__c, 'Prior active deactivated');
        System.assertEquals(true,  inactive.Is_Active__c, 'Newly active stays active');
    }

    @isTest
    static void updateStayingActiveIsNoop() {
        // Covers isBeingActivated == false on update path.
        General_Setup__c gs = new General_Setup__c(Is_Active__c = true);
        insert gs;

        Test.startTest();
        gs.Description__c = 'Just an edit';
        update gs;
        Test.stopTest();

        gs = [SELECT Is_Active__c FROM General_Setup__c WHERE Id = :gs.Id];
        System.assertEquals(true, gs.Is_Active__c);
    }

    @isTest
    static void updateDeactivationIsNoop() {
        // Covers deactivation path (was active, now not) — isBeingActivated false.
        General_Setup__c gs = new General_Setup__c(Is_Active__c = true);
        insert gs;

        Test.startTest();
        gs.Is_Active__c = false;
        update gs;
        Test.stopTest();

        gs = [SELECT Is_Active__c FROM General_Setup__c WHERE Id = :gs.Id];
        System.assertEquals(false, gs.Is_Active__c);
    }
}