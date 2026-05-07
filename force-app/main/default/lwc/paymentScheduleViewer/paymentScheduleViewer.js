import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getPaymentSchedules from '@salesforce/apex/PaymentScheduleViewController.getPaymentSchedules';

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

    // View states (main | nextDemand | email)
    @track showMainModal = true;
    @track showNextDemandView = false;
    @track showEmailModal = false;

    // Load data on component initialization
    connectedCallback() {
        if (this.recordId) {
            this.loadData();
        } else {
            this.hasError = true;
            this.errorMessage = 'Booking ID is missing. Please launch this action from a Booking record.';
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
        this.schedules = result.schedules || [];
        this.nextDemand = result.nextDemand || {};
        this.bookingName = result.bookingName || '';
        this.projectName = result.projectName || 'N/A';
        this.unitName = result.unitName || 'N/A';
        
        console.log('Processed - Schedules:', this.schedules.length);
        console.log('Next Demand Total:', this.nextDemand.grandTotal);
    }
    
    // Handle "Next" button click - Show Next Demand View
    handleNext() {
        if (this.hasNextDemand) {
            this.showMainModal = false;
            this.showNextDemandView = true;
        } else {
            this.showToast('Info', 'No completed schedules with pending amounts.', 'info');
        }
    }
    
    // Handle "Back" button - Return to main view
    handleBack() {
        this.showNextDemandView = false;
        this.showEmailModal = false;
        this.showMainModal = true;
    }
    
    // Handle "Send Email" button - Open email modal
    handleSendEmail() {
        this.showEmailModal = true;
    }
    
    // Handle email modal close
    handleCloseEmailModal() {
        this.showEmailModal = false;
    }
    
    // Handle email sent successfully
    handleEmailSent() {
        this.showEmailModal = false;
        this.showToast('Success', 'Demand email sent successfully!', 'success');
        
        // Close the entire component after 1 second
        setTimeout(() => {
            this.handleClose();
        }, 1000);
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
    
    get hasNextDemand() {
        return this.nextDemand && this.nextDemand.grandTotal > 0;
    }
    
    get nextDemandTitle() {
        return `Next Demand Summary`;
    }
    
    get completedSchedulesText() {
        return `${this.nextDemand.completedScheduleCount || 0} Completed Schedule${this.nextDemand.completedScheduleCount !== 1 ? 's' : ''}`;
    }
}