import { LightningElement, track } from 'lwc';

export default class PostInstallationGuide extends LightningElement {
    @track activeSections = ['upload', 'roundRobin', 'duplication', 'costSheet', 'discount', 'pushToSales'];

    searchTerm = '';
// This is a single-line comment
    steps = [
        {
            id: 'upload',
            number: '01',
            title: 'Upload Custom Metadata Records',
            icon: 'utility:upload',
            summary: 'Several features in this package ship with seed Custom Metadata Type rows (Cost Sheet field config, Lead status actions, AI integration, etc.). Load them once before configuring the features below.',
            bullets: [
                'Download the seed records bundle from the public link below.',
                'Install Salesforce Inspector Reloaded (Chrome / Edge / Firefox) in your browser.',
                'Log in to the target org, open Salesforce Inspector, and click "Data Import" in the side panel.',
                'Set Action = Insert (use Upsert if re-running), Object = the Custom Metadata Type API name (for example Cost_Sheet_Field_Config__mdt, Lead_Status_Action_Config__mdt, AI_Integration_Config__mdt).',
                'Paste the CSV (or drag-drop the .csv file) from the bundle and click "Run Import". Re-run failed rows after fixing them.',
                'To edit later: Setup -> Custom Metadata Types -> Manage Records -> Edit; for bulk edits use Inspector "Data Export", edit in a spreadsheet, then "Data Import" with Action = Update.'
            ],
            links: [
                {
                    label: 'Custom Metadata Records (public link)',
                    url: 'https://realai-c-dev-ed.develop.my.salesforce.com/sfc/p/#f600000HNFKl/a/f6000000BVgP/zkEsUVVjqGqpL66ubUeqnJ0r0J_EG7vYZTgO0hTm9nQ'
                }
            ]
        },
        {
            id: 'roundRobin',
            number: '02',
            title: 'Round Robin (Lead Assignment)',
            icon: 'standard:work_queue',
            summary: 'Distribute incoming leads automatically across a team using filter-driven buckets and a sequenced rotation.',
            bullets: [
                'Open the "RoundRobin Configurator" tab (LWC: roundRobinConfiguratorLWC).',
                'Create a new Round_Robin__c bucket and add filter rules in Round_Robin_Filter__c (project, source, lead type, etc.).',
                'Add team members under Round_Robin_Member__c with sequence numbers - the lower the sequence, the earlier they receive leads.',
                'Optional: use the "RR Wizard" tab to scaffold a bucket end-to-end in one flow.',
                'Verify by creating a test lead that matches the filter and confirming ownership lands on the next member in rotation.'
            ]
        },
        {
            id: 'duplication',
            number: '03',
            title: 'Lead Duplication',
            icon: 'standard:record_lookup',
            summary: 'Detect duplicate leads on incoming data and decide what action to take (close, merge, or flag).',
            bullets: [
                'Open the "Duplication Configurator" tab (LWC: duplicationConfigurator).',
                'Create a Duplication_Configuration__c rule and pick the match fields (e.g. Mobile + Project + Source).',
                'Set the action: close the duplicate, merge, or flag for manual review.',
                'Schedule the CleanupDuplicateLeadsBatch Apex job (snippet in /scripts) to run daily.',
                'Verify on the "Duplication Configuration" tab - duplicate leads created after the rule should be flagged automatically.'
            ]
        },
        {
            id: 'costSheet',
            number: '04',
            title: 'Cost Sheet Calculations',
            icon: 'standard:quotes',
            summary: 'Calibrate cost-sheet pricing components (base price, GST, maintenance, floor rise, etc.) and field mappings on the Project record using the Formula Builder.',
            bullets: [
                'Open the target Project__c record.',
                'Launch the Formula Builder from the Project page (LWC: formulaBuilder, controller: FormulaBuilderController) to define cost-sheet line items and their formulas.',
                'Map each cost-sheet field (Base Price, GST %, Maintenance / Sqft, Floor Rise / Sqft, etc.) to the corresponding Project field or formula expression.',
                'Save the configuration on the Project so every Cost Sheet generated for that project picks up these formulas automatically.',
                'Test by opening a Lead linked to that Project and running the "New Cost Sheet" quick action; confirm the calculated total matches expectations.',
                'Approved Cost Sheets can be promoted using the "Create Booking" quick action (LWC: createBookingFromCostSheet).'
            ]
        },
        {
            id: 'discount',
            number: '05',
            title: 'Discount Approval Matrix',
            icon: 'standard:approval',
            summary: 'Define discount bands and the approver hierarchy that fires when a sales rep requests a discount.',
            bullets: [
                'Open the "Discount Approval Matrix" tab (LWC: discountMatrixForm / discountApprovalPanel).',
                'Add a row in Discount_Approval_Matrix__c for each discount band (e.g. 0-5% auto-approve, 5-15% Sr. Manager, >15% Director).',
                'Pick approver users or queues per row.',
                'Schedule DiscountApprovalEscalationBatch to auto-escalate pending approvals.',
                'Audit trail of every approval / rejection lands in Discount_Approval_Log__c.'
            ]
        },
        {
            id: 'pushToSales',
            number: '06',
            title: 'Push to Sales',
            icon: 'standard:opportunity',
            summary: 'Hand a qualified pre-sales lead over to the sales team with the right field mapping and ownership.',
            bullets: [
                'Open the "Pre-Sales Admin Config" tab and go to the "General Setup Config" sub-tab.',
                'Configure the pre-sales -> sales field mapping there (do NOT use the standalone "Push To Sales Field Map" tab).',
                'Add the Lead__c.Push_to_Sales quick action (LWC: pushToSalesAction, controller: PushToSalesController) to the Lead layout used by pre-sales reps.',
                'Add the "Push To Sales" tab to the sales app for visibility on handed-over records.',
                'Verify by pushing a qualified lead and confirming the resulting Opportunity / Booking carries the mapped fields and the new owner.'
            ]
        }
    ];

    get filteredSteps() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        if (!term) {
            return this.steps;
        }
        return this.steps.filter(step => {
            if (step.title.toLowerCase().includes(term)) return true;
            if (step.summary.toLowerCase().includes(term)) return true;
            return (step.bullets || []).some(b => b.toLowerCase().includes(term));
        });
    }

    get hasResults() {
        return this.filteredSteps.length > 0;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleExpandAll() {
        this.activeSections = this.steps.map(s => s.id);
    }

    handleCollapseAll() {
        this.activeSections = [];
    }

    handleSectionToggle(event) {
        this.activeSections = event.detail.openSections;
    }
}