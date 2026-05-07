import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

// Apex Methods
import getDocumentsWithConfig from '@salesforce/apex/DocumentManagerController.getDocumentsWithConfig';
import updateDocumentMetadata from '@salesforce/apex/DocumentManagerController.updateDocumentMetadata';
import deleteDocument from '@salesforce/apex/DocumentManagerController.deleteDocument';
import getDocumentDownloadUrls from '@salesforce/apex/DocumentManagerController.getDocumentDownloadUrls';
import getObjectApiName from '@salesforce/apex/EmailSenderController.getObjectApiName';

export default class DocumentManager extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    _resolvedObjectApiName = '';

    @track isLoading = true;
    @track categories = [];

    // Statistics
    @track uploadedCount = 0;
    @track totalCount = 0;
    @track completionPercentage = 0;

    // Upload Modal
    @track showUploadModal = false;
    @track uploadCategory = '';
    @track uploadDocType = '';
    @track uploadDocTypeName = '';
    uploadAcceptTypes = '.jpg,.jpeg,.png,.pdf,.doc,.docx,.xls,.xlsx';

    // Delete Modal
    @track showDeleteModal = false;
    @track deleteFileName = '';
    @track deleteContentDocId = '';

    // Download All Modal
    @track showDownloadConfirmModal = false;
    @track downloadFileCount = 0;
    @track isDownloading = false;
    @track downloadProgress = 0;
    @track currentDownloadFile = '';
    documentsToDownload = [];

    // File List Modal (Multiple Files)
    @track showFileListModal = false;
    @track fileListTitle = '';
    @track fileListCount = 0;
    @track fileListItems = [];
    @track currentFileListCategory = '';
    @track currentFileListDocType = '';

    // Hidden container for download iframes
    downloadContainer = null;

    // ============ LIFECYCLE HOOKS ============

    async connectedCallback() {
        // Always resolve object API name from recordId for reliable filtering
        if (this.recordId) {
            try {
                this._resolvedObjectApiName = await getObjectApiName({ recordId: this.recordId });
            } catch (e) {
                console.error('Error resolving object name:', e);
                this._resolvedObjectApiName = this.objectApiName || '';
            }
        } else {
            this._resolvedObjectApiName = this.objectApiName || '';
        }
        this.loadData();
        this.createDownloadContainer();
    }

    disconnectedCallback() {
        this.removeDownloadContainer();
    }

    // ============ DOWNLOAD CONTAINER MANAGEMENT ============

    createDownloadContainer() {
        this.downloadContainer = document.createElement('div');
        this.downloadContainer.id = 'download-container-' + this.recordId;
        this.downloadContainer.style.cssText = 'position: fixed;left:-99999px;top:-99999px;width:1px;height:1px;overflow:hidden;visibility:hidden;';
        document.body.appendChild(this.downloadContainer);
    }

    removeDownloadContainer() {
        if (this.downloadContainer && this.downloadContainer.parentNode) {
            this.downloadContainer.parentNode.removeChild(this.downloadContainer);
        }
    }

    clearDownloadContainer() {
        if (this.downloadContainer) {
            this.downloadContainer.innerHTML = '';
        }
    }

    // ============ DATA LOADING ============

    async loadData() {
        try {
            this.isLoading = true;

            const categoriesData = await getDocumentsWithConfig({
                bookingId: this.recordId,
                objectApiName: this._resolvedObjectApiName || this.objectApiName || ''
            });

            this.categories = categoriesData.map(cat => ({
                ...cat,
                documentTypes: cat.documentTypes.map(dt => ({
                    ...dt,
                    cardClass: dt.hasFiles ? 'document-card uploaded' : 'document-card empty',
                    previewButtonTitle: dt.multipleFiles ? `View all ${dt.fileCount} files` : 'Preview'
                }))
            }));

            this.calculateStats();

        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
            console.error('Error loading data:', error);
        } finally {
            this.isLoading = false;
        }
    }

    calculateStats() {
        let uploaded = 0;
        let total = 0;

        this.categories.forEach(cat => {
            cat.documentTypes.forEach(dt => {
                total++;
                if (dt.hasFiles) {
                    uploaded++;
                }
            });
        });

        this.uploadedCount = uploaded;
        this.totalCount = total;
        this.completionPercentage = total > 0 ? Math.round((uploaded / total) * 100) : 0;
    }

    // ============ GETTERS ============

    get progressBarStyle() {
        return `width: ${this.completionPercentage}%`;
    }

    get downloadProgressStyle() {
        return `width: ${this.downloadProgress}%`;
    }

    // ============ UTILITY METHODS ============

    findDocType(categoryValue, docTypeValue) {
        const category = this.categories.find(c => c.value === categoryValue);
        if (!category) return null;
        return category.documentTypes.find(dt => dt.value === docTypeValue);
    }

    formatFileSize(bytes) {
        if (!bytes) return '0 B';
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(1024));
        return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${sizes[i]}`;
    }

    formatDate(dateValue) {
        if (!dateValue) return '';
        const date = new Date(dateValue);
        return date.toLocaleDateString('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceErrors(errors) {
        if (!Array.isArray(errors)) errors = [errors];
        return errors
            .filter(e => !!e)
            .map(e => e.message || e.body?.message || JSON.stringify(e))
            .join(', ');
    }

    // ============ IMAGE ERROR HANDLER ============

    handleImageError(event) {
        event.target.src = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect fill="#f0f0f0" width="100" height="100"/><text fill="#999" font-size="12" x="50%" y="50%" text-anchor="middle" dy=".3em">No Preview</text></svg>');
    }

    // ============ PREVIEW ============

    handlePreviewClick(event) {
        event.stopPropagation();
        const category = event.currentTarget.dataset.category;
        const docType = event.currentTarget.dataset.doctype;
        const dt = this.findDocType(category, docType);

        if (dt && dt.hasFiles) {
            if (dt.multipleFiles) {
                // Multiple files - show file list modal
                this.openFileListModal(category, docType);
            } else {
                // Single file - open preview directly
                this.openFilePreview(dt.files[0].contentDocumentId);
            }
        }
    }

    openFilePreview(contentDocumentId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'filePreview'
            },
            state: {
                selectedRecordId: contentDocumentId
            }
        });
    }

    // ============ FILE LIST MODAL (Multiple Files) ============

    handleViewAllFiles(event) {
        event.stopPropagation();
        const category = event.currentTarget.dataset.category;
        const docType = event.currentTarget.dataset.doctype;
        this.openFileListModal(category, docType);
    }

    openFileListModal(category, docType) {
        const dt = this.findDocType(category, docType);
        if (!dt || !dt.hasFiles) return;

        this.fileListTitle = dt.label;
        this.fileListCount = dt.fileCount;
        this.currentFileListCategory = category;
        this.currentFileListDocType = docType;

        // Process files for display
        this.fileListItems = dt.files.map((file, index) => ({
            ...file,
            serialNumber: index + 1,
            formattedSize: this.formatFileSize(file.contentSize),
            formattedDate: this.formatDate(file.uploadedDate),
            fileExtension: file.fileExtension ? file.fileExtension.toUpperCase() : 'FILE'
        }));

        this.showFileListModal = true;
    }

    closeFileListModal() {
        this.showFileListModal = false;
        this.fileListTitle = '';
        this.fileListCount = 0;
        this.fileListItems = [];
        this.currentFileListCategory = '';
        this.currentFileListDocType = '';
    }

    handleFilePreview(event) {
        const contentDocumentId = event.currentTarget.dataset.id;
        this.openFilePreview(contentDocumentId);
    }

    handleFileDownload(event) {
        const contentDocumentId = event.currentTarget.dataset.id;
        const title = event.currentTarget.dataset.title;
        this.downloadSingleFile(contentDocumentId, title);
    }

    handleFileDelete(event) {
        const contentDocumentId = event.currentTarget.dataset.id;
        const title = event.currentTarget.dataset.title;

        // Close file list modal and open delete confirmation
        this.closeFileListModal();
        this.deleteFileName = title;
        this.deleteContentDocId = contentDocumentId;
        this.showDeleteModal = true;
    }

    handleUploadMoreFromList() {
        const dt = this.findDocType(this.currentFileListCategory, this.currentFileListDocType);
        if (dt) {
            this.closeFileListModal();
            this.openUploadModal(dt, this.currentFileListCategory);
        }
    }

    // ============ DOWNLOAD SINGLE FILE ============

    handleDownloadClick(event) {
        event.stopPropagation();
        const category = event.currentTarget.dataset.category;
        const docType = event.currentTarget.dataset.doctype;
        const dt = this.findDocType(category, docType);

        if (dt && dt.hasFiles) {
            if (dt.multipleFiles) {
                // Multiple files - show file list modal
                this.openFileListModal(category, docType);
            } else {
                // Single file - download directly
                this.downloadSingleFile(dt.files[0].contentDocumentId, dt.files[0].title);
            }
        }
    }

    downloadSingleFile(contentDocumentId, fileName) {
        const downloadUrl = '/sfc/servlet.shepherd/document/download/' + contentDocumentId;

        const link = document.createElement('a');
        link.href = downloadUrl;
        link.download = fileName || 'document';
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();

        setTimeout(() => {
            document.body.removeChild(link);
        }, 100);
    }

    // ============ DOWNLOAD ALL ============

    async handleDownloadAll() {
        try {
            this.isLoading = true;

            const documents = await getDocumentDownloadUrls({ bookingId: this.recordId });

            if (!documents || documents.length === 0) {
                this.showToast('Info', 'No documents found to download', 'info');
                return;
            }

            this.documentsToDownload = documents;
            this.downloadFileCount = documents.length;
            this.showDownloadConfirmModal = true;

        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    closeDownloadConfirmModal() {
        if (this.isDownloading) {
            return;
        }
        this.showDownloadConfirmModal = false;
        this.documentsToDownload = [];
        this.downloadFileCount = 0;
        this.isDownloading = false;
        this.downloadProgress = 0;
        this.currentDownloadFile = '';
        this.clearDownloadContainer();
    }

    confirmDownloadAll() {
        if (!this.documentsToDownload || this.documentsToDownload.length === 0) {
            this.closeDownloadConfirmModal();
            return;
        }

        this.isDownloading = true;
        this.downloadProgress = 0;

        const documents = [...this.documentsToDownload];
        const totalFiles = documents.length;

        this.downloadFilesSequentially(documents, 0, totalFiles);
    }

    downloadFilesSequentially(documents, index, totalFiles) {
        if (index >= totalFiles) {
            this.isDownloading = false;
            this.downloadProgress = 100;
            this.currentDownloadFile = 'Complete! ';

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                this.showDownloadConfirmModal = false;
                this.documentsToDownload = [];
                this.downloadFileCount = 0;
                this.downloadProgress = 0;
                this.currentDownloadFile = '';
                this.clearDownloadContainer();
                this.showToast('Success', `${totalFiles} file(s) downloaded successfully`, 'success');
            }, 1000);
            return;
        }

        const doc = documents[index];
        this.downloadProgress = Math.round(((index + 1) / totalFiles) * 100);
        this.currentDownloadFile = doc.title || `File ${index + 1}`;

        this.triggerFileDownload(doc.contentDocumentId);

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.downloadFilesSequentially(documents, index + 1, totalFiles);
        }, 1500);
    }

    triggerFileDownload(contentDocumentId) {
        const downloadUrl = '/sfc/servlet.shepherd/document/download/' + contentDocumentId;

        if (this.downloadContainer) {
            const iframe = document.createElement('iframe');
            iframe.style.cssText = 'width: 1px;height:1px;border:none;';
            iframe.src = downloadUrl;
            this.downloadContainer.appendChild(iframe);

            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                if (iframe && iframe.parentNode) {
                    iframe.parentNode.removeChild(iframe);
                }
            }, 5000);
        }
    }

    // ============ REPLACE ============

    handleReplaceClick(event) {
        event.stopPropagation();
        const category = event.currentTarget.dataset.category;
        const docType = event.currentTarget.dataset.doctype;
        const dt = this.findDocType(category, docType);

        if (dt) {
            this.openUploadModal(dt, category);
        }
    }

    // ============ UPLOAD ============

    handleUploadClick(event) {
        event.stopPropagation();
        const category = event.currentTarget.dataset.category;
        const docType = event.currentTarget.dataset.doctype;
        const dt = this.findDocType(category, docType);

        if (dt) {
            this.openUploadModal(dt, category);
        }
    }

    openUploadModal(docType, category) {
        this.uploadCategory = category;
        this.uploadDocType = docType.value;
        this.uploadDocTypeName = docType.label;
        this.showUploadModal = true;
    }

    closeUploadModal() {
        this.showUploadModal = false;
        this.uploadCategory = '';
        this.uploadDocType = '';
        this.uploadDocTypeName = '';
    }

    async handleUploadFinished(event) {
        const uploadedFiles = event.detail.files;

        try {
            this.isLoading = true;

            for (const file of uploadedFiles) {
                await updateDocumentMetadata({
                    contentDocumentId: file.documentId,
                    bookingId: this.recordId,
                    category: this.uploadCategory,
                    documentType: this.uploadDocType,
                    objectApiName: this._resolvedObjectApiName || this.objectApiName || ''
                });
            }

            this.showToast('Success', `${uploadedFiles.length} file(s) uploaded successfully`, 'success');
            this.closeUploadModal();
            await this.loadData();

        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // ============ DELETE ============

    handleDeleteClick(event) {
        event.stopPropagation();
        const category = event.currentTarget.dataset.category;
        const docType = event.currentTarget.dataset.doctype;
        const dt = this.findDocType(category, docType);

        if (dt && dt.hasFiles) {
            if (dt.multipleFiles) {
                // Multiple files - show file list modal to choose which to delete
                this.openFileListModal(category, docType);
            } else {
                // Single file - open delete modal directly
                this.openDeleteModal(dt.files[0]);
            }
        }
    }

    openDeleteModal(file) {
        this.deleteFileName = file.title;
        this.deleteContentDocId = file.contentDocumentId;
        this.showDeleteModal = true;
    }

    closeDeleteModal() {
        this.showDeleteModal = false;
        this.deleteFileName = '';
        this.deleteContentDocId = '';
    }

    async confirmDelete() {
        try {
            this.isLoading = true;
            await deleteDocument({ contentDocumentId: this.deleteContentDocId });
            this.showToast('Success', 'Document deleted successfully', 'success');
            this.closeDeleteModal();
            await this.loadData();
        } catch (error) {
            this.showToast('Error', this.reduceErrors(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }
}