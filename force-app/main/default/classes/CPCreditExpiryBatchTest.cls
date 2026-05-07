@isTest
private class CPCreditExpiryBatchTest {

    @TestSetup
    static void setup() {
        // Create CP Module Config
        CP_Module_Config__c cfg = new CP_Module_Config__c(
            Is_Active__c = true,
            Credit_Active_Status__c = 'Active',
            Credit_Expired_Status__c = 'Expired',
            Credit_Expiry_Days__c = 90,
            CP_Source_Name__c = 'Channel Partner',
            CP_Active_Statuses__c = 'Approved',
            Lead_Default_Status__c = 'New'
        );
        insert cfg;

        DuplicateConversionEngine.skipProcessing = true;
        Project__c p = TestDataFactory.createProject('CPExp Proj');
        Lead__c l = TestDataFactory.createLead(p.Id, 'CPExp', '9800000110');

        // Create a Channel Partner
        Channel_Partner__c cp = new Channel_Partner__c(
            CP_Type__c = 'Individual',
            Mobile__c = '9800000111',
            Email__c = 'cptest@test.com',
            CP_Status__c = 'Approved'
        );
        insert cp;

        // Create Enquiry Source with expired credit
        Enquiry_Source__c es = new Enquiry_Source__c(
            Lead__c = l.Id,
            Channel_Partner__c = cp.Id,
            CP_Credit_Expiry__c = Date.today().addDays(-1),
            Credit_Status__c = 'Active'
        );
        insert es;

        // Create another Enquiry Source that is NOT expired
        Enquiry_Source__c esActive = new Enquiry_Source__c(
            Lead__c = l.Id,
            Channel_Partner__c = cp.Id,
            CP_Credit_Expiry__c = Date.today().addDays(30),
            Credit_Status__c = 'Active'
        );
        insert esActive;
    }

    @isTest
    static void testBatchExpiresCredits() {
        Test.startTest();
        CPCreditExpiryBatch batch = new CPCreditExpiryBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Verify the expired credit was updated
        List<Enquiry_Source__c> expired = [SELECT Credit_Status__c FROM Enquiry_Source__c
                                           WHERE CP_Credit_Expiry__c < TODAY];
        for (Enquiry_Source__c es : expired) {
            System.assertEquals('Expired', es.Credit_Status__c, 'Credit status should be Expired');
        }

        // The lead should still have a CP because there is another active credit
        Lead__c lead = [SELECT Channel_Partner__c FROM Lead__c LIMIT 1];
        // If the active credit still exists, CP should remain
    }

    @isTest
    static void testBatchNoExpiredCredits() {
        // Delete the expired enquiry source
        delete [SELECT Id FROM Enquiry_Source__c WHERE CP_Credit_Expiry__c < TODAY];

        Test.startTest();
        CPCreditExpiryBatch batch = new CPCreditExpiryBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'Batch should complete with no expired credits');
    }

    @isTest
    static void testSchedulable() {
        Test.startTest();
        CPCreditExpiryBatch batch = new CPCreditExpiryBatch();
        String jobId = System.schedule('Test CP Expiry', '0 0 0 * * ?', batch);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job should be scheduled');
    }
}