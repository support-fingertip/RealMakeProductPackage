import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getPaymentSchedules from '@salesforce/apex/PaymentScheduleViewController.getPaymentSchedules';
import saveScheduleAmounts from '@salesforce/apex/PaymentScheduleViewController.saveScheduleAmounts';
import getConfigurationByType from '@salesforce/apex/PostSalesAdminController.getConfigurationByType';

export default class PaymentScheduleEditor extends LightningElement {
    @api recordId; // Booking ID from Quick Action

    @track isLoading = false;
    @track schedules = [];
    @track nextDemand = {};
    @track bookingName = '';
    @track projectName = '';
    @track unitName = '';
    @track errorMessage = '';
    @track hasError = false;

    // View states
    @track showMainModal = true;

    // Edit state
    @track changedAmounts = {};
    @track isSaving = false;
    @track bookingTotal = 0;
    @track scheduleMode = 'Standard';
    @track isCustomMode = false;

    // Load data on component initialization
    connectedCallback() {
        // Small delay to ensure recordId is injected by the ScreenAction framework
        setTimeout(() => {
            if (this.recordId) {
                this.loadScheduleConfig();
                this.loadData();
            } else {
                this.hasError = true;
                this.errorMessage = 'Booking ID is missing. Please launch this action from a Booking record.';
            }
        }, 150);
    }

    loadScheduleConfig() {
        getConfigurationByType({ configurationType: 'Payment Schedule' })
            .then(config => {
                if (config && config.scheduleMode) {
                    this.scheduleMode = config.scheduleMode;
                    this.isCustomMode = config.scheduleMode === 'Custom';
                }
            })
            .catch(() => {
                // No config = default Standard (not editable)
                this.isCustomMode = false;
            });
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
        
        console.log('Loading data for Booking:', this.recordId);
        
        getPaymentSchedules({ bookingId: this.recordId })
            .then(result => {
                console.log('Result:', JSON.stringify(result));
                
                if (result.success) {
                    this.processData(result);
                } else {
                    this.hasError = true;
                    this.errorMessage = result.errorMessage || 'Unknown error occurred';
                    this.showToast('Error', this.errorMessage, 'error');
                }
            })
            .catch(error => {
                console.error('Error:', error);
                this.hasError = true;
                this.errorMessage = this.getErrorMessage(error);
                this.showToast('Error', this.errorMessage, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    // Process data from Apex
    processData(result) {
        this.changedAmounts = {};
        this.schedules = (result.schedules || []).map(s => ({
            ...s,
            demandRaised: s.status === 'Paid' || s.status === 'Completed' || s.isPaid || s.isCompleted,
            isEditable: this.isCustomMode && !(s.isPaid || s.isCompleted),
            rowClass: (s.isPaid || s.isCompleted) ? 'row-locked' : (!this.isCustomMode ? 'row-locked' : '')
        }));
        this.nextDemand = result.nextDemand || {};
        this.bookingName = result.bookingName || '';
        this.projectName = result.projectName || 'N/A';
        this.unitName = result.unitName || 'N/A';

        // Use booking's actual Total Payable Amount for validation (not sum of schedules)
        this.bookingTotal = result.totalPayableAmount || 0;
    }

    // ============ AMOUNT EDITING ============

    handleAmountChange(event) {
        const scheduleId = event.currentTarget.dataset.id;
        const newAmount = parseFloat(event.detail.value) || 0;

        this.changedAmounts = { ...this.changedAmounts, [scheduleId]: newAmount };

        this.schedules = this.schedules.map(s => {
            if (s.id === scheduleId) {
                return {
                    ...s,
                    amount: newAmount,
                    pendingAmount: newAmount,
                    formattedAmount: this._formatCurrency(newAmount),
                    formattedPending: this._formatCurrency(newAmount)
                };
            }
            return s;
        });
    }

    async handleSaveAmounts() {
        if (Object.keys(this.changedAmounts).length === 0) return;

        // Client-side validation: total must match booking total
        const currentTotal = this.schedules.reduce((sum, s) => sum + (s.amount || 0), 0);
        if (this.bookingTotal > 0 && Math.abs(currentTotal - this.bookingTotal) > 0.01) {
            const diff = this.bookingTotal - currentTotal;
            this.showToast(
                'Validation Error',
                `Total of all schedules (${this._formatCurrency(currentTotal)}) must equal booking total (${this._formatCurrency(this.bookingTotal)}). Difference: ${this._formatCurrency(diff)}`,
                'error'
            );
            return;
        }

        this.isSaving = true;
        try {
            await saveScheduleAmounts({
                bookingId: this.recordId,
                amountsJson: JSON.stringify(this.changedAmounts)
            });
            this.showToast('Success', 'Payment schedule amounts updated successfully', 'success');
            this.changedAmounts = {};
            this.loadData();
        } catch (error) {
            this.showToast('Error', this.getErrorMessage(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    get totalMismatch() {
        if (this.bookingTotal <= 0) return false;
        const currentTotal = this.schedules.reduce((sum, s) => sum + (s.amount || 0), 0);
        return Math.abs(currentTotal - this.bookingTotal) > 0.01;
    }

    get totalDifference() {
        const currentTotal = this.schedules.reduce((sum, s) => sum + (s.amount || 0), 0);
        return this._formatCurrency(this.bookingTotal - currentTotal);
    }

    get formattedBookingTotal() {
        return this._formatCurrency(this.bookingTotal);
    }

    get hasChanges() {
        return Object.keys(this.changedAmounts).length > 0;
    }

    get formattedTotalAmount() {
        const total = this.schedules.reduce((sum, s) => sum + (s.amount || 0), 0);
        return this._formatCurrency(total);
    }

    get formattedTotalPending() {
        const total = this.schedules.reduce((sum, s) => sum + (s.pendingAmount || 0), 0);
        return this._formatCurrency(total);
    }

    get formattedTotalInterest() {
        const total = this.schedules.reduce((sum, s) => sum + (s.interestPending || 0), 0);
        return this._formatCurrency(total);
    }

    _formatCurrency(value) {
        if (value == null) return '₹0';
        return '₹' + Number(value).toLocaleString('en-IN');
    }

    // Refresh data
    handleRefresh() {
        this.loadData();
    }
    
    // Close the modal (for Quick Action)
    handleClose() {
        // Dispatch close event for Quick Action
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    
    // Show toast notification
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    
    // Get error message from error object
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
    
    // Computed properties
    get hasSchedules() {
        return this.schedules && this.schedules.length > 0;
    }
}