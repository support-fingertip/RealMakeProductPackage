/**
 * @description Test class for AutoDemandBatch and AutoDemandSchedulable.
 *              Validates that the daily batch job correctly raises demands
 *              for Payment Schedules where Auto_Demand_Date__c matches today.
 * @author System
 * @date 2026-03-31
 */
@IsTest
private class AutoDemandBatchTest {

    @TestSetup
    static void setupData() {
        Project__c project = new Project__c(
            Name = 'Auto Demand Test Project',
            Project_Type__c = 'Apartment',
            Interest_Rate__c = 12,
            Enable_Reminder_1__c = true,
            Reminder_1_Days__c = 7,
            Enable_Reminder_2__c = true,
            Reminder_2_Days__c = 14,
            Property_Types__c = 'Apartment;Villa',
            Allowed_BHK_Types__c = '2BHK;3BHK',
            Min_Booking_Amount__c = 100000,
            Max_Block_Days__c = 7
        );
        insert project;

        Tower__c tower = new Tower__c(
            Project__c = project.Id,
            Tower_Status__c = 'Under Construction',
            Sales_Active__c = true,
            Booking_Allowed__c = true,
            Total_Floors__c = 10,
            Total_Units__c = 40
        );
        insert tower;

        Unit__c unit = new Unit__c(
            Project__c = project.Id,
            Tower__c = tower.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked',
            Unit_Number__c = 'AD-101',
            BHK_Type__c = '2BHK',
            Super_Builtup_Area__c = 1100,
            Base_Rate_Sqft__c = 5000
        );
        insert unit;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Unit__c = unit.Id,
            Booking_Date__c = Date.today().addDays(-60),
            Total_Flat_Cost__c = 10000000,
            GST_Amount__c = 500000,
            Total_Payable_Amount__c = 10500000,
            Payment_Schedules_Created__c = true,
            Status__c = 'Approved, Active'
        );
        insert booking;

        List<Payment_Schedule__c> schedules = new List<Payment_Schedule__c>();

        // Schedule with Auto_Demand_Date__c = today - should be picked up
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'On Agreement',
            Percentage__c = 20,
            Amount__c = 2100000,
            Payment_Schedule_Amount__c = 2000000,
            GST_Amount__c = 100000,
            TDS_Amount__c = 0,
            Pending_Amount__c = 2100000,
            Payment_Schedule_Amount_Pending__c = 2000000,
            GST_Amount_Pending__c = 100000,
            TDS_Amount_Pending__c = 0,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(30),
            Auto_Demand_Date__c = Date.today(),
            Demand_Raised__c = false,
            Status__c = 'Pending'
        ));

        // Schedule with Auto_Demand_Date__c = tomorrow - should NOT be picked up
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'On Foundation',
            Percentage__c = 15,
            Amount__c = 1575000,
            Pending_Amount__c = 1575000,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(60),
            Auto_Demand_Date__c = Date.today().addDays(1),
            Demand_Raised__c = false,
            Status__c = 'Pending'
        ));

        // Schedule already demand raised - should NOT be picked up
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 3,
            Milestone_Name__c = 'On Booking',
            Percentage__c = 10,
            Amount__c = 1050000,
            Pending_Amount__c = 1050000,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(-30),
            Auto_Demand_Date__c = Date.today(),
            Demand_Raised__c = true,
            Demand_Date__c = Date.today().addDays(-30),
            Status__c = 'Demand Raised'
        ));

        insert schedules;
    }

    @IsTest
    static void testBatchCreatesAutoDemand() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify demand was created
        List<Demands__c> demands = [
            SELECT Id, Demand_Type__c, Demand_Amount__c, Demand_Date__c,
                   Due_Date__c, Status__c, Booking__c, Grace_Period_Days__c
            FROM Demands__c
            WHERE Demand_Type__c = :PostSalesConstants.DEMAND_TYPE_AUTO
        ];
        System.assertEquals(1, demands.size(), 'Should create exactly one auto demand');

        Demands__c demand = demands[0];
        System.assertEquals(PostSalesConstants.DEMAND_STATUS_RAISED, demand.Status__c, 'Demand status should be Raised');
        System.assertEquals(Date.today(), demand.Demand_Date__c, 'Demand date should be today');
        System.assertEquals(2100000, demand.Demand_Amount__c, 'Demand amount should match pending amount');
        System.assertNotEquals(null, demand.Due_Date__c, 'Due date should be set');

        // Verify payment schedule was updated
        Payment_Schedule__c updated = [
            SELECT Demand_Raised__c, Demand_Date__c
            FROM Payment_Schedule__c
            WHERE Sequence__c = 1 AND Milestone_Name__c = 'On Agreement'
        ];
        System.assertEquals(true, updated.Demand_Raised__c, 'Demand_Raised__c should be true');
        System.assertEquals(Date.today(), updated.Demand_Date__c, 'Demand_Date__c should be today');
    }

    @IsTest
    static void testBatchSkipsFutureAutoDemandDate() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Schedule with tomorrow's Auto_Demand_Date should not have demand raised
        Payment_Schedule__c future = [
            SELECT Demand_Raised__c
            FROM Payment_Schedule__c
            WHERE Sequence__c = 2 AND Milestone_Name__c = 'On Foundation'
        ];
        System.assertEquals(false, future.Demand_Raised__c, 'Future auto demand date should not be processed');
    }

    @IsTest
    static void testBatchSkipsAlreadyRaised() {
        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Only 1 demand should be created (not for the already-raised schedule)
        Integer demandCount = [SELECT COUNT() FROM Demands__c WHERE Demand_Type__c = :PostSalesConstants.DEMAND_TYPE_AUTO];
        System.assertEquals(1, demandCount, 'Should not create demand for already-raised schedule');
    }

    @IsTest
    static void testBatchWithCustomDate() {
        Date tomorrow = Date.today().addDays(1);

        Test.startTest();
        AutoDemandBatch batch = new AutoDemandBatch(tomorrow);
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Should pick up the schedule with Auto_Demand_Date__c = tomorrow
        List<Demands__c> demands = [
            SELECT Id, Demand_Date__c
            FROM Demands__c
            WHERE Demand_Type__c = :PostSalesConstants.DEMAND_TYPE_AUTO
        ];
        System.assertEquals(1, demands.size(), 'Should create demand for tomorrow date');
        System.assertEquals(tomorrow, demands[0].Demand_Date__c, 'Demand date should match custom date');
    }

    @IsTest
    static void testSchedulableExecutesBatch() {
        Test.startTest();
        AutoDemandSchedulable schedulable = new AutoDemandSchedulable();
        String jobId = System.schedule(
            'Test Daily Auto Demand',
            '0 0 2 * * ?',
            schedulable
        );
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, State
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        System.assertEquals(1, jobs.size(), 'Scheduled job should exist');
    }
}