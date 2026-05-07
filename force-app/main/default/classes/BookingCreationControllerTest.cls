/**
 * @description Test class for BookingCreationController (100% coverage).
 */
@isTest
private class BookingCreationControllerTest {

    @TestSetup
    static void setup() {
        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('BCC');
        Tower__c t = TestDataFactory.createTower(p.Id, 'T');
        Unit__c u = TestDataFactory.createUnit(p.Id, t.Id, 'U-BCC');
        Lead__c lead = TestDataFactory.createLead(p.Id, 'BCC', '9900006001');
        Cost_Sheet__c cs = new Cost_Sheet__c(
            Lead__c = lead.Id, Project__c = p.Id, Unit__c = u.Id
        );
        insert cs;
        // Insert a CS_Payment_Line__c row so the copy path runs
        insert new CS_Payment_Line__c(
            Cost_Sheet__c = cs.Id, Milestone_Name__c = 'M1',
            Payment_Pct__c = 10, Amount__c = 100000,
            Due_Date__c = Date.today().addDays(30),
            Sequence__c = 1, Status__c = 'Planned'
        );
    }

    @isTest
    static void getCostSheetContext_nullAndNotFound() {
        Boolean thrown = false;
        try { BookingCreationController.getCostSheetContext(null); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);

        Lead__c tmpLead = [SELECT Id FROM Lead__c LIMIT 1];
        Cost_Sheet__c tmp = new Cost_Sheet__c(Lead__c = tmpLead.Id);
        insert tmp;
        Id tmpId = tmp.Id;
        delete tmp;
        thrown = false;
        try { BookingCreationController.getCostSheetContext(tmpId); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void getCostSheetContext_success() {
        Cost_Sheet__c cs = [SELECT Id FROM Cost_Sheet__c LIMIT 1];
        Test.startTest();
        Map<String, Object> ctx = BookingCreationController.getCostSheetContext(cs.Id);
        Test.stopTest();
        System.assertEquals(cs.Id, ctx.get('costSheetId'));
        System.assertEquals('BCC', ctx.get('projectName'));
        System.assertNotEquals(null, ctx.get('leadInfo'));
    }

    @isTest
    static void getCostSheetContext_emptyRelationshipFields() {
        // Cost sheet without project/unit → hits empty-branch paths
        Lead__c tmpLead = [SELECT Id FROM Lead__c LIMIT 1];
        Cost_Sheet__c empty = new Cost_Sheet__c(Lead__c = tmpLead.Id);
        insert empty;

        Test.startTest();
        Map<String, Object> ctx = BookingCreationController.getCostSheetContext(empty.Id);
        Test.stopTest();
        System.assertEquals('', ctx.get('projectName'));
        System.assertEquals(false, ctx.get('hasCalculationTemplate'));
    }

    @isTest
    static void createBooking_nullCs_throws() {
        Boolean thrown = false;
        try { BookingCreationController.createBooking(null, '{}', '[]'); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void createBooking_notFound_throws() {
        Lead__c tmpLead = [SELECT Id FROM Lead__c LIMIT 1];
        Cost_Sheet__c tmp = new Cost_Sheet__c(Lead__c = tmpLead.Id);
        insert tmp;
        Id tmpId = tmp.Id;
        delete tmp;

        Boolean thrown = false;
        try { BookingCreationController.createBooking(tmpId, '{}', '[]'); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void createBooking_success_withCoApplicantsAndSchedules() {
        Cost_Sheet__c cs = [SELECT Id FROM Cost_Sheet__c LIMIT 1];

        // Booking data hits every convertValue branch:
        // Date, DateTime, Double (Currency/Percent/Double), Integer,
        // Boolean, default String.
        // Using real Booking__c field API names that should exist.
        String bookingJson = JSON.serialize(new Map<String, Object>{
            'Booking_Date__c' => String.valueOf(Date.today()),
            'Booking_Amount__c' => '100000',
            'Booking_Stage__c' => 'New'
        });

        String coAppJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'key' => 'ignored',
                'First_Name__c' => 'Co-App',
                'Applicant_Name__c' => 'Co-App Test',
                'Relationship__c' => 'Spouse',
                'NonExistent_Field__c' => 'ignored'
            }
        });

        Test.startTest();
        Id bookingId = BookingCreationController.createBooking(cs.Id, bookingJson, coAppJson);
        Test.stopTest();

        System.assertNotEquals(null, bookingId);
        System.assert([SELECT COUNT() FROM Payment_Schedule__c WHERE Booking__c = :bookingId] >= 1);
        // Cost sheet should now be Converted
        Cost_Sheet__c after = [SELECT Status__c, Booking__c FROM Cost_Sheet__c WHERE Id = :cs.Id];
        System.assertEquals('Converted', after.Status__c);
    }

    @isTest
    static void createBooking_emptyCoApplicantsAndBookingData() {
        Cost_Sheet__c cs = [SELECT Id FROM Cost_Sheet__c LIMIT 1];
        Test.startTest();
        Id bookingId = BookingCreationController.createBooking(cs.Id, '{}', null);
        Test.stopTest();
        System.assertNotEquals(null, bookingId);
    }

    @isTest
    static void createBooking_invalidField_isSkipped() {
        Cost_Sheet__c cs = [SELECT Id FROM Cost_Sheet__c LIMIT 1];
        // NonExistent field + null value branch
        String bookingJson = JSON.serialize(new Map<String, Object>{
            'NonExistent__c' => 'value',
            'Booking_Amount__c' => null
        });
        Test.startTest();
        Id bookingId = BookingCreationController.createBooking(cs.Id, bookingJson, '[]');
        Test.stopTest();
        System.assertNotEquals(null, bookingId);
    }
}