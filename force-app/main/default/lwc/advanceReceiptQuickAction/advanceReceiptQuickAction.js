import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class AdvanceReceiptQuickAction extends NavigationMixin(LightningElement) {
    @api recordId; // Contact Id from quick action context
    @track selectedProjectId;
    @track selectedUnitId;
    @track paymentMode;

    get isTxnRequired() {
        return this.paymentMode && this.paymentMode !== 'Cash';
    }

    get isBankRequired() {
        return this.paymentMode === 'Cheque';
    }

    handleProjectChange(event) {
        const projectId = event.detail.value;
        this.selectedProjectId = projectId;

        // Clear any previously selected Unit in the custom lookup
        const unitLookup = this.template.querySelector('c-unit-lookup');
        if (unitLookup) {
            unitLookup.clearSelection();
        }
    }

    handleUnitSelect(event) {
        // Expect custom event detail like { unitId: 'a01xx...', unitName: '...' }
        this.selectedUnitId = event.detail && event.detail.unitId ? event.detail.unitId : null;
    }

    handlePaymentModeChange(event) {
        // lightning-input-field emits value in event.detail.value
        this.paymentMode = event.detail.value;
    }

    handleCancel() {
        // Close quick action by navigating back to the record page
        if (this.recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.recordId,
                    objectApiName: 'Contact',
                    actionName: 'view'
                }
            });
        }
    }

    handleSubmit(event) {
        // Enforce Project -> Unit rules on client prior to submit
        event.preventDefault();
        const fields = event.detail.fields;

        // Ensure Customer is current contact and not editable
        fields.Customer__c = this.recordId;

        // Block unit without project
        if (!this.selectedProjectId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation',
                    message: 'Select Project before choosing a Unit.',
                    variant: 'error'
                })
            );
            return;
        }

        // Ensure Unit is selected
        if (!this.selectedUnitId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation',
                    message: 'Select a Unit.',
                    variant: 'error'
                })
            );
            return;
        }

        // Assign Unit__c and set system-controlled defaults
        fields.Unit__c = this.selectedUnitId;
        fields.Project__c = this.selectedProjectId;
        fields.Status__c = 'Advance';
        fields.Approval_Status__c = 'Pending';

        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSuccess(event) {
        const recId = event.detail.id;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Advance Receipt created.',
                variant: 'success'
            })
        );

        // Redirect to created record
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recId,
                objectApiName: 'Advance_Receipt__c',
                actionName: 'view'
            }
        });
    }

    handleError(event) {
        let message = 'An unexpected error occurred';
        if (event && event.detail && event.detail.detail) {
            message = event.detail.detail;
        } else if (event && event.detail && event.detail.message) {
            message = event.detail.message;
        }
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error creating Advance Receipt',
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }
}