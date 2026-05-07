import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import convertPdfToSvg from '@salesforce/apex/PdfToSvgController.convertPdfToSvg';

const MAX_FILE_SIZE_MB = 10;

export default class PdfToSvgConverter extends LightningElement {
    @track isLoading = false;
    @track loadingMessage = '';
    @track pdfLoaded = false;
    @track fileName = '';
    @track totalPages = 0;
    @track currentPage = 1;
    @track showPreview = false;
    @track errorMessage = '';

    svgPages = {};
    isDragActive = false;

    get uploadZoneClass() {
        if (this.pdfLoaded) return 'upload-zone-loaded';
        if (this.isDragActive) return 'upload-zone-active';
        return 'upload-zone';
    }

    get isPrevDisabled() {
        return this.currentPage <= 1;
    }

    get isNextDisabled() {
        return this.currentPage >= this.totalPages;
    }

    // ── Drag & Drop ──

    handleDragOver(event) {
        event.preventDefault();
        event.stopPropagation();
        this.isDragActive = true;
    }

    handleDragLeave(event) {
        event.preventDefault();
        event.stopPropagation();
        this.isDragActive = false;
    }

    handleDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        this.isDragActive = false;
        const files = event.dataTransfer?.files;
        if (files && files.length > 0) {
            this.processFile(files[0]);
        }
    }

    // ── File Selection ──

    handleFileSelect(event) {
        const files = event.target.files;
        if (files && files.length > 0) {
            this.processFile(files[0]);
        }
    }

    handleChangeFile() {
        this.resetState();
    }

    resetState() {
        this.pdfLoaded = false;
        this.svgPages = {};
        this.currentPage = 1;
        this.totalPages = 0;
        this.fileName = '';
        this.showPreview = false;
        this.isLoading = false;
        this.errorMessage = '';
    }

    // ── File Processing via ConvertAPI ──

    async processFile(file) {
        if (!file.name.toLowerCase().endsWith('.pdf')) {
            this.showToast('Invalid File', 'Please select a PDF file (.pdf)', 'error');
            return;
        }

        const sizeMB = file.size / (1024 * 1024);
        if (sizeMB > MAX_FILE_SIZE_MB) {
            this.showToast(
                'Large File',
                `This file is ${sizeMB.toFixed(1)}MB. Processing may be slow for files over ${MAX_FILE_SIZE_MB}MB.`,
                'warning'
            );
        }

        this.fileName = file.name;
        this.isLoading = true;
        this.errorMessage = '';
        this.loadingMessage = 'Reading PDF file...';

        try {
            const base64 = await this.readFileAsBase64(file);

            this.loadingMessage = 'Converting PDF to SVG (this may take a moment for complex drawings)...';
            const pages = await convertPdfToSvg({
                base64Data: base64,
                fileName: file.name
            });

            if (!pages || pages.length === 0) {
                throw new Error('No SVG pages returned from conversion.');
            }

            this.svgPages = {};
            for (let i = 0; i < pages.length; i++) {
                this.svgPages[i + 1] = pages[i].svgContent;
            }

            this.totalPages = pages.length;
            this.pdfLoaded = true;
            this.currentPage = 1;
            this.showPreview = true;
            this.isLoading = false;

            this.injectSvg(1);
            this.showToast('Success', `PDF converted: ${this.totalPages} page(s) with vector paths.`, 'success');
        } catch (error) {
            this.isLoading = false;
            const msg = error.body?.message || error.message || 'Unknown error';
            this.errorMessage = 'Failed to convert PDF: ' + msg;
            console.error('[PDF2SVG] processFile error:', error);
            this.showToast('Error', this.errorMessage, 'error');
        }
    }

    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const result = reader.result;
                const base64 = result.split(',')[1];
                resolve(base64);
            };
            reader.onerror = () => reject(new Error('Failed to read file'));
            reader.readAsDataURL(file);
        });
    }

    // ── SVG Display ──

    injectSvg(pageNum) {
        const container = this.template.querySelector('[data-id="svg-preview"]');
        if (container && this.svgPages[pageNum]) {
            container.innerHTML = this.svgPages[pageNum];
        }
    }

    renderedCallback() {
        if (this.showPreview && this.svgPages[this.currentPage]) {
            const container = this.template.querySelector('[data-id="svg-preview"]');
            if (container && container.innerHTML === '') {
                container.innerHTML = this.svgPages[this.currentPage];
            }
        }
    }

    // ── Page Navigation ──

    handlePrevPage() {
        if (this.currentPage > 1) {
            this.currentPage--;
            this.injectSvg(this.currentPage);
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage++;
            this.injectSvg(this.currentPage);
        }
    }

    // ── Download ──

    handleDownloadCurrentPage() {
        const svgString = this.svgPages[this.currentPage];
        if (!svgString) {
            this.showToast('Error', 'No SVG content available for this page.', 'error');
            return;
        }

        const baseName = this.fileName.replace(/\.pdf$/i, '');
        const downloadName = this.totalPages > 1
            ? `${baseName}_page${this.currentPage}.svg`
            : `${baseName}.svg`;

        this.downloadSvg(svgString, downloadName);
    }

    handleDownloadAllPages() {
        const baseName = this.fileName.replace(/\.pdf$/i, '');
        let downloadCount = 0;

        for (let i = 1; i <= this.totalPages; i++) {
            const svgString = this.svgPages[i];
            if (svgString) {
                const downloadName = this.totalPages > 1
                    ? `${baseName}_page${i}.svg`
                    : `${baseName}.svg`;

                this.downloadSvg(svgString, downloadName);
                downloadCount++;
            }
        }

        if (downloadCount > 0) {
            this.showToast('Success', `Downloaded ${downloadCount} SVG file(s).`, 'success');
        }
    }

    downloadSvg(svgContent, fileName) {
        const blob = new Blob([svgContent], { type: 'image/svg+xml;charset=utf-8' });
        const url = URL.createObjectURL(blob);

        const link = document.createElement('a');
        link.href = url;
        link.download = fileName;
        link.style.display = 'none';

        const container = this.template.querySelector('[data-id="svg-preview"]');
        const parent = container || document.body;
        parent.appendChild(link);
        link.click();

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            parent.removeChild(link);
            URL.revokeObjectURL(url);
        }, 100);
    }

    // ── Utilities ──

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}