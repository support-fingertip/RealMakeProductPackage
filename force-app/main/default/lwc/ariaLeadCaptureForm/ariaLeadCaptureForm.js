import { LightningElement, track, wire } from 'lwc';
import getStates from '@salesforce/apex/AriaLeadFormController.getStates';
import getProjectsByState from '@salesforce/apex/AriaLeadFormController.getProjectsByState';
import getBhkOptionsForProject from '@salesforce/apex/AriaLeadFormController.getBhkOptionsForProject';
import getStaticOptions from '@salesforce/apex/AriaLeadFormController.getStaticOptions';
import submitLead from '@salesforce/apex/AriaLeadFormController.submitLead';

export default class AriaLeadCaptureForm extends LightningElement {

    @track stateOptions = [];
    @track projectOptions = [];
    @track bhkOptions = [];
    @track budgetOptions = [];
    @track purposeOptions = [];
    @track timelineOptions = [];

    // Selected project detail — shown as an inline info box so the exec sees
    // exactly which project they're creating the lead against.
    @track selectedProject = null;

    @track form = {
        state: '',
        projectId: '',
        projectCode: '',
        bhk: '',
        budget: '',
        purpose: '',
        timeline: '',
        firstName: '',
        lastName: '',
        mobile: '',
        email: ''
    };

    @track isLoadingProjects = false;
    @track isSubmitting = false;
    @track errorMessage = '';

    // ════════════════════════════════════════════════════════════
    // Wire
    // ════════════════════════════════════════════════════════════

    @wire(getStates)
    wiredStates({ data, error }) {
        if (data) this.stateOptions = data;
        if (error) this.errorMessage = this._formatError(error);
    }

    @wire(getStaticOptions)
    wiredStatic({ data, error }) {
        if (data) {
            this.budgetOptions = data.budgets || [];
            this.purposeOptions = data.purposes || [];
            this.timelineOptions = data.timelines || [];
        }
        if (error) this.errorMessage = this._formatError(error);
    }

    // ════════════════════════════════════════════════════════════
    // Cascading dropdown handlers
    // ════════════════════════════════════════════════════════════

    async handleStateChange(event) {
        const state = event.detail.value;
        this.form = { ...this.form, state, projectId: '', projectCode: '', bhk: '' };
        this.projectOptions = [];
        this.bhkOptions = [];
        this.selectedProject = null;
        this.errorMessage = '';

        if (!state) return;

        this.isLoadingProjects = true;
        try {
            this.projectOptions = await getProjectsByState({ state });
            if (!this.projectOptions.length) {
                this.errorMessage = `No active projects in ${state}. Pick another state.`;
            }
        } catch (e) {
            this.errorMessage = this._formatError(e);
        } finally {
            this.isLoadingProjects = false;
        }
    }

    async handleProjectChange(event) {
        const projectId = event.detail.value;
        const selected = this.projectOptions.find(p => p.value === projectId) || null;
        this.selectedProject = selected;
        const projectCode = selected ? selected.project_code : '';
        this.form = { ...this.form, projectId, projectCode, bhk: '' };
        this.bhkOptions = [];
        this.errorMessage = '';

        if (!projectId) return;

        try {
            this.bhkOptions = await getBhkOptionsForProject({ projectId });
        } catch (e) {
            this.errorMessage = this._formatError(e);
        }
    }

    handleBhkChange(event)        { this.form = { ...this.form, bhk: event.detail.value }; }
    handleBudgetChange(event)     { this.form = { ...this.form, budget: event.detail.value }; }
    handlePurposeChange(event)    { this.form = { ...this.form, purpose: event.detail.value }; }
    handleTimelineChange(event)   { this.form = { ...this.form, timeline: event.detail.value }; }
    handleFirstNameChange(event)  { this.form = { ...this.form, firstName: event.target.value }; }
    handleLastNameChange(event)   { this.form = { ...this.form, lastName: event.target.value }; }
    handleMobileChange(event)     { this.form = { ...this.form, mobile: (event.target.value || '').replace(/\D/g, '') }; }
    handleEmailChange(event)      { this.form = { ...this.form, email: event.target.value }; }

    // ════════════════════════════════════════════════════════════
    // Computed
    // ════════════════════════════════════════════════════════════

    get isProjectDisabled() { return !this.form.state || this.isLoadingProjects; }
    get isBhkDisabled()     { return !this.form.projectId; }

    get projectPlaceholder() {
        if (this.isLoadingProjects) return 'Loading projects…';
        if (!this.form.state) return 'Pick a state first';
        if (!this.projectOptions.length) return 'No active projects in this state';
        return 'Select project';
    }

    get hasProjectInfo() {
        return this.selectedProject != null;
    }

    get projectInfoLines() {
        if (!this.selectedProject) return [];
        const s = this.selectedProject;
        const lines = [];
        if (s.project_code)  lines.push(`Code: ${s.project_code}`);
        if (s.allowed_bhk)   lines.push(`BHK: ${s.allowed_bhk}`);
        if (s.property_types) lines.push(`Types: ${s.property_types}`);
        return lines.map((t, i) => ({ id: `pi-${i}`, text: t }));
    }

    get isMobileValid() {
        return this.form.mobile && this.form.mobile.length >= 10;
    }

    get isSubmitDisabled() {
        return this.isSubmitting
            || !this.form.projectCode
            || !this.isMobileValid
            || (!this.form.firstName && !this.form.lastName);
    }

    get submitHelpText() {
        if (!this.form.projectCode)                        return 'Select a project first.';
        if (!this.form.firstName && !this.form.lastName)   return 'Enter the customer\'s name.';
        if (!this.isMobileValid)                           return 'Enter a 10-digit mobile number.';
        return '';
    }

    // ════════════════════════════════════════════════════════════
    // Submit / Cancel
    // ════════════════════════════════════════════════════════════

    async handleSubmit() {
        this.errorMessage = '';
        if (this.isSubmitDisabled) return;

        const payload = {
            first_name:         this.form.firstName,
            last_name:          this.form.lastName || this.form.firstName,
            mobile:             this.form.mobile,
            email:              this.form.email,
            project_code:       this.form.projectCode,
            bhk_preference:     this.form.bhk,
            budget_range:       this.form.budget,
            purchase_purpose:   this.form.purpose,
            purchase_timeline:  this.form.timeline,
            source:             'Aria AI',
            sub_source:         'Aria Form'
        };

        this.isSubmitting = true;
        try {
            const result = await submitLead({ payloadJson: JSON.stringify(payload) });
            // The controller throws on ERROR-action lead results now, so a
            // successful resolve means we genuinely have a record.
            this.dispatchEvent(new CustomEvent('leadcreated', {
                detail: {
                    leadId:  result.lead_id,
                    action:  result.action,
                    message: result.message
                }
            }));
        } catch (e) {
            this.errorMessage = this._formatError(e);
        } finally {
            this.isSubmitting = false;
        }
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleBackdropClick(event) {
        if (event.target.classList.contains('aria-form-backdrop')) {
            this.handleCancel();
        }
    }

    _formatError(e) {
        if (!e) return 'Something went wrong.';
        if (e.body && e.body.message) return e.body.message;
        if (e.message) return e.message;
        return JSON.stringify(e);
    }
}