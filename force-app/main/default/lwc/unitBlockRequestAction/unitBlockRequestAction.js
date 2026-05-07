import { LightningElement, api, track, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import getProjects from '@salesforce/apex/BulkLeadReassignmentController.getProjects';
import searchUnits from '@salesforce/apex/BulkLeadReassignmentController.searchUnits';
import searchActiveUsers from '@salesforce/apex/BulkLeadReassignmentController.searchActiveUsers';
import getCurrentUserManager from '@salesforce/apex/BulkLeadReassignmentController.getCurrentUserManager';
import createBlockRequest from '@salesforce/apex/BulkLeadReassignmentController.createBlockRequest';

import LEAD_PROJECT_FIELD from '@salesforce/schema/Lead__c.Project__c';
import LEAD_NAME_FIELD from '@salesforce/schema/Lead__c.Full_Name__c';

export default class UnitBlockRequestAction extends LightningElement {
    @api recordId;

    // Loading
    isLoading = true;

    // Lead context
    leadProjectId;

    // Project
    projectId = '';
    projectOptions = [];

    // Unit lookup
    unitId = '';
    unitName = '';
    unitSearchTerm = '';
    @track unitResults = [];
    showUnitDropdown = false;
    isUnitSearching = false;
    _unitSearchTimeout;

    // Duration & Reason
    blockDays = '';
    reason = '';

    // Approver lookup
    approverId = '';
    approverName = '';
    approverSearchTerm = '';
    @track approverResults = [];
    showApproverDropdown = false;
    isApproverSearching = false;
    _approverSearchTimeout;
    defaultManagerName = '';

    @wire(getRecord, { recordId: '$recordId', fields: [LEAD_PROJECT_FIELD, LEAD_NAME_FIELD] })
    wiredLead({ data, error }) {
        if (data) {
            this.leadProjectId = getFieldValue(data, LEAD_PROJECT_FIELD);
            if (this.leadProjectId && !this.projectId) {
                this.projectId = this.leadProjectId;
            }
        }
    }

    connectedCallback() {
        this.loadInitialData();
    }

    async loadInitialData() {
        this.isLoading = true;
        try {
            const [projects, manager] = await Promise.all([
                getProjects(),
                getCurrentUserManager()
            ]);

            this.projectOptions = [
                { label: '-- Select Project --', value: '' },
                ...projects.map(p => ({ label: p.Name, value: p.Id }))
            ];

            if (manager) {
                this.approverId = manager.Id;
                this.approverName = manager.Name;
                this.defaultManagerName = manager.Name;
            }
        } catch (error) {
            this.showError('Failed to load data: ' + this.reduceError(error));
        } finally {
            this.isLoading = false;
        }
    }

    // ── Project ──────────────────────────────────────────────────
    handleProjectChange(event) {
        this.projectId = event.detail.value;
        // Clear unit when project changes
        this.unitId = '';
        this.unitName = '';
        this.unitSearchTerm = '';
        this.unitResults = [];
    }

    // ── Unit Lookup ──────────────────────────────────────────────
    handleUnitSearch(event) {
        this.unitSearchTerm = event.target.value;
        clearTimeout(this._unitSearchTimeout);
        if (this.unitSearchTerm.length < 2) {
            this.unitResults = [];
            this.showUnitDropdown = false;
            return;
        }
        this.isUnitSearching = true;
        this.showUnitDropdown = true;
        this._unitSearchTimeout = setTimeout(() => this.doUnitSearch(), 300);
    }

    async doUnitSearch() {
        try {
            const results = await searchUnits({
                projectId: this.projectId || null,
                unitStatus: 'Available',
                unitNumber: this.unitSearchTerm
            });
            this.unitResults = results;
        } catch (error) {
            this.unitResults = [];
        } finally {
            this.isUnitSearching = false;
        }
    }

    handleUnitFocus() {
        if (this.unitResults.length > 0) {
            this.showUnitDropdown = true;
        }
    }

    handleUnitBlur() {
        // Delay to allow click events
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showUnitDropdown = false; }, 200);
    }

    handleUnitSelect(event) {
        this.unitId = event.currentTarget.dataset.recordId;
        this.unitName = event.currentTarget.dataset.recordName;
        this.unitSearchTerm = '';
        this.unitResults = [];
        this.showUnitDropdown = false;
    }

    handleClearUnit() {
        this.unitId = '';
        this.unitName = '';
        this.unitSearchTerm = '';
        this.unitResults = [];
    }

    get hasUnitResults() {
        return this.unitResults.length > 0;
    }

    // ── Duration ─────────────────────────────────────────────────
    handleBlockDaysChange(event) {
        this.blockDays = event.detail.value;
    }

    // ── Reason ───────────────────────────────────────────────────
    handleReasonChange(event) {
        this.reason = event.detail.value;
    }

    // ── Approver Lookup ──────────────────────────────────────────
    handleApproverSearch(event) {
        this.approverSearchTerm = event.target.value;
        clearTimeout(this._approverSearchTimeout);
        if (this.approverSearchTerm.length < 2) {
            this.approverResults = [];
            this.showApproverDropdown = false;
            return;
        }
        this.isApproverSearching = true;
        this.showApproverDropdown = true;
        this._approverSearchTimeout = setTimeout(() => this.doApproverSearch(), 300);
    }

    async doApproverSearch() {
        try {
            const results = await searchActiveUsers({ searchTerm: this.approverSearchTerm });
            this.approverResults = results;
        } catch (error) {
            this.approverResults = [];
        } finally {
            this.isApproverSearching = false;
        }
    }

    handleApproverFocus() {
        if (this.approverResults.length > 0) {
            this.showApproverDropdown = true;
        }
    }

    handleApproverBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showApproverDropdown = false; }, 200);
    }

    handleApproverSelect(event) {
        this.approverId = event.currentTarget.dataset.recordId;
        this.approverName = event.currentTarget.dataset.recordName;
        this.approverSearchTerm = '';
        this.approverResults = [];
        this.showApproverDropdown = false;
    }

    handleClearApprover() {
        this.approverId = '';
        this.approverName = '';
        this.approverSearchTerm = '';
        this.approverResults = [];
    }

    get hasApproverResults() {
        return this.approverResults.length > 0;
    }

    // ── Submit / Cancel ──────────────────────────────────────────
    get isSubmitDisabled() {
        return !this.unitId || !this.approverId || !this.blockDays || !this.reason;
    }

    async handleSubmit() {
        if (this.isSubmitDisabled) return;

        this.isLoading = true;
        try {
            await createBlockRequest({
                unitId: this.unitId,
                projectId: this.projectId || null,
                leadId: this.recordId,
                approverId: this.approverId,
                blockDays: parseInt(this.blockDays, 10),
                reason: this.reason,
                isManagement: false
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'Unit block request submitted successfully.',
                variant: 'success'
            }));
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.showError('Failed to submit request: ' + this.reduceError(error));
        } finally {
            this.isLoading = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // ── Helpers ──────────────────────────────────────────────────
    showError(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message,
            variant: 'error'
        }));
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return JSON.stringify(error);
    }
}