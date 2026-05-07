@IsTest
private class FieldMappingSetupControllerTest {

    @TestSetup
    static void setupTestData() {
        General_Setup__c setup = new General_Setup__c(
            Push_To_Sales_Type__c = 'Manual',
            Is_Active__c = true,
            Description__c = 'Test description'
        );
        insert setup;

        List<Field_Mapping__c> mappings = new List<Field_Mapping__c>();
        mappings.add(new Field_Mapping__c(
            General_Setup__c = setup.Id,
            Primary_Object_Field_value__c = 'Primary_Mobile__c',
            Related_object_field__c = 'Primary_Mobile__c',
            Mapping_Type__c = 'field',
            Sequence__c = 1,
            Active__c = true
        ));
        mappings.add(new Field_Mapping__c(
            General_Setup__c = setup.Id,
            Primary_Object_Field_value__c = 'Primary_Email__c',
            Related_object_field__c = 'Primary_Email__c',
            Mapping_Type__c = 'field',
            Sequence__c = 2,
            Active__c = true
        ));
        insert mappings;
    }

    @IsTest
    static void testGetGeneralSetups() {
        Test.startTest();
        List<General_Setup__c> setups = FieldMappingSetupController.getGeneralSetups();
        Test.stopTest();

        System.assertEquals(1, setups.size(), 'Should return one setup');
        System.assert(setups[0].Name.startsWith('GS-'), 'Name should be auto-generated');
        System.assertEquals('Manual', setups[0].Push_To_Sales_Type__c, 'Push type should match');
    }

    @IsTest
    static void testGetGeneralSetupWithMappings() {
        General_Setup__c setup = [SELECT Id FROM General_Setup__c LIMIT 1];

        Test.startTest();
        General_Setup__c result = FieldMappingSetupController.getGeneralSetupWithMappings(setup.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return setup');
        System.assertEquals(2, result.Field_Mappings__r.size(), 'Should have 2 mappings');
    }

    @IsTest
    static void testGetLeadFields() {
        Test.startTest();
        List<FieldMappingSetupController.FieldOption> fields = FieldMappingSetupController.getLeadFields();
        Test.stopTest();

        System.assert(fields.size() > 0, 'Should return Lead fields');

        Boolean foundMobile = false;
        for (FieldMappingSetupController.FieldOption f : fields) {
            if (f.apiName == 'Primary_Mobile__c') {
                foundMobile = true;
                break;
            }
        }
        System.assert(foundMobile, 'Should include Primary_Mobile__c field');
    }

    @IsTest
    static void testSaveGeneralSetupInsert() {
        Map<String, Object> data = new Map<String, Object>{
            'pushToSalesType' => 'Automation /On Site-Visit Creation',
            'isActive' => true,
            'description' => 'New setup description'
        };

        Test.startTest();
        Id setupId = FieldMappingSetupController.saveGeneralSetup(JSON.serialize(data));
        Test.stopTest();

        General_Setup__c saved = [SELECT Push_To_Sales_Type__c FROM General_Setup__c WHERE Id = :setupId];
        System.assertEquals('Automation /On Site-Visit Creation', saved.Push_To_Sales_Type__c);
    }

    @IsTest
    static void testSaveGeneralSetupUpdate() {
        General_Setup__c setup = [SELECT Id FROM General_Setup__c LIMIT 1];

        Map<String, Object> data = new Map<String, Object>{
            'id' => setup.Id,
            'pushToSalesType' => 'Automation /On Site-Visit Completion',
            'isActive' => false,
            'description' => 'Updated description'
        };

        Test.startTest();
        Id setupId = FieldMappingSetupController.saveGeneralSetup(JSON.serialize(data));
        Test.stopTest();

        General_Setup__c updated = [SELECT Push_To_Sales_Type__c, Is_Active__c FROM General_Setup__c WHERE Id = :setupId];
        System.assertEquals('Automation /On Site-Visit Completion', updated.Push_To_Sales_Type__c);
        System.assertEquals(false, updated.Is_Active__c);
    }

    @IsTest
    static void testSaveFieldMappings() {
        General_Setup__c setup = [SELECT Id FROM General_Setup__c LIMIT 1];

        List<Map<String, Object>> mappings = new List<Map<String, Object>>();
        mappings.add(new Map<String, Object>{
            'sourceField' => 'First_Name__c',
            'targetField' => 'First_Name__c',
            'mappingType' => 'field',
            'sequence' => 1,
            'isActive' => true
        });
        mappings.add(new Map<String, Object>{
            'sourceField' => 'Last_Name__c',
            'targetField' => 'Last_Name__c',
            'mappingType' => 'field',
            'sequence' => 2,
            'isActive' => true
        });

        Test.startTest();
        FieldMappingSetupController.saveFieldMappings(setup.Id, JSON.serialize(mappings));
        Test.stopTest();

        List<Field_Mapping__c> saved = [
            SELECT Primary_Object_Field_value__c, Related_object_field__c, Sequence__c
            FROM Field_Mapping__c
            WHERE General_Setup__c = :setup.Id
            ORDER BY Sequence__c
        ];
        System.assertEquals(2, saved.size(), 'Should have 2 new mappings (old ones deleted)');
        System.assertEquals('First_Name__c', saved[0].Primary_Object_Field_value__c);
        System.assertEquals('Last_Name__c', saved[1].Primary_Object_Field_value__c);
    }

    @IsTest
    static void testSaveFieldMappingsWithExistingIds() {
        General_Setup__c setup = [SELECT Id FROM General_Setup__c LIMIT 1];
        Field_Mapping__c existing = [SELECT Id FROM Field_Mapping__c WHERE General_Setup__c = :setup.Id LIMIT 1];

        List<Map<String, Object>> mappings = new List<Map<String, Object>>();
        mappings.add(new Map<String, Object>{
            'id' => existing.Id,
            'sourceField' => 'Primary_Mobile__c',
            'targetField' => 'Secondary_Mobile__c',
            'mappingType' => 'field',
            'sequence' => 1,
            'isActive' => true
        });

        Test.startTest();
        FieldMappingSetupController.saveFieldMappings(setup.Id, JSON.serialize(mappings));
        Test.stopTest();

        List<Field_Mapping__c> saved = [
            SELECT Id, Related_object_field__c
            FROM Field_Mapping__c
            WHERE General_Setup__c = :setup.Id
        ];
        System.assertEquals(1, saved.size(), 'Should have 1 mapping (1 updated, 1 deleted)');
        System.assertEquals('Secondary_Mobile__c', saved[0].Related_object_field__c);
    }

    @IsTest
    static void testDeleteFieldMapping() {
        Field_Mapping__c mapping = [SELECT Id FROM Field_Mapping__c LIMIT 1];

        Test.startTest();
        FieldMappingSetupController.deleteFieldMapping(mapping.Id);
        Test.stopTest();

        List<Field_Mapping__c> remaining = [SELECT Id FROM Field_Mapping__c WHERE Id = :mapping.Id];
        System.assertEquals(0, remaining.size(), 'Mapping should be deleted');
    }

    @IsTest
    static void testDeleteGeneralSetup() {
        General_Setup__c setup = [SELECT Id FROM General_Setup__c LIMIT 1];

        Test.startTest();
        FieldMappingSetupController.deleteGeneralSetup(setup.Id);
        Test.stopTest();

        List<General_Setup__c> remainingSetups = [SELECT Id FROM General_Setup__c WHERE Id = :setup.Id];
        List<Field_Mapping__c> remainingMappings = [SELECT Id FROM Field_Mapping__c WHERE General_Setup__c = :setup.Id];
        System.assertEquals(0, remainingSetups.size(), 'Setup should be deleted');
        System.assertEquals(0, remainingMappings.size(), 'Child mappings should be deleted');
    }

    @IsTest
    static void testFieldOptionComparable() {
        FieldMappingSetupController.FieldOption a = new FieldMappingSetupController.FieldOption('Alpha', 'Alpha__c', 'STRING', true);
        FieldMappingSetupController.FieldOption b = new FieldMappingSetupController.FieldOption('Beta', 'Beta__c', 'STRING', true);

        System.assert(a.compareTo(b) < 0, 'Alpha should sort before Beta');
    }
}