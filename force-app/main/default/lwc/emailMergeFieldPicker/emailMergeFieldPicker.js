import { LightningElement, api, track } from 'lwc';
import getMergeFieldsForObject from '@salesforce/apex/EmailFieldPickerController.getMergeFieldsForObject';

export default class EmailMergeFieldPicker extends LightningElement {
    @api objectApiName;
    @api buttonLabel = 'Insert Field';
    @api buttonVariant = 'neutral';
    @api disabled = false;
    
    @track isLoading = false;
    @track fields = [];
    @track filteredFields = [];
    @track searchTerm = '';
    @track showModal = false;
    @track groupedFields = [];
    
    @track _objectApiName;
    
    connectedCallback() {
        this._objectApiName = this.objectApiName;
    }
    
    @api
    set objectName(value) {
        if (value !== this._objectApiName) {
            this._objectApiName = value;
            this.fields = [];
            this.groupedFields = [];
        }
    }
    
    get objectName() {
        return this._objectApiName;
    }
    
    async loadFields() {
        if (!this._objectApiName) {
            return;
        }
        
        try {
            this.isLoading = true;
            const data = await getMergeFieldsForObject({ objectApiName: this._objectApiName });
            
            this.fields = data.map(field => ({
                ...field,
                mergeField: `{! ${field.value}}`,
                searchLabel: (field.label + ' ' + field.value).toLowerCase()
            }));
            
            this.filteredFields = [...this.fields];
            this.groupFields();
            
        } catch (error) {
            console.error('Error loading merge fields:', error);
        } finally {
            this.isLoading = false;
        }
    }
    
    groupFields() {
        const groups = {};
        
        this.filteredFields.forEach(field => {
            // Determine group based on field path
            let groupName = 'Direct Fields';
            
            if (field.value.includes('.')) {
                const parts = field.label.split(' → ');
                groupName = parts.slice(0, -1).join(' → ');
            }
            
            if (!groups[groupName]) {
                groups[groupName] = {
                    name: groupName,
                    fields: [],
                    isExpanded: groupName === 'Direct Fields'
                };
            }
            
            groups[groupName].fields.push(field);
        });
        
        // Sort groups - Direct Fields first
        const sortedGroups = Object.values(groups).sort((a, b) => {
            if (a.name === 'Direct Fields') return -1;
            if (b.name === 'Direct Fields') return 1;
            return a.name.localeCompare(b.name);
        });
        
        this.groupedFields = sortedGroups;
    }
    
    handleOpenModal() {
        this.showModal = true;
        if (this.fields.length === 0) {
            this.loadFields();
        }
    }
    
    handleCloseModal() {
        this.showModal = false;
        this.searchTerm = '';
        this.filteredFields = [...this.fields];
        this.groupFields();
    }
    
    handleSearchChange(event) {
        this.searchTerm = event.target.value.toLowerCase();
        this.filterFields();
    }
    
    filterFields() {
        if (!this.searchTerm) {
            this.filteredFields = [...this.fields];
        } else {
            this.filteredFields = this.fields.filter(field =>
                field.searchLabel.includes(this.searchTerm)
            );
        }
        this.groupFields();
    }
    
    handleFieldSelect(event) {
        const mergeField = event.currentTarget.dataset.mergefield;
        const fieldLabel = event.currentTarget.dataset.label;
        
        this.dispatchEvent(new CustomEvent('insert', {
            detail:  {
                mergeField: mergeField,
                label: fieldLabel
            }
        }));
        
        this.handleCloseModal();
    }
    
    handleToggleGroup(event) {
        const groupName = event.currentTarget.dataset.group;
        this.groupedFields = this.groupedFields.map(group => {
            if (group.name === groupName) {
                return { ...group, isExpanded: !group.isExpanded };
            }
            return group;
        });
    }
    
    handleCopyField(event) {
        event.stopPropagation();
        const mergeField = event.currentTarget.dataset.mergefield;
        
        navigator.clipboard.writeText(mergeField).then(() => {
            // Show copied feedback
            const button = event.currentTarget;
            button.iconName = 'utility:check';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                button.iconName = 'utility:copy';
            }, 1500);
        });
    }
    
    // Getters
    get hasFields() {
        return this.filteredFields.length > 0;
    }
    
    get modalTitle() {
        return `Insert Merge Field - ${this.objectApiName}`;
    }
}