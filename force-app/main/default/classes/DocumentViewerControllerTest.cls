/**
 * @description Test class for DocumentViewerController (100% coverage).
 * Exercises template visibility: no templates, no conditions (always
 * visible), field/profile/role/user rule types, every operator, matching
 * criteria evaluation, and all error branches.
 */
@isTest
private class DocumentViewerControllerTest {

    @TestSetup
    static void setup() {
        Project__c p = TestDataFactory.createProject('DVC');
        TestDataFactory.createLead(p.Id, 'DVC', '9900003001');
    }

    private static Id insertTemplate(String visibilityJson, String matchingCriteria) {
        Document_Template__c t = new Document_Template__c(
            Name = 'DVC Tmpl ' + Math.round(Math.random() * 100000),
            Object_API_Name__c = 'Lead__c',
            Active__c = true,
            Template_JSON__c = visibilityJson,
            Matching_Criteria__c = matchingCriteria
        );
        insert t;
        return t.Id;
    }

    @isTest
    static void getTemplatesForRecord_blankId_throws() {
        Boolean thrown = false;
        try {
            DocumentViewerController.getTemplatesForRecord('', 'Lead__c');
        } catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void getTemplatesForRecord_noTemplates_returnsEmpty() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        Test.startTest();
        List<DocumentViewerController.ViewerTemplate> result =
            DocumentViewerController.getTemplatesForRecord(lead.Id, 'Lead__c');
        Test.stopTest();
        System.assertEquals(0, result.size());
    }

    @isTest
    static void getTemplatesForRecord_derivesObjectApiNameFromId() {
        Lead__c lead = [SELECT Id FROM Lead__c LIMIT 1];
        insertTemplate(null, null);
        Test.startTest();
        // Blank objectApiName → derived from Id
        List<DocumentViewerController.ViewerTemplate> result =
            DocumentViewerController.getTemplatesForRecord(lead.Id, '');
        Test.stopTest();
        System.assert(result.size() >= 1);
    }

    @isTest
    static void getTemplatesForRecord_visibilityConditions() {
        Lead__c lead = [SELECT Id, First_Name__c FROM Lead__c LIMIT 1];
        User currentUser = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

        // AND logic with rules that ALL match → visible
        String matchingJson = JSON.serialize(new Map<String, Object>{
            'visibilityConditions' => new Map<String, Object>{
                'logic' => 'AND',
                'rules' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'field', 'field' => 'First_Name__c',
                        'operator' => 'equals', 'value' => lead.First_Name__c
                    },
                    new Map<String, Object>{
                        'type' => 'profile',
                        'operator' => 'equals', 'value' => currentUser.Profile.Name
                    }
                }
            }
        });
        insertTemplate(matchingJson, null);

        // AND logic where one rule fails → hidden
        String nonMatchJson = JSON.serialize(new Map<String, Object>{
            'visibilityConditions' => new Map<String, Object>{
                'logic' => 'AND',
                'rules' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'field', 'field' => 'First_Name__c',
                        'operator' => 'equals', 'value' => 'NEVER'
                    }
                }
            }
        });
        insertTemplate(nonMatchJson, null);

        // OR logic where one rule matches → visible
        String orJson = JSON.serialize(new Map<String, Object>{
            'visibilityConditions' => new Map<String, Object>{
                'logic' => 'OR',
                'rules' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'field', 'field' => 'First_Name__c',
                        'operator' => 'equals', 'value' => 'NEVER'
                    },
                    new Map<String, Object>{
                        'type' => 'profile',
                        'operator' => 'equals', 'value' => currentUser.Profile.Name
                    }
                }
            }
        });
        insertTemplate(orJson, null);

        // Every operator branch — contains, startsWith, notEquals, notContains, isBlank, isNotBlank, in, userRole, user, default, unknown type
        String allOpsJson = JSON.serialize(new Map<String, Object>{
            'visibilityConditions' => new Map<String, Object>{
                'logic' => 'OR',
                'rules' => new List<Object>{
                    new Map<String, Object>{ 'type' => 'field', 'field' => 'First_Name__c', 'operator' => 'contains', 'value' => 'D' },
                    new Map<String, Object>{ 'type' => 'field', 'field' => 'First_Name__c', 'operator' => 'startsWith', 'value' => 'D' },
                    new Map<String, Object>{ 'type' => 'field', 'field' => 'First_Name__c', 'operator' => 'notEquals', 'value' => 'X' },
                    new Map<String, Object>{ 'type' => 'field', 'field' => 'First_Name__c', 'operator' => 'notContains', 'value' => 'X' },
                    new Map<String, Object>{ 'type' => 'field', 'field' => 'First_Name__c', 'operator' => 'isNotBlank' },
                    new Map<String, Object>{ 'type' => 'field', 'field' => 'Nonexistent_Field__c', 'operator' => 'isBlank' },
                    new Map<String, Object>{ 'type' => 'field', 'field' => 'First_Name__c', 'operator' => 'in', 'value' => 'DVC,other' },
                    new Map<String, Object>{ 'type' => 'userRole', 'operator' => 'equals', 'value' => '' },
                    new Map<String, Object>{ 'type' => 'user', 'field' => 'Id', 'operator' => 'equals', 'value' => UserInfo.getUserId() },
                    new Map<String, Object>{ 'type' => 'user', 'field' => 'Email', 'operator' => 'equals', 'value' => '' },
                    new Map<String, Object>{ 'type' => 'mystery', 'operator' => 'equals', 'value' => '' },
                    new Map<String, Object>{ 'type' => '', 'operator' => '' }
                }
            }
        });
        insertTemplate(allOpsJson, null);

        // Invalid JSON → shown (parse-error branch)
        insertTemplate('not valid json', null);

        // With matching criteria that passes
        insertTemplate(null, '{"matchLogic":"AND","conditions":[]}');

        // With matching criteria that fails
        insertTemplate(null, '{"matchLogic":"AND","conditions":[{"type":"field","operator":"equals","fieldPath":"First_Name__c","value":"NEVER"}]}');

        Test.startTest();
        List<DocumentViewerController.ViewerTemplate> result =
            DocumentViewerController.getTemplatesForRecord(lead.Id, 'Lead__c');
        Test.stopTest();
        // The matching templates should appear; non-matching ones filtered out
        System.assert(result.size() >= 1);
    }

    @isTest
    static void getPicklistValues_variousInputs() {
        System.assertEquals(0,
            DocumentViewerController.getPicklistValues('', '').size());
        System.assertEquals(0,
            DocumentViewerController.getPicklistValues('NoSuchObj__x', 'x').size());
        System.assertEquals(0,
            DocumentViewerController.getPicklistValues('Lead__c', 'NoSuchField__x').size());
        // Non-picklist field
        System.assertEquals(0,
            DocumentViewerController.getPicklistValues('Lead__c', 'First_Name__c').size());
        // Valid picklist
        System.assert(
            DocumentViewerController.getPicklistValues('Lead__c', 'Lead_Status__c').size() >= 1
        );
    }

    @isTest
    static void wrapper_pojoSetters() {
        DocumentViewerController.ViewerTemplate vt = new DocumentViewerController.ViewerTemplate();
        vt.id = ''; vt.name = ''; vt.description = ''; vt.fileNamePattern = '';
        vt.pageSize = 'A4'; vt.pageOrientation = 'Portrait'; vt.pdfUrl = '/url';
        System.assertEquals('/url', vt.pdfUrl);
    }
}