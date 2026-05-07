import { LightningElement, api, track } from 'lwc';
import getFieldsForObject from '@salesforce/apex/EmailFieldPickerController.getFieldsForObject';
import getEmailFieldsForObject from '@salesforce/apex/EmailFieldPickerController.getEmailFieldsForObject';
import getMergeFieldsForObject from '@salesforce/apex/EmailFieldPickerController.getMergeFieldsForObject';

export default class EmailFieldPicker extends LightningElement {
    @api objectApiName;
    @api fieldType = 'all'; // 'all', 'email', 'merge'
    @api label = 'Select Field';
    @api placeholder = 'Search fields...';
    @api value;
    @api required = false;
    @api disabled = false;
    
    @track isLoading = false;
    @track fields = [];
    @track filteredFields = [];
    @track searchTerm = '';
    @track showDropdown = false;
    @track selectedField = null;
    
    _objectApiName;
    
    connectedCallback() {
        this._objectApiName = this.objectApiName;
        if (this.objectApiName) {
            this.loadFields();
        }
    }
    
    @api
    refresh() {
        this.loadFields();
    }
    
    @api
    get objectName() {
        return this._objectApiName;
    }
    
    set objectName(value) {
        if (value !== this._objectApiName) {
            this._objectApiName = value;
            this.value = null;
            this.selectedField = null;
            this.loadFields();
        }
    }
    
    async loadFields() {
        if (!this._objectApiName) {
            this.fields = [];
            this.filteredFields = [];
            return;
        }
        
        try {
            this.isLoading = true;
            let data;
            
            if (this.fieldType === 'email') {
                data = await getEmailFieldsForObject({ objectApiName: this._objectApiName });
            } else if (this.fieldType === 'merge') {
                data = await getMergeFieldsForObject({ objectApiName: this._objectApiName });
            } else {
                data = await getFieldsForObject({ objectApiName: this._objectApiName });
            }
            
            this.fields = data.map(field => ({
                ...field,
                displayLabel: field.label,
                searchLabel: (field.label + ' ' + field.value).toLowerCase()
            }));
            
            this.filteredFields = [...this.fields];
            
            // Set selected field if value exists
            if (this.value) {
                this.selectedField = this.fields.find(f => f.value === this.value);
            }
            
        } catch (error) {
            console.error('Error loading fields:', error);
            this.fields = [];
            this.filteredFields = [];
        } finally {
            this.isLoading = false;
        }
    }
    
    handleInputFocus() {
        this.showDropdown = true;
    }
    
    handleInputBlur() {
        // Delay to allow click on dropdown item
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showDropdown = false;
        }, 200);
    }
    
    handleSearchChange(event) {
        this.searchTerm = event.target.value.toLowerCase();
        this.filterFields();
        this.showDropdown = true;
    }
    
    filterFields() {
        if (!this.searchTerm) {
            this.filteredFields = [...this.fields];
        } else {
            this.filteredFields = this.fields.filter(field =>
                field.searchLabel.includes(this.searchTerm)
            );
        }
    }
    
    handleFieldSelect(event) {
        const fieldValue = event.currentTarget.dataset.value;
        this.selectedField = this.fields.find(f => f.value === fieldValue);
        this.value = fieldValue;
        this.searchTerm = '';
        this.showDropdown = false;
        
        // Dispatch change event
        this.dispatchEvent(new CustomEvent('change', {
            detail: {
                value: fieldValue,
                field: this.selectedField
            }
        }));
    }
    
    handleClear() {
        this.selectedField = null;
        this.value = null;
        this.searchTerm = '';
        
        this.dispatchEvent(new CustomEvent('change', {
            detail: {
                value: null,
                field: null
            }
        }));
    }
    
    // Getters
    get displayValue() {
        return this.selectedField ? this.selectedField.label : '';
    }
    
    get hasSelection() {
        return this.selectedField !== null;
    }
    
    get hasFields() {
        return this.filteredFields.length > 0;
    }
    
    get dropdownClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${this.showDropdown ? 'slds-is-open' : ''}`;
    }
    
    get inputClass() {
        return `slds-input slds-combobox__input ${this.hasSelection ? 'slds-combobox__input-value' : ''}`;
    }
}