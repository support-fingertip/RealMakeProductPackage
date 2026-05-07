import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getUnitNumericFields from '@salesforce/apex/DiscountApprovalController.getUnitNumericFields';
import getExistingFieldNumbers from '@salesforce/apex/DiscountApprovalController.getExistingFieldNumbers';

export default class DiscountMatrixForm extends NavigationMixin(LightningElement) {
    @api recordId; // For edit mode
    @api objectApiName;

    @track unitFieldOptions = [];
    @track selectedUnitField = '';
    @track isLoading = true;
    @track isFull = false;
    @track availableFieldNumbers = [];
    @track fieldNumberOptions = [];

    get isEditMode() {
        return !!this.recordId;
    }

    get cardTitle() {
        return this.isEditMode ? 'Edit Discount Approval Matrix' : 'New Discount Approval Matrix';
    }

    get saveDisabled() {
        return this.isFull && !this.isEditMode;
    }

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        try {
            const [fields, existing] = await Promise.all([
                getUnitNumericFields(),
                getExistingFieldNumbers()
            ]);

            // Unit field picklist
            this.unitFieldOptions = [
                { label: '-- None --', value: '' },
                ...fields.map(f => ({ label: f.label, value: f.value }))
            ];

            // 6-record limit check
            this.isFull = existing.isFull && !this.isEditMode;
            this.availableFieldNumbers = existing.availableFieldNumbers || [];

            // Build field number options (only show available numbers for new records)
            if (this.isEditMode) {
                // Edit mode: show all 1-6
                this.fieldNumberOptions = [1, 2, 3, 4, 5, 6].map(n => ({
                    label: String(n), value: String(n)
                }));
            } else {
                this.fieldNumberOptions = this.availableFieldNumbers.map(n => ({
                    label: String(n), value: String(n)
                }));
            }
        } catch (error) {
            this.showToast('Error', 'Error loading form data', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleUnitFieldChange(event) {
        this.selectedUnitField = event.detail.value;
    }

    handleLoad(event) {
        // On edit mode, pre-populate the unit field picklist from existing record
        if (this.isEditMode) {
            const fields = event.detail.records?.[this.recordId]?.fields;
            if (fields && fields.Unit_Field_API__c) {
                this.selectedUnitField = fields.Unit_Field_API__c.value || '';
            }
        }
    }

    handleSubmit(event) {
        event.preventDefault();

        if (this.isFull) {
            this.showToast('Error', 'Maximum 6 discount matrix records allowed (one per discount field 1-6).', 'error');
            return;
        }

        const fields = event.detail.fields;
        // Inject the Unit_Field_API__c value from the combobox
        fields.Unit_Field_API__c = this.selectedUnitField || '';
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSuccess(event) {
        const recordId = event.detail.id;
        this.showToast('Success',
            this.isEditMode ? 'Matrix record updated.' : 'Matrix record created.',
            'success'
        );
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                objectApiName: 'Discount_Approval_Matrix__c',
                actionName: 'view'
            }
        });
    }

    handleError(event) {
        this.showToast('Error', event.detail.message || 'Error saving record', 'error');
    }

    handleCancel() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Discount_Approval_Matrix__c',
                actionName: 'list'
            },
            state: { filterName: 'Recent' }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}