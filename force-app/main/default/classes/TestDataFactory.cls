/**
 * @description Utility class for creating test data.
 *              Combines Pre-Sales CRM test data and Integration Platform test data.
 *              All methods insert records and return the persisted instances.
 */
@isTest
public class TestDataFactory {

    // ═══════════════════════════════════════════════════════════════
    //  PRE-SALES CRM TEST DATA
    // ═══════════════════════════════════════════════════════════════

    public static Project__c createProject(String name) {
        Project__c p = new Project__c();
        p.Name = name;
        p.Project_Code__c = 'TST-' + String.valueOf(Math.random()).substring(2, 6);
        p.City__c = 'Hyderabad';
        p.Country__c = 'INDIA';
        p.State__c = 'Telangana';
        p.Property_Types__c = 'Apartment;Villa';
        p.Allowed_BHK_Types__c = '2BHK;3BHK';
        p.Min_Booking_Amount__c = 100000;
        p.Max_Block_Days__c = 7;
        p.Demand_Due_Days__c = 15;
        p.Reminder1_Offset__c = 7;
        p.Reminder2_Offset__c = 14;
        p.Termination_Offset__c = 21;
        p.Unblocking_Offset__c = 30;
        p.Sales_Head__c = UserInfo.getUserId();
        p.CRM_Head__c = UserInfo.getUserId();
        p.Finance_User__c = UserInfo.getUserId();
        p.Legal_User__c = UserInfo.getUserId();
        insert p;
        return p;
    }

    public static Tower__c createTower(Id projectId, String name) {
        Tower__c t = new Tower__c();
        t.Project__c = projectId;
        t.Tower_Status__c = 'Under Construction';
        t.Sales_Active__c = true;
        t.Booking_Allowed__c = true;
        t.Total_Floors__c = 10;
        t.Total_Units__c = 40;
        insert t;
        return t;
    }

    public static Unit__c createUnit(Id projectId, Id towerId, String unitNumber) {
        Unit__c u = new Unit__c();
        u.Project__c = projectId;
        u.Tower__c = towerId;
        u.Unit_Number__c = unitNumber;
        u.Unit_Type__c = 'Apartment';
        u.BHK_Type__c = '2BHK';
        u.Facing__c = 'North-East';
        u.Carpet_Area__c = 800;
        u.Super_Builtup_Area__c = 1100;
        u.Base_Rate_Sqft__c = 5000;
        u.Base_Price__c = 5500000;
        u.Amenity_Charges__c = 200000;
        u.Infra_Charges__c = 100000;
        u.Doc_Charges__c = 50000;
        u.Maintenance_Sqft_Month__c = 3;
        u.Maintenance_Months__c = 24;
        u.GST_Percentage__c = 5;
        u.Stamp_Duty_Pct__c = 6;
        u.Registration_Pct__c = 1;
        u.Status__c = 'Available';
        insert u;
        return u;
    }

    public static Campaign__c createCampaign(String name) {
        // Target_Project__c is required. Reuse an existing project if the
        // caller's @TestSetup created one; otherwise create a throwaway.
        List<Project__c> existing = [SELECT Id FROM Project__c LIMIT 1];
        Id targetProjectId = !existing.isEmpty()
            ? existing[0].Id
            : createProject('Auto Campaign Target').Id;

        Campaign__c c = new Campaign__c();
        c.Campaign_Name__c = name;
        c.Target_Project__c = targetProjectId;
        c.Source__c = 'Google';
        c.Campaign_Type__c = 'Digital';
        c.Status__c = 'Started';
        c.Start_Date__c = Date.today();
        c.Owner__c = UserInfo.getUserId();
        insert c;
        return c;
    }

    public static Channel_Partner__c createCP(String name) {
        Channel_Partner__c cp = new Channel_Partner__c();
        cp.CP_Type__c = 'Individual';
        cp.Mobile__c = '9' + String.valueOf(Math.random()).substring(2, 11);
        cp.Email__c = name.toLowerCase().replaceAll(' ', '') + '@test.com';
        cp.CP_Status__c = 'Approved';
        cp.Doc_Verification__c = 'Verified';
        insert cp;
        return cp;
    }

    public static Lead__c createLead(Id projectId, String firstName, String mobile) {
        Lead__c l = new Lead__c();
        l.First_Name__c = firstName;
        l.Last_Name__c = 'TestLast';
        l.Primary_Mobile__c = mobile;
        l.Primary_Email__c = firstName.toLowerCase() + '@test.com';
        l.Project__c = projectId;
        l.Owner__c = UserInfo.getUserId();
        l.Lead_Status__c = 'New Enquiry';
        l.Lead_Type__c = 'Fresh';
        l.Lead_Source__c = 'Digital';
        l.Lead_Sub_Source__c = 'Google';
        insert l;
        return l;
    }

    public static Round_Robin__c createRoundRobin(Id projectId) {
        Round_Robin__c rr = new Round_Robin__c();
        rr.Project__c = projectId;
        rr.Is_Active__c = true;
        rr.Last_Assigned_Index__c = 0;
        insert rr;
        return rr;
    }

    public static Round_Robin_Member__c createRRMember(Id rrId, Id userId, String userType, Integer seq) {
        Round_Robin_Member__c m = new Round_Robin_Member__c();
        m.Round_Robin__c = rrId;
        m.User__c = userId;
        m.Assignment_Type__c = userType;
        m.Is_Active__c = true;
        m.Sequence__c = seq;
        insert m;
        return m;
    }

    public static Payment_Milestone__c createPaymentMilestone(Id projectId, Id towerId, String name, Decimal pct, Integer seq, String category) {
        Payment_Milestone__c pm = new Payment_Milestone__c();
        pm.Project__c = projectId;
        pm.Tower__c = towerId;
        pm.Payment_Pct__c = pct;
        pm.Sequence__c = seq;
        pm.Category__c = category;
        pm.Interest_Applicable__c = true;
        insert pm;
        return pm;
    }

    public static Followup__c createFollowup(Id leadId, Id userId) {
        Followup__c fu = new Followup__c();
        fu.Lead__c = leadId;
        fu.Subject__c = 'Test Followup';
        fu.Due_Date__c = DateTime.now().addDays(1);
        fu.Status__c = 'Pending';
        fu.Assigned_To__c = userId;
        insert fu;
        return fu;
    }

    public static Site_Visit__c createSiteVisit(Id leadId, Id projectId, Id userId) {
        Site_Visit__c sv = new Site_Visit__c();
        sv.Lead__c = leadId;
        sv.Project__c = projectId;
        sv.Scheduled_Date__c = DateTime.now().addDays(1);
        sv.Status__c = 'Scheduled';
        sv.Mode_Of_Visit__c = 'On Site';
        sv.Source_Type__c = 'Digital (Own)';
        sv.Assigned_To__c = userId;
        insert sv;
        return sv;
    }

    public static Construction_Milestone__c createConstructionMilestone(Id projectId, Id towerId, String name, Integer seq) {
        Construction_Milestone__c cm = new Construction_Milestone__c();
        cm.Project__c = projectId;
        cm.Tower__c = towerId;
        cm.Sequence__c = seq;
        cm.Status__c = 'Planned';
        insert cm;
        return cm;
    }

    public static Round_Robin_Filter__c createRRFilter(Id rrId, String fieldApiName, String fieldValue, Decimal priority) {
        Round_Robin_Filter__c f = new Round_Robin_Filter__c();
        f.Round_Robin__c = rrId;
        f.Field_API_Name__c = fieldApiName;
        f.Field_Value__c = fieldValue;
        f.Field_Priority__c = priority;
        f.Preference_Order__c = priority;
        insert f;
        return f;
    }

    public static Duplication_Configuration__c createDuplicationConfig(String objectApiName, String expression) {
        Duplication_Configuration__c dc = new Duplication_Configuration__c();
        dc.Primary_Object_API_Name__c = objectApiName;
        dc.Primary_Expression__c = expression;
        dc.Active__c = true;
        insert dc;
        return dc;
    }

    public static CP_Module_Config__c createCPModuleConfig() {
        CP_Module_Config__c cfg = new CP_Module_Config__c();
        cfg.Name = 'Default';
        cfg.Is_Active__c = true;
        cfg.CP_Source_Name__c = 'Channel Partner';
        cfg.CP_Approval_Process__c = 'CP_Registration_Approval';
        cfg.CP_Active_Statuses__c = '["Approved","Active"]';
        cfg.Lead_Inactive_Statuses__c = '["Unqualified","Closed Lost","Booked"]';
        cfg.Lead_Reopened_Type__c = 'Re-opened';
        cfg.Lead_Reengaged_Type__c = 'Re-engaged';
        cfg.Lead_Default_Status__c = 'New Enquiry';
        cfg.Credit_Expiry_Days__c = 90;
        cfg.Credit_Active_Status__c = 'Active';
        cfg.Credit_Expired_Status__c = 'Expired';
        cfg.Assignment_Type__c = 'Pre Sales';
        insert cfg;
        return cfg;
    }

    // ═══════════════════════════════════════════════════════════════
    //  INTEGRATION PLATFORM TEST DATA
    // ═══════════════════════════════════════════════════════════════

    public static Integration_Endpoint__c createEndpoint(String key) {
        Integration_Endpoint__c endpoint = new Integration_Endpoint__c(
            Integration_Key__c = key,
            Base_URL__c = 'https://api.example.com',
            Path__c = '/v1/resource',
            HTTP_Method__c = 'POST',
            Content_Type__c = 'application/json',
            Timeout__c = 30000,
            Active__c = true,
            Custom_Headers__c = '{"X-Custom-Header":"TestValue"}',
            Query_Parameters__c = '{"param1":"value1"}',
            Execution_Mode__c = 'Synchronous',
            Category__c = 'Test',
            Owner_Team__c = 'Integration Team',
            Description__c = 'Test endpoint for ' + key
        );
        insert endpoint;
        return endpoint;
    }

    public static Integration_Auth_Profile__c createAuthProfile(String name, String authType) {
        Integration_Auth_Profile__c profile = new Integration_Auth_Profile__c(
            Profile_Name__c = name,
            Auth_Type__c = authType,
            Active__c = true,
            Description__c = 'Test auth profile'
        );
        if (authType == 'API_Key') {
            profile.Auth_Header_Name__c = 'x-api-key';
            profile.API_Key__c = 'test-api-key-12345';
        } else if (authType == 'Basic_Auth') {
            profile.Username__c = 'testuser';
            profile.Password__c = 'testpass';
        } else if (authType == 'OAuth_2_0') {
            profile.OAuth_Token_Endpoint__c = 'https://auth.example.com/token';
            profile.OAuth_Client_Id__c = 'client_id_123';
            profile.OAuth_Client_Secret__c = 'client_secret_456';
            profile.OAuth_Scope__c = 'read write';
            profile.OAuth_Grant_Type__c = 'client_credentials';
            profile.Token_Cache_Duration__c = 3600;
        } else if (authType == 'HMAC') {
            profile.HMAC_Secret__c = 'hmac-test-secret-key';
            profile.HMAC_Algorithm__c = 'HmacSHA256';
            profile.HMAC_Header_Name__c = 'X-HMAC-Signature';
        }
        insert profile;
        return profile;
    }

    public static Integration_Retry_Config__c createRetryConfig(String name) {
        Integration_Retry_Config__c config = new Integration_Retry_Config__c(
            Config_Name__c = name,
            Max_Retries__c = 3,
            Retry_Interval__c = 60,
            Backoff_Multiplier__c = 2.0,
            Max_Retry_Interval__c = 3600,
            Retry_On_Status_Codes__c = '408,429,500,502,503,504',
            Dead_Letter_Enabled__c = true,
            Active__c = true
        );
        insert config;
        return config;
    }

    public static Integration_Request_Template__c createRequestTemplate(Id endpointId, String body) {
        Integration_Request_Template__c template = new Integration_Request_Template__c(
            Integration_Endpoint__c = endpointId,
            Template_Name__c = 'Test Template',
            Body_Template__c = body,
            Source_Object__c = 'Account',
            Source_Fields__c = 'Id, Name',
            Active__c = true
        );
        insert template;
        return template;
    }

    public static Integration_Response_Mapping__c createResponseMapping(Id endpointId, String path, String targetField) {
        Integration_Response_Mapping__c mapping = new Integration_Response_Mapping__c(
            Integration_Endpoint__c = endpointId,
            Mapping_Name__c = 'Map ' + targetField,
            Response_JSON_Path__c = path,
            Target_Object__c = 'Account',
            Target_Field__c = targetField,
            Data_Type__c = 'String',
            Active__c = true,
            Order__c = 1
        );
        insert mapping;
        return mapping;
    }

    public static Integration_Field_Mapping__c createFieldMapping(Id endpointId, String source, String target, String direction) {
        Integration_Field_Mapping__c mapping = new Integration_Field_Mapping__c(
            Integration_Endpoint__c = endpointId,
            Mapping_Name__c = source + ' to ' + target,
            Direction__c = direction,
            Source_Field__c = source,
            Target_Field__c = target,
            Target_Object__c = 'Account',
            Data_Type__c = 'String',
            Is_Required__c = false,
            Order__c = 1,
            Active__c = true
        );
        insert mapping;
        return mapping;
    }

    public static Integration_Log__c createLog(Id endpointId, Boolean success) {
        Integration_Log__c log = new Integration_Log__c(
            Integration_Endpoint__c = endpointId,
            Integration_Key__c = 'TEST_KEY',
            Correlation_Id__c = 'test-corr-' + String.valueOf(Math.random()).substring(2, 10),
            Direction__c = 'Outbound',
            HTTP_Method__c = 'POST',
            Request_URL__c = 'https://api.example.com/v1/resource',
            Request_Body__c = '{"test":"data"}',
            Response_Status_Code__c = success ? 200 : 500,
            Response_Body__c = success ? '{"status":"ok"}' : '{"error":"fail"}',
            Is_Success__c = success,
            Execution_Time_ms__c = 150,
            Execution_Start__c = Datetime.now().addSeconds(-1),
            Execution_End__c = Datetime.now(),
            Execution_Mode__c = 'Synchronous',
            Triggered_By__c = UserInfo.getUserId()
        );
        insert log;
        return log;
    }

    public static Integration_Error_Log__c createErrorLog(Id logId, String errorType, String message) {
        Integration_Error_Log__c errorLog = new Integration_Error_Log__c(
            Integration_Log__c = logId,
            Error_Type__c = errorType,
            Error_Message__c = message,
            Stack_Trace__c = 'Test stack trace line 1\nTest stack trace line 2',
            Severity__c = 'High',
            Is_Resolved__c = false,
            Is_Dead_Letter__c = false,
            Retry_Eligible__c = true,
            Original_Payload__c = '{"original":"payload"}'
        );
        insert errorLog;
        return errorLog;
    }
}