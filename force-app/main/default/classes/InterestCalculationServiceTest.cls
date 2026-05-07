/**
 * @description Test class for InterestCalculationService.
 *              Tests interest calculation on overdue payment schedules.
 * @author System
 * @date 2026-03-15
 */
@IsTest
private class InterestCalculationServiceTest {

    @TestSetup
    static void setupData() {
        // Create Project with 18% annual interest rate
        Project__c project = new Project__c(
            Name = 'Test Project',
            Project_Type__c = 'Apartment',
            Interest_Rate__c = 18,
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

        // Create Unit
        Unit__c unit = new Unit__c(
            Project__c = project.Id,
            Tower__c = tower.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked',
            Unit_Number__c = 'IS-101',
            BHK_Type__c = '2BHK',
            Super_Builtup_Area__c = 1100,
            Base_Rate_Sqft__c = 5000
        );
        insert unit;

        // Create Booking
        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Unit__c = unit.Id,
            Booking_Date__c = Date.today().addDays(-120),
            Total_Flat_Cost__c = 10000000,
            GST_Amount__c = 500000,
            Total_Payable_Amount__c = 10500000,
            Payment_Schedules_Created__c = true,
            Status__c = 'Approved, Active'
        );
        insert booking;

        // Create Payment Schedules - some overdue
        List<Payment_Schedule__c> schedules = new List<Payment_Schedule__c>();

        // Schedule 1: Paid - should NOT have interest
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'On Booking',
            Percentage__c = 10,
            Amount__c = 1050000,
            Pending_Amount__c = 0,
            Amount_Paid__c = 1050000,
            Due_Date__c = Date.today().addDays(-120),
            Status__c = 'Paid'
        ));

        // Schedule 2: Overdue with pending amount - SHOULD have interest
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 2,
            Milestone_Name__c = 'On Agreement',
            Percentage__c = 15,
            Amount__c = 1575000,
            Pending_Amount__c = 575000,
            Amount_Paid__c = 1000000,
            Due_Date__c = Date.today().addDays(-60),
            Status__c = 'Partially Paid'
        ));

        // Schedule 3: Overdue completely unpaid - SHOULD have interest
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 3,
            Milestone_Name__c = 'On Foundation',
            Percentage__c = 10,
            Amount__c = 1050000,
            Pending_Amount__c = 1050000,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(-30),
            Status__c = 'Pending'
        ));

        // Schedule 4: Future due date - should NOT have interest
        schedules.add(new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 4,
            Milestone_Name__c = 'On Possession',
            Percentage__c = 65,
            Amount__c = 6825000,
            Pending_Amount__c = 6825000,
            Amount_Paid__c = 0,
            Due_Date__c = Date.today().addDays(180),
            Status__c = 'Pending'
        ));

        insert schedules;
    }

    @IsTest
    static void testInterestCalculationOnOverdueSchedules() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        Test.startTest();
        InterestCalculationService.FlowInput input = new InterestCalculationService.FlowInput();
        input.bookingId = booking.Id;
        input.calculationDate = Date.today();

        List<InterestCalculationService.FlowOutput> outputs =
            InterestCalculationService.calculateInterest(
                new List<InterestCalculationService.FlowInput>{ input }
            );
        Test.stopTest();

        // Verify output
        System.assertEquals(1, outputs.size(), 'Should return one output');
        InterestCalculationService.FlowOutput output = outputs[0];
        System.assert(output.totalInterest > 0, 'Total interest should be > 0');
        System.assertEquals(2, output.schedulesWithInterest, 'Should calculate interest for 2 overdue schedules');

        // Verify Interest Line Items were created
        List<Interest_Line_Item__c> lineItems = [
            SELECT Id, Booking__c, Payment_Schedule__c, Amount__c,
                   Principal_Amount__c, Number_of_Days__c, Interest_Rate__c,
                   From_Date__c, To_Date__c, Status__c, Allocation_Type__c
            FROM Interest_Line_Item__c
            WHERE Booking__c = :booking.Id
            ORDER BY Payment_Schedule__r.Sequence__c ASC
        ];

        System.assertEquals(2, lineItems.size(), 'Should create 2 interest line items');

        // Verify first line item (Schedule 2: 575,000 overdue for 60 days @ 18%)
        Interest_Line_Item__c item1 = lineItems[0];
        System.assertEquals('Interest', item1.Allocation_Type__c, 'Allocation type should be Interest');
        System.assertEquals('Calculated', item1.Status__c, 'Status should be Calculated');
        System.assertEquals(575000, item1.Principal_Amount__c, 'Principal should be 575,000');
        System.assert(item1.Number_of_Days__c > 0, 'Days should be > 0');
        System.assert(item1.Amount__c > 0, 'Interest amount should be > 0');

        // Verify Payment Schedules were updated
        List<Payment_Schedule__c> updatedSchedules = [
            SELECT Id, Interest_Pending__c, Interest_Applicable__c, Sequence__c
            FROM Payment_Schedule__c
            WHERE Booking__c = :booking.Id
            AND Sequence__c IN (2, 3)
            ORDER BY Sequence__c ASC
        ];

        for (Payment_Schedule__c ps : updatedSchedules) {
            System.assert(ps.Interest_Pending__c > 0, 'Interest_Pending should be > 0 for sequence ' + ps.Sequence__c);
            System.assertEquals(true, ps.Interest_Applicable__c, 'Interest_Applicable should be true');
        }
    }

    @IsTest
    static void testNoInterestWhenNoOverdueSchedules() {
        // Create a booking with no overdue schedules
        Project__c project = [SELECT Id FROM Project__c LIMIT 1];
        Tower__c tower = [SELECT Id FROM Tower__c WHERE Project__c = :project.Id LIMIT 1];
        Unit__c unit = new Unit__c(
            Project__c = project.Id,
            Tower__c = tower.Id,
            Unit_Type__c = 'Apartment',
            Status__c = 'Booked',
            Unit_Number__c = 'IS-NoOverdue',
            BHK_Type__c = '2BHK',
            Super_Builtup_Area__c = 1100,
            Base_Rate_Sqft__c = 5000
        );
        insert unit;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Unit__c = unit.Id,
            Booking_Date__c = Date.today(),
            Total_Payable_Amount__c = 5000000,
            Payment_Schedules_Created__c = true,
            Status__c = 'Approved, Active'
        );
        insert booking;

        // Create only future schedule
        Payment_Schedule__c ps = new Payment_Schedule__c(
            Booking__c = booking.Id,
            Sequence__c = 1,
            Milestone_Name__c = 'Future Payment',
            Percentage__c = 100,
            Amount__c = 5000000,
            Pending_Amount__c = 5000000,
            Due_Date__c = Date.today().addDays(90),
            Status__c = 'Pending'
        );
        insert ps;

        Test.startTest();
        InterestCalculationService.FlowInput input = new InterestCalculationService.FlowInput();
        input.bookingId = booking.Id;

        List<InterestCalculationService.FlowOutput> outputs =
            InterestCalculationService.calculateInterest(
                new List<InterestCalculationService.FlowInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(0, outputs[0].totalInterest, 'No interest for future schedules');
        System.assertEquals(0, outputs[0].schedulesWithInterest, 'No schedules with interest');
    }

    @IsTest
    static void testNoInterestWhenRateIsZero() {
        // Create project with 0% interest
        Project__c project = new Project__c(
            Name = 'Zero Interest Project',
            Project_Type__c = 'Plot',
            Interest_Rate__c = 0,
            Property_Types__c = 'Apartment;Villa',
            Allowed_BHK_Types__c = '2BHK;3BHK',
            Min_Booking_Amount__c = 100000,
            Max_Block_Days__c = 7
        );
        insert project;

        Booking__c booking = new Booking__c(
            Project__c = project.Id,
            Booking_Date__c = Date.today(),
            Total_Payable_Amount__c = 5000000,
            Payment_Schedules_Created__c = true,
            Status__c = 'Approved, Active'
        );
        insert booking;

        Test.startTest();
        InterestCalculationService.FlowInput input = new InterestCalculationService.FlowInput();
        input.bookingId = booking.Id;

        List<InterestCalculationService.FlowOutput> outputs =
            InterestCalculationService.calculateInterest(
                new List<InterestCalculationService.FlowInput>{ input }
            );
        Test.stopTest();

        System.assertEquals(0, outputs[0].totalInterest, 'No interest when rate is 0');
    }

    @IsTest
    static void testIncrementalCalculation() {
        Booking__c booking = [SELECT Id FROM Booking__c LIMIT 1];

        // First calculation
        Test.startTest();
        InterestCalculationService.FlowInput input1 = new InterestCalculationService.FlowInput();
        input1.bookingId = booking.Id;
        input1.calculationDate = Date.today();
        InterestCalculationService.calculateInterest(
            new List<InterestCalculationService.FlowInput>{ input1 }
        );

        Integer firstCount = [SELECT COUNT() FROM Interest_Line_Item__c WHERE Booking__c = :booking.Id];

        // Second calculation on same date should not create duplicates
        InterestCalculationService.FlowInput input2 = new InterestCalculationService.FlowInput();
        input2.bookingId = booking.Id;
        input2.calculationDate = Date.today();
        InterestCalculationService.calculateInterest(
            new List<InterestCalculationService.FlowInput>{ input2 }
        );
        Test.stopTest();

        Integer secondCount = [SELECT COUNT() FROM Interest_Line_Item__c WHERE Booking__c = :booking.Id];
        System.assertEquals(firstCount, secondCount, 'Should not create duplicate interest line items for same date');
    }
}