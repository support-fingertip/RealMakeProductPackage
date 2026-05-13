@isTest
private class NamespaceUtilTest {

    @isTest
    static void prefix_isStableAcrossCalls() {
        NamespaceUtil.cachedPrefix = null;
        String first = NamespaceUtil.prefix();
        String second = NamespaceUtil.prefix();
        System.assertEquals(first, second, 'prefix() should be deterministic');
        System.assertNotEquals(null, first, 'prefix() never returns null');
    }

    @isTest
    static void strip_removesPrefix_orReturnsInput() {
        NamespaceUtil.cachedPrefix = 'NS__';
        System.assertEquals('Lead__c', NamespaceUtil.strip('NS__Lead__c'));
        System.assertEquals('Lead__c', NamespaceUtil.strip('Lead__c'));
        System.assertEquals('Account', NamespaceUtil.strip('Account'));
        System.assertEquals(null, NamespaceUtil.strip(null));
        System.assertEquals('', NamespaceUtil.strip(''));
    }

    @isTest
    static void strip_noOpWhenPrefixEmpty() {
        NamespaceUtil.cachedPrefix = '';
        System.assertEquals('Lead__c', NamespaceUtil.strip('Lead__c'));
        System.assertEquals('NS__Lead__c', NamespaceUtil.strip('NS__Lead__c'));
    }

    @isTest
    static void qualify_addsPrefixOnlyForCustomFields() {
        NamespaceUtil.cachedPrefix = 'NS__';
        System.assertEquals('NS__Lead__c', NamespaceUtil.qualify('Lead__c'));
        System.assertEquals('NS__Lead__c', NamespaceUtil.qualify('NS__Lead__c'));
        System.assertEquals('Account', NamespaceUtil.qualify('Account'));
        System.assertEquals('Name', NamespaceUtil.qualify('Name'));
    }

    @isTest
    static void qualify_noOpWhenPrefixEmpty() {
        NamespaceUtil.cachedPrefix = '';
        System.assertEquals('Lead__c', NamespaceUtil.qualify('Lead__c'));
    }

    @isTest
    static void describeObject_handlesPrefixedAndUnprefixed() {
        NamespaceUtil.cachedPrefix = null;
        // Account is standard – describe should always succeed
        System.assertNotEquals(null, NamespaceUtil.describeObject('Account'));
        // A garbage name should resolve to null (not throw)
        System.assertEquals(null, NamespaceUtil.describeObject('NoSuchObject__zzz'));
        System.assertEquals(null, NamespaceUtil.describeObject(null));
        System.assertEquals(null, NamespaceUtil.describeObject(''));
    }

    @isTest
    static void describeField_resolvesByPrefixedOrUnprefixedName() {
        Schema.SObjectType acct = Account.SObjectType;
        System.assertNotEquals(null, NamespaceUtil.describeField(acct, 'Name'));
        System.assertEquals(null, NamespaceUtil.describeField(null, 'Name'));
        System.assertEquals(null, NamespaceUtil.describeField(acct, ''));
        System.assertEquals(null, NamespaceUtil.describeField(acct, 'Definitely_Not_A_Field__c'));
    }
}