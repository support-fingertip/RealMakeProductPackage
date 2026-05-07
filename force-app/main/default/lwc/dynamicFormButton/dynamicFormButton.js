import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAvailableConfigurations from '@salesforce/apex/DynamicFormExecutionController.getAvailableConfigurations';

export default class DynamicFormButton extends LightningElement {
    @api objectApiName; // Context object API name (where button is placed)
    @api recordId;      // Current record ID
    @api buttonLabel = 'Create Record';
    @api buttonVariant = 'brand';
    @api buttonIcon = 'utility:add';
    @api isCloneMode = false;   // When true, pre-populates form from current record

    @track showConfigModal = false;
    @track showFormModal = false;
    @track availableConfigs = [];
    @track selectedConfig = null;

    isLoading = false;

    get cloneRecordId() {
        return this.isCloneMode ? this.recordId : null;
    }

    handleButtonClick() {
        this.loadConfigurations();
    }

    loadConfigurations() {
        if (!this.objectApiName) {
            this.showToast('Error', 'Object API Name is required', 'error');
            return;
        }

        this.isLoading = true;
        getAvailableConfigurations({
            contextObjectApiName: this.objectApiName,
            recordId: this.recordId || null
        })
            .then(result => {
                this.availableConfigs = result;
                this.isLoading = false;

                if (this.availableConfigs.length === 0) {
                    this.showToast('Info', 'No forms available for this object', 'info');
                } else if (this.availableConfigs.length === 1) {
                    this.selectedConfig = this.availableConfigs[0];
                    this.showFormModal = true;
                } else {
                    this.showConfigModal = true;
                }
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load configurations', 'error');
                this.isLoading = false;
                console.error(error);
            });
    }

    handleConfigSelect(event) {
        const configId = event.currentTarget.dataset.id;
        this.selectedConfig = this.availableConfigs.find(c => c.id === configId);
        this.showConfigModal = false;
        this.showFormModal = true;
    }

    handleCloseConfigModal() {
        this.showConfigModal = false;
    }

    handleCloseFormModal() {
        this.showFormModal = false;
        this.selectedConfig = null;
    }

    handleFormSuccess(event) {
        this.showFormModal = false;
        this.selectedConfig = null;

        this.dispatchEvent(new CustomEvent('formsuccess', {
            detail: { recordId: event.detail.recordId }
        }));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get hasMultipleConfigs() {
        return this.availableConfigs.length > 1;
    }

    get targetObjectApiName() {
        if (this.selectedConfig) {
            return this.selectedConfig.targetObject || this.objectApiName;
        }
        return this.objectApiName;
    }
}