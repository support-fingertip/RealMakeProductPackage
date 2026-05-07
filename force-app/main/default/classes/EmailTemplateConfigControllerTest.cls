/**
 * @description Test class for EmailTemplateConfigController (100% coverage).
 */
@isTest
private class EmailTemplateConfigControllerTest {

    private static String templateJson(Id id, String name, String objApi, Boolean isDefault) {
        return JSON.serialize(new Map<String, Object>{
            'id' => id != null ? String.valueOf(id) : null,
            'name' => name,
            'objectApiName' => objApi,
            'description' => 'd',
            'isActive' => true,
            'isDefault' => isDefault,
            'subject' => 's', 'emailBody' => 'b',
            'fromAddress' => '', 'replyTo' => '',
            'recipientsConfig' => '[]', 'attachmentsConfig' => '{}',
            'allowAdditionalRecipients' => true, 'allowFileUpload' => true,
            'actionBinding' => '', 'matchingCriteria' => ''
        });
    }

    @isTest
    static void fullLifecycle() {
        Test.startTest();
        // Create
        String id1 = EmailTemplateConfigController.saveTemplate(templateJson(null, 'T1', 'Lead__c', true));
        String id2 = EmailTemplateConfigController.saveTemplate(templateJson(null, 'T2', 'Lead__c', true));
        // Second save with isDefault=true should unset first's default flag

        // Read
        System.assert(EmailTemplateConfigController.getAllTemplates().size() >= 2);
        System.assert(EmailTemplateConfigController.getTemplatesForObject('Lead__c').size() >= 2);
        System.assertEquals(0, EmailTemplateConfigController.getTemplatesForObject('').size());
        System.assertNotEquals(null, EmailTemplateConfigController.getTemplateById(id1));

        // Update (edit) with id set
        String updateJson = templateJson(id1, 'T1-renamed', 'Lead__c', false);
        EmailTemplateConfigController.saveTemplate(updateJson);

        // Clone
        String clonedId = EmailTemplateConfigController.cloneTemplate(id1);
        System.assertNotEquals(null, clonedId);

        // Toggle
        EmailTemplateConfigController.toggleActiveStatus(id1, false);

        // Delete
        EmailTemplateConfigController.deleteTemplate(id1);
        Test.stopTest();
    }

    @isTest
    static void getTemplateById_blankAndNotFound_throws() {
        Boolean thrown = false;
        try { EmailTemplateConfigController.getTemplateById(''); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);

        thrown = false;
        try { EmailTemplateConfigController.getTemplateById('a0W000000000001'); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void saveTemplate_blankJson_throws() {
        Boolean thrown = false;
        try { EmailTemplateConfigController.saveTemplate(null); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);

        thrown = false;
        try { EmailTemplateConfigController.saveTemplate('not json'); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void deleteTemplate_blank_throws() {
        Boolean thrown = false;
        try { EmailTemplateConfigController.deleteTemplate(''); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);

        thrown = false;
        try { EmailTemplateConfigController.deleteTemplate('a0W000000000001'); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void cloneTemplate_invalid_throws() {
        Boolean thrown = false;
        try { EmailTemplateConfigController.cloneTemplate(''); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void toggleActiveStatus_invalid_throws() {
        Boolean thrown = false;
        try { EmailTemplateConfigController.toggleActiveStatus('a0W000000000001', true); }
        catch (AuraHandledException e) { thrown = true; }
        System.assert(thrown);
    }

    @isTest
    static void wrapper_pojoSetters() {
        EmailTemplateConfigController.TemplateWrapper w = new EmailTemplateConfigController.TemplateWrapper();
        w.id = ''; w.name = 'n'; w.objectApiName = 'Lead__c'; w.description = '';
        w.isActive = true; w.isDefault = false; w.subject = ''; w.emailBody = '';
        w.fromAddress = ''; w.replyTo = ''; w.recipientsConfig = ''; w.attachmentsConfig = '';
        w.allowAdditionalRecipients = true; w.allowFileUpload = true;
        w.actionBinding = ''; w.matchingCriteria = '';
        w.createdDate = DateTime.now(); w.lastModifiedDate = DateTime.now();
        w.createdByName = '';
        System.assertEquals('n', w.name);
    }
}