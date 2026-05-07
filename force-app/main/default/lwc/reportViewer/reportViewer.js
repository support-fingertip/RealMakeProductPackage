import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getAvailableReports from '@salesforce/apex/ReportConfigController.getAvailableReports';
import getReportConfig from '@salesforce/apex/ReportConfigController.getReportConfig';
import executeReport from '@salesforce/apex/ReportDataService.executeReport';

export default class ReportViewer extends LightningElement {
    @track currentView = 'list'; // list | report
    @track isLoading = false;
    @track reports = [];

    // Active report state
    @track activeReportId = null;
    @track activeReportName = '';
    @track activeReportDescription = '';
    @track reportResult = null;
    @track reportError = '';

    // Pagination per section (keyed by sectionId)
    @track sectionPagination = {};
    pageSize = 25;

    // Sort per section
    @track sectionSort = {};

    connectedCallback() {
        this.loadReports();
    }

    // ── Getters ──
    get isListView() { return this.currentView === 'list'; }
    get isReportView() { return this.currentView === 'report'; }
    get hasReports() { return this.reports && this.reports.length > 0; }

    get hasReportSections() {
        return this.reportResult && this.reportResult.sections && this.reportResult.sections.length > 0;
    }

    get processedSections() {
        if (!this.reportResult || !this.reportResult.sections) return [];

        return this.reportResult.sections.map(sec => {
            const secId = sec.sectionId;
            const pagination = this.sectionPagination[secId] || { currentPage: 1 };
            const sortInfo = this.sectionSort[secId] || { field: null, direction: 'ASC' };

            // Sort rows if sort is active
            let sortedRows = sec.rawRows ? [...sec.rawRows] : [];
            if (sortInfo.field && sortedRows.length > 0) {
                const col = sec.columns.find(c => c.fieldName === sortInfo.field);
                const isNum = col && col.columnType === 'number';
                sortedRows.sort((a, b) => {
                    let valA = a[sortInfo.field];
                    let valB = b[sortInfo.field];
                    if (valA === undefined || valA === null) valA = '';
                    if (valB === undefined || valB === null) valB = '';
                    if (isNum) {
                        valA = parseFloat(valA) || 0;
                        valB = parseFloat(valB) || 0;
                    } else {
                        valA = String(valA).toLowerCase();
                        valB = String(valB).toLowerCase();
                    }
                    if (valA < valB) return sortInfo.direction === 'ASC' ? -1 : 1;
                    if (valA > valB) return sortInfo.direction === 'ASC' ? 1 : -1;
                    return 0;
                });
            }

            // Paginate
            const totalRows = sortedRows.length;
            const totalPages = Math.max(1, Math.ceil(totalRows / this.pageSize));
            const currentPage = Math.min(pagination.currentPage, totalPages);
            const startIdx = (currentPage - 1) * this.pageSize;
            const endIdx = Math.min(startIdx + this.pageSize, totalRows);
            const pageRows = sortedRows.slice(startIdx, endIdx);

            // Process rows for template
            const processedRows = pageRows.map((row, rowIdx) => ({
                key: 'row-' + (startIdx + rowIdx),
                cells: sec.columns.map(col => ({
                    key: col.fieldName,
                    value: row[col.fieldName] !== undefined ? String(row[col.fieldName]) : '',
                    isNumber: col.columnType === 'number'
                }))
            }));

            // Sort-aware columns
            const sortedColumns = sec.columns.map(col => ({
                ...col,
                isSorted: sortInfo.field === col.fieldName,
                sortDirection: sortInfo.field === col.fieldName ? sortInfo.direction : 'ASC',
                sortIcon: sortInfo.field === col.fieldName
                    ? (sortInfo.direction === 'ASC' ? 'utility:arrowup' : 'utility:arrowdown')
                    : 'utility:arrowup',
                sortClass: sortInfo.field === col.fieldName ? 'th-sorted' : ''
            }));

            return {
                ...sec,
                hasRows: totalRows > 0,
                processedRows,
                sortedColumns,
                currentPage,
                totalPages,
                totalRows,
                showPagination: totalRows > this.pageSize,
                paginationInfo: 'Showing ' + (totalRows > 0 ? startIdx + 1 : 0) + '-' + endIdx + ' of ' + totalRows,
                hasPrevPage: currentPage > 1,
                hasNextPage: currentPage < totalPages,
                isPrevDisabled: currentPage <= 1,
                isNextDisabled: currentPage >= totalPages
            };
        });
    }

    // ── Load Available Reports ──
    loadReports() {
        this.isLoading = true;
        getAvailableReports()
            .then(result => {
                this.reports = result;
            })
            .catch(error => {
                this.showToast('Error', this.getErrorMessage(error), 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    // ── Run Report ──
    handleRunReport(event) {
        const reportId = event.currentTarget.dataset.id;
        const report = this.reports.find(r => r.id === reportId);

        this.activeReportId = reportId;
        this.activeReportName = report ? report.name : '';
        this.activeReportDescription = report ? report.description : '';
        this.isLoading = true;
        this.reportResult = null;
        this.reportError = '';
        this.sectionPagination = {};
        this.sectionSort = {};

        getReportConfig({ configId: reportId })
            .then(config => {
                if (!config.Configuration_JSON__c) {
                    throw new Error('No configuration found for this report.');
                }
                return executeReport({
                    configJson: config.Configuration_JSON__c,
                    filtersJson: '[]'
                });
            })
            .then(result => {
                this.reportResult = {
                    sections: result.sections.map(sec => ({
                        ...sec,
                        rawRows: sec.rows || []
                    }))
                };
                // Init pagination for each section
                const pagination = {};
                result.sections.forEach(sec => {
                    pagination[sec.sectionId] = { currentPage: 1 };
                });
                this.sectionPagination = pagination;
                this.currentView = 'report';
            })
            .catch(error => {
                this.reportError = this.getErrorMessage(error);
                this.showToast('Error', this.reportError, 'error');
            })
            .finally(() => { this.isLoading = false; });
    }

    handleBackToList() {
        this.currentView = 'list';
        this.reportResult = null;
        this.reportError = '';
    }

    handleRefreshReport() {
        if (this.activeReportId) {
            const fakeEvent = { currentTarget: { dataset: { id: this.activeReportId } } };
            this.handleRunReport(fakeEvent);
        }
    }

    // ── Pagination ──
    handlePrevPage(event) {
        const secId = event.currentTarget.dataset.sectionid;
        const pagination = { ...this.sectionPagination };
        if (pagination[secId] && pagination[secId].currentPage > 1) {
            pagination[secId] = { ...pagination[secId], currentPage: pagination[secId].currentPage - 1 };
            this.sectionPagination = pagination;
        }
    }

    handleNextPage(event) {
        const secId = event.currentTarget.dataset.sectionid;
        const pagination = { ...this.sectionPagination };
        if (pagination[secId]) {
            pagination[secId] = { ...pagination[secId], currentPage: pagination[secId].currentPage + 1 };
            this.sectionPagination = pagination;
        }
    }

    // ── Column Sorting ──
    handleSort(event) {
        const secId = event.currentTarget.dataset.sectionid;
        const fieldName = event.currentTarget.dataset.field;
        const sortInfo = this.sectionSort[secId] || { field: null, direction: 'ASC' };

        let newDirection = 'ASC';
        if (sortInfo.field === fieldName) {
            newDirection = sortInfo.direction === 'ASC' ? 'DESC' : 'ASC';
        }

        this.sectionSort = {
            ...this.sectionSort,
            [secId]: { field: fieldName, direction: newDirection }
        };

        // Reset to page 1 when sorting
        this.sectionPagination = {
            ...this.sectionPagination,
            [secId]: { currentPage: 1 }
        };
    }

    // ── Excel Export (all sections) ──
    handleExportExcel() {
        if (!this.reportResult || !this.reportResult.sections) {
            this.showToast('Info', 'No data to export', 'info');
            return;
        }

        const reportName = this.activeReportName || 'Report';
        let html = '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40">';
        html += '<head><meta charset="UTF-8"><!--[if gte mso 9]><xml><x:ExcelWorkbook><x:ExcelWorksheets><x:ExcelWorksheet>';
        html += '<x:Name>' + this.escapeHtml(reportName) + '</x:Name>';
        html += '<x:WorksheetOptions><x:DisplayGridlines/></x:WorksheetOptions></x:ExcelWorksheet></x:ExcelWorksheets></x:ExcelWorkbook></xml><![endif]-->';
        html += '<style>table { border-collapse: collapse; } th { background-color: #0176d3; color: #ffffff; font-weight: bold; padding: 8px 12px; border: 1px solid #ccc; font-family: Calibri, Arial, sans-serif; font-size: 11pt; } td { padding: 6px 12px; border: 1px solid #ddd; font-family: Calibri, Arial, sans-serif; font-size: 10pt; } .section-title { background-color: #f0f7ff; font-weight: bold; font-size: 12pt; padding: 10px; color: #0b5cab; } .number-cell { mso-number-format: General; text-align: right; }</style>';
        html += '</head><body>';

        for (const sec of this.reportResult.sections) {
            if (!sec.rawRows || sec.rawRows.length === 0) continue;

            // Section title row
            html += '<table>';
            html += '<tr><td colspan="' + sec.columns.length + '" class="section-title">' + this.escapeHtml(sec.sectionTitle || '') + ' (' + sec.rawRows.length + ' records)</td></tr>';

            // Headers
            html += '<tr>';
            for (const col of sec.columns) {
                html += '<th>' + this.escapeHtml(col.label || col.fieldName) + '</th>';
            }
            html += '</tr>';

            // Data rows
            for (const row of sec.rawRows) {
                html += '<tr>';
                for (const col of sec.columns) {
                    const val = row[col.fieldName] !== undefined ? String(row[col.fieldName]) : '';
                    const cls = col.columnType === 'number' ? ' class="number-cell"' : '';
                    html += '<td' + cls + '>' + this.escapeHtml(val) + '</td>';
                }
                html += '</tr>';
            }
            html += '</table><br/>';
        }

        html += '</body></html>';

        const blob = new Blob([html], { type: 'application/vnd.ms-excel;charset=utf-8;' });
        this._downloadBlob(blob, reportName.replace(/[^a-zA-Z0-9 ]/g, '_') + '.xls');
        this.showToast('Success', 'Report downloaded as Excel', 'success');
    }

    // ── CSV Export (per section) ──
    handleExportCsv(event) {
        const secId = event.currentTarget.dataset.sectionid;
        const section = this.reportResult.sections.find(s => s.sectionId === secId);
        if (!section || !section.rawRows || section.rawRows.length === 0) {
            this.showToast('Info', 'No data to export', 'info');
            return;
        }

        const headers = section.columns.map(c => '"' + (c.label || c.fieldName).replace(/"/g, '""') + '"');
        const rows = section.rawRows.map(row =>
            section.columns.map(col => {
                const val = row[col.fieldName] !== undefined ? String(row[col.fieldName]) : '';
                return '"' + val.replace(/"/g, '""') + '"';
            }).join(',')
        );

        const csv = headers.join(',') + '\n' + rows.join('\n');
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const fileName = (this.activeReportName || 'report') + '_' + (section.sectionTitle || 'data') + '.csv';
        this._downloadBlob(blob, fileName);
    }

    _downloadBlob(blob, fileName) {
        // LWC Locker Service requires the anchor to be in the DOM before click
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = fileName;
        link.style.display = 'none';
        // Append to body (works in Locker Service unlike shadow DOM append)
        document.body.appendChild(link);
        link.click();
        // Clean up after a tick
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
        }, 100);
    }

    escapeHtml(str) {
        if (!str) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // ── Helpers ──
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getErrorMessage(error) {
        if (Array.isArray(error.body)) {
            return error.body.map(e => e.message).join(', ');
        } else if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        }
        return 'Unknown error';
    }
}