/**
 * @description @AuraEnabled entry point for on-demand call transcription.
 *              The LWC / quick action invokes this and the user polls the
 *              Call_Detail__c record for status changes.
 *
 * The heavy lifting is done in CallTranscriptionService — this class exists
 * only to provide the @future(callout=true) boundary required to call out
 * from an LWC without blocking the UI.
 */
public with sharing class AriaTranscriptionController {

    @AuraEnabled
    public static String startTranscription(Id callDetailId) {
        if (callDetailId == null) {
            throw new AuraHandledException('Call Detail Id is required.');
        }
        // Pre-flight: record must exist and caller must have access to mark it Processing
        List<Call_Detail__c> rows = [
            SELECT Id, Transcription_Status__c FROM Call_Detail__c
            WHERE Id = :callDetailId LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new AuraHandledException('Call Detail not found.');
        }
        Call_Detail__c cd = rows[0];
        cd.Transcription_Status__c = 'Processing';
        update cd;

        // Kick off the async callout
        runAsync(callDetailId);
        return 'Processing';
    }

    /**
     * @description @future boundary for the callout. Kept on its own so tests
     *              can invoke CallTranscriptionService directly while still
     *              exercising the synchronous path.
     */
    @future(callout=true)
    public static void runAsync(Id callDetailId) {
        try {
            CallTranscriptionService.transcribeRecording(callDetailId);
        } catch (Exception e) {
            // CallTranscriptionService already marks the record Failed and
            // records the reason in Summary__c, so we just log here.
            System.debug(LoggingLevel.ERROR,
                'Aria transcription async failed for ' + callDetailId + ': ' + e.getMessage());
        }
    }
}