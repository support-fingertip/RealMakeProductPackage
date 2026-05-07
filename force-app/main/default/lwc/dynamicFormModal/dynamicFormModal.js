import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getFieldsMetadata from '@salesforce/apex/DynamicFormExecutionController.getFieldsMetadata';
import saveFormWithChildren from '@salesforce/apex/DynamicFormExecutionController.saveFormWithChildren';
import getRecordValuesForClone from '@salesforce/apex/DynamicFormExecutionController.getRecordValuesForClone';
import searchLookupRecords from '@salesforce/apex/DynamicFormExecutionController.searchLookupRecords';
import getRecordName from '@salesforce/apex/DynamicFormExecutionController.getRecordName';
import updateDocumentMetadata from '@salesforce/apex/DocumentManagerController.updateDocumentMetadata';

export default class DynamicFormModal extends NavigationMixin(LightningElement) {
    @api config;
    @api objectApiName;
    @api contextRecordId;
    @api cloneRecordId;

    @track formConfig;
    @track fieldMetadata = {};
    @track childFieldMetadata = {};
    @track fieldValues = {};
    @track renderedSections = [];

    // Lookup search state
    _lookupSearchTimers = {};
    @track lookupSearchResults = {};
    @track lookupDisplayNames = {};

    // Document upload state
    @track documentUploadSlots = [];
    @track uploadedDocuments = {};
    @track renderedChildSections = [];

    isLoading = false;

    connectedCallback() {
        this.parseConfiguration();
        this.applyContextDefaults();
        this.loadAllMetadata();
    }

    parseConfiguration() {
        if (this.config && this.config.configJson) {
            this.formConfig = JSON.parse(this.config.configJson);
        }
    }

    applyContextDefaults() {
        if (!this.formConfig || !this.contextRecordId) return;

        // Auto-populate lookup fields that reference the context record's object
        // The config JSON may have a contextLookupField to identify which field to populate
        if (this.formConfig.contextLookupField) {
            this.fieldValues[this.formConfig.contextLookupField] = this.contextRecordId;
        }

        // Also check sections for fields with defaultValue = '{!contextRecordId}'
        if (this.formConfig.sections) {
            this.formConfig.sections.forEach(section => {
                (section.fields || []).forEach(field => {
                    if (field.defaultValue === '{!contextRecordId}') {
                        this.fieldValues[field.apiName] = this.contextRecordId;
                        field.defaultValue = this.contextRecordId;
                    }
                });
            });
        }
    }

    loadAllMetadata() {
        if (!this.formConfig) return;

        this.isLoading = true;
        const promises = [];

        const parentFieldNames = [];
        const targetObject = this.formConfig.targetObject || this.objectApiName;

        if (this.formConfig.sections) {
            this.formConfig.sections.forEach(section => {
                (section.fields || []).forEach(f => {
                    if (!parentFieldNames.includes(f.apiName)) {
                        parentFieldNames.push(f.apiName);
                    }
                });
            });
        }

        if (parentFieldNames.length > 0) {
            promises.push(
                getFieldsMetadata({
                    objectApiName: targetObject,
                    fieldApiNames: parentFieldNames
                }).then(result => {
                    this.fieldMetadata = result;
                })
            );
        }

        // Load clone data if cloneRecordId is provided
        if (this.cloneRecordId) {
            promises.push(
                getRecordValuesForClone({
                    objectApiName: targetObject,
                    recordId: this.cloneRecordId
                }).then(result => {
                    // Pre-populate field values from the cloned record
                    for (const fieldName in result) {
                        if (Object.prototype.hasOwnProperty.call(result, fieldName)) {
                            this.fieldValues[fieldName] = result[fieldName];
                        }
                    }
                })
            );
        }

        if (this.formConfig.childConfigs) {
            this.formConfig.childConfigs.forEach((cc, idx) => {
                const childFieldNames = (cc.fields || []).map(f => f.apiName);
                if (childFieldNames.length > 0) {
                    promises.push(
                        getFieldsMetadata({
                            objectApiName: cc.childObject,
                            fieldApiNames: childFieldNames
                        }).then(result => {
                            this.childFieldMetadata[idx] = result;
                        })
                    );
                }
            });
        }

        Promise.all(promises)
            .then(async () => {
                this.buildRenderedSections();
                this.buildRenderedChildSections();
                this._buildDocumentUploadSlots();
                await this._resolveInitialLookupNames();
                this._refreshLookupFields();
                this.isLoading = false;
            })
            .catch(error => {
                this.showToast('Error', 'Failed to load field metadata', 'error');
                this.isLoading = false;
                console.error(error);
            });
    }

    buildRenderedSections() {
        if (!this.formConfig || !this.formConfig.sections) {
            this.renderedSections = [];
            return;
        }

        this.renderedSections = this.formConfig.sections.map((section, idx) => {
            const cols = section.columns || '2';
            const fields = (section.fields || []).map(field => {
                const metadata = this.fieldMetadata[field.apiName] || {};
                const fieldType = metadata.type;
                const defaultVal = field.defaultValue || null;

                if (defaultVal != null) {
                    this.fieldValues[field.apiName] = defaultVal;
                }

                const showCondition = field.showCondition || null;
                const isVisible = this._evaluateFieldCondition(showCondition);

                // Determine validation attributes from field config
                const validation = field.validation || {};

                return {
                    apiName: field.apiName,
                    displayLabel: field.label || metadata.label || field.apiName,
                    displayRequired: field.isRequired || metadata.isRequired,
                    value: this.fieldValues[field.apiName] || defaultVal || null,
                    fieldType: fieldType,
                    isTextField: ['STRING', 'URL', 'EMAIL', 'PHONE'].includes(fieldType),
                    isTextArea: fieldType === 'TEXTAREA',
                    isNumber: ['INTEGER', 'DOUBLE', 'CURRENCY', 'PERCENT'].includes(fieldType),
                    isDate: fieldType === 'DATE',
                    isDateTime: fieldType === 'DATETIME',
                    isBoolean: fieldType === 'BOOLEAN',
                    isPicklist: ['PICKLIST', 'MULTIPICKLIST'].includes(fieldType),
                    isLookup: fieldType === 'REFERENCE',
                    referenceObjectName: metadata.referenceObjectName || '',
                    lookupDisplayName: this.lookupDisplayNames[field.apiName] || '',
                    lookupResults: this.lookupSearchResults[field.apiName] || [],
                    hasLookupResults: (this.lookupSearchResults[field.apiName] || []).length > 0,
                    isLookupFilled: !!this.fieldValues[field.apiName],
                    picklistOptions: (metadata.picklistValues || []).map(p => ({
                        label: p.label, value: p.value
                    })),
                    showCondition: showCondition,
                    isVisible: isVisible,
                    // Validation attributes
                    pattern: validation.pattern || field.pattern || null,
                    messageWhenPatternMismatch: validation.patternMessage || field.patternMessage || null,
                    min: validation.min != null ? validation.min : (field.min != null ? field.min : null),
                    max: validation.max != null ? validation.max : (field.max != null ? field.max : null),
                    maxLength: validation.maxLength || field.maxLength || metadata.length || null,
                    minLength: validation.minLength || field.minLength || null,
                    step: validation.step || field.step || null,
                    messageWhenRangeOverflow: validation.maxMessage || field.maxMessage || null,
                    messageWhenRangeUnderflow: validation.minMessage || field.minMessage || null
                };
            });

            return {
                id: `section-${idx}`,
                label: section.label,
                columns: cols,
                gridClass: 'slds-grid slds-gutters slds-wrap',
                colClass: cols === '1' ? 'slds-col slds-size_1-of-1 slds-p-bottom_small'
                    : 'slds-col slds-size_1-of-2 slds-p-bottom_small',
                fields
            };
        });
    }

    buildRenderedChildSections() {
        if (!this.formConfig || !this.formConfig.childConfigs) {
            this.renderedChildSections = [];
            return;
        }

        this.renderedChildSections = this.formConfig.childConfigs.map((cc, idx) => {
            const metadata = this.childFieldMetadata[idx] || {};
            const fields = (cc.fields || []).map(f => {
                const meta = metadata[f.apiName] || {};
                const validation = f.validation || {};
                return {
                    apiName: f.apiName,
                    label: f.label || meta.label || f.apiName,
                    isRequired: f.isRequired || false,
                    fieldType: meta.type || 'STRING',
                    picklistValues: meta.picklistValues || [],
                    validation: validation
                };
            });

            return {
                id: `child-${idx}`,
                childObject: cc.childObject,
                relationshipField: cc.relationshipField,
                sectionLabel: cc.sectionLabel || cc.childObject,
                fields: fields,
                rows: [],
                hasRows: false
            };
        });
    }

    handleFieldChange(event) {
        const fieldName = event.target.dataset.field;
        let value = event.target.value;

        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        }

        this.fieldValues[fieldName] = value;

        // Update value and re-evaluate all field conditions
        this.renderedSections = this.renderedSections.map(section => ({
            ...section,
            fields: section.fields.map(f => {
                const updated = f.apiName === fieldName ? { ...f, value } : { ...f };
                updated.isVisible = this._evaluateFieldCondition(updated.showCondition);
                return updated;
            })
        }));
    }

    // ==================== LOOKUP SEARCH ====================

    handleLookupSearch(event) {
        const fieldName = event.target.dataset.field;
        const refObject = event.target.dataset.refobject;
        const searchTerm = event.target.value;

        clearTimeout(this._lookupSearchTimers[fieldName]);

        if (!searchTerm || searchTerm.length < 2) {
            this.lookupSearchResults = { ...this.lookupSearchResults, [fieldName]: [] };
            this._refreshLookupFields();
            return;
        }

        this._lookupSearchTimers[fieldName] = setTimeout(() => {
            searchLookupRecords({ objectApiName: refObject, searchTerm })
                .then(results => {
                    this.lookupSearchResults = { ...this.lookupSearchResults, [fieldName]: results };
                    this._refreshLookupFields();
                })
                .catch(() => {
                    this.lookupSearchResults = { ...this.lookupSearchResults, [fieldName]: [] };
                    this._refreshLookupFields();
                });
        }, 300);
    }

    handleLookupSelect(event) {
        const fieldName = event.currentTarget.dataset.field;
        const recordId = event.currentTarget.dataset.id;
        const recordName = event.currentTarget.dataset.name;

        this.fieldValues[fieldName] = recordId;
        this.lookupDisplayNames = { ...this.lookupDisplayNames, [fieldName]: recordName };
        this.lookupSearchResults = { ...this.lookupSearchResults, [fieldName]: [] };
        this._refreshLookupFields();
    }

    handleLookupClear(event) {
        const fieldName = event.currentTarget.dataset.field;
        this.fieldValues[fieldName] = null;
        this.lookupDisplayNames = { ...this.lookupDisplayNames, [fieldName]: '' };
        this.lookupSearchResults = { ...this.lookupSearchResults, [fieldName]: [] };
        this._refreshLookupFields();
    }

    _refreshLookupFields() {
        this.renderedSections = this.renderedSections.map(section => ({
            ...section,
            fields: section.fields.map(f => {
                if (f.isLookup) {
                    return {
                        ...f,
                        value: this.fieldValues[f.apiName] || null,
                        lookupDisplayName: this.lookupDisplayNames[f.apiName] || '',
                        lookupResults: this.lookupSearchResults[f.apiName] || [],
                        hasLookupResults: (this.lookupSearchResults[f.apiName] || []).length > 0,
                        isLookupFilled: !!this.fieldValues[f.apiName]
                    };
                }
                return f;
            })
        }));
    }

    async _resolveInitialLookupNames() {
        for (const fieldName of Object.keys(this.fieldValues)) {
            const meta = this.fieldMetadata[fieldName];
            if (meta && meta.type === 'REFERENCE' && this.fieldValues[fieldName]) {
                try {
                    const name = await getRecordName({ recordId: this.fieldValues[fieldName] });
                    if (name) {
                        this.lookupDisplayNames = { ...this.lookupDisplayNames, [fieldName]: name };
                    }
                } catch (e) { /* skip */ }
            }
        }
    }

    // ==================== DOCUMENT UPLOAD ====================

    get hasDocumentUploadSlots() {
        return this.documentUploadSlots && this.documentUploadSlots.length > 0;
    }

    get hasUnfulfilledRequiredDocs() {
        return this.documentUploadSlots.some(s => s.isRequired && !s.isUploaded);
    }

    _buildDocumentUploadSlots() {
        const docConfig = this.formConfig?.documentUploadConfig;
        if (!docConfig || !Array.isArray(docConfig)) {
            this.documentUploadSlots = [];
            return;
        }
        this.documentUploadSlots = docConfig.map((d, i) => ({
            key: 'doc-' + i,
            category: d.category,
            categoryLabel: d.categoryLabel,
            documentType: d.documentType,
            documentTypeLabel: d.documentTypeLabel,
            isRequired: d.isRequired,
            isUploaded: false,
            fileName: '',
            contentDocumentId: ''
        }));
    }

    handleDocFileUpload(event) {
        const slotKey = event.currentTarget.dataset.key;
        const uploadedFiles = event.detail.files;
        if (!uploadedFiles || uploadedFiles.length === 0) return;

        const file = uploadedFiles[0];
        const slot = this.documentUploadSlots.find(s => s.key === slotKey);
        if (!slot) return;

        // Tag the uploaded file with category and type metadata
        updateDocumentMetadata({
            contentDocumentId: file.documentId,
            bookingId: this.contextRecordId || '',
            category: slot.category,
            documentType: slot.documentType,
            objectApiName: this.formConfig.targetObject || this.objectApiName
        }).then(() => {
            this.documentUploadSlots = this.documentUploadSlots.map(s => {
                if (s.key === slotKey) {
                    return { ...s, isUploaded: true, fileName: file.name, contentDocumentId: file.documentId };
                }
                return s;
            });
        }).catch(error => {
            console.error('Error tagging document:', error);
            // Still mark as uploaded since the file exists
            this.documentUploadSlots = this.documentUploadSlots.map(s => {
                if (s.key === slotKey) {
                    return { ...s, isUploaded: true, fileName: file.name, contentDocumentId: file.documentId };
                }
                return s;
            });
        });
    }

    handleDocFileRemove(event) {
        const slotKey = event.currentTarget.dataset.key;
        this.documentUploadSlots = this.documentUploadSlots.map(s => {
            if (s.key === slotKey) {
                return { ...s, isUploaded: false, fileName: '', contentDocumentId: '' };
            }
            return s;
        });
    }

    _evaluateFieldCondition(showCondition) {
        if (!showCondition || !showCondition.field) return true;

        const condField = showCondition.field;
        const condOperator = showCondition.operator || 'equals';
        const condValue = (showCondition.value || '').toString().toLowerCase();
        const actualValue = (this.fieldValues[condField] != null
            ? this.fieldValues[condField].toString() : '').toLowerCase();

        switch (condOperator) {
            case 'equals':
                return actualValue === condValue;
            case 'notEquals':
                return actualValue !== condValue;
            case 'contains':
                return actualValue.includes(condValue);
            case 'notContains':
                return !actualValue.includes(condValue);
            default:
                return true;
        }
    }

    handleChildFieldChange(event) {
        const childId = event.target.dataset.childId;
        const rowId = event.target.dataset.rowId;
        const fieldName = event.target.dataset.field;
        let value = event.target.value;

        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        }

        this.renderedChildSections = this.renderedChildSections.map(cs => {
            if (cs.id !== childId) return cs;
            return {
                ...cs,
                rows: cs.rows.map(row => {
                    if (row.tempId !== rowId) return row;
                    const updatedValues = { ...row.values, [fieldName]: value };
                    return {
                        ...row,
                        values: updatedValues,
                        cells: row.cells.map(c =>
                            c.apiName === fieldName ? { ...c, value } : c
                        )
                    };
                })
            };
        });
    }

    handleAddChildRow(event) {
        const childId = event.currentTarget.dataset.childId;

        this.renderedChildSections = this.renderedChildSections.map(cs => {
            if (cs.id !== childId) return cs;

            const tempId = `row-${Date.now()}-${Math.random()}`;
            const values = {};
            const cells = cs.fields.map(f => {
                values[f.apiName] = null;
                const fType = f.fieldType;
                const v = f.validation || {};
                return {
                    apiName: f.apiName,
                    value: null,
                    isRequired: f.isRequired,
                    isTextField: ['STRING', 'URL', 'EMAIL', 'PHONE', 'TEXTAREA'].includes(fType),
                    isNumber: ['INTEGER', 'DOUBLE', 'CURRENCY', 'PERCENT'].includes(fType),
                    isDate: fType === 'DATE' || fType === 'DATETIME',
                    isBoolean: fType === 'BOOLEAN',
                    isPicklist: ['PICKLIST', 'MULTIPICKLIST'].includes(fType),
                    isOther: !['STRING', 'URL', 'EMAIL', 'PHONE', 'TEXTAREA', 'INTEGER', 'DOUBLE',
                        'CURRENCY', 'PERCENT', 'DATE', 'DATETIME', 'BOOLEAN', 'PICKLIST',
                        'MULTIPICKLIST'].includes(fType),
                    picklistOptions: (f.picklistValues || []).map(p => ({
                        label: p.label, value: p.value
                    })),
                    min: v.min != null ? v.min : null,
                    max: v.max != null ? v.max : null,
                    step: v.step || null,
                    pattern: v.pattern || null,
                    messageWhenPatternMismatch: v.patternMessage || null,
                    messageWhenRangeOverflow: v.maxMessage || null,
                    messageWhenRangeUnderflow: v.minMessage || null
                };
            });

            const newRow = { tempId, rowNum: cs.rows.length + 1, values, cells };
            const newRows = [...cs.rows, newRow];
            return { ...cs, rows: newRows, hasRows: true };
        });
    }

    handleDeleteChildRow(event) {
        const childId = event.currentTarget.dataset.childId;
        const rowId = event.currentTarget.dataset.rowId;

        this.renderedChildSections = this.renderedChildSections.map(cs => {
            if (cs.id !== childId) return cs;
            const newRows = cs.rows
                .filter(r => r.tempId !== rowId)
                .map((r, i) => ({ ...r, rowNum: i + 1 }));
            return { ...cs, rows: newRows, hasRows: newRows.length > 0 };
        });
    }

    handleCancel() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleSave() {
        if (!this.validateForm()) return;

        // Validate required document uploads
        if (this.hasUnfulfilledRequiredDocs) {
            this.showToast('Error', 'Please upload all required documents before saving', 'error');
            return;
        }

        this.isLoading = true;
        const targetObject = this.formConfig.targetObject || this.objectApiName;

        // Exclude hidden fields from submission
        const hiddenFields = new Set();
        this.renderedSections.forEach(section => {
            section.fields.forEach(f => {
                if (!f.isVisible) {
                    hiddenFields.add(f.apiName);
                }
            });
        });
        hiddenFields.forEach(fieldName => {
            delete this.fieldValues[fieldName];
        });

        const childRecords = this.renderedChildSections
            .filter(cs => cs.rows.length > 0)
            .map(cs => ({
                childObject: cs.childObject,
                relationshipField: cs.relationshipField,
                rows: cs.rows.map(r => r.values)
            }));

        saveFormWithChildren({
            objectApiName: targetObject,
            fieldValues: this.fieldValues,
            childRecordsJson: childRecords.length > 0 ? JSON.stringify(childRecords) : null,
            formName: this.formConfig.formName,
            saveFormNameToField: this.formConfig.saveFormNameToField || null
        })
            .then(recordId => {
                // Link uploaded documents to the new record
                const linkPromises = this.documentUploadSlots
                    .filter(s => s.isUploaded && s.contentDocumentId)
                    .map(s => updateDocumentMetadata({
                        contentDocumentId: s.contentDocumentId,
                        bookingId: recordId,
                        category: s.category,
                        documentType: s.documentType,
                        objectApiName: targetObject
                    }).catch(() => {}));

                return Promise.all(linkPromises).then(() => recordId);
            })
            .then(recordId => {
                this.isLoading = false;
                this.showToast('Success', 'Record created successfully', 'success');

                this.dispatchEvent(new CustomEvent('success', {
                    detail: { recordId }
                }));

                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: recordId,
                        actionName: 'view'
                    }
                });
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Failed to save record', 'error');
                this.isLoading = false;
                console.error(error);
            });
    }

    validateForm() {
        let isValid = true;
        const inputs = this.template.querySelectorAll(
            'lightning-input, lightning-combobox, lightning-textarea'
        );

        inputs.forEach(input => {
            if (!input.reportValidity()) {
                isValid = false;
            }
        });

        return isValid;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    get modalTitle() {
        if (this.cloneRecordId) {
            return 'Clone ' + (this.formConfig?.formName || 'Record');
        }
        return this.formConfig?.formName || 'Create Record';
    }
}