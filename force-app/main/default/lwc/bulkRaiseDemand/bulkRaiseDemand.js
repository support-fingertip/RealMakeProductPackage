import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProjectContext from '@salesforce/apex/BulkDemandController.getProjectContext';
import getCompletedMilestones from '@salesforce/apex/BulkDemandController.getCompletedMilestones';
import getBookingsForMilestone from '@salesforce/apex/BulkDemandController.getBookingsForMilestone';
import getIndividualCompletedSchedules from '@salesforce/apex/BulkDemandController.getIndividualCompletedSchedules';
import createBulkDemands from '@salesforce/apex/BulkDemandController.createBulkDemands';
import sendBulkDemandEmails from '@salesforce/apex/BulkDemandController.sendBulkDemandEmails';
import getConfigurationByType from '@salesforce/apex/PostSalesAdminController.getConfigurationByType';
import resolveConfigurationForRecord from '@salesforce/apex/PostSalesAdminController.resolveConfigurationForRecord';
import getEmailTemplateOptions from '@salesforce/apex/PostSalesAdminController.getEmailTemplateOptions';
import getProjects from '@salesforce/apex/FormulaBuilderController.getProjects';

export default class BulkRaiseDemand extends LightningElement {
    @api recordId;

    // State
    @track isLoading = false;
    @track showModal = false;
    @track currentStep = 1;

    // Project selector (for Tab/AppPage mode)
    @track projectOptions = [];
    @track selectedProjectId = '';

    // Project context
    @track projectContext = {};
    @track demandConfig = {};

    // Step 2: Milestones (Apartment flow)
    @track milestones = [];
    @track selectedMilestoneId = null;

    // Step 3: Bookings
    @track bookings = [];
    @track selectAll = true;

    // Step 4: Review
    @track emailTemplateOptions = [];
    @track selectedTemplateId = '';
    @track gracePeriodDays = 15;
    @track dueDateOffsetDays = 15;
    @track includeInterest = true;
    @track includePreviousDues = false;
    @track autoSendEmail = false;
    @track notes = '';

    // Step 5/6: Results
    @track demandResult = {};
    @track isProcessing = false;

    // Flow type
    get isApartmentFlow() {
        const type = (this.projectContext.projectType || '').toLowerCase();
        return type === 'apartment';
    }

    get isIndividualFlow() {
        const type = (this.projectContext.projectType || '').toLowerCase();
        // Default to individual flow for Plot/Villa AND any other type (Mixed, Commercial, blank)
        // so the component doesn't show an empty screen
        return type !== 'apartment';
    }

    // Project selector (Tab/AppPage mode)
    get showProjectSelector() {
        return !this.recordId;
    }

    get launchDisabled() {
        return !this.recordId && !this.selectedProjectId;
    }

    get effectiveProjectId() {
        return this.recordId || this.selectedProjectId;
    }

    connectedCallback() {
        if (!this.recordId) {
            this.loadProjectList();
        }
    }

    loadProjectList() {
        getProjects()
            .then(result => {
                this.projectOptions = result.map(p => ({
                    label: p.Name,
                    value: p.Id
                }));
            })
            .catch(() => {});
    }

    handleProjectSelect(event) {
        this.selectedProjectId = event.detail.value;
    }

    // Step visibility
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get isStep4() { return this.currentStep === 4; }
    get isStep5() { return this.currentStep === 5; }
    get isStep6() { return this.currentStep === 6; }

    // Computed
    get hasMilestones() { return this.milestones && this.milestones.length > 0; }
    get hasBookings() { return this.bookings && this.bookings.length > 0; }
    get isLoadBookingsDisabled() { return !this.selectedMilestoneId; }

    get selectedBookings() {
        return this.bookings.filter(b => b.isSelected);
    }

    get selectedCount() {
        return this.selectedBookings.length;
    }

    get totalDemandAmount() {
        return this.selectedBookings.reduce((sum, b) => sum + (b.totalPending || 0), 0);
    }

    get totalInterestAmount() {
        return this.selectedBookings.reduce((sum, b) => sum + (b.totalInterest || 0), 0);
    }

    get totalNetAmount() {
        return this.selectedBookings.reduce((sum, b) => sum + (b.netDemandAmount || 0), 0);
    }

    get formattedTotalDemand() { return this.formatCurrency(this.totalDemandAmount); }
    get formattedTotalInterest() { return this.formatCurrency(this.totalInterestAmount); }
    get formattedTotalNet() { return this.formatCurrency(this.totalNetAmount); }

    get canProceedToReview() {
        return this.selectedCount > 0;
    }
    get isReviewDisabled() { return !this.canProceedToReview; }

    get selectedMilestoneName() {
        const ms = this.milestones.find(m => m.id === this.selectedMilestoneId);
        return ms ? ms.name : '';
    }

    get stepIndicator() {
        const steps = ['Init', 'Select', 'Bookings', 'Review', 'Process', 'Results'];
        return steps.map((label, idx) => ({
            label,
            number: idx + 1,
            isCurrent: this.currentStep === idx + 1,
            isComplete: this.currentStep > idx + 1,
            cssClass: this.currentStep === idx + 1 ? 'step-item step-current' :
                      this.currentStep > idx + 1 ? 'step-item step-complete' : 'step-item'
        }));
    }

    get hasResults() {
        return this.demandResult && this.demandResult.results && this.demandResult.results.length > 0;
    }

    get progressBarStyle() {
        const pct = Math.min(100, Math.max(0, (this.currentStep / 6) * 100));
        return `width: ${pct}%;`;
    }

    get footerContextText() {
        switch (this.currentStep) {
            case 2:
                return this.selectedMilestoneId
                    ? `Selected: ${this.selectedMilestoneName}`
                    : 'Select a milestone to continue';
            case 3:
                return this.selectedCount > 0
                    ? `${this.selectedCount} booking${this.selectedCount === 1 ? '' : 's'} selected · Net ${this.formattedTotalNet}`
                    : 'Select at least one booking';
            case 4:
                return `${this.selectedCount} booking${this.selectedCount === 1 ? '' : 's'} · Net ${this.formattedTotalNet}`;
            case 5:
                return 'Processing demands…';
            case 6:
                return this.demandResult && this.demandResult.totalProcessed
                    ? `${this.demandResult.successCount || 0} of ${this.demandResult.totalProcessed} succeeded`
                    : '';
            default:
                return '';
        }
    }

    // ============ LAUNCH ============

    handleLaunch() {
        if (!this.effectiveProjectId) {
            this.showToast('Project Required', 'Please select a project first.', 'warning');
            return;
        }
        this.showModal = true;
        this.currentStep = 1;
        this.loadProjectContext();
    }

    handleClose() {
        this.showModal = false;
        this.currentStep = 1;
        this.resetState();
    }

    resetState() {
        this.milestones = [];
        this.selectedMilestoneId = null;
        this.bookings = [];
        this.selectAll = true;
        this.selectedTemplateId = '';
        this.gracePeriodDays = 15;
        this.includeInterest = true;
        this.notes = '';
        this.demandResult = {};
        this.isProcessing = false;
    }

    // ============ STEP 1: PROJECT CONTEXT ============

    loadProjectContext() {
        this.isLoading = true;

        // Each promise has its own catch so one failure doesn't break all
        const contextPromise = getProjectContext({ projectId: this.effectiveProjectId })
            .catch(error => {
                this.showToast('Error', 'Failed to load project: ' + this.getErrorMessage(error), 'error');
                return null;
            });

        const configPromise = getConfigurationByType({ configurationType: 'Demand' })
            .catch(() => null);

        const templatesPromise = getEmailTemplateOptions()
            .catch(() => []);

        Promise.all([contextPromise, configPromise, templatesPromise])
            .then(([context, config, templates]) => {
                if (!context) {
                    this.isLoading = false;
                    return;
                }
                this.projectContext = context;

                if (config) {
                    this.demandConfig = config;
                    this.gracePeriodDays = config.gracePeriodDays != null ? config.gracePeriodDays : 15;
                    this.dueDateOffsetDays = config.dueDateOffsetDays != null ? config.dueDateOffsetDays : 15;
                    this.includeInterest = config.includeInterest || false;
                    this.includePreviousDues = config.includePreviousDues || false;
                    this.autoSendEmail = config.autoSendEmail || false;
                    if (config.emailTemplateId) {
                        this.selectedTemplateId = config.emailTemplateId;
                    }
                }

                if (templates) {
                    this.emailTemplateOptions = [
                        { label: '-- No Email --', value: '' },
                        ...templates.map(t => ({ label: t.label, value: t.value }))
                    ];
                }

                // Auto-advance based on project type
                this.currentStep = 2;
                this.loadStep2Data();
            })
            .finally(() => { this.isLoading = false; });
    }

    // ============ STEP 2: MILESTONE SELECTION ============

    loadStep2Data() {
        this.isLoading = true;
        // Always load all milestones regardless of flow type
        getCompletedMilestones({ projectId: this.effectiveProjectId })
            .then(result => {
                this.milestones = (result || []).map(ms => ({
                    ...ms,
                    cardClass: 'ms-card' + (ms.demandAlreadyRaised ? ' ms-card-raised' : ''),
                    radioClass: 'ms-radio'
                }));
            })
            .catch(error => { this.showToast('Error', this.getErrorMessage(error), 'error'); })
            .finally(() => { this.isLoading = false; });
    }

    handleMilestoneSelect(event) {
        const msId = event.currentTarget.dataset.id;
        this.selectedMilestoneId = msId;
        // Update card styling
        this.milestones = this.milestones.map(ms => ({
            ...ms,
            cardClass: 'ms-card' + (ms.id === msId ? ' ms-card-selected' : '') + (ms.demandAlreadyRaised ? ' ms-card-raised' : ''),
            radioClass: ms.id === msId ? 'ms-radio ms-radio-selected' : 'ms-radio'
        }));
    }

    handleLoadBookings() {
        if (!this.selectedMilestoneId) {
            this.showToast('Warning', 'Please select a milestone', 'warning');
            return;
        }

        this.isLoading = true;
        getBookingsForMilestone({
            projectId: this.effectiveProjectId,
            masterPaymentScheduleId: this.selectedMilestoneId
        })
        .then(result => {
            this.bookings = result.map(b => ({ ...b, isSelected: true }));
            this.currentStep = 3;
        })
        .catch(error => { this.showToast('Error', this.getErrorMessage(error), 'error'); })
        .finally(() => { this.isLoading = false; });
    }

    // For individual flow, go directly to step 3
    handleProceedIndividual() {
        const hasSelection = this.bookings.some(b => b.isSelected);
        if (!hasSelection) {
            this.showToast('Warning', 'Please select at least one booking', 'warning');
            return;
        }
        this.currentStep = 3;
    }

    // ============ STEP 3: BOOKING SELECTION ============

    handleSelectAll(event) {
        this.selectAll = event.target.checked;
        this.bookings = this.bookings.map(b => ({ ...b, isSelected: this.selectAll }));
    }

    handleBookingSelect(event) {
        const bookingId = event.currentTarget.dataset.id;
        this.bookings = this.bookings.map(b => {
            if (b.bookingId === bookingId) {
                return { ...b, isSelected: event.target.checked };
            }
            return b;
        });
        this.selectAll = this.bookings.every(b => b.isSelected);
    }

    handleGoToReview() {
        if (this.selectedCount === 0) {
            this.showToast('Warning', 'Please select at least one booking', 'warning');
            return;
        }
        this.currentStep = 4;
    }

    // ============ STEP 4: REVIEW & CONFIGURE ============

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
    }

    handleGracePeriodChange(event) {
        this.gracePeriodDays = event.detail.value;
    }

    handleInterestToggle(event) {
        this.includeInterest = event.target.checked;
    }

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    handleRaiseDemands() {
        this.currentStep = 5;
        this.isProcessing = true;

        const request = {
            projectId: this.effectiveProjectId,
            masterPaymentScheduleId: this.selectedMilestoneId,
            bookings: this.selectedBookings.map(b => ({
                bookingId: b.bookingId,
                demandAmount: b.totalPending,
                interestAmount: b.totalInterest,
                previousDues: 0,
                scheduleIds: b.scheduleItems ? b.scheduleItems.filter(s => s.isSelected !== false).map(s => s.scheduleId) : []
            })),
            gracePeriodDays: this.gracePeriodDays,
            dueDateOffsetDays: this.dueDateOffsetDays,
            includeInterest: this.includeInterest,
            includePreviousDues: this.includePreviousDues,
            notes: this.notes,
            demandType: 'Bulk Demand'
        };

        createBulkDemands({ requestJson: JSON.stringify(request) })
            .then(result => {
                this.demandResult = result;

                // Send emails if template selected or autoSendEmail is enabled
                if ((this.selectedTemplateId || this.autoSendEmail) && result.success) {
                    const demandIds = result.results
                        .filter(r => r.success && r.demandId)
                        .map(r => r.demandId);

                    if (demandIds.length > 0) {
                        return sendBulkDemandEmails({
                            demandIds: demandIds,
                            templateId: this.selectedTemplateId
                        }).then(() => {
                            this.demandResult.results = this.demandResult.results.map(r => ({
                                ...r,
                                emailSent: r.success
                            }));
                        });
                    }
                }
            })
            .then(() => {
                this.currentStep = 6;
                const variant = this.demandResult.failureCount === 0 ? 'success' : 'warning';
                const msg = `${this.demandResult.successCount} of ${this.demandResult.totalProcessed} demands created successfully`;
                this.showToast(variant === 'success' ? 'Success' : 'Partial Success', msg, variant);
            })
            .catch(error => {
                this.demandResult = { success: false, errorMessage: this.getErrorMessage(error), results: [] };
                this.currentStep = 6;
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => { this.isProcessing = false; });
    }

    // ============ NAVIGATION ============

    handleBack() {
        if (this.currentStep > 1) {
            if (this.currentStep === 3 && this.isApartmentFlow) {
                this.currentStep = 2;
            } else if (this.currentStep === 3 && this.isIndividualFlow) {
                this.currentStep = 2;
            } else if (this.currentStep === 4) {
                this.currentStep = 3;
            } else {
                this.currentStep--;
            }
        }
    }

    // ============ UTILITIES ============

    formatCurrency(value) {
        if (value === null || value === undefined) return '₹0.00';
        return '₹' + value.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
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