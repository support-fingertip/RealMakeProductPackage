import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

import getObjectApiNameFromRecordId from '@salesforce/apex/DynamicApprovalController.getObjectApiNameFromRecordId';
import getApprovalStatusForRecord from '@salesforce/apex/DynamicApprovalController.getApprovalStatusForRecord';
import previewApprovers from '@salesforce/apex/DynamicApprovalController.previewApprovers';
import submitForApprovalApex from '@salesforce/apex/DynamicApprovalController.submitForApproval';
import searchApproverUsers from '@salesforce/apex/DynamicApprovalController.searchApproverUsers';
import getRequiredFieldsStatus from '@salesforce/apex/DynamicApprovalController.getRequiredFieldsStatus';
import saveRequiredFieldValues from '@salesforce/apex/DynamicApprovalController.saveRequiredFieldValues';

export default class SubmitForApproval extends LightningElement {
    
    // ==================== API PROPERTIES ====================
    
    @api recordId;
    
    // ==================== TRACKED PROPERTIES ====================
    
    @track isLoading = true;
    @track isLoadingPreview = false;
    @track objectApiName = '';
    
    @track availableList = [];
    @track completedList = [];
    @track inProgressList = [];
    @track lockedList = [];
    
    @track selectedConfigId = '';
    @track approverPreviews = [];
    @track comments = '';
    @track availableOptions = [];
    @track requiredFieldStatuses = [];
    @track isLoadingRequiredFields = false;
    @track editedFieldValues = {};
    
    // ==================== NON-TRACKED PROPERTIES ====================
    
    _rawAvailableList = [];
    _hasInitialized = false;
    
    // ==================== WIRE ADAPTERS ====================
    
    // Wire to ensure recordId is populated
    @wire(getRecord, { recordId: '$recordId', fields: ['Id'] })
    wiredRecord({ error, data }) {
        if (data) {
            if (!this._hasInitialized) {
                this._hasInitialized = true;
                this.loadApprovalStatus();
            }
        } else if (error) {
            if (this.recordId && !this._hasInitialized) {
                this._hasInitialized = true;
                this.loadApprovalStatus();
            }
        }
    }
    
    // ==================== GETTERS ====================
    
    get hasAnyProcesses() {
        const hasAvail = this.availableList && this.availableList.length > 0;
        const hasComp = this.completedList && this.completedList.length > 0;
        const hasInProg = this.inProgressList && this.inProgressList.length > 0;
        const hasLock = this.lockedList && this.lockedList.length > 0;
        
        return hasAvail || hasComp || hasInProg || hasLock;
    }
    
    get hasAvailable() {
        return this.availableList && this.availableList.length > 0;
    }
    
    get hasCompleted() {
        return this.completedList && this.completedList.length > 0;
    }
    
    get hasInProgress() {
        return this.inProgressList && this.inProgressList.length > 0;
    }
    
    get hasLocked() {
        return this.lockedList && this.lockedList.length > 0;
    }

    get hasStatusCards() {
        return this.hasCompleted || this.hasInProgress || this.hasLocked;
    }
    
    get showApproverPreview() {
        return !!this.selectedConfigId;
    }
    
    get hasApproverPreviews() {
        return this.approverPreviews && this.approverPreviews.length > 0;
    }
    
    get hasRequiredFields() {
        return this.requiredFieldStatuses && this.requiredFieldStatuses.length > 0;
    }

    get hasUnfilledRequiredFields() {
        return this.requiredFieldStatuses.some(f => !f.isFilled);
    }

    get isSubmitDisabled() {
        return this.isLoading || this.isLoadingPreview || !this.selectedConfigId
            || this.isLoadingRequiredFields || this.hasUnfilledRequiredFields;
    }
    
    // ==================== LIFECYCLE ====================
    
    connectedCallback() {
        // Try multiple ways to get recordId
        if (!this.recordId) {
            // Method 1: Try to get from URL parameters
            const urlParams = new URLSearchParams(window.location.search);
            const recordIdFromUrl = urlParams.get('recordId');
            if (recordIdFromUrl) {
                this.recordId = recordIdFromUrl;
            }

            // Method 2: Try to get from window.location.pathname
            if (!this.recordId) {
                const pathParts = window.location.pathname.split('/');
                const recordIdFromPath = pathParts.find(part =>
                    part.length === 18 && /^[a-zA-Z0-9]{18}$/.test(part)
                );
                if (recordIdFromPath) {
                    this.recordId = recordIdFromPath;
                }
            }
        }

        // If we have recordId and haven't initialized, load data
        // Otherwise wait for wire adapter
        if (this.recordId && !this._hasInitialized) {
            this._hasInitialized = true;
            this.loadApprovalStatus();
        } else if (!this.recordId) {
            // Will wait for wire adapter or show error after timeout
            setTimeout(() => {
                if (!this.recordId) {
                    this.showToast('Error', 'Unable to determine record ID. Please close this dialog and try again from the record page.', 'error');
                    this.isLoading = false;
                }
            }, 2000);
        }
    }
    
    // ==================== DATA LOADING METHODS ====================
    
    async loadApprovalStatus() {
        this.isLoading = true;

        try {
            if (!this.recordId) {
                throw new Error('Record ID is null or undefined');
            }

            const objectName = await getObjectApiNameFromRecordId({
                recordId: this.recordId
            });
            this.objectApiName = objectName;

            const status = await getApprovalStatusForRecord({
                recordId: this.recordId
            });
            this.processApprovalStatus(status);

        } catch (error) {
            console.error('Error in loadApprovalStatus:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }
    
    processApprovalStatus(status) {
        const availableArr = [];
        const completedArr = [];
        const inProgressArr = [];
        const lockedArr = [];
        const optionsArr = [];
        
        // Process available
        if (status && status.available) {
            for (let i = 0; i < status.available.length; i++) {
                const item = status.available[i];
                const stepNames = (item.steps || []).filter(s => s && s.stepName).map(s => s.stepName);
                availableArr.push({
                    configId: item.configId,
                    processLabel: item.processLabel,
                    processType: item.processType,
                    numberOfSteps: item.numberOfSteps,
                    statusMessage: item.statusMessage,
                    canResubmit: item.canResubmit,
                    steps: item.steps,
                    hasStepNames: stepNames.length > 0,
                    stepFlow: stepNames.join('  →  '),
                    cardClass: 'process-card',
                    radioClass: 'process-radio'
                });
            }
        }
        
        // Process completed
        if (status && status.completed) {
            for (let i = 0; i < status.completed.length; i++) {
                const item = status.completed[i];
                completedArr.push({
                    configId: item.configId,
                    processLabel: item.processLabel,
                    statusMessage: item.statusMessage
                });
            }
        }
        
        // Process in progress
        if (status && status.inProgress) {
            for (let i = 0; i < status.inProgress.length; i++) {
                const item = status.inProgress[i];
                inProgressArr.push({
                    configId: item.configId,
                    processLabel: item.processLabel,
                    statusMessage: item.statusMessage
                });
            }
        }
        
        // Process locked
        if (status && status.locked) {
            for (let i = 0; i < status.locked.length; i++) {
                const item = status.locked[i];
                lockedArr.push({
                    configId: item.configId,
                    processLabel: item.processLabel,
                    statusMessage: item.statusMessage
                });
            }
        }
        
        // Build available options for radio group
        for (let i = 0; i < availableArr.length; i++) {
            const item = availableArr[i];
            const processLabel = item.processLabel || '';
            const configId = item.configId || '';
            const description = this.buildDescriptionFromItem(item);
            const optionLabel = processLabel + ' - ' + description;
            
            optionsArr.push({
                label: optionLabel,
                value: configId
            });
        }
        
        // Store raw list for auto-select
        this._rawAvailableList = availableArr;
        
        // Set tracked properties
        this.availableList = availableArr;
        this.completedList = completedArr;
        this.inProgressList = inProgressArr;
        this.lockedList = lockedArr;
        this.availableOptions = optionsArr;
        
        // Auto-select if only one available
        if (availableArr.length === 1) {
            this.selectedConfigId = availableArr[0].configId;
            availableArr[0].cardClass = 'process-card process-card-selected';
            availableArr[0].radioClass = 'process-radio process-radio-selected';
            this.availableList = availableArr;
            this.loadApproverPreview();
        }
    }
    
    buildDescriptionFromItem(item) {
        let description = '';
        let stepCount = 0;
        const stepNames = [];
        
        if (item && item.numberOfSteps) {
            stepCount = item.numberOfSteps;
        }
        
        description = stepCount + ' Step(s)';
        
        if (item && item.steps) {
            const steps = item.steps;
            for (let i = 0; i < steps.length; i++) {
                if (steps[i] && steps[i].stepName) {
                    const stepName = steps[i].stepName;
                    if (stepName.length > 0) {
                        stepNames.push(stepName);
                    }
                }
            }
            
            if (stepNames.length > 0) {
                description = description + ': ' + stepNames.join(' > ');
            }
        }
        
        if (item && item.canResubmit) {
            description = description + ' (Resubmit)';
        }
        
        return description;
    }
    
    async loadApproverPreview() {
        if (!this.selectedConfigId || !this.recordId) {
            this.approverPreviews = [];
            this.requiredFieldStatuses = [];
            return;
        }

        this.isLoadingPreview = true;

        try {
            const previews = await previewApprovers({
                recordId: this.recordId,
                configId: this.selectedConfigId
            });
            this.processApproverPreviews(previews);
        } catch (error) {
            console.error('Error loading approver preview:', error);
            this.approverPreviews = [];
            this.showToast('Warning', 'Could not load approver preview: ' + this.getErrorMessage(error), 'warning');
        } finally {
            this.isLoadingPreview = false;
        }

        // Load required fields status
        await this.loadRequiredFieldsStatus();
    }

    async loadRequiredFieldsStatus() {
        if (!this.selectedConfigId || !this.recordId) {
            this.requiredFieldStatuses = [];
            return;
        }
        this.isLoadingRequiredFields = true;
        this.editedFieldValues = {};
        try {
            const statuses = await getRequiredFieldsStatus({
                recordId: this.recordId,
                configId: this.selectedConfigId
            });
            this.requiredFieldStatuses = (statuses || []).map(f => ({
                ...f,
                isPicklist: f.fieldType === 'picklist',
                isCheckbox: f.fieldType === 'checkbox',
                isStandardInput: f.fieldType !== 'picklist' && f.fieldType !== 'checkbox',
                rowClass: 'req-field-edit-row' + (f.isFilled ? '' : ' req-field-edit-row-empty')
            }));
        } catch (error) {
            console.error('Error loading required fields:', error);
            this.requiredFieldStatuses = [];
        } finally {
            this.isLoadingRequiredFields = false;
        }
    }

    handleRequiredFieldChange(event) {
        const fieldName = event.currentTarget.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.detail.value;
        this.editedFieldValues = { ...this.editedFieldValues, [fieldName]: value };

        // Update the field status in-memory to reflect the new value
        this.requiredFieldStatuses = this.requiredFieldStatuses.map(f => {
            if (f.fieldApiName === fieldName) {
                const isFilled = value !== null && value !== undefined && String(value).trim().length > 0;
                return {
                    ...f,
                    currentValue: value,
                    isFilled,
                    rowClass: 'req-field-edit-row' + (isFilled ? '' : ' req-field-edit-row-empty')
                };
            }
            return f;
        });
    }
    
    processApproverPreviews(previews) {
        const previewsArr = [];
        const total = previews ? previews.length : 0;

        if (previews && total > 0) {
            for (let i = 0; i < total; i++) {
                const item = previews[i];
                previewsArr.push({
                    stepNumber: item.stepNumber,
                    stepName: item.stepName || 'Step ' + item.stepNumber,
                    fieldPath: item.fieldPath || '',
                    approverId: item.approverId || '',
                    approverName: item.approverName || '',
                    isFound: item.isFound || false,
                    message: item.message || '',
                    isLast: i === total - 1,
                    dotClass: item.isFound ? 'step-dot step-dot-ok' : 'step-dot step-dot-warn'
                });
            }
        }

        this.approverPreviews = previewsArr;
    }
    
    // ==================== MANUAL APPROVER ====================

    _searchTimeout;

    handleManualApproverSearch(event) {
        const searchTerm = event.target.value;
        const stepNumber = parseInt(event.target.dataset.step);

        clearTimeout(this._searchTimeout);
        if (!searchTerm || searchTerm.length < 2) {
            this.clearSearchResults(stepNumber);
            return;
        }

        this._searchTimeout = setTimeout(() => {
            searchApproverUsers({ searchTerm })
                .then(result => {
                    this.approverPreviews = this.approverPreviews.map(p => {
                        if (p.stepNumber === stepNumber) {
                            return { ...p, searchResults: result };
                        }
                        return p;
                    });
                })
                .catch(() => {});
        }, 300);
    }

    handleSelectManualApprover(event) {
        const stepNumber = parseInt(event.currentTarget.dataset.step);
        const userId = event.currentTarget.dataset.userId;
        const userName = event.currentTarget.dataset.userName;

        this.approverPreviews = this.approverPreviews.map(p => {
            if (p.stepNumber === stepNumber) {
                return {
                    ...p,
                    isFound: true,
                    approverId: userId,
                    approverName: userName,
                    message: '',
                    searchResults: null
                };
            }
            return p;
        });
    }

    clearSearchResults(stepNumber) {
        this.approverPreviews = this.approverPreviews.map(p => {
            if (p.stepNumber === stepNumber) {
                return { ...p, searchResults: null };
            }
            return p;
        });
    }

    // ==================== EVENT HANDLERS ====================

    handleProcessCardClick(event) {
        const configId = event.currentTarget.dataset.id;
        this.selectedConfigId = configId;
        this.availableList = this.availableList.map(p => ({
            ...p,
            cardClass: p.configId === configId ? 'process-card process-card-selected' : 'process-card',
            radioClass: p.configId === configId ? 'process-radio process-radio-selected' : 'process-radio'
        }));
        this.loadApproverPreview();
    }

    handleProcessSelection(event) {
        this.selectedConfigId = event.detail.value;
        this.loadApproverPreview();
    }
    
    handleCommentsChange(event) {
        this.comments = event.target.value;
    }
    
    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    
    async handleSubmit() {
        if (!this.recordId) {
            this.showToast('Error', 'Record ID is missing. Please refresh and try again.', 'error');
            return;
        }

        if (!this.selectedConfigId) {
            this.showToast('Error', 'Please select an approval process', 'error');
            return;
        }

        if (!this.checkHasApprover()) {
            this.showToast('Warning', 'No approvers found. At least one approver is required.', 'warning');
            return;
        }

        // Check if there are still unfilled required fields
        if (this.hasUnfilledRequiredFields) {
            this.showToast('Error', 'Please fill all required fields before submitting', 'error');
            return;
        }

        this.isLoading = true;

        try {
            // Save edited required field values to the record first
            if (Object.keys(this.editedFieldValues).length > 0) {
                await saveRequiredFieldValues({
                    recordId: this.recordId,
                    configId: this.selectedConfigId,
                    fieldValuesJson: JSON.stringify(this.editedFieldValues)
                });
            }

            const result = await submitForApprovalApex({
                recordId: this.recordId,
                configId: this.selectedConfigId,
                comments: this.comments || ''
            });
            this.handleSubmitResult(result);
        } catch (error) {
            console.error('Error submitting for approval:', error);
            this.showToast('Error', this.getErrorMessage(error), 'error');
            this.isLoading = false;
        }
    }
    
    handleSubmitResult(result) {
        let errorMsg;
        
        if (result && result.success) {
            this.showToast('Success', result.message, 'success');
            this.dispatchEvent(new CloseActionScreenEvent());
            this.refreshPage();
        } else {
            errorMsg = 'Failed to submit for approval';
            if (result && result.message) {
                errorMsg = result.message;
            }
            this.showToast('Error', errorMsg, 'error');
        }
        
        this.isLoading = false;
    }
    
    // ==================== HELPER METHODS ====================
    
    checkHasApprover() {
        if (!this.approverPreviews) {
            return false;
        }
        
        if (this.approverPreviews.length === 0) {
            return false;
        }
        
        for (let i = 0; i < this.approverPreviews.length; i++) {
            const preview = this.approverPreviews[i];
            if (preview && preview.isFound === true) {
                return true;
            }
        }
        
        return false;
    }
    
    refreshPage() {
        // Use LWC-native record update notification
        if (this.recordId) {
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        }
        // Fallback: reload the page to reflect changes
        try {
            window.location.reload();
        } catch (e) {
            // Silent fallback
        }
    }
    
    showToast(title, message, variant) {
        const toastEvent = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: 'sticky'
        });
        this.dispatchEvent(toastEvent);
    }
    
    getErrorMessage(error) {
        let message = 'Unknown error occurred';
        
        if (error) {
            if (error.body) {
                if (error.body.message) {
                    message = error.body.message;
                } else if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                    message = error.body.pageErrors[0].message;
                } else if (error.body.fieldErrors) {
                    const fieldErrors = [];
                    Object.keys(error.body.fieldErrors).forEach(field => {
                        error.body.fieldErrors[field].forEach(err => {
                            fieldErrors.push(err.message);
                        });
                    });
                    if (fieldErrors.length > 0) {
                        message = fieldErrors.join(', ');
                    }
                }
            } else if (error.message) {
                message = error.message;
            } else if (typeof error === 'string') {
                message = error;
            }
        }
        
        return message;
    }
}