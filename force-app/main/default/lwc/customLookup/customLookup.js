import { LightningElement, api, track } from 'lwc';
import searchLookupRecords from '@salesforce/apex/DynamicFormExecutionController.searchLookupRecords';
import getRecordName from '@salesforce/apex/DynamicFormExecutionController.getRecordName';

const SEARCH_DELAY = 300;

export default class CustomLookup extends LightningElement {
    @api label = 'Lookup';
    @api objectApiName;
    @api required = false;
    @api disabled = false;
    @api placeholder = 'Search...';
    @api fieldApiName;
    @api variant = 'standard'; // standard or label-hidden

    @track searchResults = [];
    @track selectedRecord = null;
    @track searchTerm = '';
    @track showDropdown = false;
    @track isSearching = false;

    _value;
    _searchTimeout;

    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val;
        if (val && !this.selectedRecord) {
            this.resolveRecordName(val);
        } else if (!val) {
            this.selectedRecord = null;
        }
    }

    resolveRecordName(recordId) {
        getRecordName({ recordId: recordId, objectApiName: this.objectApiName })
            .then(result => {
                if (result) {
                    this.selectedRecord = {
                        recordId: result.recordId,
                        name: result.name,
                        iconName: result.iconName || 'standard:record'
                    };
                }
            })
            .catch(() => {
                this.selectedRecord = {
                    recordId: recordId,
                    name: recordId,
                    iconName: 'standard:record'
                };
            });
    }

    get isLabelHidden() {
        return this.variant === 'label-hidden';
    }

    get containerClass() {
        return 'lookup-container' + (this.showDropdown && this.searchResults.length > 0 ? ' dropdown-open' : '');
    }

    get inputPlaceholder() {
        return this.placeholder || 'Search ' + (this.objectApiName || 'records') + '...';
    }

    handleSearchInput(event) {
        this.searchTerm = event.target.value;

        if (this._searchTimeout) {
            clearTimeout(this._searchTimeout);
        }

        if (this.searchTerm.length < 2) {
            this.searchResults = [];
            this.showDropdown = false;
            return;
        }

        this._searchTimeout = setTimeout(() => {
            this.performSearch();
        }, SEARCH_DELAY);
    }

    performSearch() {
        if (!this.objectApiName || this.searchTerm.length < 2) return;

        this.isSearching = true;
        searchLookupRecords({
            objectApiName: this.objectApiName,
            searchTerm: this.searchTerm,
            maxResults: 10
        })
            .then(results => {
                this.searchResults = results.map(r => ({
                    ...r,
                    iconName: r.iconName || 'standard:record'
                }));
                this.showDropdown = this.searchResults.length > 0;
                this.isSearching = false;
            })
            .catch(() => {
                this.searchResults = [];
                this.showDropdown = false;
                this.isSearching = false;
            });
    }

    handleResultSelect(event) {
        const recordId = event.currentTarget.dataset.id;
        const selected = this.searchResults.find(r => r.recordId === recordId);

        if (selected) {
            this.selectedRecord = {
                recordId: selected.recordId,
                name: selected.name,
                iconName: selected.iconName
            };
            this._value = selected.recordId;
            this.searchTerm = '';
            this.searchResults = [];
            this.showDropdown = false;

            this.dispatchEvent(new CustomEvent('lookupselect', {
                detail: {
                    recordId: selected.recordId,
                    name: selected.name,
                    fieldApiName: this.fieldApiName
                },
                bubbles: true,
                composed: true
            }));
        }
    }

    handleRemoveSelection() {
        this.selectedRecord = null;
        this._value = null;
        this.searchTerm = '';
        this.searchResults = [];
        this.showDropdown = false;

        this.dispatchEvent(new CustomEvent('lookupselect', {
            detail: {
                recordId: null,
                name: null,
                fieldApiName: this.fieldApiName
            },
            bubbles: true,
            composed: true
        }));
    }

    handleInputFocus() {
        if (this.searchTerm.length >= 2 && this.searchResults.length > 0) {
            this.showDropdown = true;
        }
    }

    handleInputBlur() {
        // Delay hiding to allow click on results
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showDropdown = false;
        }, 250);
    }

    @api
    reportValidity() {
        if (this.required && !this._value) {
            this.template.querySelector('.lookup-input-wrapper')?.classList.add('slds-has-error');
            return false;
        }
        this.template.querySelector('.lookup-input-wrapper')?.classList.remove('slds-has-error');
        return true;
    }

    @api
    clearSelection() {
        this.handleRemoveSelection();
    }
}