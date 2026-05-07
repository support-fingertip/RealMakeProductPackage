import { LightningElement, api, track, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead__c';
import getInitData from '@salesforce/apex/LeadStatusUpdateController.getInitData';
import submitLeadStatusUpdate from '@salesforce/apex/LeadStatusUpdateController.submitLeadStatusUpdate';

export default class LeadStatusUpdate extends LightningElement {
    _recordId;
    _loaded = false;

    @track isLoading = true;
    @track isSubmitting = false;

    // Lead data from Apex
    @track leadName = '';
    @track currentStatus = '';
    @track recordTypeId;
    @track recordTypeDeveloperName = '';
    @track existingLostReason = '';
    @track existingRemarks = '';

    // CMT configs from Apex
    @track statusConfigs = [];

    // Form state
    @track selectedStatus = '';
    @track lostReason = '';
    @track remarks = '';

    // Follow-up fields
    @track followUpDueDate = '';
    @track followUpSubject = '';
    @track followUpNotes = '';

    // Lead project (for auto-population)
    @track leadProjectId = '';

    // Target project for "Looking for other Project" flow
    @track targetProjectId = '';
     @track crossProjectAllowed = false;

    // Site visit fields
    @track siteVisitScheduledDate = '';
    @track siteVisitProjectId = '';
    @track siteVisitFeedback = '';
    @track siteVisitVisitType = 'On Site';
    @track siteVisitNeedPickUp = false;

    // Picklist options from wire
    @track statusOptions = [];
    @track lostReasonOptions = [];

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
    //  WIRE — Object info and picklist values
    // ═══════════════════════════════════════════════════════════════
    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    leadObjectInfo;

    @wire(getPicklistValuesByRecordType, {
        objectApiName: LEAD_OBJECT,
        recordTypeId: '$recordTypeId'
    })
    wiredPicklistValues({ error, data }) {
        if (data) {
            this.processPicklistValues(data);
        } else if (error) {
            console.error('Error loading picklist values:', error);
        }
    }

    processPicklistValues(data) {
        const picklistFieldValues = data.picklistFieldValues;

        // Lead_Status__c picklist values filtered by record type
        // Store all options first — will be filtered forward-only after init data loads
        if (picklistFieldValues.Lead_Status__c) {
            this._allStatusOptions = picklistFieldValues.Lead_Status__c.values.map(item => ({
                label: item.label,
                value: item.value
            }));
            this.statusOptions = this._allStatusOptions;
        }

        // Lost_Reason__c picklist values
        if (picklistFieldValues.Lost_Reason__c) {
            this.lostReasonOptions = picklistFieldValues.Lost_Reason__c.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  LOAD INIT DATA — Apex call
    // ═══════════════════════════════════════════════════════════════
    async loadInitData() {
        this.isLoading = true;
        try {
            const result = await getInitData({ leadId: this._recordId });
            this.leadName = result.leadName;
            this.currentStatus = result.currentStatus;
            this.selectedStatus = result.currentStatus;
            this.recordTypeId = result.recordTypeId;
            this.recordTypeDeveloperName = result.recordTypeDeveloperName;
            this.existingLostReason = result.lostReason || '';
            this.existingRemarks = result.remarks || '';
            this.lostReason = this.existingLostReason;
            this.remarks = this.existingRemarks;
            this.leadProjectId = result.leadProjectId || '';
             this.crossProjectAllowed = result.crossProjectAllowed === true;
            this.siteVisitProjectId = this.leadProjectId;
            this.statusConfigs = result.statusConfigs || [];

            // Filter status dropdown: only show current status and forward statuses
            this.filterStatusOptionsForward();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            this.handleClose();
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Filter status options to only show statuses at or after the current status
     * in the Sort_Order sequence. Prevents backward movement.
     */
    filterStatusOptionsForward() {
        if (!this._allStatusOptions || !this.statusConfigs || !this.currentStatus) return;

        // Find current status sort order from configs
        const currentConfig = this.statusConfigs.find(c => c.statusValue === this.currentStatus);
        const currentOrder = currentConfig ? currentConfig.sortOrder : 0;

        // Build set of allowed status values (current order or higher)
        const allowedStatuses = new Set();
        for (const cfg of this.statusConfigs) {
            if (cfg.sortOrder >= currentOrder) {
                allowedStatuses.add(cfg.statusValue);
            }
        }

        // Always include current status even if not in configs
        allowedStatuses.add(this.currentStatus);

        // Filter picklist options to only forward statuses
        this.statusOptions = this._allStatusOptions.filter(opt => allowedStatuses.has(opt.value));
    }

    // ═══════════════════════════════════════════════════════════════
    //  RENDERED CALLBACK — Ensure project picker shows pre-populated value
    // ═══════════════════════════════════════════════════════════════
    _projectPickerInitialized = false;

    renderedCallback() {
        if (!this._projectPickerInitialized && this.leadProjectId && this.showSiteVisitSection) {
            const picker = this.template.querySelector('[data-id="projectPicker"]');
            if (picker) {
                picker.value = this.leadProjectId;
                this._projectPickerInitialized = true;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  COMPUTED — Active config for selected status
    // ═══════════════════════════════════════════════════════════════
    get activeConfig() {
        if (!this.selectedStatus || !this.statusConfigs.length) return null;
        return this.statusConfigs.find(c => c.statusValue === this.selectedStatus) || null;
    }

    get showLostReason() {
        return this.activeConfig?.requiresLostReason === true;
    }

    get showRemarks() {
        return this.activeConfig?.requiresRemarks === true;
    }

    get showFollowUpSection() {
        const cfg = this.activeConfig;
        if (!cfg) return false;
        // Show if explicitly required
        if (cfg.requiresFollowUp) return true;
        // Show as optional if not disabled
        if (!cfg.disableFollowUp) return true;
        return false;
    }

    get showSiteVisitSection() {
        return this.activeConfig?.requiresSiteVisit === true;
    }

    get showTargetProjectPicker() {
        return this.selectedStatus === 'Unqualified'
            && this.lostReason === 'Looking for other Project';
    }

    get isFollowUpMandatory() {
        const cfg = this.activeConfig;
        return cfg?.requiresFollowUp === true && cfg?.followUpMandatory === true;
    }

    get isSiteVisitMandatory() {
        const cfg = this.activeConfig;
        return cfg?.requiresSiteVisit === true && cfg?.siteVisitMandatory === true;
    }

    get followUpSectionLabel() {
        const cfg = this.activeConfig;
        if (cfg?.sectionLabel) return cfg.sectionLabel;
        if (cfg?.requiresFollowUp && cfg?.followUpMandatory) return 'Follow-Up (Required)';
        return 'Follow-Up (Optional)';
    }

    get siteVisitSectionLabel() {
        if (this.isSiteVisitMandatory) return 'Site Visit (Required)';
        return 'Site Visit';
    }

    get isSaveDisabled() {
        return this.isSubmitting || !this.selectedStatus;
    }

    get hasStatusChanged() {
        return this.selectedStatus !== this.currentStatus;
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
    //  HANDLERS — Form input changes
    // ═══════════════════════════════════════════════════════════════
    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
        // Pre-fill follow-up subject from config
        const cfg = this.activeConfig;
        if (cfg?.followUpDefaultSubject) {
            this.followUpSubject = cfg.followUpDefaultSubject;
        } else {
            this.followUpSubject = '';
        }
        // Reset site visit and follow-up fields on status change
        this._projectPickerInitialized = false;
        this.followUpDueDate = '';
        this.followUpNotes = '';
        this.siteVisitScheduledDate = '';
        this.siteVisitProjectId = this.leadProjectId || '';
        this.siteVisitFeedback = '';
        this.siteVisitVisitType = 'On Site';
        this.siteVisitNeedPickUp = false;

        // Re-apply project value after DOM re-render so lightning-record-picker resolves the name
        if (this.leadProjectId) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const picker = this.template.querySelector('[data-id="projectPicker"]');
                if (picker) {
                    picker.value = this.leadProjectId;
                }
            }, 300);
        }
    }

    handleLostReasonChange(event) {
        this.lostReason = event.detail.value;
        // Reset target project when lost reason changes
        this.targetProjectId = '';
    }

    handleTargetProjectChange(event) {
        this.targetProjectId = event.detail.recordId || '';
    }

    handleRemarksChange(event) {
        this.remarks = event.detail.value;
    }

    handleFollowUpDueDateChange(event) {
        this.followUpDueDate = event.detail.value;
        const input = event.target;
        if (this.followUpDueDate && new Date(this.followUpDueDate) <= new Date()) {
            input.setCustomValidity('Due Date must be a future date and time.');
        } else {
            input.setCustomValidity('');
        }
        input.reportValidity();
    }

    handleFollowUpSubjectChange(event) {
        this.followUpSubject = event.detail.value;
    }

    handleFollowUpNotesChange(event) {
        this.followUpNotes = event.detail.value;
    }

    handleSiteVisitDateChange(event) {
        this.siteVisitScheduledDate = event.detail.value;
        const input = event.target;
        if (this.siteVisitScheduledDate && new Date(this.siteVisitScheduledDate) <= new Date()) {
            input.setCustomValidity('Scheduled Date must be a future date and time.');
        } else {
            input.setCustomValidity('');
        }
        input.reportValidity();
    }

    handleProjectChange(event) {
        this.siteVisitProjectId = event.detail.recordId || '';
    }

    handleSiteVisitFeedbackChange(event) {
        this.siteVisitFeedback = event.detail.value;
    }

    handleVisitTypeChange(event) {
        this.siteVisitVisitType = event.detail.value;
    }

    handleSiteVisitNeedPickUpChange(event) {
        this.siteVisitNeedPickUp = event.target.checked;
    }

    // ═══════════════════════════════════════════════════════════════
    //  SAVE — Build payload and submit
    // ═══════════════════════════════════════════════════════════════
    async handleSave() {
        // Client-side pre-validation
        if (!this.selectedStatus) {
            this.showToast('Error', 'Please select a status.', 'error');
            return;
        }

        // Validate target project for "Looking for other Project" flow
        if (this.showTargetProjectPicker && !this.targetProjectId) {
            this.showToast('Error', 'Please select a target project.', 'error');
            return;
        }
        if (this.showTargetProjectPicker && this.targetProjectId === this.leadProjectId) {
            this.showToast('Error', 'Target project must be different from the current project.', 'error');
            return;
        }

        const now = new Date();
        now.setSeconds(0, 0); // Truncate to minute level — allow current minute

        // Validate follow-up date is in the future (today + current/future time is valid)
        if (this.showFollowUpSection && this.followUpDueDate) {
            const fuDate = new Date(this.followUpDueDate);
            if (fuDate < now) {
                this.showToast('Error', 'Follow-up Due Date must be in the future.', 'error');
                return;
            }
        }

        // Validate site visit date is in the future (today + current/future time is valid)
        if (this.showSiteVisitSection && this.siteVisitScheduledDate) {
            const svDate = new Date(this.siteVisitScheduledDate);
            if (svDate < now) {
                this.showToast('Error', 'Site Visit Scheduled Date must be in the future.', 'error');
                return;
            }
        }

        this.isSubmitting = true;

        const payload = {
            leadId: this._recordId,
            newStatus: this.selectedStatus,
            lostReason: this.showLostReason ? this.lostReason : null,
            remarks: this.showRemarks ? this.remarks : null,
            targetProjectId: this.showTargetProjectPicker ? this.targetProjectId : null,
            followUp: null,
            siteVisit: null
        };

        // Include follow-up data if section is visible and user filled something
        if (this.showFollowUpSection && (this.followUpDueDate || this.followUpSubject)) {
            payload.followUp = {
                dueDate: this.followUpDueDate
                    ? new Date(this.followUpDueDate).toISOString() : null,
                subject: this.followUpSubject || null,
                notes: this.followUpNotes || null
            };
        }

        // Include site visit data if section is visible and user filled something
        if (this.showSiteVisitSection && (this.siteVisitScheduledDate || this.siteVisitProjectId)) {
            payload.siteVisit = {
                scheduledDate: this.siteVisitScheduledDate
                    ? new Date(this.siteVisitScheduledDate).toISOString() : null,
                projectId: this.siteVisitProjectId || null,
                feedback: this.siteVisitFeedback || null,
                visitType: this.siteVisitVisitType || 'On Site',
                needPickUp: this.siteVisitNeedPickUp || false
            };
        }

        try {
            const result = await submitLeadStatusUpdate({ payloadJson: JSON.stringify(payload) });

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

     get isProjectPickerDisabled() {
        return !this.crossProjectAllowed;
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