import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProjects from '@salesforce/apex/FormulaBuilderController.getProjects';
import getTemplates from '@salesforce/apex/FormulaBuilderController.getTemplates';
import getTemplateWithSteps from '@salesforce/apex/FormulaBuilderController.getTemplateWithSteps';
import getAvailableObjects from '@salesforce/apex/FormulaBuilderController.getAvailableObjects';
import getLookupFields from '@salesforce/apex/FormulaBuilderController.getLookupFields';
import getFieldsForObject from '@salesforce/apex/FormulaBuilderController.getFieldsForObject';
import getCombinedFieldsForStep from '@salesforce/apex/FormulaBuilderController.getCombinedFieldsForStep';
import saveTemplate from '@salesforce/apex/FormulaBuilderController.saveTemplate';
import saveSteps from '@salesforce/apex/FormulaBuilderController.saveSteps';
import deleteTemplate from '@salesforce/apex/FormulaBuilderController.deleteTemplate';
import toggleTemplateStatus from '@salesforce/apex/FormulaBuilderController.toggleTemplateStatus';
import testCalculation from '@salesforce/apex/FormulaBuilderController.testCalculation';
import getRecordsForObject from '@salesforce/apex/FormulaBuilderController.getRecordsForObject';
import getRichTextFields from '@salesforce/apex/FormulaBuilderController.getRichTextFields';

export default class FormulaBuilder extends LightningElement {
    @api recordId;
    @track selectedProjectId;
    @track projectOptions = [];
    @track templates = [];
    @track showTemplateBuilder = false;
    @track showStepBuilder = false;
    @track currentTemplate = {};
    @track currentStep = {};
    @track objectOptions = [];
    @track lookupFieldOptions = [];
    @track availableFieldsForStep = [];
    @track bookingFieldOptionsForStep = [];
    @track sourceRecordOptions = [];
    @track selectedTestUnitId;
    @track testResults;
    @track existingVariables = [];
    @track richTextFieldOptions = [];
    @track isLoading = false;

    modalTitle = 'New Template';

    get isOnRecordPage() {
        return this.recordId != null && this.recordId != undefined && this.recordId != '';
    }

    get showLookupField() {
        return this.currentTemplate.sourceObject && this.currentTemplate.targetObject;
    }

    get hasSteps() {
        return this.currentTemplate.steps && this.currentTemplate.steps.length > 0;
    }

    get canTest() {
        return this.currentTemplate.sourceObject && this.hasSteps;
    }

    get testButtonDisabled() {
        return !this.selectedTestUnitId || !this.hasSteps;
    }

    connectedCallback() {
        this.isLoading = true;
        if (this.recordId) {
            this.selectedProjectId = this.recordId;
            this.loadTemplates();
        } else {
            this.loadProjects();
        }
        this.loadAvailableObjects();
    }

    loadProjects() {
        getProjects()
            .then(result => {
                this.projectOptions = result.map(proj => ({
                    label: proj.Name,
                    value: proj.Id
                }));
            })
            .catch(error => {
                this.showToast('Error', 'Error loading projects', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    loadAvailableObjects() {
        getAvailableObjects()
            .then(result => {
                this.objectOptions = result.map(obj => ({
                    label: obj.label,
                    value: obj.value
                }));
            })
            .catch(error => {
                this.showToast('Error', 'Error loading objects', 'error');
            });
    }

    handleProjectChange(event) {
        this.selectedProjectId = event.detail.value;
        this.loadTemplates();
    }

    loadTemplates() {
        if (!this.selectedProjectId) return;

        this.isLoading = true;
        getTemplates({ projectId: this.selectedProjectId })
            .then(result => {
                this.templates = result.map(template => ({
                    ...template,
                    statusLabel: template.Is_Active__c ? 'Active' : 'Inactive',
                    badgeClass: template.Is_Active__c ? 'slds-theme_success' : '',
                    toggleLabel: template.Is_Active__c ? 'Deactivate' : 'Activate',
                    toggleVariant: template.Is_Active__c ? 'neutral' : 'brand'
                }));
            })
            .catch(error => {
                this.showToast('Error', 'Error loading templates', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleNewTemplate() {
        this.modalTitle = 'New Template';
        this.currentTemplate = {
            templateName: '',
            description: '',
            projectId: this.selectedProjectId,
            sourceObject: 'Unit__c',
            targetObject: 'Booking__c',
            sourceLookupField: '',
            calculationDetailField: '',
            isActive: false,
            steps: []
        };
        this.testResults = null;
        this.selectedTestUnitId = null;
        this.richTextFieldOptions = [];

        // Load fields immediately for default objects
        this.loadLookupFields();
        this.loadFieldsForObjects();
        this.loadRichTextFields();
        this.loadSourceRecords();

        this.showTemplateBuilder = true;
    }

    handleEditTemplate(event) {
        const templateId = event.currentTarget.dataset.id;
        this.modalTitle = 'Edit Template';

        getTemplateWithSteps({ templateId: templateId })
            .then(result => {
                this.currentTemplate = {
                    Id: result.Id,
                    templateName: result.Template_Name__c,
                    description: result.Description__c,
                    projectId: result.Project__c,
                    sourceObject: result.Source_Object_API_Name__c,
                    targetObject: result.Target_Object_API_Name__c,
                    sourceLookupField: result.Source_Lookup_Field__c,
                    calculationDetailField: result.Calculation_Detail_Field__c || '',
                    isActive: result.Is_Active__c,
                    steps: result.Calculation_Steps__r ? result.Calculation_Steps__r.map(step => ({
                        id: step.Id,
                        stepNumber: step.Step_Number__c,
                        stepLabel: step.Step_Label__c,
                        variableName: step.Variable_Name__c,
                        formula: step.Formula_Expression__c,
                        storeInField: step.Store_In_Field__c,
                        description: step.Description__c
                    })) : []
                };
                this.updateExistingVariables();
                this.loadLookupFields();
                this.loadFieldsForObjects();
                this.loadSourceRecords();
                this.loadRichTextFields();
                this.testResults = null;
                this.selectedTestUnitId = null;
                this.showTemplateBuilder = true;
            })
            .catch(error => {
                this.showToast('Error', 'Error loading template', 'error');
            });
    }

    handleSourceObjectChange(event) {
        this.currentTemplate.sourceObject = event.detail.value;
        this.currentTemplate.sourceLookupField = '';
        this.loadLookupFields();
        this.loadFieldsForObjects();
        this.loadSourceRecords();
    }

    handleTargetObjectChange(event) {
        this.currentTemplate.targetObject = event.detail.value;
        this.currentTemplate.sourceLookupField = '';
        this.currentTemplate.calculationDetailField = '';
        this.loadLookupFields();
        this.loadFieldsForObjects();
        this.loadRichTextFields();
    }

    handleLookupFieldChange(event) {
        this.currentTemplate.sourceLookupField = event.detail.value;
    }

    handleCalculationDetailFieldChange(event) {
        this.currentTemplate.calculationDetailField = event.detail.value;
    }

    loadLookupFields() {
        if (!this.currentTemplate.sourceObject || !this.currentTemplate.targetObject) return;

        getLookupFields({
            targetObjectAPI: this.currentTemplate.targetObject,
            sourceObjectAPI: this.currentTemplate.sourceObject
        })
            .then(result => {
                this.lookupFieldOptions = result.map(field => ({
                    label: field.label,
                    value: field.value
                }));
                if (this.lookupFieldOptions.length > 0 && !this.currentTemplate.sourceLookupField) {
                    this.currentTemplate.sourceLookupField = this.lookupFieldOptions[0].value;
                }
            })
            .catch(error => {
                this.showToast('Error', 'Error loading lookup fields', 'error');
            });
    }

    loadRichTextFields() {
        if (!this.currentTemplate.targetObject) {
            this.richTextFieldOptions = [];
            return;
        }

        getRichTextFields({ objectAPI: this.currentTemplate.targetObject })
            .then(result => {
                this.richTextFieldOptions = [
                    { label: '-- None --', value: '' },
                    ...result.map(field => ({
                        label: field.label,
                        value: field.value
                    }))
                ];
            })
            .catch(error => {
                this.richTextFieldOptions = [];
                console.error('Error loading rich text fields:', error);
            });
    }

    loadFieldsForObjects() {
        if (!this.currentTemplate.sourceObject || !this.currentTemplate.targetObject) return;

        getCombinedFieldsForStep({
            sourceObjectAPI: this.currentTemplate.sourceObject,
            targetObjectAPI: this.currentTemplate.targetObject
        })
            .then(result => {
                this.availableFieldsForStep = result.sourceFields.map(field => ({
                    label: field.label,
                    value: field.value
                }));

                this.bookingFieldOptionsForStep = result.targetFields
                    .filter(f => f.source === 'target')
                    .map(field => ({
                        label: field.label.replace('🟢 ', ''),
                        value: field.value
                    }));
            })
            .catch(error => {
                this.showToast('Error', 'Error loading fields', 'error');
            });
    }

    loadSourceRecords() {
        if (!this.currentTemplate.sourceObject || !this.selectedProjectId) return;

        getRecordsForObject({
            objectAPI: this.currentTemplate.sourceObject,
            projectId: this.selectedProjectId
        })
            .then(result => {
                this.sourceRecordOptions = result.map(rec => ({
                    label: rec.Name,
                    value: rec.Id
                }));
            })
            .catch(error => {
                this.showToast('Error', 'Error loading records', 'error');
            });
    }

    handleAddStep() {
        if (this.availableFieldsForStep.length === 0) {
            this.loadFieldsForObjects();
        }

        this.currentStep = {
            id: 'new_' + Date.now(),
            stepNumber: (this.currentTemplate.steps || []).length + 1,
            stepLabel: '',
            variableName: '',
            formula: '',
            storeInField: '',
            description: ''
        };
        this.showStepBuilder = true;
    }

    handleDeleteTemplate(event) {
        const templateId = event.currentTarget.dataset.id;
        if(confirm('Are you sure you want to delete this template?')) {
            deleteTemplate({ templateId: templateId })
                .then(() => {
                    this.showToast('Success', 'Template deleted successfully', 'success');
                    this.loadTemplates();
                })
                .catch(error => {
                    this.showToast('Error', 'Error deleting template', 'error');
                });
        }
    }

    handleToggleStatus(event) {
        const templateId = event.currentTarget.dataset.id;
        const template = this.templates.find(t => t.Id === templateId);
        const newStatus = !template.Is_Active__c;

        toggleTemplateStatus({ templateId: templateId, isActive: newStatus })
            .then(() => {
                this.showToast('Success', 'Template status updated', 'success');
                this.loadTemplates();
            })
            .catch(error => {
                this.showToast('Error', 'Error updating status', 'error');
            });
    }

    handleTemplateNameChange(event) {
        this.currentTemplate.templateName = event.detail.value;
    }

    handleDescriptionChange(event) {
        this.currentTemplate.description = event.detail.value;
    }

    handleEditStep(event) {
        const stepId = event.currentTarget.dataset.id;
        this.currentStep = { ...this.currentTemplate.steps.find(s => s.id === stepId) };
        this.showStepBuilder = true;
    }

    handleDeleteStep(event) {
        const stepId = event.currentTarget.dataset.id;
        this.currentTemplate.steps = this.currentTemplate.steps.filter(s => s.id !== stepId);
        this.renumberSteps();
        this.updateExistingVariables();
    }

    handleStepSave(event) {
        const step = event.detail;
        const existingIndex = this.currentTemplate.steps.findIndex(s => s.id === step.id);

        if(existingIndex >= 0) {
            this.currentTemplate.steps[existingIndex] = step;
        } else {
            this.currentTemplate.steps.push(step);
        }

        this.renumberSteps();
        this.updateExistingVariables();
        this.showStepBuilder = false;
    }

    handleStepCancel() {
        this.showStepBuilder = false;
    }

    renumberSteps() {
        this.currentTemplate.steps.forEach((step, index) => {
            step.stepNumber = index + 1;
        });
    }

    updateExistingVariables() {
        this.existingVariables = this.currentTemplate.steps
            .filter(s => s.variableName)
            .map(s => s.variableName);
    }

    handleSaveTemplate() {
        if(!this.currentTemplate.templateName) {
            this.showToast('Error', 'Template name is required', 'error');
            return;
        }
        if(!this.currentTemplate.sourceObject || !this.currentTemplate.targetObject) {
            this.showToast('Error', 'Source and Target objects are required', 'error');
            return;
        }
        if(!this.currentTemplate.sourceLookupField) {
            this.showToast('Error', 'Source lookup field is required', 'error');
            return;
        }

        const templateData = JSON.stringify({
            Id: this.currentTemplate.Id,
            templateName: this.currentTemplate.templateName,
            description: this.currentTemplate.description,
            projectId: this.currentTemplate.projectId,
            sourceObject: this.currentTemplate.sourceObject,
            targetObject: this.currentTemplate.targetObject,
            sourceLookupField: this.currentTemplate.sourceLookupField,
            calculationDetailField: this.currentTemplate.calculationDetailField || '',
            isActive: this.currentTemplate.isActive
        });

        saveTemplate({ templateData: templateData })
            .then(templateId => {
                const stepsData = JSON.stringify(this.currentTemplate.steps || []);
                return saveSteps({ templateId: templateId, stepsData: stepsData });
            })
            .then(() => {
                this.showToast('Success', 'Template saved successfully', 'success');
                this.showTemplateBuilder = false;
                this.loadTemplates();
            })
            .catch(error => {
                this.showToast('Error', 'Error saving template: ' + (error.body ? error.body.message : error.message), 'error');
            });
    }

    handleCancelTemplate() {
        this.showTemplateBuilder = false;
    }

    handleTestRecordChange(event) {
        this.selectedTestUnitId = event.detail.value;
    }

    handleRunTest() {
        if(!this.currentTemplate.Id) {
            this.showToast('Info', 'Please save the template before testing', 'info');
            return;
        }

        testCalculation({
            templateId: this.currentTemplate.Id,
            unitId: this.selectedTestUnitId
        })
            .then(result => {
                if(result.success) {
                    this.testResults = result;
                    this.showToast('Success', 'Test calculation completed', 'success');
                } else {
                    this.showToast('Error', 'Test failed: ' + result.error, 'error');
                }
            })
            .catch(error => {
                this.showToast('Error', 'Error running test', 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}