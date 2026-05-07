import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord } from 'lightning/uiRecordApi';
import getPaymentSchedules from '@salesforce/apex/PaymentScheduleViewController.getPaymentSchedules';
import getTemplatesForAction from '@salesforce/apex/DocumentViewerController.getTemplatesForAction';
import resolveEmailTemplateForAction from '@salesforce/apex/ConfigMatchingService.resolveEmailTemplateForAction';

export default class PaymentScheduleViewer extends LightningElement {
    @api recordId; // Booking ID from Quick Action

    @track isLoading = false;
    @track schedules = [];
    @track nextDemand = {};
    @track bookingName = '';
    @track projectName = '';
    @track unitName = '';
    @track errorMessage = '';
    @track hasError = false;

    // Modal states
    @track showMainModal = false;
    @track showNextDemandView = false;
    @track showDocumentView = false;

    // Next Demand specific fields
    @track lastCompletedMilestone = '';
    @track totalPaidAmount = 0;
    @track formattedPaidAmount = '₹0.00';
    @track paymentDueDate = '';

    // Document preview fields
    @track documentTemplates = [];
    @track isLoadingDocuments = false;
    @track selectedDocUrl = '';
    @track selectedDocName = '';
    @track showDocPreview = false;

    // Email config fields
    @track resolvedEmailTemplateId = '';
    @track isResolvingEmail = false;
    @track showEmailSender = false;

    // Wire to ensure recordId is available
    @wire(getRecord, { recordId: '$recordId', fields: ['Booking__c.Id'] })
    wiredRecord({ error, data }) {
        if (data) {
            console.log('Record loaded successfully:', this.recordId);
            if (!this.showMainModal && !this.showNextDemandView && !this.showDocumentView) {
                this.showMainModal = true;
                this.loadData();
            }
        } else if (error) {
            console.error('Error loading record:', error);
            this.hasError = true;
            this.errorMessage = 'Unable to load booking record';
        }
    }

    // Load data on component initialization
    connectedCallback() {
        console.log('Connected - RecordId:', this.recordId);
        this.addBodyClass();

        setTimeout(() => {
            if (this.recordId) {
                this.showMainModal = true;
                this.loadData();
            } else {
                this.hasError = true;
                this.errorMessage = 'Booking ID is missing. Please ensure this component is launched from a Booking record.';
                this.showMainModal = true;
            }
        }, 100);
    }

    disconnectedCallback() {
        this.removeBodyClass();
    }

    addBodyClass() {
        try {
            document.body.classList.add('modal-open');
        } catch (e) {
            console.error('Error adding body class:', e);
        }
    }

    removeBodyClass() {
        try {
            document.body.classList.remove('modal-open');
        } catch (e) {
            console.error('Error removing body class:', e);
        }
    }

    // Load payment schedules
    loadData() {
        if (!this.recordId) {
            console.error('No recordId available');
            this.hasError = true;
            this.errorMessage = 'Booking ID is required';
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.hasError = false;
        this.errorMessage = '';

        getPaymentSchedules({ bookingId: this.recordId })
            .then(result => {
                if (result.success) {
                    this.processData(result);
                } else {
                    this.hasError = true;
                    this.errorMessage = result.errorMessage || 'Unknown error occurred';
                    this.showToast('Error', this.errorMessage, 'error');
                }
            })
            .catch(error => {
                this.hasError = true;
                this.errorMessage = this.getErrorMessage(error);
                this.showToast('Error', this.errorMessage, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    processData(result) {
        this.schedules = result.schedules || [];
        this.nextDemand = result.nextDemand || {};
        this.bookingName = result.bookingName || '';
        this.projectName = result.projectName || 'N/A';
        this.unitName = result.unitName || 'N/A';
        this.calculateNextDemandDetails();
    }

    calculateNextDemandDetails() {
        let lastCompleted = null;
        for (let i = this.schedules.length - 1; i >= 0; i--) {
            if (this.schedules[i].isCompleted) {
                lastCompleted = this.schedules[i];
                break;
            }
        }

        this.lastCompletedMilestone = lastCompleted
            ? lastCompleted.milestoneName
            : 'No completed milestones';

        let totalScheduleAmount = 0;
        let totalPendingAmount = 0;

        this.schedules.forEach(schedule => {
            totalScheduleAmount += schedule.amount || 0;
            totalPendingAmount += schedule.pendingAmount || 0;
        });

        this.totalPaidAmount = totalScheduleAmount - totalPendingAmount;
        this.formattedPaidAmount = this.formatCurrency(this.totalPaidAmount);

        const today = new Date();
        const dueDate = new Date(today);
        dueDate.setDate(dueDate.getDate() + 15);
        this.paymentDueDate = this.formatDate(dueDate);
    }

    formatCurrency(value) {
        if (value === null || value === undefined) {
            return '₹0.00';
        }
        return '₹' + value.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    formatDate(date) {
        const options = { year: 'numeric', month: 'long', day: 'numeric' };
        return date.toLocaleDateString('en-IN', options);
    }

    // ==================== NAVIGATION ====================

    handleNext() {
        this.showMainModal = false;
        this.showNextDemandView = true;
    }

    handleBack() {
        this.showNextDemandView = false;
        this.showDocumentView = false;
        this.showDocPreview = false;
        this.selectedDocUrl = '';
        this.selectedDocName = '';
        this.showMainModal = true;
    }

    handleBackToNextDemand() {
        this.showDocumentView = false;
        this.showDocPreview = false;
        this.selectedDocUrl = '';
        this.selectedDocName = '';
        this.showNextDemandView = true;
    }

    handleViewDocuments() {
        this.showNextDemandView = false;
        this.showDocumentView = true;
        this.loadDocumentTemplates();
        this.resolveEmailTemplate();
    }

    // ==================== DOCUMENT TEMPLATES ====================

    loadDocumentTemplates() {
        if (!this.recordId) return;
        this.isLoadingDocuments = true;

        getTemplatesForAction({ recordId: this.recordId, objectApiName: 'Booking__c', actionName: 'Demand Raiser' })
            .then(result => {
                this.documentTemplates = (result || []).map((t, i) => ({
                    ...t,
                    _key: 'doc-' + i,
                    _index: i + 1
                }));
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load document templates', 'error');
                this.documentTemplates = [];
            })
            .finally(() => {
                this.isLoadingDocuments = false;
            });
    }

    handlePreviewDocument(event) {
        const url = event.currentTarget.dataset.url;
        const name = event.currentTarget.dataset.name;
        this.selectedDocUrl = url;
        this.selectedDocName = name;
        this.showDocPreview = true;
    }

    handleCloseDocPreview() {
        this.showDocPreview = false;
        this.selectedDocUrl = '';
        this.selectedDocName = '';
    }

    handleDownloadPdf(event) {
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    // ==================== EMAIL CONFIG ====================

    resolveEmailTemplate() {
        this.isResolvingEmail = true;
        resolveEmailTemplateForAction({
            actionName: 'Demand Raiser',
            recordId: this.recordId,
            objectApiName: 'Booking__c'
        })
            .then(templateId => {
                this.resolvedEmailTemplateId = templateId || '';
            })
            .catch(error => {
                console.error('Error resolving email template:', error);
                this.resolvedEmailTemplateId = '';
            })
            .finally(() => {
                this.isResolvingEmail = false;
            });
    }

    handleSendEmail() {
        if (!this.resolvedEmailTemplateId) {
            this.showToast('Warning', 'No email template is configured for the Demand Raiser action. Please configure one in Email Templates admin.', 'warning');
            return;
        }
        this.showEmailSender = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const emailSender = this.template.querySelector('c-email-sender');
            if (emailSender) {
                emailSender.openWithTemplate(this.resolvedEmailTemplateId);
            }
        }, 100);
    }

    handleEmailSent() {
        this.showEmailSender = false;
        this.showToast('Success', 'Demand email sent successfully!', 'success');
    }

    handleRefresh() {
        this.loadData();
    }

    handleClose() {
        this.removeBodyClass();
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleBackdropClick(event) {
        if (event.target.classList.contains('modal-container')) {
            // Optionally close on backdrop click
        }
    }

    handleModalClick(event) {
        event.stopPropagation();
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
        return 'Unknown error occurred';
    }

    // ==================== COMPUTED PROPERTIES ====================

    get hasSchedules() {
        return this.schedules && this.schedules.length > 0;
    }

    get hasNextDemand() {
        return this.nextDemand && this.nextDemand.grandTotal > 0;
    }

    get nextDemandTitle() {
        return 'Next Demand Summary';
    }

    get completedSchedulesText() {
        const count = this.nextDemand.completedScheduleCount || 0;
        return `${count} Completed Schedule${count !== 1 ? 's' : ''}`;
    }

    get hasDocumentTemplates() {
        return this.documentTemplates && this.documentTemplates.length > 0;
    }

    get documentCount() {
        return this.documentTemplates ? this.documentTemplates.length : 0;
    }

    get hasResolvedEmailTemplate() {
        return !!this.resolvedEmailTemplateId;
    }

    get sendEmailDisabled() {
        return !this.resolvedEmailTemplateId || this.isResolvingEmail;
    }

    // Step indicator computed
    get stepIndicatorClasses() {
        if (this.showMainModal) return { step1: 'step-dot active', step2: 'step-dot', step3: 'step-dot' };
        if (this.showNextDemandView) return { step1: 'step-dot done', step2: 'step-dot active', step3: 'step-dot' };
        if (this.showDocumentView) return { step1: 'step-dot done', step2: 'step-dot done', step3: 'step-dot active' };
        return { step1: 'step-dot', step2: 'step-dot', step3: 'step-dot' };
    }

    get step1DotClass() { return this.stepIndicatorClasses.step1; }
    get step2DotClass() { return this.stepIndicatorClasses.step2; }
    get step3DotClass() { return this.stepIndicatorClasses.step3; }

    // Expanded detail calculation values
    get hasGstBreakdown() {
        return this.schedules.some(s => s.gstAmount > 0 || s.basePending > 0);
    }

    get totalBaseAmount() {
        let total = 0;
        this.schedules.forEach(s => { total += s.baseAmount || 0; });
        return this.formatCurrency(total);
    }

    get totalGstAmount() {
        let total = 0;
        this.schedules.forEach(s => { total += s.gstAmount || 0; });
        return this.formatCurrency(total);
    }

    get totalScheduleAmount() {
        let total = 0;
        this.schedules.forEach(s => { total += s.amount || 0; });
        return this.formatCurrency(total);
    }

    get totalBasePaid() {
        let total = 0;
        this.schedules.forEach(s => { total += s.basePaid || 0; });
        return this.formatCurrency(total);
    }

    get totalGstPaid() {
        let total = 0;
        this.schedules.forEach(s => { total += s.gstPaid || 0; });
        return this.formatCurrency(total);
    }

    get totalBasePending() {
        let total = 0;
        this.schedules.forEach(s => { total += s.basePending || 0; });
        return this.formatCurrency(total);
    }

    get totalGstPending() {
        let total = 0;
        this.schedules.forEach(s => { total += s.gstPending || 0; });
        return this.formatCurrency(total);
    }

    get totalPending() {
        let total = 0;
        this.schedules.forEach(s => { total += s.pendingAmount || 0; });
        return this.formatCurrency(total);
    }

    get totalInterest() {
        let total = 0;
        this.schedules.forEach(s => { total += s.interestPending || 0; });
        return this.formatCurrency(total);
    }

    get hasAnyInterest() {
        return this.schedules.some(s => (s.interestPending || 0) > 0);
    }

    get completedSchedules() {
        return this.schedules.filter(s => s.isCompleted);
    }

    get paidSchedules() {
        return this.schedules.filter(s => s.isPaid);
    }

    get pendingSchedules() {
        return this.schedules.filter(s => !s.isPaid && !s.isCompleted);
    }

    get completedCount() {
        return this.completedSchedules.length;
    }

    get paidCount() {
        return this.paidSchedules.length;
    }

    get pendingCount() {
        return this.pendingSchedules.length;
    }

    get totalCount() {
        return this.schedules.length;
    }

    get progressPercent() {
        if (!this.schedules.length) return 0;
        return Math.round(((this.paidCount + this.completedCount) / this.totalCount) * 100);
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%`;
    }
}