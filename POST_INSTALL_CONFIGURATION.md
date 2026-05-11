# RealMake-Product — Post-Install Configuration Guide

This document lists **everything that must be configured after the RealMake-Product
managed/unmanaged package is deployed to a Salesforce org**. Work through the
sections in order; later steps depend on data created in earlier ones.

A condensed in-app version of this guide is available on the **Welcome Guide** tab
(LWC: `postInstallationGuide`). This file is the authoritative reference for
implementation engineers and admins.

---

## 0. Pre-flight checklist

Before configuring anything, verify the deploy succeeded:

| Item | Where to check | Expected |
|---|---|---|
| Package deploy status | Setup → Deployment Status | All components Succeeded |
| API version | `sfdx-project.json` / org | `62.0` (Winter '25) or higher |
| My Domain | Setup → My Domain | Deployed & enabled (required for LWC) |
| Lightning Experience | Setup → Lightning Experience Transition | Enabled |
| Person Accounts | (Optional) Setup → Account Settings | Enable only if the customer uses person accounts |

Install the **Salesforce Inspector Reloaded** browser extension before starting
— several steps below use its **Data Import** panel for bulk seeding.

---

## 1. Assign permission sets & profiles

The package ships with these permission sets / profile updates. Assign to the
appropriate users **first**, otherwise tabs and LWCs will not appear.

1. Setup → **Permission Sets** → assign to admins / power users:
   - `sfdc_nc_constraints_engine_deploy` (platform managed)
   - `sfdc_scrt2` (platform managed)
2. For each functional team (Pre-Sales, Post-Sales, Channel Partner, GRE,
   Finance), create or update a **Profile** and grant:
   - **Object access** to all `__c` objects deployed (Lead, Booking, Cost Sheet,
     Project, Unit, Tower, Receipt, Demand, Refund, Complaint, etc.).
   - **Tab visibility** for the tabs that team needs (see Section 13).
   - **Apex class access** for the controllers used by the LWCs (e.g.
     `FormulaBuilderController`, `PushToSalesController`,
     `ApprovalCenterController`).
   - **Visualforce page access** for any VF pages used in demand letters.

> Tip: until the customer is ready to lock down profiles, assigning **System
> Administrator** to the implementation user keeps the rest of the setup
> unblocked.

---

## 2. Upload seed Custom Metadata Type (CMDT) records

Several features ship with **empty** Custom Metadata Types. They must be seeded
before the features work. Use the **public link in the Welcome Guide LWC**
(`postInstallationGuide.js`, step `upload`) to download the CSV bundle.

For each CMDT below: open Salesforce Inspector → **Data Import** → Action
`Insert` (or `Upsert` if re-running) → Object = the CMDT API name → paste CSV →
Run.

| CMDT API Name | Purpose | Required? |
|---|---|---|
| `Cost_Sheet_Field_Config__mdt` | Field layout, order, visibility, and defaults for the Cost Sheet UI | **Yes** — Cost Sheet won't render without rows |
| `Lead_Status_Action_Config__mdt` | Per-status rules: requires follow-up / site visit / lost reason / remarks | **Yes** — Lead status update modal depends on this |
| `AI_Integration_Config__mdt` | Provider, model, endpoint, and API key for the Aria / AI chat-bot | Only if AI features are used |
| `Dashboard_Tab_Config__mdt` | Tabs shown on the home notification dashboard | **Yes** — dashboard is empty without rows |
| `Dashboard_Field_Config__mdt` | Fields displayed on each dashboard tab card | **Yes** — pairs with `Dashboard_Tab_Config__mdt` |
| `Forecast_Config__mdt` | Funnel stages, moving-average window, seasonality lookback, health-score weights for `salesForecaster` | Only if sales forecasting is used |
| `Shift_Configuration__mdt` | Working-hour shifts (start / end time, default flag) | Only if user availability is tracked |
| `User_Availability_Profile_Config__mdt` | Maps profiles → shifts and which profiles can see availability | Only if user availability is tracked |
| `Integration_Doc_Setting__mdt` | Company name, header colour, logo, watermark for integration-generated documents | Only if outbound documents are issued |

To edit later: **Setup → Custom Metadata Types → Manage Records → Edit**, or for
bulk edits use Salesforce Inspector **Data Export** → spreadsheet edit → **Data
Import** with Action `Update`.

---

## 3. Remote Site Settings & Trusted Sites

The package deploys one remote site (`ApexDevNet`) as a placeholder. Replace or
add entries before any HTTP callout will succeed.

1. **Setup → Remote Site Settings** — add an entry for every external host the
   integrations will hit (payment gateway, SMS, email service, AI provider,
   ERP, etc.). Set `Disable Protocol Security = false`.
2. **Setup → CSP Trusted Sites** — add entries for any external domain whose
   resources (fonts, scripts, iframes) the LWCs need to load.
3. **Setup → Named Credentials** — for OAuth / signed callouts, prefer Named
   Credentials over hardcoded URLs in `Integration_Endpoint__c`.

---

## 4. General Setup (`General_Setup__c`)

Open the **General Setup** list view (Setup → Object Manager →
`General_Setup__c` → tab or App Launcher).

Create one active row per environment with:

| Field | Allowed values | Notes |
|---|---|---|
| `Is_Active__c` | true | Only one active row should exist |
| `Lead_Duplication_Type__c` | `Close` / `Merge` / `Flag` | Default fallback when no `Duplication_Configuration__c` rule matches |
| `Push_To_Sales_Type__c` | `Booking` / `Opportunity` / both | Target object created when Push-To-Sales fires |
| `Description__c` | free text | Document the environment intent |

---

## 5. Round Robin (Lead Assignment)

Configure on the **RoundRobin Configurator** tab (LWC:
`roundRobinConfiguratorLWC`) or use the **RR Wizard** for a guided flow.

1. Create a `Round_Robin__c` bucket for each team / region (e.g. `US Platinum`,
   `International Silver`).
2. Add filter rows in `Round_Robin_Filter__c` — project, source, lead type,
   country, etc. **All filters in one bucket are AND-ed**; create multiple
   buckets for OR semantics.
3. Add the team members in `Round_Robin_Member__c`. The **sequence number**
   controls rotation order; lower numbers receive earlier.
4. Optional: weight members via `Round_Robin_Field_Priority__c`.
5. Confirm the matching queues (Section 6) exist for the buckets.
6. **Smoke test**: create a Lead matching the filter — owner should rotate
   through members on subsequent matching leads.

---

## 6. Queues (verify membership)

The package deploys these Lead/Case queues — they exist but **have no members**:

- `USLeads`, `USPlatinumGold`, `USSilverBronze`, `USEscalations`
- `InternationalLeads`, `InternationalPlatinumGold`,
  `InternationalSilverBronze`, `InternationalEscalations`
- `PartnerRelations`

Setup → **Queues** → for each queue: add **Public Group** or individual users
who should own the records routed to it.

---

## 7. Lead Duplication

1. Open the **Duplication Configurator** tab (LWC: `duplicationConfigurator`).
2. Create one or more `Duplication_Configuration__c` rules. Pick:
   - Match fields (e.g. `Mobile + Project + Source`).
   - Action: `Close`, `Merge`, or `Flag`.
3. Schedule the `CleanupDuplicateLeadsBatch` Apex job (snippet in `/scripts`)
   to run nightly:
   ```apex
   System.schedule('Cleanup Duplicate Leads',
       '0 0 1 * * ?', new CleanupDuplicateLeadsBatch());
   ```
4. Verify: create a duplicate Lead — it should be flagged / closed / merged
   per the rule.

---

## 8. Cost Sheet (Pricing) Configuration

Per-project pricing lives on the **Project__c** record.

1. Confirm `Cost_Sheet_Field_Config__mdt` rows were seeded (Section 2).
2. Open each `Project__c` record.
3. Launch **Formula Builder** from the Project page (LWC: `formulaBuilder`,
   controller: `FormulaBuilderController`).
4. For each cost-sheet line item (Base Price, GST %, PLC, Floor Rise / Sqft,
   Maintenance / Sqft, Stamp Duty, Registration, etc.), define the formula or
   map to the corresponding Project field.
5. Save — every Cost Sheet generated for that project picks up these formulas.
6. (Optional) Create `Project_Calculation_Template__c` records to share a
   formula set across multiple projects.
7. **Smoke test**: open a Lead linked to the project → **New Cost Sheet** quick
   action → confirm totals match.
8. Approved Cost Sheets are converted with the **Create Booking** quick action
   (LWC: `createBookingFromCostSheet`).

---

## 9. Discount Approval Matrix

1. Open the **Discount Approval Matrix** tab (LWC: `discountMatrixForm` /
   `discountApprovalPanel`).
2. Add a `Discount_Approval_Matrix__c` row per band, e.g.:
   - 0 – 5 % → Auto-approve
   - 5 – 15 % → Sr. Manager
   - 15 % + → Director
3. Pick approver **users or queues** per row.
4. Activate / schedule `DiscountApprovalEscalationBatch` so unattended
   approvals auto-escalate.
5. Audit trail of every approve / reject lands in `Discount_Approval_Log__c`.

---

## 10. Approval Configuration (generic engine)

`Approval_Configuration__c` powers the dynamic approval engine used by
Booking, Refund, Unit Block, etc.

For each business process that needs approvals:

| Field | What to fill |
|---|---|
| `Process_Label__c` | Human-readable name |
| `Process_Type__c` | Booking / Refund / Unit Block / Cost Sheet / etc. |
| `Object_API_Name__c` | The triggering object's API name |
| `Status_Field_API_Name__c` | The status picklist field |
| `Pending_Status_Value__c` / `Approved_Status_Value__c` / `Rejected_Status_Value__c` | The exact picklist values |
| `Approval_Process_API_Name__c` | (Optional) Existing Salesforce approval process |
| `Steps_JSON__c` | JSON array of steps — built using the `approvalStepConfig` / `stepBuilder` LWC |
| `Required_Fields_JSON__c` | Fields that must be populated before submit |
| `Matching_Criteria__c` | Criteria expression matching records eligible for this config |
| `On_Approval_JSON__c` / `On_Rejection_JSON__c` | Post-decision field updates / actions |
| `Prerequisite_Process_Type__c` + `Prerequisite_Status_Value__c` | Chain approvals (e.g. Cost Sheet must be approved before Booking) |
| `Sequence_Order__c` | Order when multiple configs match |
| `Is_Active__c` | true |

The end-user approval inbox is the **Approval Center** LWC
(`approvalCenter` / `bulkApprovalManager`).

---

## 11. Push To Sales (Pre-Sales → Sales hand-off)

> **Important**: the canonical setup tab is **Pre-Sales Admin Config → General
> Setup Config sub-tab**. The standalone `Push To Sales Field Map` tab is
> deprecated.

1. Open the **Pre-Sales Admin Config** tab (LWC: `presalesAdminConfig`).
2. Choose the **General Setup Config** sub-tab and define the
   pre-sales → sales field mapping there (uses
   `Field_Mapping_Configuration__c` + `Field_Mapping_Detail__c` underneath).
3. Add the `Lead__c.Push_to_Sales` quick action (LWC: `pushToSalesAction`,
   controller: `PushToSalesController`) to the Lead page layout used by
   pre-sales reps.
4. Add the **Push To Sales** tab to the Sales app so handed-over records are
   visible to the sales team.
5. **Smoke test**: push a qualified Lead → confirm the Booking / Opportunity
   carries the mapped fields and the new owner.

For bulk imports, use **Pre-Sales Bulk Config** (LWC: `presalesBulkConfig`).

---

## 12. Post-Sales Configuration

Post-Sales has its own configurator: **Post-Sales Admin** tab (LWC:
`postSalesAdmin`). For each post-sales process create one or more
`Post_Sales_Configuration__c` rows.

Key fields:

- `Configuration_Type__c` — Demand / Receipt / Refund / Credit Note / Debit
  Note / Schedule.
- `Schedule_Mode__c`, `Schedule_Source__c`, `Schedule_Edit_Mode__c` — control
  how the payment schedule is generated and edited.
- `Demand_Mode__c`, `Demand_Due_Duration__c`, `Due_Date_Offset_Days__c`,
  `Grace_Period_Days__c` — demand-letter cadence.
- `Receipt_Creation_Mode__c`, `Receipt_Amount_Field__c`,
  `Receipt_Field_Mapping__c` — how receipts are produced.
- `Document_Template__c` — points to a `Document_Template__c` (Section 17).
- `Email_Template__c` + `Auto_Send_Email__c` — points to
  `Email_Template_Config__c` (Section 16).
- `Approval_Configuration__c` — links to the approval config (Section 10).
- `Include_Interest__c`, `Include_Previous_Dues__c`,
  `Amount_Composition_Config__c` — financial composition.
- `Enable_Reminders__c` + `Reminder_Config__c` — reminder cadence.
- `Matching_Criteria__c` — which records the config applies to.

Master / global post-sales defaults: `Post_Sales_Config_Master__c`.

Demand-letter project defaults: `Demand_Letter_Config__c` (template, email,
grace days, interest flag) — one row per `Project__c`.

Payment schedule templates: `Master_Payment_Schedule__c` — one row per
milestone with `Percentage__c`, `Days_After_Booking__c` /
`Days_After_Previous__c`, `Payment_Type__c`, `Applicable_For__c`.

---

## 13. Tabs to expose per app

The package deploys ~40 tabs. Expose them on the Lightning App that the team
uses (App Builder → App Manager → edit → Navigation Items):

**Pre-Sales app**: `Lead__c`, `Followup__c`, `Site_Visit__c`, `Campaign__c`,
`Enquiry_Source__c`, `RoundRobin_Configurator`, `Duplication_Configurator`,
`Pre_Sales_Admin_Config`, `Pre_Sales_Bulk_Config`, `Lead_Scoring_Designer`,
`Welcome_Guide`.

**Sales app**: `Booking__c`, `Cost_Sheet__c`, `Unit__c`, `Tower__c`,
`Project__c`, `Car_Parking__c`, `Push_To_Sales`, `Formula_Builder`,
`Discount_Approval_Matrix`, `Discount_Approval_Log__c`.

**Post-Sales / Finance app**: `Payment_Schedule__c`,
`Master_Payment_Schedule__c`, `Refund__c`, `Post_Sales_Admin`,
`Unit_Block_Request__c`, `Complaint__c`, `Inspection__c`.

**Channel Partner app**: `Channel_Partner__c`, `CP_Module_Config__c`,
`Daily_Log__c`.

**Admin / Cross-functional**: `CRM_Dashboards`, `CRM_Reports`,
`Field_Mapping_Setup`, `Integration_Mapping_Designer`,
`Integration_Source_Config__c`, `Integration_Field_Rule__c`,
`Integration_Lookup_Rule__c`, `GRE`, `Bulk_Lead_Reassignment`,
`Formula_Builder`, `Welcome_Guide`.

---

## 14. Dashboards & Reports (configurator)

The home dashboard is configured per-user-profile via metadata + records:

1. Seed `Dashboard_Tab_Config__mdt` (Section 2) — defines which tabs show up.
2. Seed `Dashboard_Field_Config__mdt` (Section 2) — fields shown on each card.
3. (Optional) Per-user / per-org overrides via `Dashboard_Configuration__c`
   (JSON column edited via the **Dashboard Configurator** LWC).
4. Reports are similarly described in `Report_Configuration__c`, edited via
   `reportConfigurator` LWC and rendered by `reportViewer`.

---

## 15. Lead Scoring

1. Open the **Lead Scoring Designer** tab (LWC: `leadScoringDesigner`).
2. Create `Lead_Score_Tier__c` rows (Hot / Warm / Cold thresholds).
3. Create `Lead_Score_Rule__c` rows. Each rule is one positive / negative
   signal — e.g. *Source = Website → +10*, *Site Visits ≥ 2 → +20*.
4. Activate the rules (`Is_Active__c = true`) and re-run scoring on existing
   leads via the batch button on the designer.

---

## 16. Email templates (`Email_Template_Config__c`)

Create one row per outbound email template. Use the **Email Template** list
view / **Document Designer** LWC chain (`emailSender`, `emailFieldPicker`,
`emailMergeFieldPicker`, `emailPreviewModal`).

Critical fields: `Template_Name__c`, `Object_API_Name__c`, `Subject__c`,
`Email_Body__c` (HTML), `Recipients_Config__c` (JSON), `From_Address__c`,
`Reply_To__c`, `Attachments_Config__c`, `Matching_Criteria__c`,
`Allow_Additional_Recipients__c`, `Is_Default__c`, `Is_Active__c`,
`Action_Binding__c` (links to the button / process that fires it).

Mark exactly **one** default per `(Object_API_Name__c, Action_Binding__c)`.

---

## 17. Document templates (`Document_Template__c`)

PDF / VF / HTML templates for demand letters, receipts, allotment letters,
etc. Built via the **Document Designer** LWC (`documentDesigner`).

Fields: `Object_API_Name__c`, `Template_HTML__c` / `Template_JSON__c` /
`Template_Content_Document_Id__c` (whichever rendering pipeline is used),
`Page_Size__c`, `Page_Orientation__c`, `Logo_URL__c`, `File_Name_Pattern__c`,
`Action_Binding__c`, `Display_Context__c`, `Include_Related_Lists__c`,
`Matching_Criteria__c`, `Active__c`.

Link templates from `Post_Sales_Configuration__c.Document_Template__c` and
from `Demand_Letter_Config__c.Document_Template__c`.

---

## 18. Complaint Escalation Matrix

`Complaint_Escalation_Matrix__c` — one row per Project × Category × Priority.

Fill the three levels:

| Level | Days | User | Notify? |
|---|---|---|---|
| Level 1 | `Level_1_Days__c` | `Level_1_User__c` | `Level_1_Notify__c` |
| Level 2 | `Level_2_Days__c` | `Level_2_User__c` | `Level_2_Notify__c` |
| Level 3 | `Level_3_Days__c` | `Level_3_User__c` | `Level_3_Notify__c` |

Toggle `Auto_Reassign__c` if the complaint owner should change automatically
when an SLA is breached. Configure via the `complaintEscalationConfig` LWC.

---

## 19. Channel Partner module (`CP_Module_Config__c`)

Create one active row per CP onboarding flow. Required values:

- `CP_Source_Name__c` — Lead source value used for CP-originated leads.
- `Assignment_Type__c` — how CP leads route (Round Robin, Owner of CP, etc.).
- `CP_Approval_Process__c` — approval used to activate a new CP.
- `CP_Active_Statuses__c` (multi-value) — statuses considered "active".
- `Credit_Active_Status__c`, `Credit_Expired_Status__c`,
  `Credit_Expiry_Days__c` — controls the CP credit / commission lifecycle.
- `Lead_Default_Status__c`, `Lead_Inactive_Statuses__c`,
  `Lead_Reengaged_Type__c`, `Lead_Reopened_Type__c` — drive Lead state
  transitions for CP-sourced leads.

---

## 20. Integration framework

A full integration stack is shipped — configure only what the customer needs.

### 20.1 Auth profiles (`Integration_Auth_Profile__c`)
One row per credential set. Pick `Auth_Type__c`: `API Key`, `Basic`, `Bearer`,
`OAuth2`, or `HMAC`. Fill only the fields relevant to the chosen type:
- API Key → `API_Key__c`, `Auth_Header_Name__c`, `Auth_Token_Prefix__c`.
- Basic → `Username__c`, `Password__c`.
- OAuth2 → `OAuth_Client_Id__c`, `OAuth_Client_Secret__c`,
  `OAuth_Token_Endpoint__c`, `OAuth_Grant_Type__c`, `OAuth_Scope__c`,
  `Token_Cache_Duration__c`.
- HMAC → `HMAC_Algorithm__c`, `HMAC_Header_Name__c`, `HMAC_Secret__c`.

Store secrets via Protected Custom Settings or Named Credentials if PCI / PII
is in scope.

### 20.2 Endpoints (`Integration_Endpoint__c`)
URL + method + headers per outbound call. Link to an
`Integration_Auth_Profile__c`. UI: `integrationEndpointList` /
`integrationEndpointForm`.

### 20.3 Source configs (`Integration_Source_Config__c`)
For inbound calls — `Source_Name__c`, `Endpoint_URL__c` (Site URL),
`Target_Object__c`, `API_Schema_JSON__c`, `Validation_Rules_JSON__c`,
`Enable_Duplicate_Check__c`.

### 20.4 Field mappings (`Integration_Field_Mapping__c` /
`Integration_Field_Rule__c` / `Integration_Lookup_Rule__c` /
`Integration_Response_Mapping__c`)
Build via **Integration Mapping Designer** (LWC:
`integrationMappingDesigner`) and **Field Mapping Setup** (LWC:
`fieldMappingSetup` / `fieldMapper`).

### 20.5 Request templates (`Integration_Request_Template__c`)
Body templates with merge fields, referenced by outbound calls.

### 20.6 Retry (`Integration_Retry_Config__c`)
Max attempts, back-off seconds, status codes to retry, dead-letter behaviour.

### 20.7 Monitoring
`Integration_Log__c`, `Integration_Error_Log__c`,
`Field_Mapping_Error_Log__c`. Surface in **Integration Dashboard** (LWC:
`integrationDashboard` / `integrationMonitorCards` /
`integrationErrorPanel`). Schedule a retention batch to purge logs older than
N days.

### 20.8 Test console
Use `integrationTestConsole` LWC to dry-run any endpoint without affecting
production records.

---

## 21. Forms & dynamic UI

- `Dynamic_Form_Configuration__c` — drives runtime forms via `dynamicFormButton`
  / `dynamicFormModal` / `dynamicFormAction`. Configure via
  `formConfiguratorBuilder` LWC.
- `Field_Mapping_Configuration__c` + `Field_Mapping_Detail__c` — runtime field
  remapping for inbound / Push-To-Sales flows.

---

## 22. AI / Aria chatbot (optional)

Skip entirely if AI is not licensed. Otherwise:

1. Seed at least one active `AI_Integration_Config__mdt` row with
   `Provider__c`, `Model__c`, `Endpoint__c`, `API_Key__c`, `Is_Active__c = true`.
2. Add the provider's host to **Remote Site Settings** and **CSP Trusted
   Sites**.
3. (Optional) Configure language / locale via `ariaLangLocale`.
4. Place the `aiChatBot` / `ariaChatBot` LWC on a Lightning Home or App page.
5. Place `ariaLeadCaptureForm` on a public Experience Cloud site if inbound
   chat-to-lead is in scope.

---

## 23. Performance, forecasting, availability (optional modules)

- **Performance**: `Performance_Target__c` + `Performance_Snapshot__c`,
  surfaced via `performanceManager` / `performanceLeaderboard` /
  `performanceTargetForm`. Create one target per user per period.
- **Forecasting**: requires `Forecast_Config__mdt`. UI: `salesForecaster`.
- **User availability**: requires `Shift_Configuration__mdt` and
  `User_Availability_Profile_Config__mdt`. UI: `userAvailabilityManager` /
  `myAvailabilityToggle`.

---

## 24. Static resources

The package ships:

- `Property_images` — replace with the customer's project imagery (zip).
- `SiteSamples` — sample HTML / CSS bundle for Experience Cloud — replace if
  used.
- `chartjs` — third-party chart library; do not modify.

---

## 25. Scheduled jobs to set up

Schedule the following Apex jobs after the data above is configured
(Setup → **Apex Classes → Schedule Apex** or via anonymous Apex):

| Job | Suggested cadence | Purpose |
|---|---|---|
| `CleanupDuplicateLeadsBatch` | Daily 01:00 | Resolve duplicate leads per `Duplication_Configuration__c` |
| `DiscountApprovalEscalationBatch` | Daily 08:00 | Escalate pending discount approvals past SLA |
| Demand reminder batch (per `Reminder_Config__c`) | Daily | Send demand-letter reminders |
| Complaint escalation batch | Hourly / Daily | Honour `Complaint_Escalation_Matrix__c` SLAs |
| Integration retry batch | Every 30 min | Retry failed integration calls per `Integration_Retry_Config__c` |
| Integration log purge | Weekly | Trim `Integration_Log__c` / `Integration_Error_Log__c` |
| Lead score recompute | Daily | Rebuild lead scores after rule changes |

---

## 26. Verification smoke tests

Run all of these before declaring the org configured:

1. **Lead creation** matches a Round Robin filter and lands on the correct
   user.
2. **Duplicate Lead** is closed / merged / flagged per the active duplication
   rule.
3. **Cost Sheet** generated on a Lead → totals match expected math; **Create
   Booking** quick action produces a Booking with mapped fields.
4. **Discount request** > 5 % triggers approval to the configured approver.
5. **Push To Sales** on a qualified Lead creates an Opportunity / Booking
   with the right owner and field values.
6. **Demand Letter** raised on a Booking emails the right template and
   attaches the right PDF.
7. **Complaint** opened with no action breaches Level 1 SLA after
   `Level_1_Days__c` days and re-assigns / notifies as configured.
8. **Integration** test console returns 200 for every active endpoint.
9. **Approval Center** lists pending items for the logged-in approver.
10. **Welcome Guide** tab loads with all six in-app sections expanded.

---

## 27. Going live — final checklist

- [ ] All seed CMDT rows imported (Section 2).
- [ ] At least one active `General_Setup__c` row (Section 4).
- [ ] Round Robin buckets + members + queues populated (Sections 5 & 6).
- [ ] Duplication rule + scheduled batch (Section 7).
- [ ] Cost Sheet formulas saved on every active `Project__c` (Section 8).
- [ ] Discount Approval Matrix populated for every band (Section 9).
- [ ] Approval Configurations created for every approving process (Section 10).
- [ ] Push-To-Sales mapping defined and quick action on layout (Section 11).
- [ ] Post-Sales config + demand letter config + payment schedule master
      populated (Section 12).
- [ ] Apps / tabs exposed to each team (Section 13).
- [ ] Dashboards & reports configured (Section 14).
- [ ] Lead scoring rules + tiers active (Section 15).
- [ ] Email + Document templates created and linked (Sections 16 & 17).
- [ ] Complaint Escalation Matrix populated per project (Section 18).
- [ ] Channel Partner module configured (Section 19) — if in scope.
- [ ] Integration auth profiles, endpoints, mappings, retry config in
      place (Section 20) — if in scope.
- [ ] AI chatbot wired up (Section 22) — if licensed.
- [ ] Scheduled Apex jobs activated (Section 25).
- [ ] Smoke tests in Section 26 all pass.

---

_For an interactive, searchable version of this guide inside Salesforce, open
the **Welcome Guide** tab in any Lightning app the package is deployed to._
