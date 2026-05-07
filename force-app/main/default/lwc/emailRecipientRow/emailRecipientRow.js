import { LightningElement, api, track } from 'lwc';

export default class EmailRecipientRow extends LightningElement {
    @api index;
    @api objectApiName;
    @api recipientData = {};
    @api canDelete = false; // Changed from true to false
    
    @track localData = {};
    
    recipientTypeOptions = [
        { label: 'To', value: 'to' },
        { label: 'CC', value: 'cc' },
        { label: 'BCC', value: 'bcc' }
    ];
    
    sourceTypeOptions = [
        { label: 'Field from Record', value: 'Field' },
        { label: 'Static Email', value: 'Static' },
        { label: 'Current User', value: 'CurrentUser' },
        { label:  'Record Owner', value: 'RecordOwner' },
        { label:  'Owner\'s Manager', value: 'OwnerManager' }
    ];
    
    connectedCallback() {
        this.localData = { ... this.recipientData };
    }
    
    // Handlers
    handleRecipientTypeChange(event) {
        this.localData.type = event.detail.value;
        this.notifyChange();
    }
    
    handleSourceTypeChange(event) {
        this.localData.sourceType = event.detail.value;
        // Clear field/email when source type changes
        this.localData.fieldApiName = '';
        this.localData.staticEmail = '';
        this.notifyChange();
    }
    
    handleFieldChange(event) {
        this.localData.fieldApiName = event.detail.value;
        this.localData.label = event.detail.field?.label || '';
        this.notifyChange();
    }
    
    handleStaticEmailChange(event) {
        this.localData.staticEmail = event.target.value;
        this.localData.label = event.target.value;
        this.notifyChange();
    }
    
    handleLabelChange(event) {
        this.localData.label = event.target.value;
        this.notifyChange();
    }
    
    handleRequiredChange(event) {
        this.localData.isRequired = event.target.checked;
        this.notifyChange();
    }
    
    handleEditableChange(event) {
        this.localData.isEditable = event.target.checked;
        this.notifyChange();
    }
    
    handleDelete() {
        this.dispatchEvent(new CustomEvent('delete', {
            detail: { index: this.index }
        }));
    }
    
    notifyChange() {
        this.dispatchEvent(new CustomEvent('change', {
            detail: {
                index: this.index,
                data: { ...this.localData }
            }
        }));
    }
    
    // Getters
    get showFieldPicker() {
        return this.localData.sourceType === 'Field';
    }
    
    get showStaticEmail() {
        return this.localData.sourceType === 'Static';
    }
    
    get showAutoLabel() {
        return ['CurrentUser', 'RecordOwner', 'OwnerManager'].includes(this.localData.sourceType);
    }
    
    get autoLabelText() {
        const labels = {
            'CurrentUser': 'Current User\'s Email',
            'RecordOwner': 'Record Owner\'s Email',
            'OwnerManager': 'Owner\'s Manager Email'
        };
        return labels[this.localData.sourceType] || '';
    }
    
    get rowNumber() {
        return this.index + 1;
    }
    
    get recipientType() {
        return this.localData.type || 'to';
    }
    
    get sourceType() {
        return this.localData.sourceType || 'Field';
    }
    
    get fieldApiName() {
        return this.localData.fieldApiName || '';
    }
    
    get staticEmail() {
        return this.localData.staticEmail || '';
    }
    
    get label() {
        return this.localData.label || '';
    }
    
    get isRequired() {
        return this.localData.isRequired || false;
    }
    
    get isEditable() {
        return this.localData.isEditable !== false;
    }
    
    // Getter to determine if delete button should show
    get showDeleteButton() {
        // If canDelete is not explicitly set to false, show delete button
        return this.canDelete !== false;
    }
}