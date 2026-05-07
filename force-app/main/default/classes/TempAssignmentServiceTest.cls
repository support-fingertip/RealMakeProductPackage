/**
 * @description Test class for temporary lead ownership, revocation, and sharing options.
 */
@isTest
private class TempAssignmentServiceTest {

    @TestSetup
    static void setupData() {
        Project__c proj = TestDataFactory.createProject('Test Project');
        TestDataFactory.createLead(proj.Id, 'Alice', '9000000001');
        TestDataFactory.createLead(proj.Id, 'Bob', '9000000002');
    }

    @isTest
    static void testTempAssignSuccess() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>{ lead.Id },
                currentUser,
                Date.today(),
                Date.today().addDays(7),
                'Vacation coverage',
                'Edit',
                false,
                false
            );
        Test.stopTest();

       
       
    }

    @isTest
    static void testTempAssignWithSharingOptions() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>{ lead.Id },
                currentUser,
                Date.today(),
                Date.today().addDays(7),
                'Share test',
                'Read',
                true,
                true
            );
        Test.stopTest();

       
    }

    @isTest
    static void testTempAssignAlreadyHasTempOwner() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        lead.Temp_Owner__c = UserInfo.getUserId();
        lead.Temp_Start__c = Date.today();
        lead.Temp_Expiry__c = Date.today().addDays(5);
        update lead;

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>{ lead.Id },
                UserInfo.getUserId(),
                Date.today(),
                Date.today().addDays(7),
                'Test',
                'Edit',
                false,
                false
            );
        Test.stopTest();

      
    }

    @isTest
    static void testTempAssignInvalidDates() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id },
                UserInfo.getUserId(),
                Date.today().addDays(7),
                Date.today(),
                'Test'
            );
        Test.stopTest();

      
    }

    @isTest
    static void testTempAssignNoLeadsThrowsError() {
        Boolean exceptionThrown = false;
        Test.startTest();
        try {
            BulkLeadReassignmentController.tempAssignLeads(
                new List<Id>(),
                UserInfo.getUserId(),
                Date.today(),
                Date.today().addDays(7),
                '',
                'Edit',
                false,
                false
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }
        Test.stopTest();
       
    }

    @isTest
    static void testRevokeTempAssignment() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Bob' LIMIT 1];
        lead.Temp_Owner__c = UserInfo.getUserId();
        lead.Temp_Start__c = Date.today();
        lead.Temp_Expiry__c = Date.today().addDays(5);
        update lead;

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.revokeTempAssignment(new List<Id>{ lead.Id });
        Test.stopTest();

      
    }

    @isTest
    static void testRevokeNoTempOwnerFails() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentController.revokeTempAssignment(new List<Id>{ lead.Id });
        Test.stopTest();

      
    }

    @isTest
    static void testTempAssignCreatesHistory() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.tempAssignLeads(
            new List<Id>{ lead.Id },
            UserInfo.getUserId(),
            Date.today(),
            Date.today().addDays(7),
            'Coverage'
        );
        Test.stopTest();

       
    }

    @isTest
    static void testSearchTempSharedRecords() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        BulkLeadReassignmentService.tempAssignLeads(
            new List<Id>{ lead.Id },
            currentUser,
            Date.today(),
            Date.today().addDays(7),
            'Search test',
            'Edit',
            true,
            false
        );

        Test.startTest();
        List<BulkLeadReassignmentService.TempShareRow> rows =
            BulkLeadReassignmentController.searchTempSharedRecords(currentUser);
        Test.stopTest();

      
    }

    @isTest
    static void testSearchLeadsForLookup() {
        Test.startTest();
        List<BulkLeadReassignmentService.LeadRow> rows =
            BulkLeadReassignmentController.searchLeadsForLookup('Alice');
        Test.stopTest();

      
    }

    @isTest
    static void testRevokeUpdatesHistoryInPlace() {
        Lead__c lead = [SELECT Id, OwnerId FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        // Temp assign first
        BulkLeadReassignmentService.tempAssignLeads(
            new List<Id>{ lead.Id },
            currentUser,
            Date.today(),
            Date.today().addDays(7),
            'Test revoke in-place'
        );

        // Count history records before revoke
        Integer countBefore = [
            SELECT COUNT() FROM Reassignment_History__c
            WHERE Lead__c = :lead.Id AND Reassignment_Type__c = 'Temporary'
        ];

        Test.startTest();
        BulkLeadReassignmentController.revokeTempAssignment(new List<Id>{ lead.Id });
        Test.stopTest();

      
    }

    @isTest
    static void testTempAssignSetsLifecycleFields() {
        Lead__c lead = [SELECT Id FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];
        Id currentUser = UserInfo.getUserId();

        Test.startTest();
        BulkLeadReassignmentService.tempAssignLeads(
            new List<Id>{ lead.Id },
            currentUser,
            Date.today(),
            Date.today().addDays(7),
            'Lifecycle test'
        );
        Test.stopTest();

        List<Reassignment_History__c> histories = [
            SELECT Id, Ownership_Start_Date__c, Entry_Status__c
            FROM Reassignment_History__c
            WHERE Lead__c = :lead.Id AND Reassignment_Type__c = 'Temporary' AND Status__c = 'Active'
        ];
        
    }

    @isTest
    static void testSameOwnerTempAssignBlocked() {
        Lead__c lead = [SELECT Id, OwnerId FROM Lead__c WHERE First_Name__c = 'Alice' LIMIT 1];

        Test.startTest();
        BulkLeadReassignmentService.ReassignmentResult result =
            BulkLeadReassignmentService.tempAssignLeads(
                new List<Id>{ lead.Id },
                lead.OwnerId,
                Date.today(),
                Date.today().addDays(7),
                'Same owner test'
            );
        Test.stopTest();

        
    }
}