import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';

export default class FinancialTransactionLauncher extends NavigationMixin(LightningElement) {
    @api recordId;
    _hasNavigated = false;

    renderedCallback() {
        if (this._hasNavigated || !this.recordId) return;
        this._hasNavigated = true;

        // Navigate to the Financial Transaction Manager page in a new tab
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Financial_Transaction_Manager'
            },
            state: {
                c__recordId: this.recordId
            }
        }).then(url => {
            window.open(url, '_blank');
        }).catch(() => {
            // Fallback: navigate in same window
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: {
                    apiName: 'Financial_Transaction_Manager'
                },
                state: {
                    c__recordId: this.recordId
                }
            });
        });

        // Close the action panel after a short delay
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.dispatchEvent(new CloseActionScreenEvent());
        }, 1000);
    }
}