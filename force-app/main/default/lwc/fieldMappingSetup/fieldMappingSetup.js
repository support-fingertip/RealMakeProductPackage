import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getGeneralSetups from '@salesforce/apex/FieldMappingSetupController.getGeneralSetups';
import getGeneralSetupWithMappings from '@salesforce/apex/FieldMappingSetupController.getGeneralSetupWithMappings';
import getLeadFields from '@salesforce/apex/FieldMappingSetupController.getLeadFields';
import saveGeneralSetup from '@salesforce/apex/FieldMappingSetupController.saveGeneralSetup';
import saveFieldMappings from '@salesforce/apex/FieldMappingSetupController.saveFieldMappings';
import deleteGeneralSetup from '@salesforce/apex/FieldMappingSetupController.deleteGeneralSetup';

export default class FieldMappingSetup extends LightningElement {
    @track currentStep = '1';
    @track isLoading = false;
    @track isSaving = false;

    // Step 1: Setup list
    @track generalSetups = [];

    // Step 2: Setup form
    @track selectedSetupId = null;
    @track setupName = '';
    @track pushToSalesType = 'Manual';
    @track leadDuplicationType = '';
    @track setupIsActive = false;
    @track setupDescription = '';

    // Step 2: Field mappings
    @track fieldMappings = [];
    @track leadFields = [];

    _keyCounter = 0;

    pushToSalesTypeOptions = [
        { label: 'Manual', value: 'Manual' },
        { label: 'Automation /On Site-Visit Creation', value: 'Automation /On Site-Visit Creation' },
        { label: 'Automation /On Site-Visit Completion', value: 'Automation /On Site-Visit Completion' }
    ];

    leadDuplicationTypeOptions = [
        { label: 'Mobile Only', value: 'Mobile Only' },
        { label: 'Mobile with Project', value: 'Mobile with Project' },
        { label: 'Mobile with Project & Email with Project', value: 'Mobile with Project & Email with Project' }
    ];

    connectedCallback() {
        this.loadSetups();
        this.loadLeadFields();
    }

    // ===== Computed Properties =====

    get isStep1() { return this.currentStep === '1'; }
    get isStep2() { return this.currentStep === '2'; }
    get isStep3() { return this.currentStep === '3'; }

    get hasSetups() { return this.generalSetups && this.generalSetups.length > 0; }
    get hasMappings() { return this.fieldMappings && this.fieldMappings.length > 0; }
    get mappingCount() { return this.fieldMappings.length; }

    get sourceFieldOptions() {
        return this.leadFields.map(f => ({
            label: f.label + ' (' + f.apiName + ')',
            value: f.apiName
        }));
    }

    get targetFieldOptions() {
        return this.leadFields
            .filter(f => f.isUpdateable)
            .map(f => ({
                label: f.label + ' (' + f.apiName + ')',
                value: f.apiName
            }));
    }

    // ===== Data Loading =====

    loadSetups() {
        this.isLoading = true;
        getGeneralSetups()
            .then(result => {
                this.generalSetups = result.map(s => ({
                    ...s,
                    badgeClass: s.Push_To_Sales_Type__c === 'Manual' ? 'slds-badge' : 'slds-badge slds-theme_success'
                }));
            })
            .catch(error => {
                this.showToast('Error', this.extractErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    loadLeadFields() {
        getLeadFields()
            .then(result => {
                this.leadFields = result;
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load Lead fields: ' + this.extractErrorMessage(error), 'error');
            });
    }

    loadSetupWithMappings(setupId) {
        this.isLoading = true;
        getGeneralSetupWithMappings({ setupId: setupId })
            .then(result => {
                this.selectedSetupId = result.Id;
                this.setupName = result.Name;
                this.pushToSalesType = result.Push_To_Sales_Type__c;
                this.leadDuplicationType = result.Lead_Duplication_Type__c || '';
                this.setupIsActive = result.Is_Active__c;
                this.setupDescription = result.Description__c;

                this.fieldMappings = (result.Field_Mappings__r || []).map((m, index) => ({
                    key: this._generateKey(),
                    id: m.Id,
                    sourceField: m.Primary_Object_Field_value__c,
                    targetField: m.Related_object_field__c,
                    mappingType: m.Mapping_Type__c || 'field',
                    sequence: index + 1,
                    isActive: m.Active__c,
                    isFirst: index === 0,
                    isLast: false,
                    sourceFieldLabel: this._getFieldLabel(m.Primary_Object_Field_value__c),
                    targetFieldLabel: this._getFieldLabel(m.Related_object_field__c)
                }));
                this._refreshMappingBoundaries();

                this.currentStep = '2';
            })
            .catch(error => {
                this.showToast('Error', this.extractErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ===== Step 1 Handlers =====

    handleNewSetup() {
        this.selectedSetupId = null;
        this.setupName = '';
        this.pushToSalesType = 'Manual';
        this.leadDuplicationType = '';
        this.setupIsActive = false;
        this.setupDescription = '';
        this.fieldMappings = [];
        this.currentStep = '2';
    }

    handleSelectSetup(event) {
        const setupId = event.currentTarget.dataset.id;
        this.loadSetupWithMappings(setupId);
    }

    handleEditSetup(event) {
        const setupId = event.currentTarget.dataset.id;
        this.loadSetupWithMappings(setupId);
    }

    handleDeleteSetup(event) {
        const setupId = event.currentTarget.dataset.id;
        const setup = this.generalSetups.find(s => s.Id === setupId);
        const confirmed = confirm('Are you sure you want to delete "' + setup.Name + '" and all its field mappings?');
        if (!confirmed) return;

        this.isLoading = true;
        deleteGeneralSetup({ setupId: setupId })
            .then(() => {
                this.showToast('Success', 'General Setup deleted successfully', 'success');
                this.loadSetups();
            })
            .catch(error => {
                this.showToast('Error', this.extractErrorMessage(error), 'error');
                this.isLoading = false;
            });
    }

    // ===== Step 2 Handlers: Setup Form =====

    handleSetupNameChange(event) {
        this.setupName = event.detail.value;
    }

    handlePushToSalesTypeChange(event) {
        this.pushToSalesType = event.detail.value;
    }

    handleLeadDuplicationTypeChange(event) {
        this.leadDuplicationType = event.detail.value;
    }

    handleDescriptionChange(event) {
        this.setupDescription = event.detail.value;
    }

    handleIsActiveChange(event) {
        this.setupIsActive = event.detail.checked;
    }

    // ===== Step 2 Handlers: Field Mappings =====

    handleAddMapping() {
        const seq = this.fieldMappings.length + 1;
        this.fieldMappings = [
            ...this.fieldMappings,
            {
                key: this._generateKey(),
                id: null,
                sourceField: '',
                targetField: '',
                mappingType: 'field',
                sequence: seq,
                isActive: true,
                isFirst: seq === 1,
                isLast: true,
                sourceFieldLabel: '',
                targetFieldLabel: ''
            }
        ];
        this._refreshMappingBoundaries();
    }

    handleSourceFieldChange(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.detail.value;
        this.fieldMappings = this.fieldMappings.map(m => {
            if (String(m.key) === String(key)) {
                return {
                    ...m,
                    sourceField: value,
                    sourceFieldLabel: this._getFieldLabel(value)
                };
            }
            return m;
        });
    }

    handleTargetFieldChange(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.detail.value;
        this.fieldMappings = this.fieldMappings.map(m => {
            if (String(m.key) === String(key)) {
                return {
                    ...m,
                    targetField: value,
                    targetFieldLabel: this._getFieldLabel(value)
                };
            }
            return m;
        });
    }

    handleMappingActiveChange(event) {
        const key = event.currentTarget.dataset.key;
        const checked = event.detail.checked;
        this.fieldMappings = this.fieldMappings.map(m => {
            if (String(m.key) === String(key)) {
                return { ...m, isActive: checked };
            }
            return m;
        });
    }

    handleRemoveMapping(event) {
        const key = event.currentTarget.dataset.key;
        this.fieldMappings = this.fieldMappings
            .filter(m => String(m.key) !== String(key))
            .map((m, i) => ({ ...m, sequence: i + 1 }));
        this._refreshMappingBoundaries();
    }

    handleMoveUp(event) {
        const key = event.currentTarget.dataset.key;
        const idx = this.fieldMappings.findIndex(m => String(m.key) === String(key));
        if (idx <= 0) return;

        const mappings = [...this.fieldMappings];
        [mappings[idx - 1], mappings[idx]] = [mappings[idx], mappings[idx - 1]];
        this.fieldMappings = mappings.map((m, i) => ({ ...m, sequence: i + 1 }));
        this._refreshMappingBoundaries();
    }

    handleMoveDown(event) {
        const key = event.currentTarget.dataset.key;
        const idx = this.fieldMappings.findIndex(m => String(m.key) === String(key));
        if (idx >= this.fieldMappings.length - 1) return;

        const mappings = [...this.fieldMappings];
        [mappings[idx], mappings[idx + 1]] = [mappings[idx + 1], mappings[idx]];
        this.fieldMappings = mappings.map((m, i) => ({ ...m, sequence: i + 1 }));
        this._refreshMappingBoundaries();
    }

    // ===== Navigation =====

    handleBack() {
        this.currentStep = '1';
        this.loadSetups();
    }

    handleGoToReview() {
        if (!this._validateStep2()) return;
        this.currentStep = '3';
    }

    handleBackToEdit() {
        this.currentStep = '2';
    }

    // ===== Save =====

    handleSave() {
        if (!this._validateStep2()) return;

        this.isSaving = true;
        this.isLoading = true;

        const setupData = {
            id: this.selectedSetupId,
            name: this.setupName,
            pushToSalesType: this.pushToSalesType,
            leadDuplicationType: this.leadDuplicationType,
            isActive: this.setupIsActive,
            description: this.setupDescription
        };

        saveGeneralSetup({ setupData: JSON.stringify(setupData) })
            .then(setupId => {
                this.selectedSetupId = setupId;

                const mappingsPayload = this.fieldMappings.map(m => ({
                    id: m.id,
                    sourceField: m.sourceField,
                    targetField: m.targetField,
                    mappingType: m.mappingType,
                    sequence: m.sequence,
                    isActive: m.isActive
                }));

                return saveFieldMappings({
                    generalSetupId: setupId,
                    mappingsJson: JSON.stringify(mappingsPayload)
                });
            })
            .then(() => {
                this.showToast('Success', 'Configuration saved successfully', 'success');
                this.currentStep = '1';
                this.loadSetups();
            })
            .catch(error => {
                this.showToast('Error', 'Failed to save: ' + this.extractErrorMessage(error), 'error');
            })
            .finally(() => {
                this.isSaving = false;
                this.isLoading = false;
            });
    }

    // ===== Helpers =====

    _generateKey() {
        this._keyCounter++;
        return 'mapping-' + this._keyCounter + '-' + Date.now();
    }

    _getFieldLabel(apiName) {
        if (!apiName) return '';
        const field = this.leadFields.find(f => f.apiName === apiName);
        return field ? field.label + ' (' + apiName + ')' : apiName;
    }

    _refreshMappingBoundaries() {
        const len = this.fieldMappings.length;
        this.fieldMappings = this.fieldMappings.map((m, i) => ({
            ...m,
            isFirst: i === 0,
            isLast: i === len - 1
        }));
    }

    _validateStep2() {
        if (!this.setupName || !this.setupName.trim()) {
            this.showToast('Validation Error', 'Please enter a Setup Name', 'error');
            return false;
        }
        if (!this.pushToSalesType) {
            this.showToast('Validation Error', 'Please select a Push To Sales Type', 'error');
            return false;
        }
        if (!this.leadDuplicationType) {
            this.showToast('Validation Error', 'Please select a Lead Duplication Type', 'error');
            return false;
        }

        for (let mapping of this.fieldMappings) {
            if (!mapping.sourceField || !mapping.targetField) {
                this.showToast('Validation Error', 'All field mappings must have both Source and Target fields selected', 'error');
                return false;
            }
        }

        // Check for duplicate source-target combinations
        const seen = new Set();
        for (let mapping of this.fieldMappings) {
            const combo = mapping.sourceField + '->' + mapping.targetField;
            if (seen.has(combo)) {
                this.showToast('Validation Error', 'Duplicate mapping found: ' + combo, 'error');
                return false;
            }
            seen.add(combo);
        }

        return true;
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unexpected error occurred';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}