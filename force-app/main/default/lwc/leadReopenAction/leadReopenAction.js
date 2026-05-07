import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getLeadInfo from '@salesforce/apex/LeadReopenController.getLeadInfo';
import reopenLead from '@salesforce/apex/LeadReopenController.reopenLead';

export default class LeadReopenAction extends LightningElement {
    _recordId;
    _loaded = false;

    @track isLoading = true;
    @track isSubmitting = false;

    // Lead data
    @track leadName = '';
    @track leadStatus = '';
    @track isActive = false;
    @track projectName = '';

    // Form state
    @track source = 'Manual';
    @track subSource = '';

    // ═══════════════════════════════════════════════════════════════
    //  RECORD ID — Setter triggers data load
    // ═══════════════════════════════════════════════════════════════
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

    // ═══════════════════════════════════════════════════════════════
    //  LOAD LEAD INFO
    // ═══════════════════════════════════════════════════════════════
    async loadLeadInfo() {
        this.isLoading = true;
        try {
            const result = await getLeadInfo({ leadId: this._recordId });
            this.leadName = result.leadName;
            this.leadStatus = result.leadStatus;
            this.isActive = result.isActive;
            this.projectName = result.projectName || '';
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.handleClose();
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  HANDLERS
    // ═══════════════════════════════════════════════════════════════
    handleSourceChange(event) {
        this.source = event.detail.value;
    }

    handleSubSourceChange(event) {
        this.subSource = event.detail.value;
    }

    // ═══════════════════════════════════════════════════════════════
    //  REOPEN
    // ═══════════════════════════════════════════════════════════════
    async handleReopen() {
        this.isSubmitting = true;

        try {
            const result = await reopenLead({
                leadId: this._recordId,
                source: this.source || 'Manual',
                subSource: this.subSource || null
            });

            this.showToast('Success', result.message, 'success');
            await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
            this.handleClose();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ═══════════════════════════════════════════════════════════════
    //  UTILITIES
    // ═══════════════════════════════════════════════════════════════
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
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