import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTemplatesForRecord from '@salesforce/apex/DocumentViewerController.getTemplatesForRecord';

export default class DocumentViewer extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    @api cardTitle = 'Documents';
    @api hideDescription = false;
    @api layout = 'list'; // list | grid | compact

    @track templates = [];
    @track isLoading = false;
    @track error;

    // Preview state
    @track showPreview = false;
    @track previewUrl = '';
    @track previewDocName = '';

    connectedCallback() {
        this.loadTemplates();
    }

    loadTemplates() {
        if (!this.recordId) return;
        this.isLoading = true;
        this.error = undefined;
        getTemplatesForRecord({ recordId: this.recordId, objectApiName: this.objectApiName || '' })
            .then(result => {
                this.templates = (result || []).map((t, i) => ({
                    ...t,
                    _key: 'doc-' + i,
                    _hasDescription: !this.hideDescription && !!t.description
                }));
            })
            .catch(err => {
                this.error = this._getError(err);
                this.templates = [];
            })
            .finally(() => { this.isLoading = false; });
    }

    // ==================== COMPUTED ====================

    get hasTemplates() {
        return this.templates && this.templates.length > 0;
    }

    get templateCount() {
        return this.templates ? this.templates.length : 0;
    }

    get pluralSuffix() {
        return this.templateCount === 1 ? '' : 's';
    }

    get isListLayout() { return this.layout === 'list'; }
    get isGridLayout() { return this.layout === 'grid'; }
    get isCompactLayout() { return this.layout === 'compact'; }

    get containerClass() {
        if (this.layout === 'grid') return 'doc-grid';
        if (this.layout === 'compact') return 'doc-compact';
        return 'doc-list';
    }

    // ==================== HANDLERS ====================

    handlePreviewPdf(event) {
        event.stopPropagation();
        const url = event.currentTarget.dataset.url;
        const name = event.currentTarget.dataset.name || 'Document';
        if (url) {
            this.previewUrl = url;
            this.previewDocName = name;
            this.showPreview = true;
        }
    }

    handleDownloadPdf(event) {
        event.stopPropagation();
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleClosePreview() {
        this.showPreview = false;
        this.previewUrl = '';
        this.previewDocName = '';
    }

    handleRefresh() {
        this.showPreview = false;
        this.loadTemplates();
    }

    // ==================== HELPERS ====================

    _getError(error) {
        if (Array.isArray(error?.body)) return error.body.map(e => e.message).join(', ');
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'Unknown error';
    }
}