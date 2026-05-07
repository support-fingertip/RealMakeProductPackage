/**
 * @description Test class for EmailFieldPickerController (100% coverage).
 */
@isTest
private class EmailFieldPickerControllerTest {

    @isTest
    static void getAllObjects_returnsList() {
        Test.startTest();
        List<EmailFieldPickerController.ObjectWrapper> objs =
            EmailFieldPickerController.getAllObjects();
        Test.stopTest();
        System.assert(objs.size() >= 1);
    }

    @isTest
    static void getFieldsForObject_branches() {
        System.assertEquals(0, EmailFieldPickerController.getFieldsForObject('').size());

        Boolean thrown = false;
        try {
            EmailFieldPickerController.getFieldsForObject('NoSuchObj__x');
        } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);

        System.assert(EmailFieldPickerController.getFieldsForObject('Lead__c').size() >= 1);
    }

    @isTest
    static void getEmailFieldsForObject_returnsList() {
        Test.startTest();
        List<EmailFieldPickerController.FieldWrapper> emailFields =
            EmailFieldPickerController.getEmailFieldsForObject('Lead__c');
        Test.stopTest();
        System.assert(emailFields.size() >= 1, 'Lead__c has Primary_Email__c');
    }

    @isTest
    static void getMergeFieldsForObject_returnsList() {
        Test.startTest();
        List<EmailFieldPickerController.FieldWrapper> mergeFields =
            EmailFieldPickerController.getMergeFieldsForObject('Lead__c');
        Test.stopTest();
        System.assert(mergeFields.size() >= 1);
    }

    @isTest
    static void getOrgWideEmailAddresses_runsCleanly() {
        Test.startTest();
        EmailFieldPickerController.getOrgWideEmailAddresses();
        Test.stopTest();
    }

    @isTest
    static void getVisualforcePages_runsCleanly() {
        Test.startTest();
        EmailFieldPickerController.getVisualforcePages();
        Test.stopTest();
    }

    @isTest
    static void getRelatedObjects_branches() {
        System.assertEquals(0, EmailFieldPickerController.getRelatedObjects('').size());

        Boolean thrown = false;
        try {
            EmailFieldPickerController.getRelatedObjects('NoSuchObj__x');
        } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);

        Test.startTest();
        System.assert(EmailFieldPickerController.getRelatedObjects('Lead__c').size() >= 1);
        Test.stopTest();
    }

    @isTest
    static void searchRecords_branches() {
        Project__c p = TestDataFactory.createProject('EFP Search');

        // Blank object
        System.assertEquals(0, EmailFieldPickerController.searchRecords('', '').size());

        // Short search term → no WHERE clause → returns up to 20
        Test.startTest();
        List<EmailFieldPickerController.ObjectWrapper> noSearch =
            EmailFieldPickerController.searchRecords('Project__c', '');
        System.assert(noSearch.size() >= 1);

        // Valid search
        List<EmailFieldPickerController.ObjectWrapper> withSearch =
            EmailFieldPickerController.searchRecords('Project__c', 'EFP');
        System.assert(withSearch.size() >= 1);
        Test.stopTest();

        // Invalid object → exception caught and rethrown
        Boolean thrown = false;
        try { EmailFieldPickerController.searchRecords('NoSuchObj__x', 'X'); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void objectWrapper_compareTo() {
        EmailFieldPickerController.ObjectWrapper a = new EmailFieldPickerController.ObjectWrapper('Alpha', 'a');
        EmailFieldPickerController.ObjectWrapper b = new EmailFieldPickerController.ObjectWrapper('Beta', 'b');
        EmailFieldPickerController.ObjectWrapper nullA = new EmailFieldPickerController.ObjectWrapper(null, 'n1');
        EmailFieldPickerController.ObjectWrapper nullB = new EmailFieldPickerController.ObjectWrapper(null, 'n2');
        System.assert(a.compareTo(b) < 0);
        System.assertEquals(0, nullA.compareTo(nullB));
        System.assert(nullA.compareTo(a) < 0);
        System.assert(a.compareTo(nullA) > 0);
    }

    @isTest
    static void fieldWrapper_compareTo() {
        EmailFieldPickerController.FieldWrapper a = new EmailFieldPickerController.FieldWrapper();
        a.label = 'A';
        EmailFieldPickerController.FieldWrapper b = new EmailFieldPickerController.FieldWrapper();
        b.label = 'B';
        EmailFieldPickerController.FieldWrapper nullA = new EmailFieldPickerController.FieldWrapper();
        EmailFieldPickerController.FieldWrapper nullB = new EmailFieldPickerController.FieldWrapper();
        System.assert(a.compareTo(b) < 0);
        System.assertEquals(0, nullA.compareTo(nullB));
        System.assert(nullA.compareTo(a) < 0);
        System.assert(a.compareTo(nullA) > 0);
    }

    @isTest
    static void relationshipWrapper_compareTo() {
        EmailFieldPickerController.RelationshipWrapper parent = new EmailFieldPickerController.RelationshipWrapper(
            'A', 'a', 'Parent', 'pRel', 'Lead__c'
        );
        EmailFieldPickerController.RelationshipWrapper child = new EmailFieldPickerController.RelationshipWrapper(
            'B', 'b', 'Child', 'cRel', 'Lead__c'
        );
        System.assert(parent.compareTo(child) > 0,
            'Parent comes after Child alphabetically on type');

        EmailFieldPickerController.RelationshipWrapper parentB = new EmailFieldPickerController.RelationshipWrapper(
            'B', 'b', 'Parent', 'x', 'X'
        );
        System.assert(parent.compareTo(parentB) < 0);

        EmailFieldPickerController.RelationshipWrapper nullA = new EmailFieldPickerController.RelationshipWrapper(
            null, '', 'Parent', '', ''
        );
        EmailFieldPickerController.RelationshipWrapper nullB2 = new EmailFieldPickerController.RelationshipWrapper(
            null, '', 'Parent', '', ''
        );
        System.assertEquals(0, nullA.compareTo(nullB2));
        System.assert(nullA.compareTo(parent) < 0);
        System.assert(parent.compareTo(nullA) > 0);
    }
}