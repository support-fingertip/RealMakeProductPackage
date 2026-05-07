import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import sendDemandEmail from '@salesforce/apex/BulkDemandController.sendDemandEmail';
import getConfigurationByType from '@salesforce/apex/PostSalesAdminController.getConfigurationByType';
import getEmailTemplateOptions from '@salesforce/apex/PostSalesAdminController.getEmailTemplateOptions';
import getDocumentTemplateOptions from '@salesforce/apex/PostSalesAdminController.getDocumentTemplateOptions';

export default class DemandEmailAction extends LightningElement {
    @api recordId;

    @track isLoading = false;
    @track isSending = false;
    @track emailTemplateOptions = [];
    @track documentTemplateOptions = [];
    @track selectedEmailTemplateId = '';
    @track selectedDocumentTemplateId = '';
    @track configLoaded = false;
    @track emailSent = false;
    @track errorMessage = '';

    connectedCallback() {
        this.loadConfig();
    }

    loadConfig() {
        this.isLoading = true;
        Promise.all([
            getConfigurationByType({ configurationType: 'Demand' }),
            getEmailTemplateOptions(),
            getDocumentTemplateOptions()
        ])
        .then(([config, emailTemplates, docTemplates]) => {
            if (config) {
                if (config.emailTemplateId) {
                    this.selectedEmailTemplateId = config.emailTemplateId;
                }
                if (config.documentTemplateId) {
                    this.selectedDocumentTemplateId = config.documentTemplateId;
                }
            }

            if (emailTemplates) {
                this.emailTemplateOptions = [
                    { label: '-- Use Default from Config --', value: '' },
                    ...emailTemplates.map(t => ({ label: t.label, value: t.value }))
                ];
            }

            if (docTemplates) {
                this.documentTemplateOptions = [
                    { label: '-- Use Default from Config --', value: '' },
                    ...docTemplates.map(t => ({ label: t.label, value: t.value }))
                ];
            }

            this.configLoaded = true;
        })
        .catch(error => {
            this.errorMessage = this.getErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        })
        .finally(() => { this.isLoading = false; });
    }

    handleEmailTemplateChange(event) {
        this.selectedEmailTemplateId = event.detail.value;
    }

    handleDocumentTemplateChange(event) {
        this.selectedDocumentTemplateId = event.detail.value;
    }

    handleSend() {
        this.isSending = true;
        this.errorMessage = '';

        sendDemandEmail({
            demandId: this.recordId,
            emailTemplateId: this.selectedEmailTemplateId,
            documentTemplateId: this.selectedDocumentTemplateId
        })
        .then(() => {
            this.emailSent = true;
            this.showToast('Success', 'Demand email sent with document attachment', 'success');
        })
        .catch(error => {
            this.errorMessage = this.getErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        })
        .finally(() => { this.isSending = false; });
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    get sendDisabled() {
        return this.isSending;
    }

    get showForm() {
        return this.configLoaded && !this.emailSent;
    }

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