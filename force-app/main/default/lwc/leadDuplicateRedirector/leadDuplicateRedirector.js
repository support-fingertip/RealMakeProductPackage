import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDuplicateOfId from '@salesforce/apex/LeadDuplicateController.getDuplicateOfId';
import deleteDuplicateLead from '@salesforce/apex/LeadDuplicateController.deleteDuplicateLead';

export default class LeadDuplicateRedirector extends NavigationMixin(LightningElement) {
    @api recordId;
    _hasRedirected = false;

    connectedCallback() {
        this.checkDuplicate();
    }

    async checkDuplicate() {
        if (this._hasRedirected) return;
        try {
            const duplicateOfId = await getDuplicateOfId({ recordId: this.recordId });
            if (duplicateOfId && !this._hasRedirected) {
                this._hasRedirected = true;

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Duplicate Lead Detected',
                        message: 'Duplicate Lead found. Redirecting to the existing record.',
                        variant: 'info'
                    })
                );

                // Fire-and-forget: delete the duplicate lead in the background
                deleteDuplicateLead({ recordId: this.recordId }).catch(err => {
                    console.error('Failed to delete duplicate lead:', err);
                });

                this[NavigationMixin.Navigate](
                    {
                        type: 'standard__recordPage',
                        attributes: {
                            recordId: duplicateOfId,
                            objectApiName: 'Lead__c',
                            actionName: 'view'
                        }
                    },
                    true // replace history entry to avoid back-button loop
                );
            }
        } catch (error) {
            console.error('LeadDuplicateRedirector error:', error);
        }
    }
}