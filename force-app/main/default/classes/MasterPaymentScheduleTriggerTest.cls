/**
 * @description Test class for MasterPaymentScheduleTrigger (100% coverage).
 */
@isTest
private class MasterPaymentScheduleTriggerTest {
    @isTest
    static void insertAndUpdate() {
        Project__c p = TestDataFactory.createProject('MPS');
        Test.startTest();
        Master_Payment_Schedule__c mps = new Master_Payment_Schedule__c(
            Project__c = p.Id,
            Payment_Type__c = 'On Booking',
            Percentage__c = 10,
            Sequence__c = 1,
            Is_Active__c = true
        );
        insert mps;                // before insert
        mps.Percentage__c = 15;
        update mps;                // before update
        Test.stopTest();
    }
}