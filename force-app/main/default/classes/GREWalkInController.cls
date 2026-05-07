/**
 * GRE Walk-In Controller
 * Handles the Guest Relationship Executive walk-in flow for customer site visits.
 *
 * Scenarios:
 * 1. No Lead exists        -> Create Lead + Enquiry Source + Site Visit (Completed)
 * 2. Active Lead exists:
 *    a. Valid Enquiry Source -> Update/Create Site Visit (Completed)
 *    b. No valid Enquiry    -> Create Enquiry Source + Site Visit (Completed)
 * 3. Inactive Lead exists   -> Create Enquiry Source + Site Visit (Completed)
 *
 * Integrates with existing RoundRobinService for assignment.
 */
public with sharing class GREWalkInController {

    // ─── Wrapper Classes ────────────────────────────────────────────

    public class CheckResult {
        @AuraEnabled public String scenario;   // NO_LEAD, ACTIVE_LEAD, INACTIVE_LEAD
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String leadStatus;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String message;
    }

    public class ProcessResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Id leadId;
        @AuraEnabled public Id enquirySourceId;
        @AuraEnabled public Id siteVisitId;
        @AuraEnabled public String scenario;
        @AuraEnabled public String message;
    }

    public class LeadSearchResult {
        @AuraEnabled public Id leadId;
        @AuraEnabled public String leadName;
        @AuraEnabled public String mobile;
        @AuraEnabled public String projectName;
        @AuraEnabled public String projectId;
        @AuraEnabled public String source;
        @AuraEnabled public String status;
        @AuraEnabled public String leadStatus;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String recordTypeDev;
    }

    public class SiteVisitCard {
        @AuraEnabled public Id siteVisitId;
        @AuraEnabled public String name;
        @AuraEnabled public String projectName;
        @AuraEnabled public Id projectId;
        @AuraEnabled public DateTime scheduledDate;
        @AuraEnabled public DateTime completedDate;
        @AuraEnabled public String visitStatus;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Id assignedToId;
        @AuraEnabled public Boolean canComplete;
        @AuraEnabled public Boolean isCompleted;
        @AuraEnabled public DateTime checkInTime;
        @AuraEnabled public DateTime checkOutTime;
        @AuraEnabled public Boolean canCheckout;
        @AuraEnabled public String sourceType;
        @AuraEnabled public String channelPartnerName;
    }

    // ─── Cross-Project Gate ──────────────────────────────────────────

    /**
     * Exposes the active General Setup's cross-project policy to the LWC so
     * it can hide the "Create Site Visit for Another Project" affordance when
     * leads are scoped per-project.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isCrossProjectSiteVisitAllowed() {
        return ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed();
    }

    // ─── Step 1: Search Leads by Mobile ──────────────────────────────

    /**
     * Search for all leads matching a mobile number.
     * Checks both Lead (Primary/Secondary Mobile) and Enquiry Source
     * (Primary/Secondary/Contact Mobile). Returns the parent Lead for
     * any matching Enquiry Source.
     */
    @AuraEnabled
    public static List<LeadSearchResult> searchLeadsByMobile(String phone) {
        if (String.isBlank(phone)) {
            throw new AuraHandledException('Phone number is required.');
        }

        // Collect lead IDs from Lead__c
        Set<Id> leadIds = new Set<Id>();
        for (Lead__c l : [
            SELECT Id FROM Lead__c
            WHERE Primary_Mobile__c = :phone OR Secondary_Mobile__c = :phone
        ]) {
            leadIds.add(l.Id);
        }

        // Collect lead IDs from Enquiry_Source__c
        for (Enquiry_Source__c es : [
            SELECT Lead__c FROM Enquiry_Source__c
            WHERE Lead__c != null
            AND (Primary_Mobile__c = :phone
                 OR Secondary_Mobile__c = :phone)
        ]) {
            leadIds.add(es.Lead__c);
        }

        if (leadIds.isEmpty()) {
            return new List<LeadSearchResult>();
        }

        List<LeadSearchResult> results = new List<LeadSearchResult>();
        for (Lead__c l : [
            SELECT Id, Full_Name__c, Primary_Mobile__c, Project__c, Project__r.Name,
                   Lead_Source__c, Lead_Status__c,
                   OwnerId, Owner.Name, Is_Active__c,
                   RecordType.DeveloperName
            FROM Lead__c
            WHERE Id IN :leadIds
            ORDER BY CreatedDate DESC
        ]) {
            LeadSearchResult r = new LeadSearchResult();
            r.leadId = l.Id;
            r.leadName = l.Full_Name__c;
            r.mobile = l.Primary_Mobile__c;
            r.projectName = l.Project__r.Name;
            r.projectId = l.Project__c;
            r.source = l.Lead_Source__c;
            r.status = l.Is_Active__c ? 'Active' : 'Inactive';
            r.leadStatus = l.Lead_Status__c;
            r.isActive = l.Is_Active__c;
            r.ownerName = l.Owner.Name;
            r.recordTypeDev = l.RecordType.DeveloperName;
            results.add(r);
        }

        return results;
    }

    // ─── Legacy: Check Lead Existence ─────────────────────────────────

    /**
     * Check if a lead exists for the given phone + project combination.
     * Returns scenario type so the LWC can render the appropriate UI.
     */
    @AuraEnabled
    public static CheckResult checkLead(String phone, Id projectId) {
        if (String.isBlank(phone) || projectId == null) {
            throw new AuraHandledException('Phone and Project are required.');
        }

        CheckResult result = new CheckResult();

        List<Lead__c> existingLeads = [
            SELECT Id, First_Name__c, Last_Name__c, Full_Name__c,
                   Primary_Mobile__c, Lead_Status__c,
                   OwnerId, Owner.Name, Is_Active__c, Project__c,
                   Last_Reopened_Date__c, CreatedDate
            FROM Lead__c
            WHERE Project__c = :projectId
            AND (Primary_Mobile__c = :phone OR Secondary_Mobile__c = :phone)
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (existingLeads.isEmpty()) {
            result.scenario = 'NO_LEAD';
            result.message = 'No existing lead found. Please create a new lead.';
        } else {
            Lead__c existing = existingLeads[0];
            result.leadId = existing.Id;
            result.leadName = existing.Full_Name__c;
            result.ownerName = existing.Owner.Name;

            if (existing.Is_Active__c) {
                result.scenario = 'ACTIVE_LEAD';
                result.leadStatus = existing.Lead_Status__c;
                result.message = 'Active lead found: ' + existing.Full_Name__c
                    + ' (Owner: ' + existing.Owner.Name + ')';
            } else {
                result.scenario = 'INACTIVE_LEAD';
                result.leadStatus = existing.Lead_Status__c;
                result.message = 'Inactive lead found: ' + existing.Full_Name__c
                    + '. Will create new enquiry source and site visit.';
            }
        }

        return result;
    }

    // ─── Step 2A: Scenario 1 – Create New Lead ─────────────────────

    /**
     * Creates a new Lead, Enquiry Source, and completed Site Visit.
     * Supports manual executive selection or Round Robin assignment.
     */
    @AuraEnabled
    public static ProcessResult processNewLead(
        String firstName, String lastName, String phone, String email,
        Id projectId, String source, String bhkType, String propertyType,
        String budgetRange, String remarks, Id salesExecId, Boolean useRoundRobin,
        String greSourceType, Id channelPartnerId, String greRemarks
    ) {
        ProcessResult result = new ProcessResult();
        result.scenario = 'NEW_LEAD';

        try {
            // Build Lead record first so Round Robin can match all filters
            Lead__c newLead = new Lead__c();
            String safeLastName = String.isNotBlank(lastName) ? lastName : firstName;
            newLead.First_Name__c = firstName;
            newLead.Last_Name__c = safeLastName;
            newLead.Primary_Mobile__c = phone;
            newLead.Project__c = projectId;
            newLead.Lead_Source__c = String.isNotBlank(source) ? source : 'Walk-in';
            newLead.Lead_Type__c = 'Fresh';
            newLead.Lead_Status__c = 'New Enquiry';
            if (String.isNotBlank(email))        newLead.Primary_Email__c = email;
            if (String.isNotBlank(bhkType))      newLead.BHK_Type__c = bhkType;
            if (String.isNotBlank(propertyType)) newLead.Property_Type__c = propertyType;
            if (String.isNotBlank(budgetRange))  newLead.Budget_Range__c = budgetRange;
            if (String.isNotBlank(remarks))      newLead.Remarks__c = remarks;

            // Determine owner: GRE leads use 'Sales' assignment type
            Id ownerId;
            Boolean isSalesAssignment = false;
            if (useRoundRobin == true) {
                ownerId = RoundRobinService.getNextUser(newLead, 'Sales');
                if (ownerId != null) isSalesAssignment = true;
            }
            if (ownerId == null && salesExecId != null) {
                ownerId = salesExecId;
                isSalesAssignment = true;
            }
            if (ownerId == null) {
                ownerId = UserInfo.getUserId();
            }

            newLead.OwnerId = ownerId;

            // Set Sales record type when a Sales user is assigned (round-robin or manual)
            if (isSalesAssignment) {
                Id salesRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
                    .get('Sales').getRecordTypeId();
                newLead.RecordTypeId = salesRTId;
                newLead.Lead_Status__c = 'Site Visit Completed';
                newLead.Transferred_On__c = System.now();
                newLead.Transferred_By__c = UserInfo.getUserId();
            }

            // Skip trigger's DuplicateConversionEngine — GRE creates its own Enquiry Source below
            DuplicateConversionEngine.skipProcessing = true;
            insert newLead;
            DuplicateConversionEngine.skipProcessing = false;

            // Create Enquiry Source
            Enquiry_Source__c es = buildEnquirySource(
                newLead.Id, projectId, 'New', 'Walk-in',
                firstName, newLead.Last_Name__c, phone, email
            );
            insert es;

            // Create completed Site Visit
            Site_Visit__c sv = buildCompletedSiteVisit(newLead.Id, projectId, ownerId, greSourceType, channelPartnerId, greRemarks);
            insert sv;

            result.success = true;
            result.leadId = newLead.Id;
            result.enquirySourceId = es.Id;
            result.siteVisitId = sv.Id;
            result.message = 'New lead created and site visit recorded successfully.';
        } catch (Exception e) {
            throw new AuraHandledException('Error creating lead: ' + e.getMessage());
        }

        return result;
    }

    // ─── Step 2B: Scenarios 2 & 3 – Process Existing Lead ──────────

    /**
     * Handles active-lead and inactive-lead scenarios.
     * Creates or updates Enquiry Source and Site Visit as needed.
     */
    @AuraEnabled
    public static ProcessResult processExistingLead(Id leadId, String greSourceType, Id channelPartnerId, String greRemarks) {
        ProcessResult result = new ProcessResult();

        try {
            Lead__c lead = [
                SELECT Id, First_Name__c, Last_Name__c, Full_Name__c,
                       Primary_Mobile__c, Primary_Email__c, Project__c,
                       Lead_Status__c, OwnerId,
                       Is_Active__c, Last_Reopened_Date__c, CreatedDate
                FROM Lead__c
                WHERE Id = :leadId
            ];

            if (lead.Is_Active__c) {
                result.scenario = 'ACTIVE_LEAD';
                handleActiveLead(lead, result, greSourceType, channelPartnerId, greRemarks);
            } else {
                result.scenario = 'INACTIVE_LEAD';
                handleInactiveLead(lead, result, greSourceType, channelPartnerId, greRemarks);
            }

            result.success = true;
        } catch (Exception e) {
            throw new AuraHandledException('Error processing walk-in: ' + e.getMessage());
        }

        return result;
    }

    // ─── Scenario 2: Active Lead ────────────────────────────────────

    private static void handleActiveLead(Lead__c lead, ProcessResult result, String greSourceType, Id channelPartnerId, String greRemarks) {
        // Reference date = MAX(Last_Reopened_Date, CreatedDate)
        Date lastReopened = lead.Last_Reopened_Date__c;
        Date leadCreated  = lead.CreatedDate.date();
        Date refDate = (lastReopened != null && lastReopened > leadCreated)
            ? lastReopened : leadCreated;
        DateTime refDateTime = DateTime.newInstance(refDate, Time.newInstance(0, 0, 0, 0));

        // Check for valid Enquiry Source (Walk-in, created after reference date)
        List<Enquiry_Source__c> validEnquiries = [
            SELECT Id FROM Enquiry_Source__c
            WHERE Lead__c = :lead.Id
            AND Source__c = 'Walk-in'
            AND CreatedDate >= :refDateTime
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!validEnquiries.isEmpty()) {
            // CASE A: Valid Enquiry Source exists
            result.enquirySourceId = validEnquiries[0].Id;
            handleSiteVisitForActiveEnquiry(lead, result, greSourceType, channelPartnerId, greRemarks);
        } else {
            // CASE B: No valid Enquiry Source → create new
            Enquiry_Source__c es = buildEnquirySource(
                lead.Id, lead.Project__c, 'Re-engaged', 'Walk-in',
                lead.First_Name__c, lead.Last_Name__c,
                lead.Primary_Mobile__c, lead.Primary_Email__c
            );
            insert es;

            // Update lead fields BEFORE SV insert so the SV trigger's
            // push-to-sales (which also updates the lead) isn't overwritten
            lead.Lead_Type__c = 'Re-engaged';
            lead.Last_Reengaged_Source__c = 'Walk-in';
            lead.Last_Reengaged_Date__c = Date.today();
            update lead;

            // SV insert triggers pushOnSVCompleted → assigns Sales user via round-robin
            Site_Visit__c sv = buildCompletedSiteVisit(lead.Id, lead.Project__c, lead.OwnerId, greSourceType, channelPartnerId, greRemarks);
            insert sv;

            result.enquirySourceId = es.Id;
            result.siteVisitId = sv.Id;
            result.message = 'New enquiry source and completed site visit created for active lead.';
        }

        result.leadId = lead.Id;
    }

    /**
     * For CASE A – valid enquiry exists: update or create site visit.
     */
    private static void handleSiteVisitForActiveEnquiry(Lead__c lead, ProcessResult result, String greSourceType, Id channelPartnerId, String greRemarks) {
        List<Site_Visit__c> existingSVs = [
            SELECT Id, Status__c FROM Site_Visit__c
            WHERE Lead__c = :lead.Id
            AND Status__c IN ('Scheduled', 'Re-Scheduled')
            ORDER BY Scheduled_Date__c DESC
            LIMIT 1
        ];

        if (!existingSVs.isEmpty()) {
            existingSVs[0].Status__c = 'Completed';
            existingSVs[0].Completed_Date__c = DateTime.now();
            existingSVs[0].Check_In_Time__c = DateTime.now();
            if (existingSVs[0].FeedBack__c == null) existingSVs[0].FeedBack__c = 'Positive';
            if (String.isNotBlank(greSourceType)) existingSVs[0].Source_Type__c = greSourceType;
            if (channelPartnerId != null) existingSVs[0].Channel_Partner__c = channelPartnerId;
            if (String.isNotBlank(greRemarks)) existingSVs[0].GRE_Remarks__c = greRemarks;
            update existingSVs[0];
            result.siteVisitId = existingSVs[0].Id;
            result.message = 'Existing site visit marked as completed.';
        } else {
            Site_Visit__c sv = buildCompletedSiteVisit(lead.Id, lead.Project__c, lead.OwnerId, greSourceType, channelPartnerId, greRemarks);
            insert sv;
            result.siteVisitId = sv.Id;
            result.message = 'New completed site visit created for active lead.';
        }
    }

    // ─── Scenario 3: Inactive Lead ─────────────────────────────────

    private static void handleInactiveLead(Lead__c lead, ProcessResult result, String greSourceType, Id channelPartnerId, String greRemarks) {
        Enquiry_Source__c es = buildEnquirySource(
            lead.Id, lead.Project__c, 'Re-opened', 'Walk-in',
            lead.First_Name__c, lead.Last_Name__c,
            lead.Primary_Mobile__c, lead.Primary_Email__c
        );
        insert es;

        // Update lead fields BEFORE SV insert so the SV trigger's
        // push-to-sales (which also updates the lead) isn't overwritten
        lead.Lead_Type__c = 'Re-opened';
        lead.Lead_Status__c = 'New Enquiry';
        lead.Last_Reopened_Date__c = Date.today();
        update lead;

        // SV insert triggers pushOnSVCompleted → assigns Sales user via round-robin
        Site_Visit__c sv = buildCompletedSiteVisit(lead.Id, lead.Project__c, lead.OwnerId, greSourceType, channelPartnerId, greRemarks);
        insert sv;

        result.leadId = lead.Id;
        result.enquirySourceId = es.Id;
        result.siteVisitId = sv.Id;
        result.message = 'Lead re-opened. New enquiry source and completed site visit created.';
    }

    // ─── Builder Helpers ────────────────────────────────────────────

    private static Enquiry_Source__c buildEnquirySource(
        Id leadId, Id projectId, String enquiryType, String source,
        String firstName, String lastName, String phone, String email
    ) {
        Enquiry_Source__c es = new Enquiry_Source__c();
        es.Lead__c = leadId;
        es.Project__c = projectId;
        es.Enquiry_Date__c = DateTime.now();
        es.Enquiry_Type__c = enquiryType;
        es.Source__c = source;
        es.Primary_Mobile__c = phone;
        if (String.isNotBlank(email)) {
            es.Primary_Email__c = email;
        }
        return es;
    }

    private static Site_Visit__c buildCompletedSiteVisit(Id leadId, Id projectId, Id assignedToId, String sourceType, Id channelPartnerId, String greRemarks) {
        Site_Visit__c sv = new Site_Visit__c();
        sv.Lead__c = leadId;
        sv.Project__c = projectId;
        sv.Scheduled_Date__c = DateTime.now().addHours(-1);
        sv.Completed_Date__c = DateTime.now();
        sv.Check_In_Time__c = DateTime.now();
        sv.Status__c = 'Completed';
        sv.FeedBack__c = 'Positive';
        sv.Mode_Of_Visit__c = 'On Site';
        sv.Source_Type__c = String.isNotBlank(sourceType) ? sourceType : 'Digital (Own)';
        if (channelPartnerId != null) sv.Channel_Partner__c = channelPartnerId;
        if (String.isNotBlank(greRemarks)) sv.GRE_Remarks__c = greRemarks;
        sv.Assigned_To__c = assignedToId;
        return sv;
    }

    // ─── Lookup Methods for LWC ─────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Project__c> getActiveProjects() {
        return [
            SELECT Id, Name, Project_Code__c
            FROM Project__c
            WHERE Is_Active__c = true
            ORDER BY Name ASC
            LIMIT 200
        ];
    }

   @AuraEnabled(cacheable=true)
public static List<Project__c> searchProjects(String searchText) {

    System.debug('===== searchProjects Method Start =====');
    System.debug('Incoming searchText: ' + searchText);

    // Handle blank search
    if (String.isBlank(searchText)) {
        System.debug('Search text is blank. Fetching default 10 active projects.');

        List<Project__c> defaultProjects = [
            SELECT Id, Name, Project_Code__c
            FROM Project__c
            WHERE Is_Active__c = true
            ORDER BY Name ASC
            LIMIT 10
        ];

        System.debug('Default Projects Count: ' + defaultProjects.size());
        System.debug('===== searchProjects Method End =====');

        return defaultProjects;
    }

    // Trim and prepare LIKE key
    String trimmedText = searchText.trim();
    String key = '%' + trimmedText + '%';

    System.debug('Trimmed searchText: ' + trimmedText);
    System.debug('Generated LIKE key: ' + key);

    List<Project__c> searchedProjects = [
        SELECT Id, Name, Project_Code__c
        FROM Project__c
        WHERE Is_Active__c = true
        AND (
            Name LIKE :key
            OR Project_Code__c LIKE :key
        )
        ORDER BY Name ASC
        LIMIT 10
    ];

    System.debug('Searched Projects Count: ' + searchedProjects.size());
    System.debug('Returned Records: ' + searchedProjects);
    System.debug('===== searchProjects Method End =====');

    return searchedProjects;
}


    @AuraEnabled
    public static Map<String, Object> checkLeadDuplicate(String phone, Id projectId) {
        Map<String, Object> result = new Map<String, Object>();
        result.put('isDuplicate', false);

        if (String.isBlank(phone) || projectId == null) {
            return result;
        }

        List<Lead__c> existingLeads = [
            SELECT Id, Full_Name__c, Is_Active__c, Owner.Name,
                   Lead_Status__c
            FROM Lead__c
            WHERE Project__c = :projectId
            AND (Primary_Mobile__c = :phone OR Secondary_Mobile__c = :phone)
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!existingLeads.isEmpty()) {
            Lead__c existing = existingLeads[0];
            result.put('isDuplicate', true);
            result.put('leadId', existing.Id);
            result.put('leadName', existing.Full_Name__c);
            result.put('isActive', existing.Is_Active__c);
            result.put('ownerName', existing.Owner.Name);
            result.put('status', existing.Lead_Status__c);
        }

        return result;
    }

    @AuraEnabled
    public static List<User> getSalesExecutives(Id projectId) {
        /*if (projectId == null) return new List<User>();

        // Find Round Robins linked to this project via filters
        String projectIdStr = String.valueOf(projectId);
        Set<Id> rrIds = new Set<Id>();
        for (Round_Robin_Filter__c f : [
            SELECT Round_Robin__c FROM Round_Robin_Filter__c
            WHERE Field_API_Name__c = 'Project__c'
            AND Field_Value__c = :projectIdStr
            AND Round_Robin__r.Is_Active__c = true
        ]) {
            rrIds.add(f.Round_Robin__c);
        }
        if (rrIds.isEmpty()) return new List<User>();

        // Get active Sales members from matched Round Robins
        Set<Id> userIds = new Set<Id>();
        for (Round_Robin_Member__c m : [
            SELECT User__c FROM Round_Robin_Member__c
            WHERE Round_Robin__c IN :rrIds
            AND Is_Active__c = true
            AND Assignment_Type__c = 'Sales'
        ]) {
            userIds.add(m.User__c);
        }
        if (userIds.isEmpty()) return new List<User>();
        return [
            SELECT Id, Name, Email
            FROM User
            WHERE Id IN :userIds AND IsActive = true
            ORDER BY Name ASC
        ];*/
        return [
            SELECT Id, Name, Email
            FROM User
            WHERE IsActive = true
            AND Profile.Name LIKE '%Sales%'
            ORDER BY Name ASC
        ];
    }

    // ─── Site Visit Card Methods ──────────────────────────────────────

    /**
     * Returns all site visits for a given lead as card data.
     */
    @AuraEnabled
    public static List<SiteVisitCard> getSiteVisitsForLead(Id leadId) {
        List<SiteVisitCard> cards = new List<SiteVisitCard>();
        for (Site_Visit__c sv : [
            SELECT Id, Name, Project__c, Project__r.Name,
                   Scheduled_Date__c, Completed_Date__c, Status__c,
                   Assigned_To__c, Assigned_To__r.Name,
                   Check_In_Time__c, Check_Out_Time__c, GRE_Remarks__c,
                   Source_Type__c, Channel_Partner__c, Channel_Partner__r.Name
            FROM Site_Visit__c
            WHERE Lead__c = :leadId
            ORDER BY Scheduled_Date__c DESC
        ]) {
            SiteVisitCard card = new SiteVisitCard();
            card.siteVisitId = sv.Id;
            card.name = sv.Name;
            card.projectName = sv.Project__r.Name;
            card.projectId = sv.Project__c;
            card.scheduledDate = sv.Scheduled_Date__c;
            card.completedDate = sv.Completed_Date__c;
            card.visitStatus = sv.Status__c;
            card.ownerName = sv.Assigned_To__r != null ? sv.Assigned_To__r.Name : '';
            card.assignedToId = sv.Assigned_To__c;
            card.canComplete = sv.Status__c == 'Scheduled' || sv.Status__c == 'Re-Scheduled';
            card.isCompleted = sv.Status__c == 'Completed';
            card.checkInTime = sv.Check_In_Time__c;
            card.checkOutTime = sv.Check_Out_Time__c;
            card.canCheckout = sv.Status__c == 'Completed' && sv.Check_In_Time__c != null && sv.Check_Out_Time__c == null;
            card.sourceType = sv.Source_Type__c;
            card.channelPartnerName = sv.Channel_Partner__r != null ? sv.Channel_Partner__r.Name : '';
            cards.add(card);
        }
        return cards;
    }

    /**
     * Completes an existing scheduled site visit with checkout time and optional owner change.
     * Handles Pre-Sales → Sales transition when owner is changed.
     */
    @AuraEnabled
    public static ProcessResult completeSiteVisit(Id siteVisitId, Id ownerId, String greSourceType, Id channelPartnerId, String greRemarks) {
        ProcessResult result = new ProcessResult();
        try {
            Site_Visit__c sv = [
                SELECT Id, Lead__c, Project__c, Status__c,
                       Assigned_To__c, Lead__r.OwnerId, Lead__r.RecordType.DeveloperName,
                       Lead__r.Project__c,FeedBack__c
                FROM Site_Visit__c
                WHERE Id = :siteVisitId
            ];

            if (sv.Status__c != 'Scheduled' && sv.Status__c != 'Re-Scheduled') {
                throw new AuraHandledException('Only Scheduled or Re-Scheduled site visits can be completed.');
            }

            // Check-in: complete the site visit
            sv.Status__c = 'Completed';
            sv.Completed_Date__c = DateTime.now();
            sv.Check_In_Time__c = DateTime.now();
            if (sv.FeedBack__c == null) sv.FeedBack__c = 'Positive';
            if (String.isNotBlank(greSourceType)) sv.Source_Type__c = greSourceType;
            if (channelPartnerId != null) sv.Channel_Partner__c = channelPartnerId;
            if (String.isNotBlank(greRemarks)) sv.GRE_Remarks__c = greRemarks;
            if (ownerId != null) {
                sv.Assigned_To__c = ownerId;
            }
            update sv;

            // Always update lead: set owner + status
            Lead__c lead = new Lead__c(Id = sv.Lead__c);
            lead.Lead_Status__c = 'Site Visit Completed';

            if (ownerId != null) {
                lead.OwnerId = ownerId;
            }

            // If Pre-Sales, also transition record type to Sales
            if (sv.Lead__r.RecordType.DeveloperName == 'Pre_Sales' && ownerId != null) {
                lead.Pre_Sale_User__c = sv.Lead__r.OwnerId;
                lead.Transferred_On__c = System.now();
                lead.Transferred_By__c = UserInfo.getUserId();
                Id salesRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
                    .get('Sales').getRecordTypeId();
                lead.RecordTypeId = salesRTId;
            }

            update lead;

            result.success = true;
            result.leadId = sv.Lead__c;
            result.siteVisitId = sv.Id;
            result.message = 'Site visit completed successfully.';
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error completing site visit: ' + e.getMessage());
        }
        return result;
    }

    /**
     * Checks out a site visit that was previously checked in.
     * Sets Check_Out_Time__c and stores checkout remarks in FeedBack__c.
     */
    @AuraEnabled
    public static void checkoutSiteVisit(Id siteVisitId, String feedback) {
        Site_Visit__c sv = [
            SELECT Id, Status__c, Check_In_Time__c, Check_Out_Time__c
            FROM Site_Visit__c
            WHERE Id = :siteVisitId
            LIMIT 1
        ];
        if (sv.Check_In_Time__c == null) {
            throw new AuraHandledException('Site Visit must be checked in first.');
        }
        if (sv.Check_Out_Time__c != null) {
            throw new AuraHandledException('Site Visit is already checked out.');
        }
        sv.Check_Out_Time__c = DateTime.now();
        if (String.isNotBlank(feedback)) {
            sv.FeedBack__c = feedback;
        }
        update sv;
    }

    /**
     * Creates a new site visit for a different project on an existing lead,
     * and immediately completes it. If a scheduled SV already exists for
     * the same project, throws an error (user should complete that one instead).
     */
    @AuraEnabled
    public static ProcessResult createAndCompleteSiteVisit(Id leadId, Id projectId, Id ownerId, String greSourceType, Id channelPartnerId, String greRemarks) {
        ProcessResult result = new ProcessResult();
        try {
            // Check if a scheduled SV already exists for this lead + project
            List<Site_Visit__c> existing = [
                SELECT Id, Name FROM Site_Visit__c
                WHERE Lead__c = :leadId
                AND Project__c = :projectId
                AND Status__c IN ('Scheduled', 'Re-Scheduled')
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                throw new AuraHandledException(
                    'A scheduled site visit (' + existing[0].Name + ') already exists for this project. '
                    + 'Please complete that site visit instead.'
                );
            }

            Lead__c lead = [
                SELECT Id, OwnerId, RecordType.DeveloperName, First_Name__c, Last_Name__c,
                       Primary_Mobile__c, Primary_Email__c, Project__c
                FROM Lead__c WHERE Id = :leadId
            ];

            // Gate cross-project creation on active General Setup
            if (lead.Project__c != projectId
                && !ActiveGeneralSetupService.isCrossProjectSiteVisitAllowed()) {
                throw new AuraHandledException(
                    'Cross-project site visits are not allowed by the current General Setup. ' +
                    'Please contact your administrator.'
                );
            }

            Id assignTo = ownerId != null ? ownerId : lead.OwnerId;

            // Create enquiry source for this walk-in to another project
            Enquiry_Source__c es = buildEnquirySource(
                leadId, projectId, 'Re-engaged', 'Walk-in',
                lead.First_Name__c, lead.Last_Name__c,
                lead.Primary_Mobile__c, lead.Primary_Email__c
            );
            insert es;

            // Create completed site visit
            Site_Visit__c sv = new Site_Visit__c();
            sv.Lead__c = leadId;
            sv.Project__c = projectId;
            sv.Scheduled_Date__c = DateTime.now().addHours(-1);
            sv.Completed_Date__c = DateTime.now();
            sv.Check_In_Time__c = DateTime.now();
            sv.Status__c = 'Completed';
            sv.FeedBack__c = 'Positive';
            sv.Mode_Of_Visit__c = 'On Site';
            sv.Source_Type__c = String.isNotBlank(greSourceType) ? greSourceType : 'Digital (Own)';
            if (channelPartnerId != null) sv.Channel_Partner__c = channelPartnerId;
            if (String.isNotBlank(greRemarks)) sv.GRE_Remarks__c = greRemarks;
            sv.Assigned_To__c = assignTo;
            insert sv;

            // Always update lead: set owner + status
            Lead__c leadUpdate = new Lead__c(Id = leadId);
            leadUpdate.Lead_Status__c = 'Site Visit Completed';

            if (ownerId != null) {
                leadUpdate.OwnerId = ownerId;
            }

            // If Pre-Sales, also transition record type to Sales
            if (ownerId != null && lead.RecordType.DeveloperName == 'Pre_Sales') {
                leadUpdate.Pre_Sale_User__c = lead.OwnerId;
                leadUpdate.Transferred_On__c = System.now();
                leadUpdate.Transferred_By__c = UserInfo.getUserId();
                Id salesRTId = Schema.SObjectType.Lead__c.getRecordTypeInfosByDeveloperName()
                    .get('Sales').getRecordTypeId();
                leadUpdate.RecordTypeId = salesRTId;
            }

            update leadUpdate;

            result.success = true;
            result.leadId = leadId;
            result.enquirySourceId = es.Id;
            result.siteVisitId = sv.Id;
            result.message = 'New site visit created and completed for the selected project.';
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating site visit: ' + e.getMessage());
        }
        return result;
    }
}