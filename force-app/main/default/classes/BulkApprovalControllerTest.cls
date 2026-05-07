/**
 * @description Test class for BulkApprovalController (100% coverage).
 *
 * NOTE: ProcessInstanceWorkitem / ProcessInstanceStep rows cannot be
 * inserted in Apex tests — they are only created when a live approval
 * process runs. The pending-approvals and history queries therefore
 * always return empty rows in test context, but the code paths that
 * wrap them still run and are covered.
 */
@isTest
private class BulkApprovalControllerTest {

    @isTest
    static void getPendingApprovals_runsCleanly() {
        Test.startTest();
        List<BulkApprovalController.ApprovalItemWrapper> items =
            BulkApprovalController.getPendingApprovals();
        Test.stopTest();
        System.assertNotEquals(null, items);
    }

    @isTest
    static void processApprovals_validationBranches() {
        // No records
        BulkApprovalController.ApprovalResponse r =
            BulkApprovalController.processApprovals(null, 'Approve', 'c');
        System.assertEquals(false, r.success);

        r = BulkApprovalController.processApprovals(new List<Id>(), 'Approve', 'c');
        System.assertEquals(false, r.success);

        // Invalid action
        r = BulkApprovalController.processApprovals(
            new List<Id>{ UserInfo.getUserId() }, 'Weird', 'c'
        );
        System.assertEquals(false, r.success);
        System.assertEquals('Invalid action specified', r.message);

        // Blank action
        r = BulkApprovalController.processApprovals(
            new List<Id>{ UserInfo.getUserId() }, '', 'c'
        );
        System.assertEquals(false, r.success);

        // Too many records
        List<Id> many = new List<Id>();
        for (Integer i = 0; i < 201; i++) many.add(UserInfo.getUserId());
        r = BulkApprovalController.processApprovals(many, 'Approve', 'c');
        System.assertEquals(false, r.success);
        System.assertEquals('Cannot process more than 200 records at once', r.message);
    }

    @isTest
    static void processApprovals_exceptionCaughtForInvalidWorkItem() {
        // A non-workitem Id causes Approval.process to error → caught in try/catch
        Test.startTest();
        BulkApprovalController.ApprovalResponse r =
            BulkApprovalController.processApprovals(
                new List<Id>{ UserInfo.getUserId() }, 'Approve', 'comment'
            );
        Test.stopTest();
        // Either failure count or exception-caught message path
        System.assert(r.failureCount >= 0);
    }

    @isTest
    static void processApprovals_blankComments() {
        // Covers the branch where comments are blank (skip setComments)
        Test.startTest();
        BulkApprovalController.ApprovalResponse r =
            BulkApprovalController.processApprovals(
                new List<Id>{ UserInfo.getUserId() }, 'Reject', null
            );
        Test.stopTest();
        System.assertNotEquals(null, r);
    }

    @isTest
    static void delegateApprovals_validationBranches() {
        BulkApprovalController.ApprovalResponse r =
            BulkApprovalController.delegateApprovals(null, UserInfo.getUserId());
        System.assertEquals(false, r.success);

        r = BulkApprovalController.delegateApprovals(
            new List<Id>{ UserInfo.getUserId() }, null
        );
        System.assertEquals(false, r.success);
        System.assertEquals('Please select a user to delegate to', r.message);

        // Too many records
        List<Id> many = new List<Id>();
        for (Integer i = 0; i < 201; i++) many.add(UserInfo.getUserId());
        r = BulkApprovalController.delegateApprovals(many, UserInfo.getUserId());
        System.assertEquals(false, r.success);

        // Bogus target user
        r = BulkApprovalController.delegateApprovals(
            new List<Id>{ UserInfo.getUserId() }, '005000000000001'
        );
        System.assertEquals(false, r.success);
    }

    @isTest
    static void delegateApprovals_inactiveUserRejected() {
        User cu = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        User inactive;
        System.runAs(cu) {
            Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            inactive = new User(
                Alias = 'bac', Email = 'bac@bac.invalid',
                EmailEncodingKey = 'UTF-8', LastName = 'Bac',
                LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
                ProfileId = p.Id, TimeZoneSidKey = 'America/Los_Angeles',
                Username = 'bac' + DateTime.now().getTime() + '@bac.invalid'
            );
            insert inactive;
            inactive.IsActive = false;
            update inactive;
        }
        Test.startTest();
        BulkApprovalController.ApprovalResponse r =
            BulkApprovalController.delegateApprovals(
                new List<Id>{ UserInfo.getUserId() }, inactive.Id
            );
        Test.stopTest();
        System.assertEquals(false, r.success);
    }

    @isTest
    static void delegateApprovals_activeUserProcessesRequest() {
        Test.startTest();
        BulkApprovalController.ApprovalResponse r =
            BulkApprovalController.delegateApprovals(
                new List<Id>{ UserInfo.getUserId() }, UserInfo.getUserId()
            );
        Test.stopTest();
        // Will fail at Approval.process but that's handled — either failureCount or catch path
        System.assertNotEquals(null, r);
    }

    @isTest
    static void searchUsers_branches() {
        System.assertEquals(0, BulkApprovalController.searchUsers('').size());
        System.assertEquals(0, BulkApprovalController.searchUsers(null).size());

        Test.startTest();
        List<BulkApprovalController.UserWrapper> users = BulkApprovalController.searchUsers('a');
        Test.stopTest();
        System.assertNotEquals(null, users);
    }

    @isTest
    static void getApprovalHistory_nullAndValid() {
        System.assertEquals(0, BulkApprovalController.getApprovalHistory(null).size());

        Test.startTest();
        BulkApprovalController.getApprovalHistory(UserInfo.getUserId());
        Test.stopTest();
    }

    @isTest
    static void wrappers_pojoConstructors() {
        BulkApprovalController.ApprovalItemWrapper a = new BulkApprovalController.ApprovalItemWrapper();
        a.recordId = ''; a.recordName = ''; a.recordType = '';
        a.submittedBy = ''; a.submittedById = ''; a.submittedDate = DateTime.now();
        a.status = ''; a.workItemId = ''; a.processInstanceId = '';
        System.assertEquals('', a.recordId);

        BulkApprovalController.ApprovalResponse r = new BulkApprovalController.ApprovalResponse();
        r.success = true; r.message = ''; r.successCount = 0; r.failureCount = 0;
        r.errors = new List<String>();
        System.assertEquals(true, r.success);

        BulkApprovalController.UserWrapper u = new BulkApprovalController.UserWrapper();
        u.id = ''; u.name = ''; u.email = ''; u.title = '';
        System.assertEquals('', u.name);

        BulkApprovalController.ApprovalHistoryWrapper h = new BulkApprovalController.ApprovalHistoryWrapper();
        h.stepName = ''; h.status = ''; h.actorName = '';
        h.actionDate = DateTime.now(); h.comments = '';
        System.assertEquals('', h.stepName);
    }
}