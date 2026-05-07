/**
 * @description Test class for IntegrationMappingController (100% coverage).
 */
@isTest
private class IntegrationMappingControllerTest {

    @isTest
    static void fullCrudLifecycle() {
        // CREATE via saveSourceConfig
        String createJson = JSON.serialize(new Map<String, Object>{
            'name' => 'Cfg1', 'sourceName' => 'API1', 'targetObject' => 'Lead__c',
            'isActive' => true, 'description' => 'd',
            'apiSchemaJson' => '{}', 'validationRulesJson' => '{}',
            'endpointUrl' => 'http://x', 'enableDuplicateCheck' => true,
            'version' => 1
        });
        Test.startTest();
        Id configId = IntegrationMappingController.saveSourceConfig(createJson);
        System.assertNotEquals(null, configId);

        // UPDATE via saveSourceConfig (with id)
        String updateJson = JSON.serialize(new Map<String, Object>{
            'id' => String.valueOf(configId),
            'name' => 'Cfg1b', 'sourceName' => 'API1b', 'targetObject' => 'Lead__c',
            'isActive' => false
        });
        IntegrationMappingController.saveSourceConfig(updateJson);

        // Queries
        IntegrationMappingController.getSourceConfigs();
        IntegrationMappingController.getSourceConfigWithRules(configId);

        // Field rules: save, then re-save (exercising upsert + delete-removed)
        String rulesJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'apiFieldName' => 'name', 'apiFieldLabel' => 'Name',
                'sfFieldApiName' => 'First_Name__c',
                'isRequired' => true, 'defaultValue' => null,
                'dataType' => 'Text', 'transformExpression' => null,
                'isActive' => true, 'isStatic' => false, 'sequence' => 1,
                'lookupRule' => new Map<String, Object>{
                    'lookupObject' => 'Lead__c', 'matchField' => 'Id',
                    'returnField' => 'Id', 'failOnNoMatch' => true,
                    'additionalFilter' => null
                }
            },
            new Map<String, Object>{
                'apiFieldName' => 'mobile', 'sfFieldApiName' => 'Primary_Mobile__c',
                'isRequired' => false, 'dataType' => 'Text',
                'isActive' => false, 'isStatic' => true
                // no lookupRule → exercises the no-lookup branch
            }
        });
        IntegrationMappingController.saveFieldRules(configId, rulesJson);

        // Re-save with fewer rules to exercise "delete removed" branch
        String rulesJson2 = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'apiFieldName' => 'name', 'sfFieldApiName' => 'First_Name__c',
                'dataType' => 'Text'
            }
        });
        IntegrationMappingController.saveFieldRules(configId, rulesJson2);

        // Schema helpers
        IntegrationMappingController.getTargetObjectOptions();
        List<IntegrationMappingController.FieldOption> fields =
            IntegrationMappingController.getObjectFields('Lead__c');
        System.assert(fields.size() >= 1);
        IntegrationMappingController.getObjectFields('NoSuchObj__x');

        // DELETE
        IntegrationMappingController.deleteSourceConfig(configId);
        Test.stopTest();
    }

    @isTest
    static void dtos_comparable() {
        IntegrationMappingController.ObjectOption a = new IntegrationMappingController.ObjectOption('A', 'a');
        IntegrationMappingController.ObjectOption b = new IntegrationMappingController.ObjectOption('B', 'b');
        System.assert(a.compareTo(b) < 0);

        IntegrationMappingController.FieldOption fa = new IntegrationMappingController.FieldOption('A', 'a', 'Text', false, null);
        IntegrationMappingController.FieldOption fb = new IntegrationMappingController.FieldOption('B', 'b', 'Text', true, 'Lead__c');
        System.assert(fa.compareTo(fb) < 0);
    }
}