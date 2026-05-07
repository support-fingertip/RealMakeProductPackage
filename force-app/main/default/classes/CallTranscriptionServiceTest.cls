/**
 * Mock strategy: the transcription flow makes THREE outbound callouts in order:
 *   1) GET   audio file
 *   2) POST  Gemini Files API upload
 *   3) POST  Gemini generateContent (transcribe)
 *
 * A single HttpCalloutMock inspects the endpoint to route each one.
 */
@isTest
private class CallTranscriptionServiceTest {

    private class TranscribeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            String ep = req.getEndpoint();

            if (ep != null && ep.contains('/upload/v1beta/files')) {
                res.setStatusCode(200);
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'file' => new Map<String, Object>{
                        'uri' => 'https://gen.example/files/abc',
                        'mimeType' => 'audio/mpeg',
                        'name' => 'files/abc'
                    }
                }));
            } else if (ep != null && ep.contains(':generateContent')) {
                res.setStatusCode(200);
                // Gemini returns the JSON payload as plain text per our prompt
                String payload = JSON.serialize(new Map<String, Object>{
                    'transcript' => 'Customer: Hi. Agent: Hello.',
                    'summary'    => 'Short call about availability.',
                    'key_topics' => new List<Object>{ 'pricing', 'availability' },
                    'sentiment'  => 'Positive',
                    'language'   => 'en'
                });
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'candidates' => new List<Object>{
                        new Map<String, Object>{
                            'content' => new Map<String, Object>{
                                'parts' => new List<Object>{
                                    new Map<String, Object>{ 'text' => payload }
                                }
                            }
                        }
                    }
                }));
            } else {
                // The audio fetch
                res.setStatusCode(200);
                res.setHeader('Content-Type', 'audio/mpeg');
                res.setBodyAsBlob(Blob.valueOf('fake-audio-bytes'));
            }
            return res;
        }
    }

    private class FailingAudioMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('not found');
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Project__c p = TestDataFactory.createProject('Call Test Project');
        Lead__c l = TestDataFactory.createLead(p.Id, 'Sneha', '9988877777');

        Call_Detail__c cd = new Call_Detail__c();
        cd.Lead__c = l.Id;
        cd.Recording_File__c = 'https://example.com/recordings/test.mp3';
        cd.Status__c = 'Completed';
        cd.Transcription_Status__c = 'Pending';
        insert cd;
    }

    @isTest
    static void transcribeRecording_happy_path_populates_fields() {
        Test.setMock(HttpCalloutMock.class, new TranscribeMock());

        Call_Detail__c cd = [SELECT Id FROM Call_Detail__c LIMIT 1];

        Test.startTest();
        CallTranscriptionService.transcribeRecording(cd.Id);
        Test.stopTest();

        Call_Detail__c out = [
            SELECT Transcription__c, Summary__c, Key_Topics__c, Sentiment__c,
                   Transcription_Language__c, Transcription_Status__c
            FROM Call_Detail__c WHERE Id = :cd.Id
        ];
        System.assertEquals('Completed', out.Transcription_Status__c);
        System.assertEquals('Positive', out.Sentiment__c);
        System.assertEquals('en', out.Transcription_Language__c);
        System.assert(out.Transcription__c.contains('Customer'));
        System.assert(out.Key_Topics__c.contains('pricing'));
    }

    @isTest
    static void transcribeRecording_audio_download_failure_marks_failed() {
        Test.setMock(HttpCalloutMock.class, new FailingAudioMock());

        Call_Detail__c cd = [SELECT Id FROM Call_Detail__c LIMIT 1];

        Test.startTest();
        try {
            CallTranscriptionService.transcribeRecording(cd.Id);
        } catch (Exception ignored) {
            // expected
        }
        Test.stopTest();

        Call_Detail__c out = [SELECT Transcription_Status__c, Summary__c FROM Call_Detail__c WHERE Id = :cd.Id];
        System.assertEquals('Failed', out.Transcription_Status__c);
        System.assert(out.Summary__c.contains('failed'));
    }

    @isTest
    static void transcribeRecording_missing_recording_url_throws() {
        Call_Detail__c cd = [SELECT Id FROM Call_Detail__c LIMIT 1];
        cd.Recording_File__c = null;
        update cd;

        try {
            CallTranscriptionService.transcribeRecording(cd.Id);
            System.assert(false, 'Should have thrown');
        } catch (CallTranscriptionService.TranscriptionException e) {
            System.assert(e.getMessage().contains('empty'));
        }
    }

    @isTest
    static void transcribeRecording_null_id_throws() {
        try {
            CallTranscriptionService.transcribeRecording(null);
            System.assert(false);
        } catch (CallTranscriptionService.TranscriptionException e) {
            System.assert(e.getMessage().contains('required'));
        }
    }

    @isTest
    static void parseJsonReply_strips_code_fence() {
        String fenced = '```json\n{"transcript":"x","summary":"s","key_topics":[],"sentiment":"Neutral","language":"en"}\n```';
        Map<String, Object> parsed = CallTranscriptionService.parseJsonReply(fenced);
        System.assertEquals('x', parsed.get('transcript'));
        System.assertEquals('Neutral', parsed.get('sentiment'));
    }

    @isTest
    static void rollsUpSummaryToSiteVisit() {
        // Link the call to a site visit and re-run the happy path
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c l = [SELECT Id FROM Lead__c LIMIT 1];
        Site_Visit__c sv = TestDataFactory.createSiteVisit(l.Id, p.Id, UserInfo.getUserId());
        Call_Detail__c cd = [SELECT Id FROM Call_Detail__c LIMIT 1];
        cd.Site_Visit__c = sv.Id;
        update cd;

        Test.setMock(HttpCalloutMock.class, new TranscribeMock());

        Test.startTest();
        CallTranscriptionService.transcribeRecording(cd.Id);
        Test.stopTest();

        Site_Visit__c out = [SELECT Executive_Notes__c FROM Site_Visit__c WHERE Id = :sv.Id];
        System.assert(
            out.Executive_Notes__c != null && out.Executive_Notes__c.contains('Short call'),
            'Summary should be appended to site visit'
        );
    }
}