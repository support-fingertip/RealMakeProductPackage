import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getLeadInfo from '@salesforce/apex/PushToSalesController.getLeadInfo';
import pushToSales from '@salesforce/apex/PushToSalesController.pushToSales';

export default class PushToSalesAction extends LightningElement {
    _recordId;
    _loaded = false;
    @track isLoading = true;
    @track isPushing = false;
    @track leadInfo = {};
    @track cannotPush = false;
    @track blockReason = '';

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._loaded) {
            this._loaded = true;
            this.loadLeadInfo();
        }
    }

    async loadLeadInfo() {
        this.isLoading = true;
        try {
            this.leadInfo = await getLeadInfo({ leadId: this._recordId });

            if (!this.leadInfo.canPush) {
                this.cannotPush = true;
                if (!this.leadInfo.isPreSales) {
                    this.blockReason = 'This lead is already in the ' + this.leadInfo.recordTypeName
                        + ' bucket. Only Pre Sales leads can be pushed to Sales.';
                } else {
                    this.blockReason = 'Lead status must be "Site Visit Scheduled" or "Site Visit Completed" to push to Sales. Current status: '
                        + this.leadInfo.leadStatus;
                }
            }
        } catch (error) {
            this.cannotPush = true;
            this.blockReason = this.reduceErrors(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handlePush() {
        this.isPushing = true;
        try {
            await pushToSales({ leadId: this._recordId });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Lead has been pushed to Sales successfully. A Sales user has been assigned via Round Robin.',
                variant: 'success'
            }));

            // Refresh the record page
            await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);

            this.handleClose();
        } catch (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: this.reduceErrors(error),
                variant: 'error',
                mode: 'sticky'
            }));
        } finally {
            this.isPushing = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    reduceErrors(error) {
        if (!error) return 'An unexpected error occurred. Please try again.';
        if (typeof error === 'string') return error;
        if (error.body) {
            if (error.body.output && error.body.output.errors && error.body.output.errors.length > 0) {
                return error.body.output.errors.map(e => e.message).join(', ');
            }
            if (error.body.message) return error.body.message;
        }
        if (error.message) return error.message;
        return 'An unexpected error occurred. Please try again.';
    }
}