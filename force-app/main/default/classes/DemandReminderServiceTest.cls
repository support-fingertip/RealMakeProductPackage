@isTest
private class DemandReminderServiceTest {

    @TestSetup
    static void setup() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('DRS Proj');
        p.Enable_Reminder_1__c = true;
        p.Reminder_1_Days__c = 7;
        p.Enable_Reminder_2__c = true;
        p.Reminder_2_Days__c = 14;
        p.Enable_Reminder_3__c = true;
        p.Reminder_3_Days__c = 21;
        p.Enable_Reminder_4__c = true;
        p.Reminder_4_Days__c = 28;
        p.Enable_Termination_Mail__c = true;
        p.Termination_Mail_Days__c = 35;
        p.Enable_Auto_Unit_Unblocking__c = true;
        p.Unit_Unblocking_Days__c = 45;
        update p;

        Tower__c t = TestDataFactory.createTower(p.Id, 'T1');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'DRS-01');
        Lead__c l = TestDataFactory.createLead(p.Id, 'DRS', '9800000060');
        Cost_Sheet__c cs = new Cost_Sheet__c(Lead__c = l.Id, Unit__c = u.Id);
        insert cs;
        Booking__c bk = new Booking__c(
            Lead__c = l.Id, Project__c = p.Id, Unit__c = u.Id, Tower__c = t.Id,
            Cost_Sheet__c = cs.Id, Booking_Date__c = Date.today(),
            Status__c = 'Approved, Active', Owner__c = UserInfo.getUserId()
        );
        insert bk;
    }

    @isTest
    static void testPopulateReminderDatesEmpty() {
        Test.startTest();
        DemandReminderService.populateReminderDates(new List<Demands__c>());
        Test.stopTest();
        System.assert(true, 'Empty list should not throw');
    }

    @isTest
    static void testPopulateReminderDatesNull() {
        Test.startTest();
        DemandReminderService.populateReminderDates(null);
        Test.stopTest();
        System.assert(true, 'Null should not throw');
    }

    @isTest
    static void testPopulateReminderDatesWithDemand() {
        Booking__c bk = [SELECT Id FROM Booking__c LIMIT 1];

        Demands__c demand = new Demands__c(
            Booking__c = bk.Id,
            Demand_Amount__c = 500000,
            Pending_Amount__c = 500000,
            Demand_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Reminder_Date__c = Date.today().addDays(7),
            Status__c = 'Raised',
            Demand_Type__c = 'Individual Demand'
        );
        insert demand;

        // Re-query to get a fresh copy
        List<Demands__c> demands = [SELECT Id, Booking__c, Demand_Date__c, Reminder_1_Date__c,
                                            Reminder_2_Date__c, Reminder_3_Date__c, Reminder_4_Date__c,
                                            Termination_Mail_Date__c, Unit_Unblocking_Date__c, Project__c
                                     FROM Demands__c WHERE Id = :demand.Id];

        Test.startTest();
        DemandReminderService.populateReminderDates(demands);
        Test.stopTest();

        Demands__c updated = demands[0];
        System.assertEquals(Date.today().addDays(7), updated.Reminder_1_Date__c, 'Reminder 1 date should be demand date + 7');
        System.assertEquals(Date.today().addDays(14), updated.Reminder_2_Date__c, 'Reminder 2 date should be demand date + 14');
        System.assertEquals(Date.today().addDays(21), updated.Reminder_3_Date__c, 'Reminder 3 date should be demand date + 21');
        System.assertEquals(Date.today().addDays(28), updated.Reminder_4_Date__c, 'Reminder 4 date should be demand date + 28');
        System.assertEquals(Date.today().addDays(35), updated.Termination_Mail_Date__c, 'Termination mail date should be demand date + 35');
        System.assertEquals(Date.today().addDays(45), updated.Unit_Unblocking_Date__c, 'Unit unblocking date should be demand date + 45');
    }

    @isTest
    static void testProcessDueReminders() {
        Test.startTest();
        DemandReminderService.ProcessingResult result = DemandReminderService.processDueReminders();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.toLogString(), 'Log string should not be null');
        System.assert(result.totalProcessed() >= 0, 'Total processed should be non-negative');
    }

    @isTest
    static void testDisableRemindersForPaidDemands() {
        Booking__c bk = [SELECT Id FROM Booking__c LIMIT 1];

        Demands__c demand = new Demands__c(
            Booking__c = bk.Id,
            Demand_Amount__c = 500000,
            Pending_Amount__c = 0,
            Paid_Amount__c = 500000,
            Demand_Date__c = Date.today(),
            Due_Date__c = Date.today().addDays(30),
            Reminder_Date__c = Date.today().addDays(7),
            Status__c = 'Paid',
            Demand_Type__c = 'Individual Demand',
            Reminders_Disabled__c = false
        );
        insert demand;

        Test.startTest();
        DemandReminderService.disableRemindersForPaidDemands(new Set<Id>{ bk.Id });
        Test.stopTest();

        Demands__c updated = [SELECT Reminders_Disabled__c FROM Demands__c WHERE Id = :demand.Id];
        System.assertEquals(true, updated.Reminders_Disabled__c, 'Reminders should be disabled for paid demand');
    }

    @isTest
    static void testDisableRemindersEmptySet() {
        Test.startTest();
        DemandReminderService.disableRemindersForPaidDemands(new Set<Id>());
        DemandReminderService.disableRemindersForPaidDemands(null);
        Test.stopTest();
        System.assert(true, 'Should not throw for empty/null');
    }

    @isTest
    static void testProcessingResultWrapper() {
        DemandReminderService.ProcessingResult res = new DemandReminderService.ProcessingResult();
        res.reminder1Count = 1;
        res.reminder2Count = 2;
        res.reminder3Count = 3;
        res.reminder4Count = 4;
        res.terminationCount = 5;
        res.unblockingCount = 6;
        System.assertEquals(21, res.totalProcessed());
        System.assert(res.toLogString().contains('1st Reminders: 1'));
    }
}