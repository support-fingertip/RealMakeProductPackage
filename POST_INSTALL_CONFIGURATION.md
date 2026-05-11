# RealMake-Product
## Setup Guide for Administrators

Welcome! This guide walks you through everything that needs to be set up
**after** the RealMake-Product package is installed in your Salesforce
organisation. It is written for business administrators — you do not need
to be a developer to follow it.

By the end of this guide your team will be able to:

- Capture and assign leads automatically
- Generate pricing (cost sheets) and bookings
- Send demand letters, collect receipts, and issue refunds
- Manage channel partners and complaints
- See dashboards and reports tailored to each team

---

## How to use this guide

Each section follows the same simple structure:

> **What it does** — a one-paragraph explanation in plain English.
> **Why you need it** — what breaks if you skip it.
> **Before you begin** — anything that must already be in place.
> **How to set it up** — numbered steps with the exact screens to open.
> **How to check it works** — a quick test you can run.
> **Tip / Common mistake** — things that catch people out.

Work through the sections in order. If you only have 30 minutes today, do
**Part A** (sections 1 – 5). The rest can wait until your functional leads
are ready.

---

## Table of contents

**Part A — Foundations (do these first)**
1. Before you start
2. Give your team access
3. Load the starter data
4. Connect to the outside world
5. Tell the system about your business

**Part B — Pre-Sales setup**
6. Distribute leads to your team automatically (Round Robin)
7. Catch duplicate leads
8. Score your leads
9. Set up lead capture rules

**Part C — Sales setup**
10. Build the Cost Sheet (your pricing engine)
11. Approve discounts
12. Hand leads over to Sales (Push To Sales)

**Part D — Post-Sales setup**
13. Define your payment schedule
14. Configure demand letters
15. Configure receipts, refunds, and credit / debit notes
16. Set up approval flows
17. Handle complaints

**Part E — Communication**
18. Email templates
19. Document (PDF) templates

**Part F — Optional modules**
20. Channel Partner module
21. Dashboards and reports
22. Integrations with other systems
23. The Aria AI assistant
24. Performance, forecasting, availability

**Part G — Going live**
25. Apps and tabs for each team
26. Background jobs to schedule
27. Final tests before go-live
28. Troubleshooting
29. Glossary
30. Where to get help

---

# Part A — Foundations

## 1. Before you start

> **What it does:** confirms the package is healthy in your org.
> **Why you need it:** if any of these are wrong, the rest of this guide
> will fail in confusing ways.

**Before you begin**, sit with someone who has Salesforce System Administrator
access — you will need it for almost every step.

**How to check**

Open Salesforce **Setup** (the gear icon, top right) and confirm:

| What | Where | What you want to see |
|---|---|---|
| The deployment finished cleanly | Deployment Status | Every line says *Succeeded* |
| Lightning Experience is on | Lightning Experience Transition | *Enabled* |
| My Domain is enabled | My Domain | *Deployed* and *My Domain is ready for use* |
| Email is allowed to leave the org | Deliverability | *Access to Send Email* = *All email* (in Production) |
| You have at least one verified sender | Organization-Wide Email Addresses | At least one verified entry |

**One-time tool to install**

Install the free browser extension **Salesforce Inspector Reloaded**
(available for Chrome, Edge and Firefox). You will use its *Data Import*
panel in Section 3 to upload starter data. It saves hours of clicking.

**Tip.** Keep a notepad open as you work through this guide — every team's
business rules (statuses, discount bands, payment milestones) will be
asked for in later sections, and writing them down first is much faster
than discovering them ad-hoc.

---

## 2. Give your team access

> **What it does:** tells Salesforce which users can see which tabs,
> records, and buttons.
> **Why you need it:** without this, your users will open the app and
> see empty screens.

**Step 1 — Assign two platform permission sets**

Setup → **Permission Sets**. Tick each of the following and assign them to
yourself plus any other admins:

- *sfdc_nc_constraints_engine_deploy*
- *sfdc_scrt2*

These come from Salesforce platform and are required by the package.

**Step 2 — Decide who does what**

In real estate companies the teams usually break down like this:

| Team | What they do |
|---|---|
| **Pre-Sales** | Receive enquiries, qualify them, book site visits |
| **Sales** | Take a qualified lead, build a cost sheet, close the booking |
| **Post-Sales / CRM** | Send demand letters, collect payments, handle handover |
| **Finance** | Approve receipts, refunds, credit/debit notes |
| **Channel Partner (CP)** | Manage external partner brokers |
| **GRE** | Greet walk-in visitors at the site |

Make a list of every user on your team and which group they belong to.

**Step 3 — Set up profiles or permission sets per team**

For each team, ask your admin to:

- Make the relevant tabs visible (the full list is in Section 25)
- Give read / edit access to the objects that team works with
- Allow the Apex classes and Visualforce pages the package uses

If you are early in the rollout, the simplest approach is to give the
implementation user **System Administrator** while you finish setup, and
tighten things up just before go-live.

**Common mistake.** Forgetting to make tabs visible to a team — users
report that "the screens are missing" when really their profile just hides
the tabs.

---

## 3. Load the starter data

> **What it does:** loads the small pieces of data that *the package itself*
> depends on — for example, which fields to show on the Cost Sheet, and
> which prompts to show when a lead changes status.
> **Why you need it:** without this, several screens look completely empty
> even though the package is installed.

These records are called **Custom Metadata** in Salesforce. You only upload
them once.

**Step 1 — Download the starter bundle**

Open the **Welcome Guide** tab in Salesforce (it ships with the package,
icon: trophy). The first section, *Upload Custom Metadata Records*,
contains a public download link to a ZIP of CSV files.

**Step 2 — Upload each CSV using Salesforce Inspector**

For each file in the bundle:

1. Open Salesforce, click the Inspector icon → **Data Import**.
2. **Action** — *Insert* (or *Upsert* if you're re-running after fixing rows).
3. **Object** — the name shown in the table below.
4. Drag the CSV into the panel.
5. Click **Run Import**.

| File / Object name | What it controls | Mandatory? |
|---|---|---|
| Cost_Sheet_Field_Config__mdt | Which rows appear on the cost sheet, in what order | **Yes** — Cost Sheet is blank without this |
| Lead_Status_Action_Config__mdt | What happens when a lead moves to each status (e.g. ask for a reason when "Lost") | **Yes** — status updates won't prompt without this |
| Dashboard_Tab_Config__mdt | Which tabs appear on the home dashboard | **Yes** — dashboard is blank without this |
| Dashboard_Field_Config__mdt | Which fields show inside each dashboard tab | **Yes** |
| AI_Integration_Config__mdt | API key and model for the AI chatbot | Only if you're using the AI assistant |
| Forecast_Config__mdt | Sales-forecast funnel definition | Only if using forecasting |
| Shift_Configuration__mdt | Working hour shifts | Only if tracking user availability |
| User_Availability_Profile_Config__mdt | Maps profiles to shifts | Only if tracking user availability |
| Integration_Doc_Setting__mdt | Logo, company name, watermark on integration documents | Only if you generate outbound docs |

**How to check it works.** Open the **Cost Sheet** tab — you should see
field labels (Base Price, GST, etc.) instead of an empty screen.

**Tip.** If you need to change any of this later, you do *not* re-import.
Use Setup → **Custom Metadata Types** → *Manage Records* → *Edit*.

---

## 4. Connect to the outside world

> **What it does:** tells Salesforce which external websites and APIs the
> package is allowed to talk to.
> **Why you need it:** Salesforce blocks all outbound traffic by default
> for security. Payment gateways, SMS providers, the AI assistant, etc.
> will not work until you whitelist them.

You will probably do this section together with the third-party vendors
(payment, SMS, email, ERP). Each vendor will give you a URL to whitelist.

**Step 1 — Whitelist the external URLs**

Setup → **Remote Site Settings** → **New Remote Site**.

For each vendor, add an entry: paste the URL, give it a friendly name,
tick *Active*.

**Step 2 — Whitelist any embedded content**

If a vendor sends back HTML you display on screen (a payment page, an iframe,
a font, etc.), also add the URL to:

Setup → **CSP Trusted Sites** → **New Trusted Site**.

**Step 3 — Set up secure credentials**

For anything that needs a username/password or an OAuth flow, prefer
**Named Credentials** over typing credentials into the package's
configuration screens. Setup → **Named Credentials**.

**Common mistake.** Forgetting CSP Trusted Sites. The callout itself works
but the embedded page is blank — users think the integration is broken.

---

## 5. Tell the system about your business

> **What it does:** sets two organisation-wide defaults — what to do with
> duplicate leads, and what record gets created when Pre-Sales hands a
> lead over to Sales.
> **Why you need it:** these are the "fallback" rules. Without them the
> package doesn't know what to do in edge cases.

**How to set it up**

1. From the App Launcher (the 9-dot grid), search for **General Setup** and
   open it.
2. Click **New**.
3. Fill in:

   | Field on screen | What to choose | Plain-English meaning |
   |---|---|---|
   | Active | ✓ ticked | Exactly one row should be active at a time |
   | Lead Duplication Type | *Close*, *Merge*, or *Flag* | What to do with duplicate leads when no specific rule matches |
   | Push To Sales Type | *Booking*, *Opportunity*, or both | Which record Sales gets when Pre-Sales pushes a qualified lead |
   | Description | free text | Useful for distinguishing UAT from Production |

4. Save.

---

# Part B — Pre-Sales setup

## 6. Distribute leads to your team automatically (Round Robin)

> **What it does:** when a new lead arrives, the system picks the next
> sales person in line and assigns it to them automatically.
> **Why you need it:** it stops leads from sitting unowned, and it makes
> distribution fair across the team.

**How it thinks**

You create **buckets** (e.g. *US Platinum*, *International Silver*).
Each bucket has:

- A **filter** — which leads belong in this bucket (e.g. *Country = USA AND
  Project = Skyline*).
- A list of **members** — the people who should take leads from this bucket,
  in order.

When a new lead arrives, the system finds the first matching bucket and
assigns the lead to the next member in rotation.

**How to set it up**

1. From the App Launcher open the **RoundRobin Configurator** tab. (If
   you'd prefer a step-by-step wizard, use the **RR Wizard** tab instead.)
2. Click **New Bucket**. Give it a clear name like *US Platinum Leads*.
3. Add filter rows for what defines this bucket — Project, Source, Country,
   Lead Type, etc. All filters within one bucket are AND-ed together.
4. Add members — the salespeople who should receive these leads. The
   **sequence number** sets the rotation order; the lowest sequence is
   picked first.
5. Save.
6. Make sure the queues those buckets reference exist (Section 25 lists
   them) and have members.

**How to check it works**

Create a test lead that matches one of your bucket filters. The owner
should be set automatically. Create a second one — it should go to the
next person in rotation.

**Common mistake.** Defining the bucket but forgetting to populate the
matching **queue** with people. The lead lands in the queue and sits there.

---

## 7. Catch duplicate leads

> **What it does:** when someone enquires twice, the system recognises it
> and either closes the duplicate, merges it, or flags it for a human.
> **Why you need it:** you don't want two salespeople calling the same
> customer.

**How to set it up**

1. Open the **Duplication Configurator** tab.
2. Click **New Rule**.
3. Choose the **match fields** — what makes two leads "the same"?
   Common choices: *Mobile Number*, *Email*, or a combination like
   *Mobile + Project + Source*.
4. Choose the **action**:
   - **Close** — the new (duplicate) lead is closed automatically.
   - **Merge** — fields from the new lead are merged into the existing one.
   - **Flag** — the lead is left for a human to review.
5. Save.

**Schedule the nightly cleanup**

Ask your admin to schedule the *CleanupDuplicateLeadsBatch* job to run
every night. This catches duplicates that arrive through bulk imports.

**How to check it works**

Create a lead, then create a second one with the same mobile number — the
second should be handled per the rule.

---

## 8. Score your leads

> **What it does:** gives each lead a numeric score so your salespeople
> know which to call first.
> **Why you need it:** when 200 leads come in a day, scoring tells the
> team which 20 are worth calling now.

**How it works**

You create **rules** that add or subtract points based on lead attributes,
and **tiers** that bucket the scores into Hot / Warm / Cold.

**How to set it up**

1. Open the **Lead Scoring Designer** tab.
2. Create **tiers** (e.g. *Hot* = 70+, *Warm* = 40–69, *Cold* = 0–39).
3. Create **rules**. Examples to start with:
   - *Source = Website* → +10 points
   - *Number of Site Visits ≥ 2* → +20 points
   - *No follow-up in 7 days* → −10 points
4. Activate each rule (tick *Active*).
5. Use the **Recompute** button on the designer to update scores on
   existing leads.

**How to check it works**

Open a lead that matches one of your rules and confirm the score reflects
the points.

---

## 9. Set up lead capture rules

> **What it does:** when a lead changes status (e.g. *Qualified → Lost*),
> the system can require the user to fill in a reason, schedule a follow-up,
> or log a site visit.
> **Why you need it:** keeps your data clean and your pipeline honest.

This is already controlled by the **Lead_Status_Action_Config** starter
data you loaded in Section 3. To change the rules:

1. Setup → **Custom Metadata Types** → find *Lead Status Action Config*.
2. Click **Manage Records**.
3. For each status, edit:
   - *Requires Remarks?*
   - *Requires Lost Reason?*
   - *Requires Follow-Up?*
   - *Requires Site Visit?*
   - *Mandatory* vs *Optional* flags
   - *Section Label* — the header shown above the prompt
4. Save.

**Tip.** Start simple — make Lost reason mandatory, and follow-up optional.
You can tighten the rules once the team is comfortable.

---

# Part C — Sales setup

## 10. Build the Cost Sheet (your pricing engine)

> **What it does:** generates a complete pricing breakdown — base price,
> GST, PLC, floor rise, maintenance, stamp duty, registration — whenever
> a salesperson opens a deal.
> **Why you need it:** so every quote uses the same formula and you avoid
> manual maths errors.

**Where the rules live**

Pricing rules are stored on the **Project** record, because each project
typically has its own base price and tax rules.

**How to set it up (do this per project)**

1. Open a **Project** record.
2. On the right side of the page, click **Launch Formula Builder**.
3. For each row on the cost sheet, write the formula. Examples:
   - *Base Price* = *Project Base Price × Unit Sqft*
   - *GST* = *Base Price × 5%*
   - *Floor Rise* = *Floor Rise Per Sqft × Unit Sqft*
4. Save.

Repeat for every active project.

**Tip.** If many projects share the same formulas, create a
**Project Calculation Template** once and link it from each Project, instead
of re-typing every formula.

**How to check it works**

1. Open a Lead linked to that project.
2. Click the **New Cost Sheet** quick action.
3. Confirm the calculated total matches what you expect on paper.
4. Once approved, click **Create Booking** to convert it.

---

## 11. Approve discounts

> **What it does:** when a salesperson offers a discount, the system
> automatically routes it to the right approver based on the discount
> percentage.
> **Why you need it:** prevents large discounts from being given without
> management review.

**How to set it up**

1. Open the **Discount Approval Matrix** tab.
2. Add one row per discount band. A typical setup:

   | Discount range | Goes to | Outcome |
   |---|---|---|
   | 0 – 5 % | (no approver) | Auto-approved |
   | 5 – 15 % | Sr. Sales Manager | Manual approval |
   | 15 – 25 % | Director | Manual approval |
   | Above 25 % | CEO + Director | Two-step approval |

3. Pick the approver (a user or a queue) per row.
4. Ask your admin to schedule the *DiscountApprovalEscalationBatch* job so
   that approvals which sit too long are escalated up the chain.

**How to check it works**

Create a test discount request at, say, 8% — it should land in the
Sr. Manager's Approval Center.

---

## 12. Hand leads over to Sales (Push To Sales)

> **What it does:** once Pre-Sales decides a lead is worth pursuing, one
> click hands it to the Sales team with all the right information copied
> across.
> **Why you need it:** removes the spreadsheet hand-off and ensures Sales
> gets the same data Pre-Sales had.

> **Important.** The setup screen is **Pre-Sales Admin Config → General
> Setup Config sub-tab**. There is an older standalone tab called
> *Push To Sales Field Map* — ignore it, it is deprecated.

**How to set it up**

1. Open the **Pre-Sales Admin Config** tab.
2. Click into the **General Setup Config** sub-tab.
3. Map each Pre-Sales lead field to the corresponding field on the Sales
   record (Booking or Opportunity, whichever you chose in Section 5).
   Example:
   - *Lead.Mobile* → *Booking.Customer Mobile*
   - *Lead.Project* → *Booking.Project*
   - *Lead.Owner* → *Booking.Sales Owner*
4. Save.
5. Ask your admin to add the **Push to Sales** quick action button to the
   Lead page layout used by Pre-Sales.

**How to check it works**

Find a qualified lead, click **Push to Sales**, and confirm a Booking is
created with the right fields and the new owner.

**Bulk version.** For one-time bulk hand-offs (e.g. migrating historical
leads), use the **Pre-Sales Bulk Config** tab.

---

# Part D — Post-Sales setup

## 13. Define your payment schedule

> **What it does:** describes the milestones at which your customer is
> expected to pay (Booking, Foundation, Roofing, Possession, etc.).
> **Why you need it:** the package uses this to generate demand letters,
> reminders, and reports automatically.

**How to set it up**

1. Open the **Master Payment Schedule** tab.
2. For each project (or once, if all projects share the same schedule),
   add one row per milestone:

   | Milestone | % of total | Due |
   |---|---|---|
   | At Booking | 10% | Immediately |
   | Foundation Complete | 15% | 30 days after Booking |
   | First Slab | 10% | 30 days after Foundation |
   | … | … | … |
   | Possession | 10% | 30 days after final slab |

3. Save.

**Tip.** Always make the percentages add up to 100%. The system warns you
if they don't.

---

## 14. Configure demand letters

> **What it does:** automatically sends the customer a formal letter
> asking for payment when a milestone falls due.
> **Why you need it:** removes the manual chase work and keeps cash flow
> predictable.

**How to set it up**

1. Open the **Demand Letter Config** screen.
2. For each project add a row with:
   - The **document template** to use (set up in Section 19)
   - The **email template** to use (set up in Section 18)
   - **Grace Period (days)** — how long after the due date before it's
     considered overdue
   - **Include Interest?** — whether overdue interest is added
3. Save.

**How to check it works**

Click *Raise Demand* on a test Booking — the email should be sent and the
PDF should be generated and attached.

---

## 15. Configure receipts, refunds, and credit / debit notes

> **What it does:** controls how each kind of money movement is recorded.
> **Why you need it:** every project / customer type may follow slightly
> different rules (advance receipts, milestone receipts, partial refunds).

**How to set it up**

1. Open the **Post-Sales Admin** tab.
2. Click **New Configuration**.
3. For **each** kind of process you want to enable (Receipt, Refund,
   Credit Note, Debit Note, Payment Schedule), create one row and fill in:

   - **Configuration Type** — choose the process
   - **Matches when** — the criteria that decide when this rule applies
     (e.g. *Project = Skyline*)
   - **Document Template** — the PDF to issue (Section 19)
   - **Email Template** — the email to send (Section 18)
   - **Auto Send Email** — tick if it should send without a human pressing
     "send"
   - **Approval Configuration** — link to a Section 16 approval if needed
   - **Reminders** — tick *Enable Reminders* if the system should chase

4. Save.

**Tip.** Build one configuration first, test it end-to-end, then duplicate
it for the other process types.

---

## 16. Set up approval flows

> **What it does:** lets you say "this kind of record must be approved
> before it goes live" — for Bookings, Refunds, Unit Blocks, Cost Sheets
> and more.
> **Why you need it:** financial controls, audit trail, and four-eyes
> compliance.

**How to set it up (do this per process you want to approve)**

1. Open the **Approval Configuration** tab.
2. Click **New**.
3. Fill in the basics:
   - **Process Label** — what people will see (e.g. *Booking Approval*)
   - **What kind of record?** — Booking / Refund / Unit Block / etc.
   - **Status field & values** — which field holds the status, and what
     are the *Pending*, *Approved* and *Rejected* values
4. Define the **steps**. Use the *Step Builder* — for each step pick:
   - The approver (a user, a queue, or a manager-of-submitter)
   - The conditions under which the step applies
5. Define the **post-decision actions**:
   - When approved → e.g. set status to *Active*, send confirmation email
   - When rejected → e.g. set status to *Rejected*, notify submitter
6. (Optional) **Chain it** — say "this approval can only start once the
   Cost Sheet is approved".
7. Tick *Active* and save.

**How users approve**

Users see pending items in the **Approval Center** tab. They can also
approve in bulk via **Bulk Approval Manager**.

**How to check it works**

Submit a test record and confirm:
- It changes to Pending status
- The right person sees it in Approval Center
- When they approve, the post-decision actions fire

---

## 17. Handle complaints

> **What it does:** when a customer raises a complaint, the system routes
> it to the right person and escalates it if it sits too long.
> **Why you need it:** SLA management — keeps complaints from getting lost.

**How to set it up**

1. Open the **Complaint Escalation Matrix** screen.
2. For each combination of *Project × Category × Priority* (e.g. *Skyline /
   Plumbing / High*), add a row with three escalation levels:

   | Level | Days to wait | Owner | Notify? |
   |---|---|---|---|
   | Level 1 | 1 day | Site Engineer | ✓ |
   | Level 2 | 3 days | Site Manager | ✓ |
   | Level 3 | 7 days | Customer Care Head | ✓ |

3. Tick *Auto Reassign* if the owner of the complaint should change at
   each escalation level.
4. Save.

**How to check it works**

Open a complaint and leave it alone for the *Level 1 Days*. The system
should escalate it automatically.

---

# Part E — Communication

## 18. Email templates

> **What it does:** stores all the emails your business sends — welcome
> emails, demand letters, payment confirmations, reminders, etc.
> **Why you need it:** so the wording, branding and recipients are
> consistent every time.

**How to set up a template**

1. Open the **Email Template Config** screen.
2. Click **New**.
3. Fill in:
   - **Template Name** — friendly name (e.g. *Welcome Email - Skyline*)
   - **For which record?** — Booking / Lead / Receipt / etc.
   - **Subject** — supports merge fields like `{!Lead.Name}`
   - **Body** — the HTML content of the email (the editor has a visual mode)
   - **Recipients** — who it goes to (the customer, a CC list, a queue)
   - **From Address** — must be a verified Org-Wide Email Address
     (Setup → *Organization-Wide Email Addresses*)
   - **Attachments** — static or dynamically generated
4. Tick *Active* and save.

**Tip.** Set *Default = true* on exactly one template per process — that's
the one the system picks when no specific rule matches.

**Common mistake.** Setting a *From Address* that isn't verified — the
email silently fails to send.

---

## 19. Document (PDF) templates

> **What it does:** stores the PDF templates your business issues — demand
> letters, receipts, allotment letters, NOCs, etc.
> **Why you need it:** branded, consistent documents generated in one click.

**How to set up a template**

1. Open the **Document Designer** screen.
2. Click **New Template**.
3. Fill in:
   - **Template Name**
   - **For which record?** — Booking / Receipt / Refund / etc.
   - **Page setup** — Size (A4 / Letter), Orientation (Portrait / Landscape)
   - **Logo** — your company logo URL
   - **File name pattern** — e.g. *Demand-{!Booking.Name}-{!TODAY()}.pdf*
   - **Body** — drag fields and free text into the canvas
4. Save and preview on a real record.

Then link the template into the place that issues it: e.g. the *Demand
Letter Config* (Section 14) or the *Post-Sales Configuration* (Section 15).

---

# Part F — Optional modules

Only configure these if your business uses them.

## 20. Channel Partner module

> **What it does:** manages external partner brokers — their leads, credit
> validity, and commission rules.
> **Why you need it:** if your business works through external brokers.

**How to set it up**

1. Open the **CP Module Config** tab.
2. Create one row with:
   - **CP Source Name** — the Lead Source value used for CP-originated
     leads (e.g. *Channel Partner*)
   - **Assignment Type** — how CP leads route (e.g. *Owner of CP*)
   - **CP Approval Process** — the approval that activates a new CP
   - **CP Active Statuses** — multi-pick of statuses considered "active"
   - **Credit settings** — active/expired status values and expiry days
   - **Lead status mappings** — default / reopened / inactive lists
3. Save.

---

## 21. Dashboards and reports

> **What it does:** gives each team a home screen of the records they
> care about.
> **Why you need it:** users open Salesforce and immediately see their work.

The home dashboard is mostly driven by the starter data you loaded in
Section 3 (Dashboard_Tab_Config and Dashboard_Field_Config).

**To customise further:**

1. Open the **Dashboard Configurator** screen.
2. Create per-user or per-profile overrides — e.g. *Pre-Sales users see
   Open Leads*, *Finance users see Pending Receipts*.
3. Save.

For reports, use the **Report Configurator** screen — same idea, but for
custom reports your users can run.

---

## 22. Integrations with other systems

> **What it does:** connects Salesforce to your payment gateway, SMS
> provider, ERP, lead-capture website forms, etc.
> **Why you need it:** if you want data to flow in or out automatically.

This is the most technical section — your IT team or implementation
partner usually owns it. The package gives them a no-code framework.

**The pieces involved (use the Integration Mapping Designer):**

1. **Authentication profile** — username/password, API key, OAuth, etc.
2. **Endpoint** — the URL and HTTP method to call (for outbound).
3. **Source config** — for incoming traffic, the public URL and what
   object to create.
4. **Field mapping** — which incoming field goes to which Salesforce field.
5. **Request template** — the body of the outbound request.
6. **Retry rules** — how many times to retry, when to give up.
7. **Logging** — all calls and errors are recorded automatically.

**How to check it works**

Use the **Integration Test Console** to fire a sample request without
affecting real data.

**Tip.** Build, test and monitor one integration end-to-end before adding
the next.

---

## 23. The Aria AI assistant

> **What it does:** an AI chatbot ("Aria") that captures leads, answers
> common questions, and helps users navigate the CRM.
> **Why you need it:** if AI is licensed and you want a chat experience.

**How to set it up**

1. Sign up with an AI provider (OpenAI, Anthropic, Azure OpenAI, etc.)
   and get an API key.
2. Add the provider's host URL in **Remote Site Settings** *and*
   **CSP Trusted Sites** (Section 4).
3. Setup → **Custom Metadata Types** → *AI Integration Config* → *Manage
   Records* → *New*:
   - **Provider** (e.g. *OpenAI*)
   - **Model** (e.g. *gpt-4o*)
   - **Endpoint** (the provider's API URL)
   - **API Key**
   - **Active** ✓
4. Drop the Aria chatbot component onto a Lightning Home page.
5. For inbound lead capture on your public website, drop *Aria Lead
   Capture Form* on an Experience Cloud page.

---

## 24. Performance, forecasting, availability

These are three small optional modules. Skip the ones you don't need.

- **Performance** — set sales targets per user per quarter via the
  *Performance Manager* screen. The leaderboard shows live ranking.
- **Forecasting** — needs the *Forecast_Config* starter data (Section 3).
  Open the *Sales Forecaster* screen for funnel / moving-average / health
  scores.
- **User Availability** — needs the *Shift_Configuration* and
  *User_Availability_Profile_Config* starter data (Section 3). Users
  toggle their own availability from a small widget; managers see it on
  *User Availability Manager*.

---

# Part G — Going live

## 25. Apps and tabs for each team

Setup → **App Manager** → for each app click *Edit* → *Navigation Items*
and add the tabs each team needs. Suggested mapping:

**Pre-Sales app** — Leads, Followups, Site Visits, Campaigns, Enquiry
Source, RoundRobin Configurator, Duplication Configurator, Pre-Sales Admin
Config, Pre-Sales Bulk Config, Lead Scoring Designer, Welcome Guide.

**Sales app** — Bookings, Cost Sheets, Units, Towers, Projects, Car
Parking, Push To Sales, Formula Builder, Discount Approval Matrix,
Discount Approval Log.

**Post-Sales / Finance app** — Payment Schedule, Master Payment Schedule,
Refunds, Post-Sales Admin, Unit Block Requests, Complaints, Inspections.

**Channel Partner app** — Channel Partners, CP Module Config, Daily Log.

**Admin / cross-functional app** — CRM Dashboards, CRM Reports, Field
Mapping Setup, Integration Mapping Designer, Integration Source Configs,
GRE, Bulk Lead Reassignment, Formula Builder, Welcome Guide.

**Don't forget Queues.** The package ships 9 queues (US/International ×
Leads/Platinum/Silver/Escalations, plus Partner Relations). Setup →
**Queues** → add a public group or users to each one — the queues are
empty by default.

---

## 26. Background jobs to schedule

Once everything above is configured, ask your admin to schedule these
recurring jobs (Setup → *Apex Classes → Schedule Apex*):

| Job | When | Why |
|---|---|---|
| Cleanup Duplicate Leads Batch | Every night 1 am | Catches duplicates from bulk imports |
| Discount Approval Escalation Batch | Every morning 8 am | Escalates stuck discount approvals |
| Demand Reminder Batch | Daily | Sends payment reminders |
| Complaint Escalation Batch | Hourly | Honours complaint SLA timers |
| Integration Retry Batch | Every 30 minutes | Retries failed external calls |
| Integration Log Purge | Weekly | Keeps the logs table small |
| Lead Score Recompute | Daily | Updates scores as data changes |

---

## 27. Final tests before go-live

Don't skip these. Do all ten on a sandbox or UAT org before flipping the
switch:

1. Create a new lead — does it auto-assign to the right person?
2. Create a duplicate lead — is it closed / merged / flagged?
3. Open a Cost Sheet on a real Lead — do the totals match a hand-calculated
   sheet?
4. Convert that Cost Sheet to a Booking — are fields mapped correctly?
5. Request a discount above your auto-approve band — does the right person
   get the approval?
6. Push a Lead from Pre-Sales — does the Booking / Opportunity appear with
   the right owner?
7. Raise a demand letter on the Booking — does the customer get the email
   with the PDF attached?
8. Open every active integration in the Test Console — does each return a
   success?
9. Submit one record from each approving process — does Approval Center
   show it to the right approver?
10. Open the Welcome Guide tab — do all six in-app sections render?

If all ten pass, you're ready.

---

## 28. Troubleshooting

| What you see | Likely reason | Fix |
|---|---|---|
| Welcome Guide tab is blank | My Domain isn't enabled | Setup → My Domain |
| Cost Sheet screen has no rows | Section 3 starter data wasn't loaded | Re-run the Custom Metadata import |
| Home dashboard is empty | Same — Dashboard starter data missing | Re-run the import |
| Lead status change doesn't ask for a reason | Lead Status Action Config rows missing or inactive | Edit them in Setup → Custom Metadata Types |
| New leads aren't being assigned | Bucket has no members, *or* its filter doesn't match the lead, *or* the queue is empty | Check Section 6 and Section 25 |
| Discount approval just sits there | No matrix row covers the discount % | Add a row in Section 11 |
| Push to Sales button does nothing | Either the button isn't on the page layout, or the field mapping is empty | Check Section 12 |
| Demand letter email never arrives | The "From Address" isn't a verified Org-Wide Email Address | Setup → Organization-Wide Addresses → verify it |
| External API call fails | Host not in Remote Site Settings | Add it (Section 4) |
| External page won't render inside Salesforce | Host not in CSP Trusted Sites | Add it (Section 4) |
| AI chatbot doesn't respond | API key wrong, or provider host not whitelisted | Section 23 + Section 4 |
| Approval Center is empty for everyone | The Approval Configuration isn't *Active*, or its *Matches when* criteria match nothing | Section 16 |

---

## 29. Glossary

| Term | Plain meaning |
|---|---|
| **Cost Sheet** | The pricing breakdown shown to a customer before they book |
| **Booking** | A confirmed sale — the customer has agreed to buy a unit |
| **Demand Letter** | A formal request asking the customer to pay an instalment |
| **Receipt** | A record that money has been received from the customer |
| **Credit / Debit Note** | An adjustment to the customer's balance |
| **Unit Block** | Reserving a specific unit so no one else can sell it |
| **Round Robin** | Rotating leads through a list of salespeople in order |
| **Channel Partner (CP)** | An external broker selling on your behalf |
| **GRE** | Guest Relations Executive — the person who greets site walk-ins |
| **Queue** | A shared inbox of records; users with the queue assigned can pick them up |
| **CMDT (Custom Metadata)** | Configuration records that travel with the package — what you loaded in Section 3 |
| **LWC** | Lightning Web Component — the technology behind the package's screens |
| **Aria** | The AI assistant persona shipped with the package |

---

## 30. Where to get help

- **Inside Salesforce** — open the **Welcome Guide** tab for the short
  interactive version of this document.
- **Implementation partner** — your point of contact during rollout.
- **Salesforce admin** — for anything that requires Setup access.
- **Salesforce help** — https://help.salesforce.com for platform questions
  (My Domain, Permission Sets, Org-Wide Addresses, etc.).

Good luck with your rollout!
