/**
 * @description REST API for Channel Partner registration and lead submission.
 *
 * Endpoints:
 *   POST /services/apexrest/cp/register  — Register new Channel Partner
 *   POST /services/apexrest/cp/lead      — Submit lead from Channel Partner
 *
 * CP Registration:
 *   - Uses IntegrationFieldMappingEngine (source: CP_REGISTRATION) for field mapping
 *   - Uses DuplicationDetectionHelper for dynamic duplicate detection
 *   - All business parameters from CP_Module_Config__c via CPModuleConfigService
 *   - Auto-submits for configurable approval process
 *
 * CP Lead Submission:
 *   - Validates CP ID + CP Contact Number match
 *   - Checks CP status against configurable active statuses
 *   - Delegates to LeadDeduplicationService for 5 CP dedup scenarios
 *   - Returns scenario-specific response messages
 */
@RestResource(urlMapping='/cp/*')
global with sharing class CPRegistrationAPI {

    @HttpPost
    global static CPResponse handlePost() {
        RestRequest req = RestContext.request;
        String path = req.requestURI;
        CPResponse resp = new CPResponse();
        String requestBody = req.requestBody != null ? req.requestBody.toString() : '';
        String endpoint = path.endsWith('/register') ? 'CP_REGISTRATION' : (path.endsWith('/lead') ? 'CP_LEAD_SUBMISSION' : 'UNKNOWN');

        IntegrationLogger.LogEntry logEntry = IntegrationLogger.startLog('Inbound', 'POST', path);
        logEntry.integrationSource = endpoint;
        logEntry.request = requestBody;
        logEntry.inputParameters = path;

        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(requestBody);

            if (path.endsWith('/register')) {
                resp = registerCP(body);
            } else if (path.endsWith('/lead')) {
                resp = submitCPLead(body);
            } else {
                resp.status = 'ERROR';
                resp.message = 'Unknown endpoint.';
                RestContext.response.statusCode = 404;
            }

            logEntry.response = JSON.serialize(resp);
            logEntry.httpStatusCode = RestContext.response.statusCode;
            logEntry.status = (resp.status == 'SUCCESS') ? 'Success' : 'Error';
            if (resp.status != 'SUCCESS') {
                logEntry.errorMessage = resp.message;
            }
            return resp;
        } catch (Exception e) {
            resp.status = 'SYSTEM_ERROR';
            resp.message = e.getMessage();
            RestContext.response.statusCode = 500;
            logEntry.status = 'Error';
            logEntry.httpStatusCode = 500;
            logEntry.errorMessage = e.getMessage() + '\n' + e.getStackTraceString();
            logEntry.response = JSON.serialize(resp);
            return resp;
        } finally {
            IntegrationLogger.commitLog(logEntry);
        }
    }

    // ════════════════════════════════════════════════════════════
    // CP REGISTRATION
    // ════════════════════════════════════════════════════════════

    /**
     * @description Metadata-driven CP registration.
     *              Field mapping: IntegrationFieldMappingEngine (CP_REGISTRATION)
     *              Duplicate detection: DuplicationDetectionHelper (Channel_Partner__c config)
     *              Business parameters: CPModuleConfigService
     */
    private static CPResponse registerCP(Map<String, Object> body) {
        CPResponse resp = new CPResponse();

        // 1. Validate using engine (required fields + regex rules from config)
        List<String> errors = IntegrationFieldMappingEngine.validatePayload('CP_REGISTRATION', body);
        if (!errors.isEmpty()) {
            resp.status = 'VALIDATION_ERROR';
            resp.message = String.join(errors, ' ');
            RestContext.response.statusCode = 400;
            return resp;
        }

        // 2. Map payload to Channel_Partner__c using engine (all field rules + defaults from config)
        Channel_Partner__c cp = (Channel_Partner__c) IntegrationFieldMappingEngine.mapPayload('CP_REGISTRATION', body);

        // 3. Duplicate CP check — dynamic, config-driven via Duplication_Configuration__c
        Map<String, Object> dedupValues = new Map<String, Object>();
        Map<String, Object> cpFields = cp.getPopulatedFieldsAsMap();
        for (String fieldName : cpFields.keySet()) {
            dedupValues.put(fieldName, cpFields.get(fieldName));
        }

        if (!dedupValues.isEmpty()) {
            List<SObject> existingCPs = DuplicationDetectionHelper.findDuplicatesFromPayload(
                'Channel_Partner__c',
                dedupValues,
                'Id, Name, CP_Status__c'
            );

            if (!existingCPs.isEmpty()) {
                Channel_Partner__c existing = (Channel_Partner__c) existingCPs[0];
                resp.status = 'DUPLICATE';
                resp.referenceId = existing.Id;
                resp.message = 'Channel Partner already registered with this mobile/email. Existing CP ID: '
                             + existing.Name + ', Status: ' + existing.CP_Status__c;
                RestContext.response.statusCode = 409;
                return resp;
            }
        }

        // 4. Insert (defaults like CP_Status__c, Doc_Verification__c come from field rules)
        insert cp;

        // 5. Auto-submit for approval process (name from config)
        CP_Module_Config__c cfg = CPModuleConfigService.getConfig();
        submitForApproval(cp.Id, cfg.CP_Approval_Process__c);

        // 6. Re-query to get auto-number Name
        cp = [SELECT Id, Name FROM Channel_Partner__c WHERE Id = :cp.Id LIMIT 1];

        resp.status = 'SUCCESS';
        resp.referenceId = cp.Id;
        resp.message = 'Channel Partner registration submitted successfully. Your reference: '
                     + cp.Name + '. You will receive an email once your registration is reviewed.';
        RestContext.response.statusCode = 200;
        return resp;
    }

    private static void submitForApproval(Id cpId, String approvalProcessName) {
        if (String.isBlank(approvalProcessName)) return;
        try {
            Approval.ProcessSubmitRequest approvalReq = new Approval.ProcessSubmitRequest();
            approvalReq.setObjectId(cpId);
            approvalReq.setComments('New Channel Partner registration submitted via API.');
            approvalReq.setProcessDefinitionNameOrId(approvalProcessName);
            approvalReq.setSkipEntryCriteria(false);
            Approval.ProcessResult approvalResult = Approval.process(approvalReq);
            if (!approvalResult.isSuccess()) {
                System.debug('CP approval submission failed: ' + approvalResult.getErrors());
            }
        } catch (Exception e) {
            System.debug('CP approval auto-submit error (non-blocking): ' + e.getMessage());
        }
    }

    // ════════════════════════════════════════════════════════════
    // CP LEAD SUBMISSION
    // ════════════════════════════════════════════════════════════

    private static CPResponse submitCPLead(Map<String, Object> body) {
        CPResponse resp = new CPResponse();

        String cpName = (String) body.get('cp_id');
        String cpPhone = (String) body.get('cp_phone');

        // 1. Validate required CP fields
        if (String.isBlank(cpName) || String.isBlank(cpPhone)) {
            resp.status = 'VALIDATION_ERROR';
            resp.message = 'CP ID and CP Contact Number are required.';
            RestContext.response.statusCode = 400;
            return resp;
        }

        // 2. Validate CP ID + CP Contact Number match
        List<Channel_Partner__c> cps = [
            SELECT Id, Mobile__c, CP_Status__c, Name
            FROM Channel_Partner__c
            WHERE Name = :cpName AND Mobile__c = :cpPhone
            LIMIT 1
        ];

        if (cps.isEmpty()) {
            resp.status = 'CP_MISMATCH';
            resp.message = 'CP details not matching, please enter the correct CP ID and CP Contact Number.';
            RestContext.response.statusCode = 400;
            return resp;
        }

        Channel_Partner__c cp = cps[0];

        // 3. Check CP is in an active status (from config)
        Set<String> activeStatuses = CPModuleConfigService.getCPActiveStatuses();
        if (!activeStatuses.contains(cp.CP_Status__c)) {
            resp.status = 'CP_NOT_ACTIVE';
            resp.message = 'Your Channel Partner registration is not yet approved. Current status: ' + cp.CP_Status__c;
            RestContext.response.statusCode = 400;
            return resp;
        }

        // 4. Validate lead fields
        String leadMobile = (String) body.get('mobile');
        if (String.isBlank(leadMobile)) {
            resp.status = 'VALIDATION_ERROR';
            resp.message = 'Lead mobile number is required.';
            RestContext.response.statusCode = 400;
            return resp;
        }
        String projectCode = (String) body.get('project_code');
        if (String.isBlank(projectCode)) {
            resp.status = 'VALIDATION_ERROR';
            resp.message = 'Project code is required.';
            RestContext.response.statusCode = 400;
            return resp;
        }

        // 5. Build lead data map dynamically from full request body
        Map<String, String> leadData = new Map<String, String>();
        for (String key : body.keySet()) {
            Object val = body.get(key);
            if (val != null) {
                leadData.put(key, String.valueOf(val));
            }
        }
        // Set system-managed fields (source name from config)
        leadData.put('source', CPModuleConfigService.getCPSourceName());
        leadData.put('sub_source', cp.Name);
        leadData.put('cp_id', cp.Id);

        // 6. Process through dedup service (handles all 5 CP scenarios)
        LeadDeduplicationService.LeadResult result = LeadDeduplicationService.processIncomingLead(leadData);

        // 7. Map result to API response
        resp.leadId = result.leadId;
        resp.action = result.action;
        resp.message = result.message;

        if (result.action == 'ERROR') {
            resp.status = 'ERROR';
            RestContext.response.statusCode = 400;
        } else {
            resp.status = 'SUCCESS';
            RestContext.response.statusCode = 200;
        }

        return resp;
    }

    global class CPResponse {
        public String status;
        public Id referenceId;
        public Id leadId;
        public String action;
        public String message;
    }
}