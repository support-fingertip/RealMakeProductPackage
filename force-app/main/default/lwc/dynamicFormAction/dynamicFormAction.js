import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getAvailableConfigurations from '@salesforce/apex/DynamicFormExecutionController.getAvailableConfigurations';

export default class DynamicFormAction extends LightningElement {
    // Use setters to handle async property assignment from Record Actions
    _recordId;
    _objectApiName;
    _configsLoaded = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this._tryLoadConfigurations();
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value;
        this._tryLoadConfigurations();
    }

    @track availableConfigs = [];
    @track selectedConfig = null;
    @track showConfigSelection = false;
    @track showForm = false;
    @api isCloneMode = false;

    isLoading = true;

    get cloneRecordId() {
        return this.isCloneMode ? this._recordId : null;
    }

    _tryLoadConfigurations() {
        // Only load once both objectApiName is available (recordId is optional)
        if (this._objectApiName && !this._configsLoaded) {
            this._configsLoaded = true;
            this.loadConfigurations();
        }
    }

    loadConfigurations() {
        this.isLoading = true;
        getAvailableConfigurations({
            contextObjectApiName: this._objectApiName,
            recordId: this._recordId || null
        })
            .then(result => {
                this.availableConfigs = result;
                this.isLoading = false;

                if (this.availableConfigs.length === 0) {
                    this.showToast('Info', 'No forms available for this object', 'info');
                    this.closeAction();
                } else if (this.availableConfigs.length === 1) {
                    this.selectedConfig = this.availableConfigs[0];
                    this.showForm = true;
                } else {
                    this.showConfigSelection = true;
                }
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load form configurations', 'error');
                this.isLoading = false;
                this.closeAction();
                console.error(error);
            });
    }

    handleConfigSelect(event) {
        const configId = event.currentTarget.dataset.id;
        this.selectedConfig = this.availableConfigs.find(c => c.id === configId);
        this.showConfigSelection = false;
        this.showForm = true;
    }

    handleFormSuccess() {
        this.closeAction();
    }

    handleFormClose() {
        if (this.availableConfigs.length > 1) {
            this.showForm = false;
            this.selectedConfig = null;
            this.showConfigSelection = true;
        } else {
            this.closeAction();
        }
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get hasMultipleConfigs() {
        return this.availableConfigs.length > 1;
    }

    get configCountLabel() {
        const count = this.availableConfigs.length;
        return `${count} form${count !== 1 ? 's' : ''} available`;
    }

    handleCardKeyup(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            this.handleConfigSelect(event);
        }
    }

    get targetObjectApiName() {
        if (this.selectedConfig) {
            return this.selectedConfig.targetObject || this._objectApiName;
        }
        return this._objectApiName;
    }
}