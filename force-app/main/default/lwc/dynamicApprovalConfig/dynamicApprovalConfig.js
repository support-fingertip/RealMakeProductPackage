import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getAvailableObjects from '@salesforce/apex/DynamicApprovalController.getAvailableObjects';
import getConfigurationsForObject from '@salesforce/apex/DynamicApprovalController.getConfigurationsForObject';
import discoverUserLookupFields from '@salesforce/apex/DynamicApprovalController.discoverUserLookupFields';
import discoverPicklistFields from '@salesforce/apex/DynamicApprovalController.discoverPicklistFields';
import getPicklistValues from '@salesforce/apex/DynamicApprovalController.getPicklistValues';
import getPrerequisiteOptions from '@salesforce/apex/DynamicApprovalController.getPrerequisiteOptions';
import getEmailTemplates from '@salesforce/apex/DynamicApprovalController.getEmailTemplates';
import getEmailConfigTemplates from '@salesforce/apex/DynamicApprovalController.getEmailConfigTemplates';
import saveConfiguration from '@salesforce/apex/DynamicApprovalController.saveConfiguration';
import deleteConfiguration from '@salesforce/apex/DynamicApprovalController.deleteConfiguration';
import getObjectFields from '@salesforce/apex/DynamicApprovalController.getObjectFields';

export default class DynamicApprovalConfig extends LightningElement {
    
    // ==================== TRACKED PROPERTIES ====================
    
    @track isLoading = true;
    @track objectOptions = [];
    @track selectedObject = '';
    @track selectedObjectLabel = '';
    @track allObjectFields = [];
    
    @track configurations = [];
    @track showConfigList = true;
    @track showConfigForm = false;
    
    @track isEditMode = false;
    @track currentConfigId = null;
    
    // Configuration field values
    @track configProcessLabel = '';
    @track configProcessType = '';
    @track configSequenceOrder = null;
    @track configApprovalProcessName = '';
    @track configIsActive = false;
    @track configStatusFieldName = '';
    @track configApprovedValue = 'Approved';
    @track configRejectedValue = 'Rejected';
    @track configPendingValue = 'Pending';
    @track configPrerequisiteType = '';
    @track configPrerequisiteValue = '';
    @track configStepsJson = '';
    @track configOnApprovalJson = '';
    @track configOnRejectionJson = '';
    @track configRequiredFields = [];
    @track configMatchingCriteria = '';
    @track selectedRequiredField = '';
    @track requiredFieldOptions = [];

    // Metadata options
    @track userLookupOptions = [];
    @track picklistFieldOptions = [];
    @track statusPicklistValues = [];
    @track prerequisiteOptions = [];
    @track emailTemplates = [];
    @track emailConfigTemplates = [];
    
    // ==================== STEP WIZARD ====================

    @track currentStep = 0;
    totalSteps = 8;

    get currentStepValue() {
        return String(this.currentStep);
    }

    get isStep0() { return this.currentStep === 0; }
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get isStep6() { return this.currentStep === 6; }
    get isStep7() { return this.currentStep === 7; }

    get isFirstStep() { return this.currentStep === 0; }
    get isLastStep() { return this.currentStep === this.totalSteps - 1; }

    // ==================== GETTERS ====================

    get hasConfigurations() {
        return this.configurations && this.configurations.length > 0;
    }

    get formTitle() {
        if (this.isEditMode) {
            return 'Edit Configuration';
        }
        return 'New Configuration';
    }

    get simpleUserLookupOptions() {
        var options = [];
        
        for (var i = 0; i < this.userLookupOptions.length; i++) {
            var opt = this.userLookupOptions[i];
            if (opt.level === 0) {
                options.push(opt);
            }
        }
        
        return options;
    }
    
    // ==================== LIFECYCLE ====================
    
    connectedCallback() {
        this.loadObjects();
    }

    @api
    refresh() {
        if (this.selectedObject) {
            this.loadConfigurationsAndMetadata();
        } else {
            this.loadObjects();
        }
    }

    // ==================== DATA LOADING METHODS ====================
    
    async loadObjects() {
        this.isLoading = true;
        
        try {
            var objects = await getAvailableObjects();
            var options = [];
            
            for (var i = 0; i < objects.length; i++) {
                options.push({
                    label: objects[i].label,
                    value: objects[i].value
                });
            }
            
            this.objectOptions = options;
            
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    async loadConfigurationsAndMetadata() {
    this.isLoading = true;
    try {
        // Load configurations
        var configs = await getConfigurationsForObject({ 
            objectApiName: this.selectedObject 
        });
        this.configurations = configs || [];
        
        // Load user lookup fields
        var userLookups = await discoverUserLookupFields({ 
            objectApiName: this.selectedObject 
        });
        this.userLookupOptions = this.buildUserLookupOptions(userLookups);
        
        // Load picklist fields
        var picklistFields = await discoverPicklistFields({ 
            objectApiName: this.selectedObject 
        });
        this.picklistFieldOptions = this.buildPicklistFieldOptions(picklistFields);
        
        // Load email templates
        var emailTpls = await getEmailTemplates();
        this.emailTemplates = this.buildEmailTemplateOptions(emailTpls);

        // Load email config templates
        var emailConfigs = await getEmailConfigTemplates();
        this.emailConfigTemplates = this.buildEmailTemplateOptions(emailConfigs);
        
        // Load prerequisite options
        var prereqOpts = await getPrerequisiteOptions({ 
            objectApiName: this.selectedObject, 
            currentConfigId: null 
        });
        this.prerequisiteOptions = this.buildPrerequisiteOptions(prereqOpts);
        
        // NEW: Load all object fields for merge field picker
        var objectFields = await getObjectFields({ 
            objectApiName: this.selectedObject 
        });
        this.allObjectFields = this.buildAllObjectFieldOptions(objectFields);
        this.requiredFieldOptions = (objectFields || []).map(f => ({
            label: f.label + ' (' + f.value + ')',
            value: f.value
        }));

    } catch (error) {
        this.showToast('Error', this.getErrorMessage(error), 'error');
    } finally {
        this.isLoading = false;
    }
}

    buildAllObjectFieldOptions(fields) {
    var options = [];
    var i;
    var field;
    
    if (fields && fields.length > 0) {
        for (i = 0; i < fields.length; i++) {
            field = fields[i];
            options.push({
                label: field.label,
                value: field.value
            });
        }
    }
    
    return options;
}
    
    async loadStatusPicklistValues(fieldName) {
        try {
            var values = await getPicklistValues({
                objectApiName: this.selectedObject,
                fieldApiName: fieldName
            });
            
            var options = [];
            
            for (var i = 0; i < values.length; i++) {
                options.push({
                    label: values[i].label,
                    value: values[i].value
                });
            }
            
            this.statusPicklistValues = options;
            
        } catch (error) {
            this.statusPicklistValues = [];
            console.error('Error loading picklist values:', error);
        }
    }
    
    async loadPrerequisiteOptionsForEdit() {
        try {
            var prereqOpts = await getPrerequisiteOptions({ 
                objectApiName: this.selectedObject, 
                currentConfigId: this.currentConfigId
            });
            this.prerequisiteOptions = this.buildPrerequisiteOptions(prereqOpts);
        } catch (error) {
            console.error('Error loading prerequisites:', error);
        }
    }
    
    // ==================== OPTION BUILDER METHODS ====================
    
    buildUserLookupOptions(userLookups) {
        var options = [];
        
        if (userLookups) {
            for (var i = 0; i < userLookups.length; i++) {
                options.push({
                    label: userLookups[i].label,
                    value: userLookups[i].value,
                    level: userLookups[i].level
                });
            }
        }
        
        return options;
    }
    
    buildPicklistFieldOptions(picklistFields) {
        var options = [];
        
        if (picklistFields) {
            for (var i = 0; i < picklistFields.length; i++) {
                options.push({
                    label: picklistFields[i].label,
                    value: picklistFields[i].value
                });
            }
        }
        
        return options;
    }
    
    buildEmailTemplateOptions(emailTpls) {
        var options = [];
        
        if (emailTpls) {
            for (var i = 0; i < emailTpls.length; i++) {
                options.push({
                    label: emailTpls[i].label,
                    value: emailTpls[i].value
                });
            }
        }
        
        return options;
    }
    
    buildPrerequisiteOptions(prereqOpts) {
        var options = [];
        
        // Add empty option
        options.push({
            label: '-- None --',
            value: ''
        });
        
        if (prereqOpts) {
            for (var i = 0; i < prereqOpts.length; i++) {
                if (prereqOpts[i].value) {
                    options.push({
                        label: prereqOpts[i].label,
                        value: prereqOpts[i].value
                    });
                }
            }
        }
        
        return options;
    }
    
    // ==================== EVENT HANDLERS - OBJECT SELECTION ====================
    
    async handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.selectedObjectLabel = this.findObjectLabel(this.selectedObject);
        
        this.showConfigForm = false;
        this.showConfigList = true;
        
        await this.loadConfigurationsAndMetadata();
    }
    
    findObjectLabel(objectValue) {
        for (var i = 0; i < this.objectOptions.length; i++) {
            if (this.objectOptions[i].value === objectValue) {
                return this.objectOptions[i].label;
            }
        }
        return objectValue;
    }
    
    // ==================== EVENT HANDLERS - ROW ACTIONS ====================

    handleEditRow(event) {
        var configId = event.currentTarget.dataset.id;
        var row = this.configurations.find(c => c.Id === configId);
        if (row) {
            this.handleEdit(row);
        }
    }

    handleDeleteRow(event) {
        var configId = event.currentTarget.dataset.id;
        var row = this.configurations.find(c => c.Id === configId);
        if (row) {
            this.handleDelete(row);
        }
    }
    
    // ==================== EVENT HANDLERS - CREATE NEW ====================
    
    handleCreateNew() {
        this.resetConfigForm();

        this.currentConfigId = null;
        this.isEditMode = false;
        this.currentStep = 0;
        this.showConfigList = false;
        this.showConfigForm = true;
    }
    
    // ==================== EVENT HANDLERS - EDIT ====================
    
    async handleEdit(row) {
        this.currentConfigId = row.Id;
        this.isEditMode = true;
        
        // Populate form fields
        this.configProcessLabel = row.Process_Label__c || '';
        this.configProcessType = row.Process_Type__c || '';
        this.configSequenceOrder = row.Sequence_Order__c;
        this.configApprovalProcessName = row.Approval_Process_API_Name__c || '';
        this.configIsActive = row.Is_Active__c || false;
        this.configStatusFieldName = row.Status_Field_API_Name__c || '';
        this.configApprovedValue = row.Approved_Status_Value__c || 'Approved';
        this.configRejectedValue = row.Rejected_Status_Value__c || 'Rejected';
        this.configPendingValue = row.Pending_Status_Value__c || 'Pending';
        this.configPrerequisiteType = row.Prerequisite_Process_Type__c || '';
        this.configPrerequisiteValue = row.Prerequisite_Status_Value__c || '';
        this.configStepsJson = row.Steps_JSON__c || this.getEmptyStepsJson();
        this.configOnApprovalJson = row.On_Approval_JSON__c || this.getEmptyActionsJson();
        this.configOnRejectionJson = row.On_Rejection_JSON__c || this.getEmptyActionsJson();
        this.configMatchingCriteria = row.Matching_Criteria__c || '';

        // Parse required fields
        try {
            this.configRequiredFields = row.Required_Fields_JSON__c
                ? JSON.parse(row.Required_Fields_JSON__c) : [];
        } catch (e) {
            this.configRequiredFields = [];
        }

        this.showConfigList = false;
        this.showConfigForm = true;
        
        // Load status picklist values if status field is set
        if (this.configStatusFieldName) {
            await this.loadStatusPicklistValues(this.configStatusFieldName);
        } else {
            this.statusPicklistValues = [];
        }
        
        // Load prerequisite options excluding current config
        await this.loadPrerequisiteOptionsForEdit();
    }
    
    // ==================== EVENT HANDLERS - DELETE ====================
    
    async handleDelete(row) {
        var confirmDelete = confirm('Are you sure you want to delete this configuration?');
        
        if (! confirmDelete) {
            return;
        }
        
        this.isLoading = true;
        
        try {
            await deleteConfiguration({ configId: row.Id });
            this.showToast('Success', 'Configuration deleted successfully', 'success');
            await this.loadConfigurationsAndMetadata();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // ==================== EVENT HANDLERS - NAVIGATION ====================

    handleBackToList() {
        this.showConfigForm = false;
        this.showConfigList = true;
        this.currentStep = 0;
        this.resetConfigForm();
    }

    handleNextStep() {
        if (!this.validateCurrentStep()) {
            return;
        }
        if (this.currentStep < this.totalSteps - 1) {
            this.currentStep = this.currentStep + 1;
        }
    }

    handlePreviousStep() {
        if (this.currentStep > 0) {
            this.currentStep = this.currentStep - 1;
        }
    }

    validateCurrentStep() {
        if (this.currentStep === 0) {
            if (!this.configProcessLabel) {
                this.showToast('Error', 'Process Label is required before proceeding', 'error');
                return false;
            }
            if (!this.configProcessType) {
                this.showToast('Error', 'Process Type is required before proceeding', 'error');
                return false;
            }
        }

        if (this.currentStep === 1) {
            if (this.configStatusFieldName) {
                if (!this.configPendingValue) {
                    this.showToast('Error', 'Pending Status Value is required when a Status Field is configured', 'error');
                    return false;
                }
                if (!this.configApprovedValue) {
                    this.showToast('Error', 'Approved Status Value is required when a Status Field is configured', 'error');
                    return false;
                }
                if (!this.configRejectedValue) {
                    this.showToast('Error', 'Rejected Status Value is required when a Status Field is configured', 'error');
                    return false;
                }
            }
        }

        if (this.currentStep === 2) {
            if (this.configPrerequisiteType && !this.configPrerequisiteValue) {
                this.showToast('Error', 'Prerequisite Status Value is required when a Prerequisite Process is selected', 'error');
                return false;
            }
        }

        if (this.currentStep === 3) {
            try {
                var stepsData = JSON.parse(this.configStepsJson || '{}');
                if (!stepsData.steps || stepsData.steps.length === 0) {
                    this.showToast('Error', 'At least one approval step is required before proceeding', 'error');
                    return false;
                }
            } catch (e) {
                this.showToast('Error', 'Invalid steps configuration', 'error');
                return false;
            }
        }

        return true;
    }
    
    // ==================== EVENT HANDLERS - BASIC INFO FIELDS ====================
    
    handleProcessLabelChange(event) {
        this.configProcessLabel = event.target.value;
    }
    
    handleProcessTypeChange(event) {
        this.configProcessType = event.target.value;
    }
    
    handleSequenceOrderChange(event) {
        this.configSequenceOrder = event.target.value;
    }
    
    handleApprovalProcessNameChange(event) {
        this.configApprovalProcessName = event.target.value;
    }
    
    handleIsActiveChange(event) {
        this.configIsActive = event.target.checked;
    }

    handleMatchingCriteriaChange(event) {
        this.configMatchingCriteria = event.detail.criteriaJson;
    }

    // ==================== EVENT HANDLERS - STATUS TRACKING ====================
    
    async handleStatusFieldChange(event) {
        this.configStatusFieldName = event.detail.value;
        
        if (this.configStatusFieldName) {
            await this.loadStatusPicklistValues(this.configStatusFieldName);
        } else {
            this.statusPicklistValues = [];
        }
    }
    
    handlePendingValueChange(event) {
        this.configPendingValue = event.detail.value;
    }
    
    handleApprovedValueChange(event) {
        this.configApprovedValue = event.detail.value;
    }
    
    handleRejectedValueChange(event) {
        this.configRejectedValue = event.detail.value;
    }
    
    // ==================== EVENT HANDLERS - PREREQUISITES ====================
    
    handlePrerequisiteTypeChange(event) {
        this.configPrerequisiteType = event.detail.value;
        
        if (! this.configPrerequisiteType) {
            this.configPrerequisiteValue = '';
        }
    }
    
    handlePrerequisiteValueChange(event) {
        this.configPrerequisiteValue = event.target.value;
    }
    
    // ==================== EVENT HANDLERS - CHILD COMPONENTS ====================
    
    handleStepsChange(event) {
        this.configStepsJson = event.detail.stepsJson;
    }
    
    handleApprovalActionChange(event) {
        this.configOnApprovalJson = event.detail.actionJson;
    }
    
    handleRejectionActionChange(event) {
        this.configOnRejectionJson = event.detail.actionJson;
    }
    
    // ==================== EVENT HANDLERS - SAVE ====================
    
    async handleSave() {
        // Validate required fields
        if (!this.configProcessLabel) {
            this.showToast('Error', 'Process Label is required', 'error');
            return;
        }

        if (!this.configProcessType) {
            this.showToast('Error', 'Process Type is required', 'error');
            return;
        }

        // Validate status field values if status field is configured
        if (this.configStatusFieldName) {
            if (!this.configPendingValue) {
                this.showToast('Error', 'Pending Status Value is required when a Status Field is configured', 'error');
                return;
            }
            if (!this.configApprovedValue) {
                this.showToast('Error', 'Approved Status Value is required when a Status Field is configured', 'error');
                return;
            }
            if (!this.configRejectedValue) {
                this.showToast('Error', 'Rejected Status Value is required when a Status Field is configured', 'error');
                return;
            }
        }

        // Validate prerequisite value if prerequisite type is selected
        if (this.configPrerequisiteType && !this.configPrerequisiteValue) {
            this.showToast('Error', 'Prerequisite Status Value is required when a Prerequisite Process is selected', 'error');
            return;
        }

        // Validate at least one approval step exists
        try {
            var stepsData = JSON.parse(this.configStepsJson || '{}');
            if (!stepsData.steps || stepsData.steps.length === 0) {
                this.showToast('Error', 'At least one approval step is required', 'error');
                return;
            }
        } catch (e) {
            this.showToast('Error', 'Invalid steps configuration', 'error');
            return;
        }

        // Build configuration object
        var config = {
            Object_API_Name__c: this.selectedObject,
            Process_Label__c: this.configProcessLabel,
            Process_Type__c: this.configProcessType,
            Sequence_Order__c: this.configSequenceOrder,
            Approval_Process_API_Name__c: this.configApprovalProcessName,
            Is_Active__c: this.configIsActive,
            Status_Field_API_Name__c:  this.configStatusFieldName,
            Approved_Status_Value__c: this.configApprovedValue,
            Rejected_Status_Value__c: this.configRejectedValue,
            Pending_Status_Value__c:  this.configPendingValue,
            Prerequisite_Process_Type__c: this.configPrerequisiteType,
            Prerequisite_Status_Value__c: this.configPrerequisiteValue,
            Steps_JSON__c: this.configStepsJson,
            On_Approval_JSON__c: this.configOnApprovalJson,
            On_Rejection_JSON__c:  this.configOnRejectionJson,
            Required_Fields_JSON__c: JSON.stringify(this.configRequiredFields || []),
            Matching_Criteria__c: this.configMatchingCriteria || null
        };

        // Add Id if editing
        if (this.currentConfigId) {
            config.Id = this.currentConfigId;
        }
        
        this.isLoading = true;
        
        try {
            var configJson = JSON.stringify(config);
            await saveConfiguration({ configJson:  configJson });
            
            this.showToast('Success', 'Configuration saved successfully', 'success');
            
            this.showConfigForm = false;
            this.showConfigList = true;
            this.resetConfigForm();
            
            await this.loadConfigurationsAndMetadata();
            
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    // ==================== REQUIRED FIELDS ====================

    get hasRequiredFields() {
        return this.configRequiredFields && this.configRequiredFields.length > 0;
    }

    get addRequiredFieldDisabled() {
        return !this.selectedRequiredField;
    }

    handleRequiredFieldSelect(event) {
        this.selectedRequiredField = event.detail.value;
    }

    handleAddRequiredField() {
        if (!this.selectedRequiredField) return;
        // Check duplicate
        const exists = this.configRequiredFields.find(f => f.apiName === this.selectedRequiredField);
        if (exists) {
            this.showToast('Warning', 'This field is already added', 'warning');
            return;
        }
        // Find label from requiredFieldOptions
        const opt = this.requiredFieldOptions.find(o => o.value === this.selectedRequiredField);
        const label = opt ? opt.label.split(' (')[0] : this.selectedRequiredField;
        this.configRequiredFields = [
            ...this.configRequiredFields,
            { apiName: this.selectedRequiredField, label: label }
        ];
        this.selectedRequiredField = '';
    }

    handleRemoveRequiredField(event) {
        const apiName = event.currentTarget.dataset.apiName;
        this.configRequiredFields = this.configRequiredFields.filter(f => f.apiName !== apiName);
    }

    // ==================== HELPER METHODS ====================

    resetConfigForm() {
        this.currentConfigId = null;
        this.isEditMode = false;
        
        this.configProcessLabel = '';
        this.configProcessType = '';
        this.configSequenceOrder = null;
        this.configApprovalProcessName = '';
        this.configIsActive = false;
        this.configStatusFieldName = '';
        this.configApprovedValue = 'Approved';
        this.configRejectedValue = 'Rejected';
        this.configPendingValue = 'Pending';
        this.configPrerequisiteType = '';
        this.configPrerequisiteValue = '';
        this.configStepsJson = this.getEmptyStepsJson();
        this.configOnApprovalJson = this.getEmptyActionsJson();
        this.configOnRejectionJson = this.getEmptyActionsJson();
        this.configMatchingCriteria = '';
        this.configRequiredFields = [];
        this.selectedRequiredField = '';

        this.statusPicklistValues = [];
    }
    
    getEmptyStepsJson() {
        return JSON.stringify({ numberOfSteps: 0, steps: [] });
    }
    
    getEmptyActionsJson() {
        return JSON.stringify({ actions: [] });
    }
    
    showToast(title, message, variant) {
        var toastEvent = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(toastEvent);
    }
    
    getErrorMessage(error) {
        var message = 'Unknown error occurred';
        
        if (error) {
            if (error.body && error.body.message) {
                message = error.body.message;
            } else if (error.message) {
                message = error.message;
            }
        }
        
        return message;
    }
}