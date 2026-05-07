import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import evaluateDiscounts from '@salesforce/apex/DiscountApprovalController.evaluateDiscounts';
import submitForApproval from '@salesforce/apex/DiscountApprovalController.submitForApproval';
import approveDiscount from '@salesforce/apex/DiscountApprovalController.approveDiscount';
import rejectDiscount from '@salesforce/apex/DiscountApprovalController.rejectDiscount';
import recallApproval from '@salesforce/apex/DiscountApprovalController.recallApproval';
import getApprovalHistory from '@salesforce/apex/DiscountApprovalController.getApprovalHistory';
import resendNotification from '@salesforce/apex/DiscountApprovalController.resendNotification';
import Id from '@salesforce/user/Id';

export default class DiscountApprovalPanel extends LightningElement {
    @api recordId;
    @track summary = null;
    @track history = [];
    @track isLoading = true;
    @track showHistory = false;
    @track comments = '';
    @track showCommentModal = false;
    @track pendingAction = null; // { type: 'approve'|'reject'|'submit', fieldNumber: n }

    currentUserId = Id;

    connectedCallback() {
        this.loadEvaluation();
    }

    async loadEvaluation() {
        this.isLoading = true;
        try {
            this.summary = await evaluateDiscounts({ costSheetId: this.recordId });
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed getters ──────────────────────────────────────

    get hasDiscounts() {
        return this.summary && this.summary.discounts &&
               this.summary.discounts.some(d => d.value > 0);
    }

    get activeDiscounts() {
        if (!this.summary || !this.summary.discounts) return [];
        return this.summary.discounts
            .filter(d => d.value > 0)
            .map(d => ({
                ...d,
                key: 'disc-' + d.fieldNumber,
                statusVariant: this.getStatusVariant(d.status),
                statusIcon: this.getStatusIcon(d.status),
                showApproveReject: d.status === 'Pending Approval' && this.isApprover(d),
                formattedValue: this.formatCurrency(d.value),
                formattedMax: d.maxAllowed != null ? this.formatCurrency(d.maxAllowed) : 'N/A',
                formattedPct: d.pct != null && d.pct !== undefined ? Number(d.pct).toFixed(2) + '%' : 'N/A',
                formattedMaxPct: d.maxPctAllowed != null && d.maxPctAllowed !== undefined ? Number(d.maxPctAllowed).toFixed(2) + '%' : 'N/A',
                exceedsClass: d.exceedsLimit ? 'slds-text-color_error' : 'slds-text-color_success'
            }));
    }

    get overallStatusVariant() {
        if (!this.summary) return 'default';
        return this.getStatusVariant(this.summary.overallStatus);
    }

    get showSubmitButton() {
        return this.summary && this.summary.requiresApproval &&
               this.summary.overallStatus !== 'Pending';
    }

    get historyButtonLabel() {
        return this.showHistory ? 'Hide History' : 'Show Approval History';
    }

    get showRecallButton() {
        return this.summary &&
               (this.summary.overallStatus === 'Pending' ||
                this.summary.overallStatus === 'Partially Approved');
    }

    get isPending() {
        return this.summary && this.summary.overallStatus === 'Pending';
    }

    get historyColumns() {
        return [
            { label: 'Discount', fieldName: 'label', type: 'text' },
            { label: 'Action', fieldName: 'action', type: 'text' },
            { label: 'Approver', fieldName: 'approverName', type: 'text' },
            { label: 'Comments', fieldName: 'comments', type: 'text' },
            {
                label: 'Timestamp', fieldName: 'timestamp', type: 'date',
                typeAttributes: {
                    year: 'numeric', month: 'short', day: 'numeric',
                    hour: '2-digit', minute: '2-digit'
                }
            }
        ];
    }

    // ── Actions ──────────────────────────────────────────────

    handleSubmit() {
        this.pendingAction = { type: 'submit' };
        this.comments = '';
        this.showCommentModal = true;
    }

    handleApprove(event) {
        const fieldNumber = parseInt(event.currentTarget.dataset.field, 10);
        this.pendingAction = { type: 'approve', fieldNumber };
        this.comments = '';
        this.showCommentModal = true;
    }

    handleReject(event) {
        const fieldNumber = parseInt(event.currentTarget.dataset.field, 10);
        this.pendingAction = { type: 'reject', fieldNumber };
        this.comments = '';
        this.showCommentModal = true;
    }

    handleCommentChange(event) {
        this.comments = event.target.value;
    }

    async handleConfirmAction() {
        this.showCommentModal = false;
        this.isLoading = true;

        try {
            if (this.pendingAction.type === 'submit') {
                this.summary = await submitForApproval({
                    costSheetId: this.recordId,
                    comments: this.comments
                });
                this.showSuccess('Discounts submitted for approval.');
                // Surface any notification warnings to the user
                if (this.summary.warnings && this.summary.warnings.length > 0) {
                    this.dispatchEvent(new ShowToastEvent({
                        title: 'Notification Warning',
                        message: this.summary.warnings.join(' | '),
                        variant: 'warning',
                        mode: 'sticky'
                    }));
                }
            } else if (this.pendingAction.type === 'approve') {
                await approveDiscount({
                    costSheetId: this.recordId,
                    fieldNumber: this.pendingAction.fieldNumber,
                    comments: this.comments
                });
                this.showSuccess('Discount approved successfully.');
                await this.loadEvaluation();
            } else if (this.pendingAction.type === 'reject') {
                await rejectDiscount({
                    costSheetId: this.recordId,
                    fieldNumber: this.pendingAction.fieldNumber,
                    comments: this.comments
                });
                this.showSuccess('Discount rejected.');
                await this.loadEvaluation();
            }
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isLoading = false;
            this.pendingAction = null;
        }
    }

    handleCancelAction() {
        this.showCommentModal = false;
        this.pendingAction = null;
    }

    async handleResendNotification() {
        this.isLoading = true;
        try {
            const diagnostics = await resendNotification({ costSheetId: this.recordId });
            if (diagnostics && diagnostics.length > 0) {
                const hasWarning = diagnostics.some(d => d.includes('WARNING') || d.includes('failed') || d.includes('skipped'));
                this.dispatchEvent(new ShowToastEvent({
                    title: hasWarning ? 'Notification Diagnostics' : 'Notification Sent',
                    message: diagnostics.join(' | '),
                    variant: hasWarning ? 'warning' : 'success',
                    mode: 'sticky'
                }));
            } else {
                this.showSuccess('Notification resent successfully.');
            }
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isLoading = false;
        }
    }

    async handleRecall() {
        this.isLoading = true;
        try {
            await recallApproval({ costSheetId: this.recordId });
            this.showSuccess('Approval recalled successfully.');
            await this.loadEvaluation();
        } catch (error) {
            this.showError(this.reduceErrors(error));
        } finally {
            this.isLoading = false;
        }
    }

    async toggleHistory() {
        this.showHistory = !this.showHistory;
        if (this.showHistory && this.history.length === 0) {
            try {
                this.history = await getApprovalHistory({ costSheetId: this.recordId });
            } catch (error) {
                this.showError(this.reduceErrors(error));
            }
        }
    }

    handleRefresh() {
        this.loadEvaluation();
    }

    // ── Helpers ──────────────────────────────────────────────

    isApprover(discount) {
        return discount.approverId === this.currentUserId;
    }

    getStatusVariant(status) {
        const variants = {
            'Within Limit': 'success',
            'Approved': 'success',
            'Not Required': 'default',
            'N/A': 'default',
            'Pending Approval': 'warning',
            'Pending': 'warning',
            'Partially Approved': 'warning',
            'Rejected': 'error'
        };
        return variants[status] || 'default';
    }

    getStatusIcon(status) {
        const icons = {
            'Within Limit': 'utility:success',
            'Approved': 'utility:success',
            'Pending Approval': 'utility:clock',
            'Pending': 'utility:clock',
            'Rejected': 'utility:error',
            'N/A': 'utility:dash'
        };
        return icons[status] || 'utility:info';
    }

    formatCurrency(val) {
        if (val == null) return '0.00';
        return Number(val).toLocaleString('en-IN', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    showSuccess(msg) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success', message: msg, variant: 'success'
        }));
    }

    showError(msg) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error', message: msg, variant: 'error', mode: 'sticky'
        }));
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