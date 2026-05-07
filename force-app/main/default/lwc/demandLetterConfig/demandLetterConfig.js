import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getDemandLetterConfigs from '@salesforce/apex/BulkDemandController.getDemandLetterConfigs';
import saveDemandLetterConfig from '@salesforce/apex/BulkDemandController.saveDemandLetterConfig';
import deleteDemandLetterConfig from '@salesforce/apex/BulkDemandController.deleteDemandLetterConfig';
import getEmailTemplateOptions from '@salesforce/apex/PostSalesAdminController.getEmailTemplateOptions';
import getDocumentTemplateOptions from '@salesforce/apex/PostSalesAdminController.getDocumentTemplateOptions';

export default class DemandLetterConfig extends LightningElement {
    @track configs = [];
    @track isLoading = false;
    @track showForm = false;
    @track editingConfig = {};
    @track isEditMode = false;

    // Lookup options
    @track emailTemplateOptions = [];
    @track documentTemplateOptions = [];

    wiredConfigResult;

    @wire(getDemandLetterConfigs)
    wiredConfigs(result) {
        this.wiredConfigResult = result;
        if (result.data) {
            this.configs = result.data.map(c => ({
                ...c,
                cardClass: c.isActive ? 'config-card config-card-active' : 'config-card'
            }));
        } else if (result.error) {
            this.showToast('Error', this.getErrorMessage(result.error), 'error');
        }
    }

    connectedCallback() {
        this.loadOptions();
    }

    loadOptions() {
        Promise.all([
            getEmailTemplateOptions(),
            getDocumentTemplateOptions()
        ]).then(([emails, docs]) => {
            this.emailTemplateOptions = [
                { label: '-- None --', value: '' },
                ...(emails || []).map(t => ({ label: t.label, value: t.value }))
            ];
            this.documentTemplateOptions = [
                { label: '-- None --', value: '' },
                ...(docs || []).map(t => ({ label: t.label, value: t.value }))
            ];
        }).catch(e => { console.error('Error loading config data:', e); });
    }

    // ============ COMPUTED ============

    get hasConfigs() {
        return this.configs && this.configs.length > 0;
    }

    // ============ CRUD ============

    handleNew() {
        this.editingConfig = {
            projectId: '',
            emailTemplateId: '',
            documentTemplateId: '',
            isActive: true,
            description: '',
            gracePeriodDays: 15,
            includeInterest: false,
            autoSendEmail: false
        };
        this.isEditMode = false;
        this.showForm = true;
    }

    handleEdit(event) {
        const configId = event.currentTarget.dataset.id;
        const config = this.configs.find(c => c.id === configId);
        if (config) {
            this.editingConfig = { ...config };
            this.isEditMode = true;
            this.showForm = true;
        }
    }

    handleDelete(event) {
        const configId = event.currentTarget.dataset.id;
        this.isLoading = true;
        deleteDemandLetterConfig({ configId })
            .then(() => {
                this.showToast('Success', 'Configuration deleted', 'success');
                return refreshApex(this.wiredConfigResult);
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.editingConfig = { ...this.editingConfig, [field]: value };
    }

    handleProjectChange(event) {
        this.editingConfig = { ...this.editingConfig, projectId: event.detail.value[0] || '' };
    }

    handleSave() {
        if (!this.editingConfig.projectId) {
            this.showToast('Error', 'Project is required', 'error');
            return;
        }

        this.isLoading = true;
        saveDemandLetterConfig({ configJson: JSON.stringify(this.editingConfig) })
            .then(() => {
                this.showToast('Success', 'Configuration saved', 'success');
                this.showForm = false;
                this.editingConfig = {};
                return refreshApex(this.wiredConfigResult);
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    handleCancel() {
        this.showForm = false;
        this.editingConfig = {};
    }

    // ============ PUBLIC API ============

    @api
    refresh() {
        return refreshApex(this.wiredConfigResult);
    }

    // ============ UTILITIES ============

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        } else if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}