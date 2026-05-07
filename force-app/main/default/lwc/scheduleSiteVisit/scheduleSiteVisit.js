import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getInitData from '@salesforce/apex/SiteVisitCreationController.getInitData';
import createSiteVisit from '@salesforce/apex/SiteVisitCreationController.createSiteVisit';

export default class ScheduleSiteVisit extends LightningElement {
    _recordId;
    _loaded = false;

    @track isLoading = true;
    @track isSubmitting = false;

    // Lead data
    @track leadName = '';
    @track currentProjectId = '';
    @track currentProjectName = '';
    @track ownerName = '';
    @track crossProjectAllowed = false;

    // Form state
    @track selectedProjectId = '';
    @track scheduledDate = '';
    @track visitType = 'On Site';
    @track needPickUp = false;

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
            this.loadInitData();
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  LOAD INIT DATA
    // ═══════════════════════════════════════════════════════════════
    async loadInitData() {
        this.isLoading = true;
        try {
            const result = await getInitData({ leadId: this._recordId });
            this.leadName = result.leadName;
            this.currentProjectId = result.currentProjectId || '';
            this.currentProjectName = result.currentProjectName || '';
            this.ownerName = result.ownerName || '';
            this.crossProjectAllowed = result.crossProjectAllowed === true;
            this.selectedProjectId = this.currentProjectId;
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.handleClose();
        } finally {
            this.isLoading = false;
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  RENDERED CALLBACK — Pre-populate project picker
    // ═══════════════════════════════════════════════════════════════
    _projectPickerInitialized = false;

    renderedCallback() {
        if (!this._projectPickerInitialized && this.currentProjectId && !this.isLoading) {
            const picker = this.template.querySelector('[data-id="projectPicker"]');
            if (picker) {
                picker.value = this.currentProjectId;
                this._projectPickerInitialized = true;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  COMPUTED
    // ═══════════════════════════════════════════════════════════════
    get isSaveDisabled() {
        return this.isSubmitting || !this.selectedProjectId || !this.scheduledDate;
    }

    get isProjectPickerDisabled() {
        return !this.crossProjectAllowed;
    }

    get visitTypeOptions() {
        return [
            { label: 'On Site', value: 'On Site' },
            { label: 'Virtual', value: 'Virtual' }
        ];
    }

    get minDateTime() {
        const now = new Date();
        const year = now.getFullYear();
        const month = String(now.getMonth() + 1).padStart(2, '0');
        const day = String(now.getDate()).padStart(2, '0');
        const hours = String(now.getHours()).padStart(2, '0');
        const minutes = String(now.getMinutes()).padStart(2, '0');
        return `${year}-${month}-${day}T${hours}:${minutes}`;
    }

    // ═══════════════════════════════════════════════════════════════
    //  HANDLERS
    // ═══════════════════════════════════════════════════════════════
    handleProjectChange(event) {
        this.selectedProjectId = event.detail.recordId || '';
    }

    handleDateChange(event) {
        this.scheduledDate = event.detail.value;
    }

    handleVisitTypeChange(event) {
        this.visitType = event.detail.value;
    }

    handleNeedPickUpChange(event) {
        this.needPickUp = event.target.checked;
    }

    // ═══════════════════════════════════════════════════════════════
    //  SAVE
    // ═══════════════════════════════════════════════════════════════
    async handleSave() {
        if (!this.selectedProjectId || !this.scheduledDate) {
            this.showToast('Error', 'Project and Scheduled Date are required.', 'error');
            return;
        }

        const now = new Date();
        now.setSeconds(0, 0);
        const svDate = new Date(this.scheduledDate);
        if (svDate < now) {
            this.showToast('Error', 'Scheduled Date must be in the future.', 'error');
            return;
        }

        this.isSubmitting = true;

        try {
            const result = await createSiteVisit({
                leadId: this._recordId,
                projectId: this.selectedProjectId,
                scheduledDate: this.scheduledDate,
                visitType: this.visitType,
                needPickUp: this.needPickUp
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