import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';

import getAllTemplates from '@salesforce/apex/DocumentDesignerController.getAllTemplates';
import getTemplateById from '@salesforce/apex/DocumentDesignerController.getTemplateById';
import saveTemplate from '@salesforce/apex/DocumentDesignerController.saveTemplate';
import deleteTemplate from '@salesforce/apex/DocumentDesignerController.deleteTemplate';
import cloneTemplate from '@salesforce/apex/DocumentDesignerController.cloneTemplate';
import getObjectList from '@salesforce/apex/DocumentDesignerController.getObjectList';
import getObjectFields from '@salesforce/apex/DocumentDesignerController.getObjectFields';
import getChildRelationships from '@salesforce/apex/DocumentDesignerController.getChildRelationships';
import getChildObjectFields from '@salesforce/apex/DocumentDesignerController.getChildObjectFields';
import getParentFields from '@salesforce/apex/DocumentDesignerController.getParentFields';
import uploadLogo from '@salesforce/apex/DocumentDesignerController.uploadLogo';
import getPicklistValues from '@salesforce/apex/DocumentViewerController.getPicklistValues';

export default class DocumentDesigner extends LightningElement {
    // ==================== STATE ====================
    @track currentView = 'list'; // list | editor
    @track isLoading = false;
    @track templates = [];
    wiredTemplateResult;

    // Editor state
    @track templateData = {};
    @track isEditMode = false;

    // Schema
    @track objectOptions = [];
    @track fieldOptions = [];
    @track childRelationships = [];
    @track childFieldOptions = [];
    @track parentFieldOptions = [];
    @track selectedLookupField = '';

    // Section builder
    @track sections = [];
    @track showSectionModal = false;
    @track editingSectionIndex = -1;
    @track editingSection = {};

    // Table column builder
    @track tableColumns = [];

    // Header / Footer
    @track headerConfig = {
        left: { type: 'none', content: '', logoUrl: '', logoContentVersionId: '' },
        center: { type: 'none', content: '', logoUrl: '', logoContentVersionId: '' },
        right: { type: 'none', content: '', logoUrl: '', logoContentVersionId: '' },
        fontSize: '', bold: false, textColor: '',
        // Legacy fields for backward compatibility
        showLogo: false, logoUrl: '', logoPosition: 'left', content: ''
    };
    @track footerConfig = { content: '', showPageNumbers: true, pageNumberPosition: 'center', fontSize: '10px', textColor: '#666666' };

    // Page styling
    @track styleConfig = {
        fontFamily: 'Arial, Helvetica, sans-serif',
        fontSize: '12px',
        primaryColor: '#333333',
        marginTop: '20',
        marginRight: '15',
        marginBottom: '20',
        marginLeft: '15'
    };

    // Merge field picker
    @track showMergeFieldPicker = false;
    @track mergeFieldTarget = '';
    @track mergeFieldSearchTerm = '';

    // Field grid lookup for parent fields
    @track fieldGridLookupField = '';
    @track fieldGridParentOptions = [];

    // Collapsible panels
    @track panels = {
        basic: true,
        styling: false,
        header: true,
        sections: true,
        footer: false,
        matching: false,
        visibility: false
    };

    // Logo upload
    @track isUploadingLogo = false;

    // Visibility conditions
    @track visibilityConditions = {
        logic: 'AND',
        rules: []
    };
    @track picklistValuesCache = {};

    @api
    refresh() {
        return refreshApex(this.wiredTemplateResult);
    }

    // ==================== WIRE ====================
    @wire(getAllTemplates)
    wiredTemplates(result) {
        this.wiredTemplateResult = result;
        if (result.data) {
            this.templates = result.data;
        } else if (result.error) {
            this.showToast('Error', this.getError(result.error), 'error');
        }
    }

    @wire(getObjectList)
    wiredObjects({ data }) {
        if (data) {
            this.objectOptions = [{ label: '-- Select Object --', value: '' }, ...data.map(o => ({ label: o.label, value: o.value }))];
        }
    }

    // ==================== COMPUTED ====================
    get isListView() { return this.currentView === 'list'; }
    get isEditorView() { return this.currentView === 'editor'; }
    get hasTemplates() { return this.templates && this.templates.length > 0; }
    get editorTitle() { return this.isEditMode ? 'Edit Document Template' : 'New Document Template'; }
    get hasSections() { return this.sections && this.sections.length > 0; }
    get sectionCount() { return this.sections ? this.sections.length : 0; }

    get pageSizeOptions() {
        return [
            { label: 'A4', value: 'A4' },
            { label: 'Letter', value: 'letter' },
            { label: 'Legal', value: 'legal' },
            { label: 'A3', value: 'A3' }
        ];
    }

    get orientationOptions() {
        return [
            { label: 'Portrait', value: 'portrait' },
            { label: 'Landscape', value: 'landscape' }
        ];
    }

    get displayContextOptions() {
        return [
            { label: 'Both (Email & Document Viewer)', value: 'Both' },
            { label: 'Document Viewer Only', value: 'Document Viewer' },
            { label: 'Email Only', value: 'Email' }
        ];
    }

    get actionBindingOptions() {
        return [
            { label: '-- None (Show everywhere) --', value: '' },
            { label: 'Demand Raiser', value: 'Demand Raiser' }
        ];
    }

    get separatorStyleOptions() {
        return [
            { label: 'Solid', value: 'solid' },
            { label: 'Dashed', value: 'dashed' },
            { label: 'Dotted', value: 'dotted' }
        ];
    }

    get sectionTypeOptions() {
        return [
            { label: 'Content / Rich Text', value: 'content' },
            { label: 'Heading', value: 'heading' },
            { label: 'Field Grid (Label-Value Pairs)', value: 'fieldGrid' },
            { label: 'Related Records Table', value: 'table' },
            { label: 'Separator / Divider', value: 'separator' },
            { label: 'Page Break', value: 'pageBreak' },
            { label: 'Image', value: 'image' }
        ];
    }

    get headingLevelOptions() {
        return [
            { label: 'H1 - Large', value: '1' },
            { label: 'H2 - Medium', value: '2' },
            { label: 'H3 - Small', value: '3' }
        ];
    }

    get textAlignOptions() {
        return [
            { label: 'Left', value: 'left' },
            { label: 'Center', value: 'center' },
            { label: 'Right', value: 'right' }
        ];
    }

    get logoPositionOptions() {
        return [
            { label: 'Left', value: 'left' },
            { label: 'Center', value: 'center' },
            { label: 'Right', value: 'right' }
        ];
    }

    get fontFamilyOptions() {
        return [
            { label: 'Arial', value: 'Arial, Helvetica, sans-serif' },
            { label: 'Helvetica', value: 'Helvetica, Arial, sans-serif' },
            { label: 'Times New Roman', value: 'Times New Roman, Times, serif' },
            { label: 'Georgia', value: 'Georgia, serif' },
            { label: 'Verdana', value: 'Verdana, Geneva, sans-serif' },
            { label: 'Courier New', value: 'Courier New, Courier, monospace' },
            { label: 'Tahoma', value: 'Tahoma, Geneva, sans-serif' }
        ];
    }

    get baseFontSizeOptions() {
        return [
            { label: '10px', value: '10px' },
            { label: '11px', value: '11px' },
            { label: '12px (Default)', value: '12px' },
            { label: '13px', value: '13px' },
            { label: '14px', value: '14px' },
            { label: '16px', value: '16px' },
            { label: '18px', value: '18px' }
        ];
    }

    get sectionFontSizeOptions() {
        return [
            { label: 'Default (inherit)', value: '' },
            { label: '9px', value: '9px' },
            { label: '10px', value: '10px' },
            { label: '11px', value: '11px' },
            { label: '12px', value: '12px' },
            { label: '13px', value: '13px' },
            { label: '14px', value: '14px' },
            { label: '16px', value: '16px' },
            { label: '18px', value: '18px' },
            { label: '20px', value: '20px' },
            { label: '24px', value: '24px' }
        ];
    }

    get pageNumberPositionOptions() {
        return [
            { label: 'Left', value: 'left' },
            { label: 'Center', value: 'center' },
            { label: 'Right', value: 'right' }
        ];
    }

    get richTextFormats() {
        return [
            'font', 'size', 'bold', 'italic', 'underline', 'strike',
            'list', 'indent', 'align', 'link', 'image', 'clean',
            'table', 'header', 'color', 'background'
        ];
    }

    get isContentSection() { return this.editingSection.type === 'content'; }
    get isHeadingSection() { return this.editingSection.type === 'heading'; }
    get isFieldGridSection() { return this.editingSection.type === 'fieldGrid'; }
    get isTableSection() { return this.editingSection.type === 'table'; }
    get isSeparatorSection() { return this.editingSection.type === 'separator'; }
    get isPageBreakSection() { return this.editingSection.type === 'pageBreak'; }
    get isImageSection() { return this.editingSection.type === 'image'; }
    get editingSectionImageUrl() {
        if (this.editingSection.imageContentVersionId) {
            return '/sfc/servlet.shepherd/version/download/' + this.editingSection.imageContentVersionId;
        }
        return this.editingSection.imageUrl || '';
    }
    get isEditingExistingSection() { return this.editingSectionIndex >= 0; }

    get childRelationshipOptions() {
        return [
            { label: '-- Select Relationship --', value: '' },
            ...this.childRelationships.map(r => ({
                label: r.label,
                value: r.childObjectName + '|' + r.relationshipFieldName + '|' + r.relationshipName
            }))
        ];
    }

    get lookupFieldOptions() {
        return [
            { label: '-- Select Parent Lookup --', value: '' },
            ...this.fieldOptions.filter(f => f.type === 'REFERENCE').map(f => ({
                label: f.label + ' -> ' + (f.referenceTo || ''),
                value: f.value
            }))
        ];
    }

    get hasLookupFields() {
        return this.fieldOptions.some(f => f.type === 'REFERENCE');
    }

    get hasParentFields() {
        return this.parentFieldOptions && this.parentFieldOptions.length > 0;
    }

    get fieldGridFields() {
        return this.editingSection.fields || [];
    }

    get hasTableColumns() {
        return this.tableColumns && this.tableColumns.length > 0;
    }

    get hasFieldGridFields() {
        return this.fieldGridFields && this.fieldGridFields.length > 0;
    }

    get mergeFieldList() {
        return this.fieldOptions.map(f => ({
            label: f.label,
            value: '{!' + f.value + '}',
            type: f.type
        }));
    }

    get filteredMergeFieldList() {
        const list = this.mergeFieldList;
        if (!this.mergeFieldSearchTerm) return list;
        const term = this.mergeFieldSearchTerm.toLowerCase();
        return list.filter(f =>
            f.label.toLowerCase().includes(term) || f.value.toLowerCase().includes(term)
        );
    }

    get specialTokens() {
        return [
            { label: '{!TODAY}', value: '{!TODAY}' },
            { label: '{!NOW}', value: '{!NOW}' }
        ];
    }

    get hasFilteredMergeFields() {
        return this.filteredMergeFieldList && this.filteredMergeFieldList.length > 0;
    }

    get parentMergeFieldList() {
        if (!this.parentFieldOptions || !this.selectedLookupField) return [];
        // Convert lookup field to relationship name (e.g. Account__c -> Account__r)
        let relName = this.selectedLookupField;
        if (relName.endsWith('__c')) {
            relName = relName.replace(/__c$/, '__r');
        } else if (relName === 'AccountId') {
            relName = 'Account';
        } else if (relName === 'ContactId') {
            relName = 'Contact';
        } else if (relName === 'OwnerId') {
            relName = 'Owner';
        } else if (relName.endsWith('Id')) {
            relName = relName.replace(/Id$/, '');
        }
        return this.parentFieldOptions.map(f => ({
            label: f.label,
            value: '{!' + relName + '.' + f.value + '}',
            type: f.type
        }));
    }

    // ==================== PANEL CHEVRON CLASSES ====================
    get basicChevron() { return 'config-chevron ' + (this.panels.basic ? 'config-chevron-up' : 'config-chevron-down'); }
    get stylingChevron() { return 'config-chevron ' + (this.panels.styling ? 'config-chevron-up' : 'config-chevron-down'); }
    get headerChevron() { return 'config-chevron ' + (this.panels.header ? 'config-chevron-up' : 'config-chevron-down'); }
    get sectionsChevron() { return 'config-chevron ' + (this.panels.sections ? 'config-chevron-up' : 'config-chevron-down'); }
    get footerChevron() { return 'config-chevron ' + (this.panels.footer ? 'config-chevron-up' : 'config-chevron-down'); }
    get matchingChevron() { return 'config-chevron ' + (this.panels.matching ? 'config-chevron-up' : 'config-chevron-down'); }
    get visibilityChevron() { return 'config-chevron ' + (this.panels.visibility ? 'config-chevron-up' : 'config-chevron-down'); }

    // ==================== PAGE PREVIEW COMPUTED ====================
    get pageCanvasClass() {
        return 'page-canvas' + (this.templateData.pageOrientation === 'landscape' ? ' page-canvas-landscape' : '');
    }

    get hasHeaderContent() {
        const h = this.headerConfig;
        return (h.left && h.left.type !== 'none') ||
               (h.center && h.center.type !== 'none') ||
               (h.right && h.right.type !== 'none');
    }

    get headerColumnTypeOptions() {
        return [
            { label: 'Empty', value: 'none' },
            { label: 'Text / Merge Field', value: 'text' },
            { label: 'Image / Logo', value: 'image' }
        ];
    }

    // Header column getters for template
    get headerLeft() { return this._resolveHeaderColImageUrl(this.headerConfig.left || this._getDefaultHeaderCol()); }
    get headerCenter() { return this._resolveHeaderColImageUrl(this.headerConfig.center || this._getDefaultHeaderCol()); }
    get headerRight() { return this._resolveHeaderColImageUrl(this.headerConfig.right || this._getDefaultHeaderCol()); }
    get isHeaderLeftText() { return this.headerLeft.type === 'text'; }
    get isHeaderLeftImage() { return this.headerLeft.type === 'image'; }
    get isHeaderCenterText() { return this.headerCenter.type === 'text'; }
    get isHeaderCenterImage() { return this.headerCenter.type === 'image'; }
    get isHeaderRightText() { return this.headerRight.type === 'text'; }
    get isHeaderRightImage() { return this.headerRight.type === 'image'; }
    get hasHeaderLeftContent() { return this.headerLeft.type !== 'none'; }
    get hasHeaderCenterContent() { return this.headerCenter.type !== 'none'; }
    get hasHeaderRightContent() { return this.headerRight.type !== 'none'; }

    get hasFooterContent() {
        return this.footerConfig.content || this.footerConfig.showPageNumbers;
    }

    get previewPageNumAlign() {
        return 'text-align:' + (this.footerConfig.pageNumberPosition || 'center') + ';margin-top:4px;';
    }

    get previewPageCount() {
        const pages = this.previewPages;
        return pages ? pages.length : 1;
    }

    // Split sections into pages by pageBreak sections
    get previewPages() {
        const pages = [];
        let currentSections = [];
        let pageNum = 1;

        const allSections = this.sections.map((s, i) => this._buildPreviewSection(s, i));

        for (const sec of allSections) {
            if (sec.type === 'pageBreak') {
                currentSections.push(sec);
                pages.push({
                    _key: 'page-' + pageNum,
                    _label: 'Page ' + pageNum,
                    _pageNum: pageNum,
                    _isFirst: pageNum === 1,
                    _sections: currentSections
                });
                currentSections = [];
                pageNum++;
            } else {
                currentSections.push(sec);
            }
        }

        // Last page (or only page)
        pages.push({
            _key: 'page-' + pageNum,
            _label: 'Page ' + pageNum,
            _pageNum: pageNum,
            _isFirst: pageNum === 1,
            _sections: currentSections
        });

        return pages;
    }

    _buildPreviewSection(s, i) {
        const labelMap = {
            content: 'Rich Text', heading: 'Heading', fieldGrid: 'Field Grid',
            table: 'Data Table', separator: 'Line', pageBreak: 'Page Break', image: 'Image'
        };
        const iconMap = {
            content: 'utility:richtextbulletedlist', heading: 'utility:bold',
            fieldGrid: 'utility:layout', table: 'utility:table',
            separator: 'utility:dash', pageBreak: 'utility:jump_to_right', image: 'utility:image'
        };

        const type = s.type || 'content';
        const sec = {
            ...s,
            _index: i,
            _key: 'pv-' + i,
            _label: labelMap[type] || type,
            _labelClass: 'preview-section-label label-' + type,
            _icon: iconMap[type] || 'utility:page',
            _isContent: type === 'content',
            _isHeading: type === 'heading',
            _isFieldGrid: type === 'fieldGrid',
            _isTable: type === 'table',
            _isSeparator: type === 'separator',
            _isPageBreak: type === 'pageBreak',
            _isImage: type === 'image'
        };

        // Heading
        if (type === 'heading') {
            const level = s.level || '2';
            sec._headingClass = 'pv-heading-' + level;
            sec._headingText = s.content || 'Heading';
            let style = 'text-align:' + (s.textAlign || 'left') + ';';
            if (s.textColor) style += 'color:' + s.textColor + ';';
            sec._headingStyle = style;
        }

        // Field Grid
        if (type === 'fieldGrid' && s.fields && s.fields.length) {
            const cols = parseInt(s.gridColumns, 10) || 2;
            const rows = [];
            for (let r = 0; r < s.fields.length; r += cols) {
                const cells = [];
                for (let c = 0; c < cols; c++) {
                    const f = s.fields[r + c];
                    if (f) {
                        cells.push({ _key: 'l-' + r + '-' + c, _class: 'fg-label', _text: f.label || 'Label' });
                        cells.push({ _key: 'v-' + r + '-' + c, _class: 'fg-value', _text: f.field || 'Value' });
                    }
                }
                rows.push({ _key: 'gr-' + r, _cells: cells });
            }
            sec._gridPreview = rows;
        } else if (type === 'fieldGrid') {
            sec._gridPreview = [];
        }

        // Table columns
        if (type === 'table') {
            sec._tableColumns = (s.columns || []).map((c, ci) => ({
                ...c,
                _key: 'tc-' + ci,
                label: c.label || 'Column'
            }));
        }

        // Separator
        if (type === 'separator') {
            sec._separatorStyle = 'border-top:1px ' + (s.style || 'solid') + ' #ccc;';
        }

        // Image
        if (type === 'image') {
            sec._imageAlign = 'text-align:' + (s.textAlign || 'center') + ';';
            let imgStyle = 'max-width:' + (s.imageMaxWidth || '100%') + ';';
            if (s.imageMaxHeight && s.imageMaxHeight !== 'auto') {
                imgStyle += 'max-height:' + s.imageMaxHeight + ';';
            }
            sec._imageStyle = imgStyle;
            // Resolve image URL from ContentVersionId for reliable LWC display
            if (s.imageContentVersionId) {
                sec.imageUrl = '/sfc/servlet.shepherd/version/download/' + s.imageContentVersionId;
            }
        }

        return sec;
    }

    handleTogglePanelAndScroll(event) {
        const panel = event.currentTarget.dataset.panel;
        if (!this.panels[panel]) {
            this.panels = { ...this.panels, [panel]: true };
        }
    }

    // ==================== LIST VIEW HANDLERS ====================

    handleNewTemplate() {
        this.templateData = {
            name: '',
            objectApiName: '',
            description: '',
            isActive: true,
            logoUrl: '',
            fileNamePattern: '',
            pageSize: 'A4',
            pageOrientation: 'portrait',
            displayContext: 'Both',
            actionBinding: ''
        };
        this.sections = [];
        this.headerConfig = this._getDefaultHeader();
        this.footerConfig = { content: '', showPageNumbers: true, pageNumberPosition: 'center', fontSize: '10px', textColor: '#666666' };
        this.styleConfig = {
            fontFamily: 'Arial, Helvetica, sans-serif',
            fontSize: '12px',
            primaryColor: '#333333',
            marginTop: '20',
            marginRight: '15',
            marginBottom: '20',
            marginLeft: '15'
        };
        this.visibilityConditions = { logic: 'AND', rules: [] };
        this.isEditMode = false;
        this.currentView = 'editor';
    }

    handleEditTemplate(event) {
        const templateId = event.currentTarget.dataset.id;
        this.isLoading = true;
        getTemplateById({ templateId })
            .then(result => {
                this.templateData = { ...result };
                this.isEditMode = true;

                const defaultFooter = { content: '', showPageNumbers: true, pageNumberPosition: 'center', fontSize: '10px', textColor: '#666666' };
                const defaultStyle = {
                    fontFamily: 'Arial, Helvetica, sans-serif', fontSize: '12px', primaryColor: '#333333',
                    marginTop: '20', marginRight: '15', marginBottom: '20', marginLeft: '15'
                };

                if (result.templateJson) {
                    try {
                        const parsed = JSON.parse(result.templateJson);
                        this.sections = parsed.sections || [];
                        this.headerConfig = this._migrateHeaderConfig(parsed.header);
                        this.footerConfig = { ...defaultFooter, ...(parsed.footer || {}) };
                        this.styleConfig = { ...defaultStyle, ...(parsed.styles || {}) };
                        this.visibilityConditions = parsed.visibilityConditions || { logic: 'AND', rules: [] };
                    } catch (e) {
                        this.sections = [];
                        this.headerConfig = this._getDefaultHeader();
                        this.footerConfig = { ...defaultFooter };
                        this.styleConfig = { ...defaultStyle };
                        this.visibilityConditions = { logic: 'AND', rules: [] };
                    }
                } else {
                    this.sections = [];
                    this.headerConfig = this._getDefaultHeader();
                    this.footerConfig = { ...defaultFooter };
                    this.styleConfig = { ...defaultStyle };
                    this.visibilityConditions = { logic: 'AND', rules: [] };
                }

                if (result.objectApiName) {
                    this.loadObjectSchema(result.objectApiName);
                }

                this.currentView = 'editor';
            })
            .catch(error => this.showToast('Error', this.getError(error), 'error'))
            .finally(() => { this.isLoading = false; });
    }

    handleDeleteTemplate(event) {
        const templateId = event.currentTarget.dataset.id;
        if (!confirm('Are you sure you want to delete this template?')) return;
        this.isLoading = true;
        deleteTemplate({ templateId })
            .then(() => {
                this.showToast('Success', 'Template deleted', 'success');
                return refreshApex(this.wiredTemplateResult);
            })
            .catch(error => this.showToast('Error', this.getError(error), 'error'))
            .finally(() => { this.isLoading = false; });
    }

    handleCloneTemplate(event) {
        const templateId = event.currentTarget.dataset.id;
        this.isLoading = true;
        cloneTemplate({ templateId })
            .then(() => {
                this.showToast('Success', 'Template cloned', 'success');
                return refreshApex(this.wiredTemplateResult);
            })
            .catch(error => this.showToast('Error', this.getError(error), 'error'))
            .finally(() => { this.isLoading = false; });
    }

    // ==================== PANEL TOGGLE ====================

    handleTogglePanel(event) {
        const panel = event.currentTarget.dataset.panel;
        this.panels = { ...this.panels, [panel]: !this.panels[panel] };
    }

    // ==================== EDITOR HANDLERS ====================

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : (event.detail?.value !== undefined ? event.detail.value : event.target.value);
        this.templateData = { ...this.templateData, [field]: value };

        if (field === 'objectApiName' && value) {
            this.loadObjectSchema(value);
        }
    }

    handleMatchingCriteriaChange(event) {
        this.templateData = { ...this.templateData, matchingCriteria: event.detail.criteriaJson };
    }

    handleHeaderChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : (event.detail?.value !== undefined ? event.detail.value : event.target.value);
        this.headerConfig = { ...this.headerConfig, [field]: value };
    }

    handleHeaderColChange(event) {
        const col = event.target.dataset.col; // 'left', 'center', 'right'
        const field = event.target.dataset.field;
        const value = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        const colData = { ...(this.headerConfig[col] || this._getDefaultHeaderCol()), [field]: value };
        this.headerConfig = { ...this.headerConfig, [col]: colData };
        // Sync logoUrl to templateData for backward compatibility
        if (field === 'logoUrl') {
            this.templateData = { ...this.templateData, logoUrl: value };
        }
    }

    handleHeaderColRichText(event) {
        const col = event.target.dataset.col;
        const colData = { ...(this.headerConfig[col] || this._getDefaultHeaderCol()), content: event.target.value };
        this.headerConfig = { ...this.headerConfig, [col]: colData };
    }

    handleHeaderLogoUpload(event) {
        const col = event.target.dataset.col;
        const file = event.target.files[0];
        if (!file) return;
        this._uploadImageFile(file, (url, cvId) => {
            const colData = {
                ...(this.headerConfig[col] || this._getDefaultHeaderCol()),
                type: 'image',
                logoUrl: url,
                logoContentVersionId: cvId
            };
            this.headerConfig = { ...this.headerConfig, [col]: colData };
            this.templateData = { ...this.templateData, logoUrl: url };
        });
    }

    handleSectionImageUpload(event) {
        const file = event.target.files[0];
        if (!file) return;
        this._uploadImageFile(file, (url, cvId) => {
            this.editingSection = {
                ...this.editingSection,
                imageUrl: url,
                imageContentVersionId: cvId
            };
        });
    }

    _uploadImageFile(file, callback) {
        const maxSize = 500 * 1024; // 500KB max to avoid PDF regex limits
        if (file.size > maxSize) {
            this.showToast('Error', 'Image must be under 500KB for reliable PDF rendering. Please compress the image.', 'error');
            return;
        }
        const allowedTypes = ['image/png', 'image/jpeg', 'image/gif', 'image/svg+xml'];
        if (!allowedTypes.includes(file.type)) {
            this.showToast('Error', 'Only PNG, JPG, GIF, SVG files are allowed', 'error');
            return;
        }
        this.isUploadingLogo = true;
        const reader = new FileReader();
        reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            uploadLogo({ fileName: file.name, base64Data: base64 })
                .then(responseJson => {
                    const response = JSON.parse(responseJson);
                    callback(response.url, response.contentVersionId);
                    this.showToast('Success', 'Image uploaded successfully', 'success');
                })
                .catch(error => {
                    this.showToast('Error', this.getError(error), 'error');
                })
                .finally(() => { this.isUploadingLogo = false; });
        };
        reader.readAsDataURL(file);
    }

    handleFooterChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : (event.detail?.value !== undefined ? event.detail.value : event.target.value);
        this.footerConfig = { ...this.footerConfig, [field]: value };
    }

    handleRichTextHeaderChange(event) {
        // Legacy handler - kept for backward compatibility but now unused
        this.headerConfig = { ...this.headerConfig, content: event.target.value };
    }

    handleRichTextFooterChange(event) {
        this.footerConfig = { ...this.footerConfig, content: event.target.value };
    }

    handleRichTextChange(event) {
        this.editingSection = { ...this.editingSection, content: event.target.value };
    }

    handleStyleChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        this.styleConfig = { ...this.styleConfig, [field]: value };
    }

    handleBackToList() {
        this.currentView = 'list';
        this.templateData = {};
        this.sections = [];
        this.visibilityConditions = { logic: 'AND', rules: [] };
    }

    // ==================== VISIBILITY CONDITION HANDLERS ====================

    get visibilityLogicOptions() {
        return [
            { label: 'ALL conditions must match (AND)', value: 'AND' },
            { label: 'ANY condition can match (OR)', value: 'OR' }
        ];
    }

    get conditionTypeOptions() {
        return [
            { label: 'Record Field', value: 'field' },
            { label: 'Profile', value: 'profile' },
            { label: 'User Role', value: 'userRole' },
            { label: 'User', value: 'user' }
        ];
    }

    get conditionOperatorOptions() {
        return [
            { label: 'Equals', value: 'equals' },
            { label: 'Not Equals', value: 'notEquals' },
            { label: 'Contains', value: 'contains' },
            { label: 'Not Contains', value: 'notContains' },
            { label: 'Starts With', value: 'startsWith' },
            { label: 'Is Blank', value: 'isBlank' },
            { label: 'Is Not Blank', value: 'isNotBlank' },
            { label: 'In (comma separated)', value: 'in' }
        ];
    }

    get hasVisibilityRules() {
        return this.visibilityConditions.rules && this.visibilityConditions.rules.length > 0;
    }

    get visibilityRulesWithKey() {
        const placeholders = {
            field: 'Enter value...',
            profile: 'e.g. System Administrator',
            userRole: 'e.g. Sales Manager',
            user: 'Enter User ID (005...)'
        };
        return (this.visibilityConditions.rules || []).map((r, i) => ({
            ...r,
            _key: 'rule-' + i,
            _index: i,
            _isFieldType: r.type === 'field',
            _showValueInput: r.operator !== 'isBlank' && r.operator !== 'isNotBlank',
            _picklistOptions: this.picklistValuesCache[r.field] || null,
            _hasPicklist: !!(this.picklistValuesCache[r.field] && this.picklistValuesCache[r.field].length > 0),
            _valuePlaceholder: placeholders[r.type] || 'Enter value...'
        }));
    }

    get fieldOptionsForCondition() {
        return [
            { label: '-- Select Field --', value: '' },
            ...this.fieldOptions.map(f => ({
                label: f.label + ' (' + f.value + ')',
                value: f.value
            }))
        ];
    }

    handleVisibilityLogicChange(event) {
        this.visibilityConditions = {
            ...this.visibilityConditions,
            logic: event.detail.value
        };
    }

    handleAddVisibilityRule() {
        const rules = [...(this.visibilityConditions.rules || [])];
        rules.push({ type: 'field', field: '', operator: 'equals', value: '' });
        this.visibilityConditions = { ...this.visibilityConditions, rules };
    }

    handleVisibilityRuleChange(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const prop = event.currentTarget.dataset.prop;
        const val = event.detail?.value !== undefined ? event.detail.value : event.target.value;

        const rules = this.visibilityConditions.rules.map((r, i) => {
            if (i === idx) {
                const updated = { ...r, [prop]: val };
                // Reset value when field changes
                if (prop === 'field') {
                    updated.value = '';
                    // Load picklist values if field is a picklist
                    this._loadPicklistForField(val);
                }
                if (prop === 'type') {
                    updated.field = '';
                    updated.value = '';
                }
                return updated;
            }
            return r;
        });
        this.visibilityConditions = { ...this.visibilityConditions, rules };
    }

    handleRemoveVisibilityRule(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const rules = this.visibilityConditions.rules.filter((_, i) => i !== idx);
        this.visibilityConditions = { ...this.visibilityConditions, rules };
    }

    _loadPicklistForField(fieldApiName) {
        if (!fieldApiName || !this.templateData.objectApiName) return;
        // Check if we already have it
        if (this.picklistValuesCache[fieldApiName]) return;

        // Check if this field is a picklist type
        const fieldInfo = this.fieldOptions.find(f => f.value === fieldApiName);
        if (!fieldInfo || (fieldInfo.type !== 'PICKLIST' && fieldInfo.type !== 'MULTIPICKLIST')) return;

        getPicklistValues({ objectApiName: this.templateData.objectApiName, fieldApiName })
            .then(result => {
                this.picklistValuesCache = {
                    ...this.picklistValuesCache,
                    [fieldApiName]: (result || []).map(p => ({ label: p.label, value: p.value }))
                };
            })
            .catch(() => {});
    }

    // ==================== SECTION HANDLERS ====================

    _getDefaultSection(type) {
        return {
            type: type || 'content',
            content: '',
            textAlign: 'left',
            level: '2',
            fields: [],
            childObject: '',
            relationshipField: '',
            title: '',
            columns: [],
            orderBy: '',
            maxRows: 50,
            showRowNumbers: true,
            headerBackground: '#f5f5f5',
            headerColor: '#333333',
            borderColor: '#dddddd',
            alternateRowColors: false,
            alternateRowBackground: '#f9f9f9',
            style: 'solid',
            backgroundColor: 'transparent',
            padding: '8px 0',
            gridColumns: 2,
            fontSize: '',
            bold: false,
            textColor: '',
            imageUrl: '',
            imageMaxWidth: '100%',
            imageMaxHeight: 'auto',
            imageCaption: '',
            imageContentVersionId: ''
        };
    }

    handleAddSection() {
        this.editingSection = this._getDefaultSection('content');
        this.tableColumns = [];
        this.editingSectionIndex = -1;
        this.showSectionModal = true;
    }

    handleQuickAddSection(event) {
        const type = event.currentTarget.dataset.type;
        this.editingSection = this._getDefaultSection(type);
        this.tableColumns = [];
        this.editingSectionIndex = -1;
        this.showSectionModal = true;
    }

    handleEditSection(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const section = JSON.parse(JSON.stringify(this.sections[idx]));
        if (section.fields) {
            section.fields = section.fields.map((f) => ({ ...f, _id: f._id || this._generateId() }));
        }
        this.editingSection = section;
        this.tableColumns = section.columns
            ? section.columns.map((c) => ({ ...c, _id: c._id || this._generateId() }))
            : [];
        this.editingSectionIndex = idx;
        this.showSectionModal = true;

        if (section.type === 'table' && section.childObject) {
            this.loadChildFields(section.childObject);
        }
    }

    handleDeleteSection(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        this.sections = this.sections.filter((_, i) => i !== idx);
    }

    handleMoveSectionUp(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (idx > 0) {
            const arr = [...this.sections];
            [arr[idx - 1], arr[idx]] = [arr[idx], arr[idx - 1]];
            this.sections = arr;
        }
    }

    handleMoveSectionDown(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (idx < this.sections.length - 1) {
            const arr = [...this.sections];
            [arr[idx], arr[idx + 1]] = [arr[idx + 1], arr[idx]];
            this.sections = arr;
        }
    }

    handleSectionFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : (event.detail?.value !== undefined ? event.detail.value : event.target.value);
        this.editingSection = { ...this.editingSection, [field]: value };

        if (field === 'selectedRelationship' && value) {
            const parts = value.split('|');
            this.editingSection.childObject = parts[0];
            this.editingSection.relationshipField = parts[1];
            this.editingSection.relationshipName = parts[2];
            this.editingSection = { ...this.editingSection };
            this.loadChildFields(parts[0]);
        }
    }

    handleSaveSection() {
        const section = { ...this.editingSection };
        if (section.type === 'table') {
            section.columns = this.tableColumns.map(({ _id, ...rest }) => rest);
        }
        if (section.fields) {
            section.fields = section.fields.map(({ _id, ...rest }) => rest);
        }

        if (this.editingSectionIndex >= 0) {
            this.sections = this.sections.map((s, i) => i === this.editingSectionIndex ? section : s);
        } else {
            this.sections = [...this.sections, section];
        }
        this.showSectionModal = false;
    }

    handleCancelSection() {
        this.showSectionModal = false;
    }

    // ==================== FIELD GRID HANDLERS ====================

    handleAddFieldGridItem() {
        const fields = this.editingSection.fields ? [...this.editingSection.fields] : [];
        fields.push({ label: '', field: '', _id: this._generateId() });
        this.editingSection = { ...this.editingSection, fields };
    }

    handleFieldGridItemChange(event) {
        const id = event.target.dataset.itemId;
        const prop = event.target.dataset.prop;
        const val = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        const fields = (this.editingSection.fields || []).map(f =>
            f._id === id ? { ...f, [prop]: val } : f
        );
        this.editingSection = { ...this.editingSection, fields };
    }

    handleRemoveFieldGridItem(event) {
        const id = event.currentTarget.dataset.itemId;
        const fields = (this.editingSection.fields || []).filter(f => f._id !== id);
        this.editingSection = { ...this.editingSection, fields };
    }

    handleFieldGridLookupChange(event) {
        const lookupField = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        this.fieldGridLookupField = lookupField;
        this.fieldGridParentOptions = [];
        if (lookupField && this.templateData.objectApiName) {
            getParentFields({ objectApiName: this.templateData.objectApiName, lookupFieldName: lookupField })
                .then(result => { this.fieldGridParentOptions = result || []; })
                .catch(() => { this.fieldGridParentOptions = []; });
        }
    }

    // ==================== TABLE COLUMN HANDLERS ====================

    handleAddColumn() {
        this.tableColumns = [...this.tableColumns, { label: '', field: '', _id: this._generateId() }];
    }

    handleColumnChange(event) {
        const id = event.target.dataset.itemId;
        const prop = event.target.dataset.prop;
        const val = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        this.tableColumns = this.tableColumns.map(c =>
            c._id === id ? { ...c, [prop]: val } : c
        );
    }

    handleRemoveColumn(event) {
        const id = event.currentTarget.dataset.itemId;
        this.tableColumns = this.tableColumns.filter(c => c._id !== id);
    }

    // ==================== MERGE FIELD PICKER ====================

    handleOpenMergeFieldPicker(event) {
        this.mergeFieldTarget = event.currentTarget.dataset.target;
        this.mergeFieldSearchTerm = '';
        this.showMergeFieldPicker = true;
    }

    handleCloseMergeFieldPicker() {
        this.showMergeFieldPicker = false;
    }

    handleMergeFieldSearch(event) {
        this.mergeFieldSearchTerm = event.target.value || '';
    }

    handleInsertMergeField(event) {
        const mergeField = event.currentTarget.dataset.value;
        if (this.mergeFieldTarget === 'headerLeft' || this.mergeFieldTarget === 'headerCenter' || this.mergeFieldTarget === 'headerRight') {
            const col = this.mergeFieldTarget.replace('header', '').toLowerCase();
            const colData = { ...(this.headerConfig[col] || this._getDefaultHeaderCol()) };
            colData.content = (colData.content || '') + ' ' + mergeField;
            this.headerConfig = { ...this.headerConfig, [col]: colData };
        } else if (this.mergeFieldTarget === 'footer') {
            this.footerConfig = { ...this.footerConfig, content: (this.footerConfig.content || '') + ' ' + mergeField };
        } else if (this.mergeFieldTarget === 'sectionContent') {
            this.editingSection = { ...this.editingSection, content: (this.editingSection.content || '') + ' ' + mergeField };
        } else if (this.mergeFieldTarget === 'fileNamePattern') {
            this.templateData = { ...this.templateData, fileNamePattern: (this.templateData.fileNamePattern || '') + mergeField };
        } else if (this.mergeFieldTarget === 'quickInsert') {
            // Create a new content section with the merge field token
            const newSection = this._getDefaultSection('content');
            newSection.content = mergeField;
            this.sections = [...this.sections, newSection];
        }
        this.showMergeFieldPicker = false;
    }

    // ==================== SAVE TEMPLATE ====================

    handleSaveTemplate() {
        if (!this.templateData.name) {
            this.showToast('Error', 'Template name is required', 'error');
            return;
        }
        if (!this.templateData.objectApiName) {
            this.showToast('Error', 'Object is required', 'error');
            return;
        }

        // Only include visibilityConditions if there are rules
        const hasRules = this.visibilityConditions.rules && this.visibilityConditions.rules.length > 0;
        const templateJson = JSON.stringify({
            header: this.headerConfig,
            footer: this.footerConfig,
            sections: this.sections,
            styles: this.styleConfig,
            ...(hasRules ? { visibilityConditions: this.visibilityConditions } : {})
        });

        const payload = {
            ...this.templateData,
            templateJson
        };

        if (this.isEditMode && this.templateData.id) {
            payload.id = this.templateData.id;
        }

        this.isLoading = true;
        saveTemplate({ templateJson: JSON.stringify(payload) })
            .then(() => {
                this.showToast('Success', 'Document template saved successfully', 'success');
                this.currentView = 'list';
                this.templateData = {};
                return refreshApex(this.wiredTemplateResult);
            })
            .catch(error => this.showToast('Error', this.getError(error), 'error'))
            .finally(() => { this.isLoading = false; });
    }

    // ==================== SCHEMA LOADING ====================

    loadObjectSchema(objectApiName) {
        getObjectFields({ objectApiName })
            .then(result => { this.fieldOptions = result || []; })
            .catch(() => { this.fieldOptions = []; });

        getChildRelationships({ objectApiName })
            .then(result => { this.childRelationships = result || []; })
            .catch(() => { this.childRelationships = []; });
    }

    loadChildFields(childObjectApiName) {
        getChildObjectFields({ childObjectApiName })
            .then(result => { this.childFieldOptions = result || []; })
            .catch(() => { this.childFieldOptions = []; });
    }

    handleLoadParentFields(event) {
        const lookupField = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        this.selectedLookupField = lookupField;
        if (lookupField && this.templateData.objectApiName) {
            getParentFields({ objectApiName: this.templateData.objectApiName, lookupFieldName: lookupField })
                .then(result => { this.parentFieldOptions = result || []; })
                .catch(() => { this.parentFieldOptions = []; });
        } else {
            this.parentFieldOptions = [];
        }
    }

    // ==================== HELPERS ====================

    getSectionLabel(section) {
        const labels = {
            content: 'Rich Text', heading: 'Heading', fieldGrid: 'Field Grid',
            table: 'Data Table', separator: 'Separator', pageBreak: 'Page Break',
            image: 'Image'
        };
        return labels[section.type] || section.type;
    }

    getSectionIcon(section) {
        const icons = {
            content: 'utility:richtextbulletedlist', heading: 'utility:bold',
            fieldGrid: 'utility:layout', table: 'utility:table',
            separator: 'utility:dash', pageBreak: 'utility:jump_to_right',
            image: 'utility:image'
        };
        return icons[section.type] || 'utility:page';
    }

    getSectionSummary(section) {
        if (section.type === 'content') {
            const text = (section.content || '').replace(/<[^>]*>/g, '');
            return text.substring(0, 80) + (text.length > 80 ? '...' : '');
        }
        if (section.type === 'heading') return section.content || 'Heading';
        if (section.type === 'table') return 'Child: ' + (section.title || section.childObject || 'Untitled');
        if (section.type === 'fieldGrid') return (section.fields ? section.fields.length : 0) + ' fields';
        if (section.type === 'separator') return 'Horizontal line (' + (section.style || 'solid') + ')';
        if (section.type === 'pageBreak') return 'Forces new page';
        if (section.type === 'image') return section.imageCaption || 'Image';
        return '';
    }

    get sectionListItems() {
        return this.sections.map((s, i) => ({
            ...s,
            _index: i,
            _key: 'sec-' + i,
            _label: this.getSectionLabel(s),
            _icon: this.getSectionIcon(s),
            _summary: this.getSectionSummary(s),
            _isFirst: i === 0,
            _isLast: i === this.sections.length - 1,
            _badgeClass: 'section-type-badge section-type-' + (s.type || 'content')
        }));
    }

    get childFieldOptionsForCombobox() {
        return [
            { label: '-- Select Field --', value: '' },
            ...this.childFieldOptions.map(f => ({ label: f.label + ' (' + f.value + ')', value: f.value }))
        ];
    }

    get fieldOptionsForGrid() {
        return [
            { label: '-- Select Field --', value: '' },
            ...this.fieldOptions.map(f => ({ label: f.label + ' (' + f.value + ')', value: f.value }))
        ];
    }

    get fieldOptionsForGridAll() {
        const opts = [
            { label: '-- Select Field --', value: '' },
            ...this.fieldOptions.map(f => ({ label: f.label + ' (' + f.value + ')', value: f.value }))
        ];
        // Add parent fields if a lookup is selected
        if (this.fieldGridLookupField && this.fieldGridParentOptions.length > 0) {
            let relName = this.fieldGridLookupField;
            if (relName.endsWith('__c')) {
                relName = relName.replace(/__c$/, '__r');
            } else if (relName === 'AccountId') {
                relName = 'Account';
            } else if (relName === 'ContactId') {
                relName = 'Contact';
            } else if (relName === 'OwnerId') {
                relName = 'Owner';
            } else if (relName.endsWith('Id')) {
                relName = relName.replace(/Id$/, '');
            }
            opts.push({ label: '── Parent: ' + relName + ' ──', value: '_parent_separator_', disabled: true });
            for (const f of this.fieldGridParentOptions) {
                opts.push({ label: f.label + ' (' + relName + '.' + f.value + ')', value: relName + '.' + f.value });
            }
        }
        return opts;
    }

    _getDefaultHeaderCol() {
        return { type: 'none', content: '', logoUrl: '', logoContentVersionId: '' };
    }

    /**
     * Resolve image URL for a header column: prefer internal Salesforce file URL
     * built from logoContentVersionId over the ContentDistribution URL (which
     * often fails in LWC due to CSP / cross-domain restrictions).
     */
    _resolveHeaderColImageUrl(col) {
        if (!col || col.type !== 'image') return col;
        if (col.logoContentVersionId) {
            return {
                ...col,
                logoUrl: '/sfc/servlet.shepherd/version/download/' + col.logoContentVersionId
            };
        }
        return col;
    }

    _getDefaultHeader() {
        return {
            left: this._getDefaultHeaderCol(),
            center: this._getDefaultHeaderCol(),
            right: this._getDefaultHeaderCol(),
            fontSize: '', bold: false, textColor: ''
        };
    }

    _migrateHeaderConfig(header) {
        // Migrate legacy single-column header to 3-column layout
        if (header && !header.left && !header.center && !header.right) {
            const migrated = this._getDefaultHeader();
            migrated.fontSize = header.fontSize || '';
            migrated.bold = header.bold || false;
            migrated.textColor = header.textColor || '';
            // Place logo and content based on old logoPosition
            if (header.showLogo && header.logoUrl) {
                const logoPos = header.logoPosition || 'left';
                const logoCol = logoPos === 'right' ? 'right' : (logoPos === 'center' ? 'center' : 'left');
                migrated[logoCol] = { type: 'image', content: '', logoUrl: header.logoUrl, logoContentVersionId: header.logoContentVersionId || '' };
            }
            if (header.content) {
                // Find the first empty column (prefer center, then the one without logo)
                if (migrated.center.type === 'none') {
                    migrated.center = { type: 'text', content: header.content, logoUrl: '', logoContentVersionId: '' };
                } else if (migrated.left.type === 'none') {
                    migrated.left = { type: 'text', content: header.content, logoUrl: '', logoContentVersionId: '' };
                } else {
                    migrated.right = { type: 'text', content: header.content, logoUrl: '', logoContentVersionId: '' };
                }
            }
            return migrated;
        }
        return { ...this._getDefaultHeader(), ...header,
            left: { ...this._getDefaultHeaderCol(), ...(header?.left || {}) },
            center: { ...this._getDefaultHeaderCol(), ...(header?.center || {}) },
            right: { ...this._getDefaultHeaderCol(), ...(header?.right || {}) }
        };
    }

    _idCounter = 0;
    _generateId() {
        return 'item_' + (++this._idCounter) + '_' + Date.now();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    getError(error) {
        if (Array.isArray(error?.body)) return error.body.map(e => e.message).join(', ');
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'Unknown error';
    }
}