/**
 * @description Interface for pre-process and post-process Apex hooks in the Integration Platform.
 *              Implement this interface and specify the class name on Integration_Endpoint__c
 *              fields Pre_Process_Apex_Class__c or Post_Process_Apex_Class__c.
 *
 *              Pre-process hooks run before the callout (outbound) or before data mapping (inbound).
 *              Post-process hooks run after the callout response (outbound) or after DML (inbound).
 *
 * @author Integration Platform
 */
public interface IIntegrationHook {

    /**
     * @description Called by the IntegrationEngine before or after integration execution.
     * @param context A map containing execution context with the following keys:
     *        - 'integrationKey' (String): The integration endpoint key
     *        - 'direction' (String): 'Outbound' or 'Inbound'
     *        - 'phase' (String): 'Pre' or 'Post'
     *        - 'recordId' (String): The Salesforce record ID (may be null)
     *        - 'payload' (String): JSON-serialized payload data
     *        - 'responseBody' (String): Response body (Post phase only)
     *        - 'statusCode' (String): HTTP status code as string (Post phase only)
     *        - 'success' (String): 'true' or 'false' (Post phase only)
     *        - 'correlationId' (String): Correlation ID for tracing
     * @return A map of key-value pairs to pass back to the engine:
     *        For Pre hooks:
     *          - 'payload' (String): Modified JSON payload (optional, replaces original)
     *          - 'skip' (String): Set to 'true' to skip the integration execution
     *          - 'skipReason' (String): Reason for skipping (logged)
     *        For Post hooks:
     *          - 'additionalDml' (String): JSON array of SObject records to insert/update
     *          - 'notifyUsers' (String): Comma-separated User IDs to notify
     *          - Any custom key-value pairs for downstream consumption
     */
    Map<String, String> execute(Map<String, String> context);
}