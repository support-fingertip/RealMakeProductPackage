/**
 * @description Test class for FieldDiscoveryService.
 * Exercises the recursive user-lookup discovery across null-object,
 * happy-path, and non-traversable-object branches.
 */
@isTest
private class FieldDiscoveryServiceTest {

    @isTest
    static void unknownObject_returnsEmpty() {
        Test.startTest();
        List<DynamicApprovalController.FieldPathOption> paths =
            FieldDiscoveryService.discoverUserLookups('NotARealObject__x');
        Test.stopTest();
        System.assertEquals(0, paths.size(), 'Unknown object → empty');
    }

    @isTest
    static void leadObject_findsOwnerLookup() {
        Test.startTest();
        List<DynamicApprovalController.FieldPathOption> paths =
            FieldDiscoveryService.discoverUserLookups('Lead__c');
        Test.stopTest();

        System.assert(paths.size() >= 1, 'Lead__c has at least OwnerId → User');
        Boolean foundOwner = false;
        for (DynamicApprovalController.FieldPathOption p : paths) {
            if (p.targetObject == 'User') {
                foundOwner = true;
                break;
            }
        }
        System.assert(foundOwner, 'Should find at least one User lookup');
    }

    @isTest
    static void userObject_recursesIntoManager() {
        // User itself has multiple User lookups (ManagerId, etc.) —
        // covers the recursion & User-match branches.
        Test.startTest();
        List<DynamicApprovalController.FieldPathOption> paths =
            FieldDiscoveryService.discoverUserLookups('User');
        Test.stopTest();
        System.assert(paths.size() >= 1, 'User object has User lookups');
    }
}