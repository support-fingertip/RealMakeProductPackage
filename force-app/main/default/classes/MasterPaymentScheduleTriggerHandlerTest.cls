/**
 * @description Test class for MasterPaymentScheduleTriggerHandler.
 *              Tests the validation that total Percentage__c per Project
 *              cannot exceed 100%.
 * @author System
 * @date 2026-04-10
 */
@IsTest
private class MasterPaymentScheduleTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        Project__c project = TestDataFactory.createProject('Test Project');

        // Insert initial record: 40%
        Master_Payment_Schedule__c mps = new Master_Payment_Schedule__c(
            Name = 'On Booking',
            Project__c = project.Id,
            Payment_Type__c = 'On Booking',
            Percentage__c = 40,
            Sequence__c = 1,
            Is_Active__c = true
        );
        insert mps;
    }

    @IsTest
    static void testInsertWithinLimit() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];

        Master_Payment_Schedule__c mps = new Master_Payment_Schedule__c(
            Name = 'On Agreement',
            Project__c = project.Id,
            Payment_Type__c = 'On Agreement',
            Percentage__c = 50,
            Sequence__c = 2,
            Is_Active__c = true
        );

        Test.startTest();
        insert mps;
        Test.stopTest();

        // Total = 40 + 50 = 90% — should succeed
        List<Master_Payment_Schedule__c> records = [
            SELECT Id FROM Master_Payment_Schedule__c WHERE Project__c = :project.Id
        ];
        System.assertEquals(2, records.size(), 'Both records should be inserted successfully');
    }

    @IsTest
    static void testInsertExactly100() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];

        Master_Payment_Schedule__c mps = new Master_Payment_Schedule__c(
            Name = 'On Possession',
            Project__c = project.Id,
            Payment_Type__c = 'On Possession',
            Percentage__c = 60,
            Sequence__c = 2,
            Is_Active__c = true
        );

        Test.startTest();
        insert mps;
        Test.stopTest();

        // Total = 40 + 60 = 100% — should succeed
        List<Master_Payment_Schedule__c> records = [
            SELECT Id FROM Master_Payment_Schedule__c WHERE Project__c = :project.Id
        ];
        System.assertEquals(2, records.size(), 'Total of exactly 100% should be allowed');
    }

    @IsTest
    static void testInsertExceeds100() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];

        Master_Payment_Schedule__c mps = new Master_Payment_Schedule__c(
            Name = 'On Possession',
            Project__c = project.Id,
            Payment_Type__c = 'On Possession',
            Percentage__c = 70,
            Sequence__c = 2,
            Is_Active__c = true
        );

        Test.startTest();
        Boolean errorThrown = false;
        try {
            insert mps;
        } catch (DmlException e) {
            errorThrown = true;
            System.assert(
                e.getMessage().contains('Total percentage for this Project cannot exceed 100%'),
                'Error message should mention percentage limit. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();

        // Total = 40 + 70 = 110% — should fail
        System.assert(errorThrown, 'DmlException should be thrown when total exceeds 100%');
    }

    @IsTest
    static void testUpdateWithinLimit() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];

        // Insert second record: 40 + 30 = 70%
        Master_Payment_Schedule__c mps = new Master_Payment_Schedule__c(
            Name = 'On Agreement',
            Project__c = project.Id,
            Payment_Type__c = 'On Agreement',
            Percentage__c = 30,
            Sequence__c = 2,
            Is_Active__c = true
        );
        insert mps;

        // Update to 60%: 40 + 60 = 100% — should succeed
        mps.Percentage__c = 60;

        Test.startTest();
        update mps;
        Test.stopTest();

        Master_Payment_Schedule__c updated = [
            SELECT Percentage__c FROM Master_Payment_Schedule__c WHERE Id = :mps.Id
        ];
        System.assertEquals(60, updated.Percentage__c, 'Percentage should be updated to 60%');
    }

    @IsTest
    static void testUpdateExceeds100() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];

        // Insert second record: 40 + 30 = 70%
        Master_Payment_Schedule__c mps = new Master_Payment_Schedule__c(
            Name = 'On Agreement',
            Project__c = project.Id,
            Payment_Type__c = 'On Agreement',
            Percentage__c = 30,
            Sequence__c = 2,
            Is_Active__c = true
        );
        insert mps;

        // Update to 70%: 40 + 70 = 110% — should fail
        mps.Percentage__c = 70;

        Test.startTest();
        Boolean errorThrown = false;
        try {
            update mps;
        } catch (DmlException e) {
            errorThrown = true;
            System.assert(
                e.getMessage().contains('Total percentage for this Project cannot exceed 100%'),
                'Error message should mention percentage limit. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assert(errorThrown, 'DmlException should be thrown when update causes total to exceed 100%');
    }

    @IsTest
    static void testBulkInsertSameProject() {
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];

        // Bulk insert: 40 (existing) + 30 + 20 + 20 = 110% — should fail
        List<Master_Payment_Schedule__c> records = new List<Master_Payment_Schedule__c>();
        records.add(new Master_Payment_Schedule__c(
            Name = 'On Agreement',
            Project__c = project.Id,
            Payment_Type__c = 'On Agreement',
            Percentage__c = 30,
            Sequence__c = 2,
            Is_Active__c = true
        ));
        records.add(new Master_Payment_Schedule__c(
            Name = 'On Foundation',
            Project__c = project.Id,
            Payment_Type__c = 'On Foundation',
            Percentage__c = 20,
            Sequence__c = 3,
            Is_Active__c = true
        ));
        records.add(new Master_Payment_Schedule__c(
            Name = 'On Possession',
            Project__c = project.Id,
            Payment_Type__c = 'On Possession',
            Percentage__c = 20,
            Sequence__c = 4,
            Is_Active__c = true
        ));

        Test.startTest();
        Boolean errorThrown = false;
        try {
            insert records;
        } catch (DmlException e) {
            errorThrown = true;
            System.assert(
                e.getMessage().contains('Total percentage for this Project cannot exceed 100%'),
                'Error message should mention percentage limit. Got: ' + e.getMessage()
            );
        }
        Test.stopTest();

        System.assert(errorThrown, 'DmlException should be thrown for bulk insert exceeding 100%');
    }

    @IsTest
    static void testMultipleProjectsIndependent() {
        Project__c project1 = [SELECT Id FROM Project__c LIMIT 1];
        Project__c project2 = TestDataFactory.createProject('Test Project 2');

        // Project1: 40 (existing) + 50 = 90% — OK
        // Project2: 80% — OK
        List<Master_Payment_Schedule__c> records = new List<Master_Payment_Schedule__c>();
        records.add(new Master_Payment_Schedule__c(
            Name = 'P1 - On Agreement',
            Project__c = project1.Id,
            Payment_Type__c = 'On Agreement',
            Percentage__c = 50,
            Sequence__c = 2,
            Is_Active__c = true
        ));
        records.add(new Master_Payment_Schedule__c(
            Name = 'P2 - On Booking',
            Project__c = project2.Id,
            Payment_Type__c = 'On Booking',
            Percentage__c = 80,
            Sequence__c = 1,
            Is_Active__c = true
        ));

        Test.startTest();
        insert records;
        Test.stopTest();

        List<Master_Payment_Schedule__c> p1Records = [
            SELECT Id FROM Master_Payment_Schedule__c WHERE Project__c = :project1.Id
        ];
        List<Master_Payment_Schedule__c> p2Records = [
            SELECT Id FROM Master_Payment_Schedule__c WHERE Project__c = :project2.Id
        ];
        System.assertEquals(2, p1Records.size(), 'Project 1 should have 2 records');
        System.assertEquals(1, p2Records.size(), 'Project 2 should have 1 record');
    }
}