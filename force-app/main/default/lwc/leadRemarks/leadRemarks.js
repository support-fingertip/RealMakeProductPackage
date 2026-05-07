import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import addRemark from '@salesforce/apex/LeadRemarkController.addRemark';
import fetchRemarks from '@salesforce/apex/LeadRemarkController.fetchRemarks';

export default class LeadRemarks extends LightningElement {
    @api recordId;
    @track remarks = [];
    @track newRemark = '';

    connectedCallback() {
        this.loadRemarks();
    }

    loadRemarks() {
        if (!this.recordId) {
            return;
        }
        fetchRemarks({ leadId: this.recordId })
            .then(result => {
                this.remarks = result || [];
            })
            .catch(error => {
                console.error('Error fetching remarks:', error);
                this.showToast('Error', 'Failed to load remarks.', 'error');
            });
    }

    handleRemarkChange(event) {
        this.newRemark = event.target.value;
    }

    handleAddRemark() {
        const remarkText = this.newRemark;

        if (!remarkText || !remarkText.trim()) {
            this.showToast('Error', "Please enter remarks in the below box.", 'error');
            return;
        }

        // Remove multiple consecutive blank lines before sending
        const cleanedRemark = remarkText.replace(/(\r\n|\n|\r){2,}/gm, '\n').trim();

        addRemark({ leadId: this.recordId, newRemark: cleanedRemark })
            .then(() => {
                this.newRemark = '';
                this.showToast('Success', 'Remark added successfully.', 'success');
                this.loadRemarks();
            })
            .catch(error => {
                console.error('Error adding remark:', error);
                const message = error.body && error.body.message
                    ? error.body.message
                    : 'An error occurred while adding the remark.';
                this.showToast('Error', message, 'error');
            });
    }

    handleClearRemark() {
        this.newRemark = '';
    }

    get noRemarks() {
        return this.remarks.length === 0;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }
}