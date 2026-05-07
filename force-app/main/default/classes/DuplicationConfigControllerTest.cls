/**
 * @description Test class for DuplicationConfigController (100% coverage).
 */
@isTest
private class DuplicationConfigControllerTest {

    @isTest
    static void schemaHelpers() {
        Test.startTest();
        System.assert(DuplicationConfigController.getAllObjects().size() >= 1);
        System.assert(DuplicationConfigController.getObjectFields('Lead__c').size() >= 1);
        System.assertEquals(0, DuplicationConfigController.getObjectFields('NoSuchObj__x').size());
        System.assert(DuplicationConfigController.getRelatedObjectFieldsImperative('Lead__c').size() >= 1);
        System.assert(DuplicationConfigController.getRelatedObjects('Lead__c').size() >= 1);
        System.assertEquals(0, DuplicationConfigController.getRelatedObjects('NoSuchObj__x').size());
        Test.stopTest();
    }

    @isTest
    static void saveConfiguration_createAndEdit() {
        // CREATE new config (deactivating existing active config in the process)
        TestDataFactory.createDuplicationConfig('Lead__c', 'Primary_Mobile__c');

        String createJson = JSON.serialize(new Map<String, Object>{
            'primaryObject' => 'Lead__c',
            'primaryExpression' => 'Primary_Mobile__c',
            'relatedObject' => 'Enquiry_Source__c',
            'relatedExpression' => 'Primary_Mobile__c',
            'fieldMappings' => new List<Object>{
                new Map<String, Object>{
                    'relatedField' => 'Lead__c',
                    'mappingType' => 'field',
                    'sourceValue' => 'Id'
                }
            }
        });

        Test.startTest();
        String createMsg = DuplicationConfigController.saveConfiguration(createJson);
        System.assert(createMsg.contains('saved successfully'));

        // EDIT existing config
        Duplication_Configuration__c existing = [
            SELECT Id FROM Duplication_Configuration__c
            WHERE Primary_Object_API_Name__c = 'Lead__c' AND Active__c = true LIMIT 1
        ];
        // Seed an existing field mapping so the "delete old" branch runs
        insert new Field_Mapping__c(
            Duplication_Configuration__c = existing.Id,
            Related_Object_Field__c = 'Old', Mapping_Type__c = 'manual',
            Sequence__c = 1, Active__c = true
        );

        String editJson = JSON.serialize(new Map<String, Object>{
            'configId' => String.valueOf(existing.Id),
            'primaryObject' => 'Lead__c',
            'primaryExpression' => 'Primary_Email__c',
            'relatedObject' => '',   // blank → nulls out related fields
            'relatedExpression' => '',
            'fieldMappings' => new List<Object>()
        });
        String editMsg = DuplicationConfigController.saveConfiguration(editJson);
        System.assert(editMsg.contains('saved successfully'));
        Test.stopTest();

        DuplicationConfigController.getConfigurationsByObject('Lead__c');
        DuplicationConfigController.getConfigurationWithMappings(existing.Id);
    }

    @isTest
    static void saveConfiguration_invalidJson_throws() {
        Boolean thrown = false;
        try {
            DuplicationConfigController.saveConfiguration('not valid json');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown);
    }

    @isTest
    static void getConfigurationWithMappings_invalid_throws() {
        Boolean thrown = false;
        try {
            DuplicationConfigController.getConfigurationWithMappings('a0W000000000001');
        } catch (AuraHandledException e) {
            thrown = true;
        }
        System.assert(thrown);
    }

    @isTest
    static void dtos_comparable() {
        DuplicationConfigController.ObjectOption a = new DuplicationConfigController.ObjectOption('A', 'a');
        DuplicationConfigController.ObjectOption b = new DuplicationConfigController.ObjectOption('B', 'b');
        System.assert(a.compareTo(b) < 0);

        DuplicationConfigController.FieldOption fa = new DuplicationConfigController.FieldOption('A', 'a', 'STRING');
        DuplicationConfigController.FieldOption fb = new DuplicationConfigController.FieldOption('B', 'b', 'STRING');
        System.assert(fa.compareTo(fb) < 0);
    }
}