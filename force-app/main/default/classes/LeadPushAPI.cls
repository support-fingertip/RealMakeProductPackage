/**
 * @description REST API endpoint for pushing leads from external sources.
 * Endpoint: POST /services/apexrest/lead/push
 */
@RestResource(urlMapping='/lead/push')
global with sharing class LeadPushAPI {

    @HttpPost
    global static LeadPushResponse pushLead() {
        RestRequest req = RestContext.request;
        LeadPushResponse resp = new LeadPushResponse();

        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            Map<String, String> leadData = new Map<String, String>();

            for (String key : body.keySet()) {
                Object val = body.get(key);
                leadData.put(key, val != null ? String.valueOf(val) : null);
            }

            // Validate required fields
            if (String.isBlank(leadData.get('first_name'))) {
                resp.status = 'VALIDATION_ERROR';
                resp.message = 'first_name is required.';
                RestContext.response.statusCode = 400;
                return resp;
            }
            if (String.isBlank(leadData.get('last_name'))) {
                resp.status = 'VALIDATION_ERROR';
                resp.message = 'last_name is required.';
                RestContext.response.statusCode = 400;
                return resp;
            }
            if (String.isBlank(leadData.get('primary_mobile'))) {
                resp.status = 'VALIDATION_ERROR';
                resp.message = 'primary_mobile is required.';
                RestContext.response.statusCode = 400;
                return resp;
            }
            if (String.isBlank(leadData.get('source'))) {
                resp.status = 'VALIDATION_ERROR';
                resp.message = 'source is required.';
                RestContext.response.statusCode = 400;
                return resp;
            }
            if (String.isBlank(leadData.get('project_code'))) {
                resp.status = 'VALIDATION_ERROR';
                resp.message = 'project_code is required.';
                RestContext.response.statusCode = 400;
                return resp;
            }

            LeadDeduplicationService.LeadResult result = LeadDeduplicationService.processIncomingLead(leadData);

            if (result.action == 'ERROR') {
                resp.status = 'VALIDATION_ERROR';
                resp.message = result.message;
                RestContext.response.statusCode = 400;
            } else {
                resp.status = result.action == 'CREATED' ? 'SUCCESS' : 'DUPLICATE';
                resp.leadId = result.leadId;
                resp.action = result.action;
                resp.message = result.message;
                RestContext.response.statusCode = 200;
            }
        } catch (Exception e) {
            resp.status = 'SYSTEM_ERROR';
            resp.message = 'An unexpected error occurred: ' + e.getMessage();
            RestContext.response.statusCode = 500;
        }

        return resp;
    }

    global class LeadPushResponse {
        public String status;
        public Id leadId;
        public String action;
        public String message;
    }
}