@isTest
private class AriaTranscriptionControllerTest {

    private class NoOpMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'audio/mpeg');
            res.setBodyAsBlob(Blob.valueOf('fake'));
            return res;
        }
    }

    @isTest
    static void startTranscription_null_id_throws() {
        try {
            AriaTranscriptionController.startTranscription(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @isTest
    static void startTranscription_marks_processing_and_queues_future() {
        Project__c p = TestDataFactory.createProject('Aria Trx Test');
        Lead__c l = TestDataFactory.createLead(p.Id, 'Ishaan', '9888811111');
        Call_Detail__c cd = new Call_Detail__c();
        cd.Lead__c = l.Id;
        cd.Recording_File__c = 'https://example.com/rec.mp3';
        cd.Status__c = 'Completed';
        cd.Transcription_Status__c = 'Pending';
        insert cd;

        Test.setMock(HttpCalloutMock.class, new NoOpMock());

        Test.startTest();
        String status = AriaTranscriptionController.startTranscription(cd.Id);
        Test.stopTest();

        System.assertEquals('Processing', status);
        // After Test.stopTest, future calls have run. The NoOpMock only returns
        // 200 for audio; the upload response body isn't valid — so the future
        // method will mark the record Failed. That's fine — we're testing that
        // the future was kicked off, not the transcription quality.
        Call_Detail__c out = [SELECT Transcription_Status__c FROM Call_Detail__c WHERE Id = :cd.Id];
        System.assert(
            out.Transcription_Status__c == 'Failed' || out.Transcription_Status__c == 'Completed',
            'Future should have moved the record off Processing'
        );
    }

    @isTest
    static void startTranscription_missing_record_throws() {
        // Create a valid Call_Detail__c, capture its Id, delete, then call
        Project__c p = TestDataFactory.createProject('Trx Gone');
        Lead__c l = TestDataFactory.createLead(p.Id, 'Gone', '9888822222');
        Call_Detail__c cd = new Call_Detail__c();
        cd.Lead__c = l.Id;
        cd.Recording_File__c = 'https://example.com/r.mp3';
        cd.Status__c = 'Completed';
        cd.Transcription_Status__c = 'Pending';
        insert cd;
        Id ghostId = cd.Id;
        delete cd;

        try {
            AriaTranscriptionController.startTranscription(ghostId);
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}