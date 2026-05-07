/**
 * @description Wrapper class representing the result of an inbound integration processing operation.
 *              Encapsulates success/failure status, created/upserted record IDs, error details,
 *              and processing metrics. Consumed by IntegrationRestResource to construct the
 *              HTTP response returned to the external caller.
 * @author Integration Platform
 */
public class InboundResult {

    /** Whether the inbound processing completed successfully */
    public Boolean success { get; set; }

    /** HTTP status code to return to the caller */
    public Integer statusCode { get; set; }

    /** IDs of records created or upserted during processing */
    public List<Id> recordIds { get; set; }

    /** Primary error message when the entire operation fails */
    public String errorMessage { get; set; }

    /** Unique correlation ID for tracing this inbound request across logs */
    public String correlationId { get; set; }

    /** Total number of records successfully processed */
    public Integer recordsProcessed { get; set; }

    /** Total number of records that failed processing */
    public Integer recordsFailed { get; set; }

    /** Granular error messages for individual record failures */
    public List<String> errors { get; set; }

    /**
     * @description Default constructor initializing all fields to safe defaults.
     */
    public InboundResult() {
        this.success = false;
        this.statusCode = 200;
        this.recordIds = new List<Id>();
        this.errorMessage = '';
        this.correlationId = generateCorrelationId();
        this.recordsProcessed = 0;
        this.recordsFailed = 0;
        this.errors = new List<String>();
    }

    /**
     * @description Constructs a successful result with the given record IDs and counts.
     * @param recordIds List of IDs of records created or upserted
     * @param recordsProcessed Number of records successfully processed
     * @return A new InboundResult marked as successful
     */
    public static InboundResult success(List<Id> recordIds, Integer recordsProcessed) {
        InboundResult result = new InboundResult();
        result.success = true;
        result.statusCode = 200;
        result.recordIds = recordIds != null ? recordIds : new List<Id>();
        result.recordsProcessed = recordsProcessed != null ? recordsProcessed : 0;
        result.recordsFailed = 0;
        return result;
    }

    /**
     * @description Constructs a failure result with the given status code and error message.
     * @param statusCode HTTP status code
     * @param errorMessage Description of what went wrong
     * @return A new InboundResult marked as failed
     */
    public static InboundResult failure(Integer statusCode, String errorMessage) {
        InboundResult result = new InboundResult();
        result.success = false;
        result.statusCode = statusCode;
        result.errorMessage = errorMessage;
        return result;
    }

    /**
     * @description Constructs a partial success result where some records succeeded and others failed.
     * @param recordIds List of IDs of successfully processed records
     * @param recordsProcessed Number of records that succeeded
     * @param recordsFailed Number of records that failed
     * @param errors List of error messages for individual failures
     * @return A new InboundResult reflecting a partial success
     */
    public static InboundResult partial(List<Id> recordIds, Integer recordsProcessed,
                                         Integer recordsFailed, List<String> errors) {
        InboundResult result = new InboundResult();
        Integer failed = recordsFailed != null ? recordsFailed : 0;
        result.success = failed == 0;
        result.statusCode = failed > 0 ? 207 : 200;
        result.recordIds = recordIds != null ? recordIds : new List<Id>();
        result.recordsProcessed = recordsProcessed != null ? recordsProcessed : 0;
        result.recordsFailed = failed;
        result.errors = errors != null ? errors : new List<String>();
        return result;
    }

    /**
     * @description Serializes this result to a JSON map suitable for the REST response body.
     * @return Map of response fields
     */
    public Map<String, Object> toResponseMap() {
        Map<String, Object> response = new Map<String, Object>();
        response.put('success', this.success);
        response.put('correlationId', this.correlationId);
        response.put('recordsProcessed', this.recordsProcessed);
        response.put('recordsFailed', this.recordsFailed);

        if (!this.recordIds.isEmpty()) {
            List<String> idStrings = new List<String>();
            for (Id recId : this.recordIds) {
                idStrings.add(String.valueOf(recId));
            }
            response.put('recordIds', idStrings);
        }

        if (String.isNotBlank(this.errorMessage)) {
            response.put('errorMessage', this.errorMessage);
        }

        if (!this.errors.isEmpty()) {
            response.put('errors', this.errors);
        }

        return response;
    }

    /**
     * @description Generates a unique correlation ID for tracing.
     * @return A UUID-like string combining timestamp and random hex
     */
    private static String generateCorrelationId() {
        String timePart = String.valueOf(Datetime.now().getTime());
        String randomPart = EncodingUtil.convertToHex(
            Crypto.generateAesKey(128)
        ).substring(0, 12);
        return timePart + '-' + randomPart;
    }
}