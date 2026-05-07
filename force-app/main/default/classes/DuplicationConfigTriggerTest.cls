/**
 * @description Test class for DuplicationConfigTrigger (100% coverage).
 */
@isTest
private class DuplicationConfigTriggerTest {
    @isTest
    static void insertAndUpdate() {
        Test.startTest();
        Duplication_Configuration__c dc =
            TestDataFactory.createDuplicationConfig('Lead__c', 'Primary_Mobile__c');  // before insert
        dc.Description__c = 'updated';
        update dc;                                                                   // before update
        Test.stopTest();
    }
}