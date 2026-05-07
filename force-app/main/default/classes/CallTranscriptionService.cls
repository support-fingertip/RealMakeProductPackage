/**
 * @description Transcribes a Call_Detail__c recording using Gemini multimodal.
 *
 * Flow:
 *   1. Read Call_Detail__c.Recording_File__c (a URL to the audio file)
 *   2. Download the audio as a Blob (requires the host to be on a remote site)
 *   3. Upload to Gemini Files API via AriaGeminiService.uploadFile
 *   4. Call Gemini with a structured JSON prompt asking for transcript +
 *      summary + key topics + sentiment + language
 *   5. Persist to the new transcription fields on Call_Detail__c
 *   6. If Call_Detail__c.Site_Visit__c is populated, append the summary to
 *      Site_Visit__c.Executive_Notes__c so it surfaces at the visit level too
 *
 * Designed to be called from a @future(callout=true) entry point so the LWC
 * returns immediately and the caller polls the record for status changes.
 */
public with sharing class CallTranscriptionService {

    public class TranscriptionException extends Exception {}

    private static final String TRANSCRIBE_PROMPT =
        'You are transcribing a call recording between a real estate sales executive and a '
      + 'customer. Transcribe the audio verbatim. Detect the primary language. Return ONLY '
      + 'valid JSON matching this exact schema (no prose, no markdown):\n'
      + '{\n'
      + '  "transcript": "full verbatim transcript with speaker labels where clear",\n'
      + '  "summary": "3 to 5 sentence summary of the conversation",\n'
      + '  "key_topics": ["short", "bulleted", "topics"],\n'
      + '  "sentiment": "Positive | Neutral | Negative",\n'
      + '  "language": "ISO 639-1 language code e.g. en, hi, te"\n'
      + '}';

    /**
     * @description Main entry point. Runs synchronously; caller should invoke
     *              from @future or Queueable for a non-blocking UX.
     */
    public static void transcribeRecording(Id callDetailId) {
        if (callDetailId == null) {
            throw new TranscriptionException('Call Detail Id is required.');
        }

        Call_Detail__c cd = loadCallDetail(callDetailId);
        if (String.isBlank(cd.Recording_File__c)) {
            markFailed(cd, 'No recording file URL on the Call Detail record.');
            throw new TranscriptionException('Recording_File__c is empty.');
        }

        try {
            // 1. Download audio (callouts must happen before any DML in this txn)
            HttpResponse audioRes = fetchAudio(cd.Recording_File__c);
            if (audioRes.getStatusCode() != 200) {
                throw new TranscriptionException(
                    'Failed to download recording (HTTP ' + audioRes.getStatusCode() + ').'
                );
            }
            Blob audio = audioRes.getBodyAsBlob();
            String mime = audioRes.getHeader('Content-Type');
            if (String.isBlank(mime)) {
                mime = guessMimeFromUrl(cd.Recording_File__c);
            }

            // 2. Upload to Gemini Files API
            AriaGeminiService.UploadedFile uploaded =
                AriaGeminiService.uploadFile(audio, mime, 'call_' + cd.Id);

            // 3. Ask Gemini to transcribe + summarise
            AriaGeminiService.ChatResponse res =
                AriaGeminiService.callGeminiWithFile(TRANSCRIBE_PROMPT, uploaded, mime);

            // 4. Parse the JSON payload out of the model's reply
            Map<String, Object> parsed = parseJsonReply(res.text);

            // 5. Persist back to Call_Detail__c
            cd.Transcription__c           = (String) parsed.get('transcript');
            cd.Summary__c                 = (String) parsed.get('summary');
            cd.Key_Topics__c              = joinList(parsed.get('key_topics'));
            cd.Sentiment__c               = coerceSentiment((String) parsed.get('sentiment'));
            cd.Transcription_Language__c  = (String) parsed.get('language');
            cd.Transcription_Status__c    = 'Completed';
            update cd;

            // 6. Optional roll-up to the linked site visit
            if (cd.Site_Visit__c != null && String.isNotBlank(cd.Summary__c)) {
                appendToSiteVisit(cd.Site_Visit__c, cd.Summary__c);
            }

        } catch (Exception ex) {
            markFailed(cd, ex.getMessage());
            throw new TranscriptionException('Transcription failed: ' + ex.getMessage());
        }
    }

    // ════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════

    private static Call_Detail__c loadCallDetail(Id id) {
        List<Call_Detail__c> rows = [
            SELECT Id, Recording_File__c, Transcription__c, Summary__c, Key_Topics__c,
                   Sentiment__c, Transcription_Status__c, Transcription_Language__c,
                   Site_Visit__c, Lead__c
            FROM Call_Detail__c
            WHERE Id = :id
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new TranscriptionException('Call Detail not found.');
        }
        return rows[0];
    }

    private static void markFailed(Call_Detail__c cd, String message) {
        try {
            cd.Transcription_Status__c = 'Failed';
            // Reuse Summary__c as a visible failure reason — admins see it at-a-glance
            cd.Summary__c = 'Transcription failed: ' + (message == null ? 'unknown error' : message);
            update cd;
        } catch (Exception ignored) {
            // Swallow — we're already in error path
        }
    }

    @TestVisible
    private static HttpResponse fetchAudio(String url) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('GET');
        req.setTimeout(60000);
        return sendRequest(req);
    }

    @TestVisible
    private static HttpResponse sendRequest(HttpRequest req) {
        return new Http().send(req);
    }

    private static String guessMimeFromUrl(String url) {
        if (url == null) return 'audio/mpeg';
        String lower = url.toLowerCase();
        if (lower.endsWith('.mp3'))  return 'audio/mpeg';
        if (lower.endsWith('.wav'))  return 'audio/wav';
        if (lower.endsWith('.m4a'))  return 'audio/mp4';
        if (lower.endsWith('.ogg'))  return 'audio/ogg';
        if (lower.endsWith('.flac')) return 'audio/flac';
        return 'audio/mpeg';
    }

    /**
     * @description Defensive JSON extraction — Gemini sometimes wraps JSON in
     *              ```json ... ``` fences despite instructions.
     */
    @TestVisible
    private static Map<String, Object> parseJsonReply(String reply) {
        if (String.isBlank(reply)) {
            throw new TranscriptionException('Empty model response.');
        }
        String cleaned = reply.trim();
        // Strip fenced code blocks if present
        if (cleaned.startsWith('```')) {
            Integer firstNewline = cleaned.indexOf('\n');
            if (firstNewline > 0) {
                cleaned = cleaned.substring(firstNewline + 1);
            }
            if (cleaned.endsWith('```')) {
                cleaned = cleaned.substring(0, cleaned.length() - 3);
            }
            cleaned = cleaned.trim();
        }
        // If the model prefixed with prose, find the first '{'
        Integer firstBrace = cleaned.indexOf('{');
        if (firstBrace > 0) {
            cleaned = cleaned.substring(firstBrace);
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(cleaned);
        } catch (Exception e) {
            throw new TranscriptionException('Model response was not valid JSON: ' + e.getMessage());
        }
    }

    private static String joinList(Object raw) {
        if (raw == null) return null;
        if (raw instanceof List<Object>) {
            List<String> parts = new List<String>();
            for (Object o : (List<Object>) raw) {
                if (o != null) parts.add(String.valueOf(o));
            }
            return String.join(parts, ', ');
        }
        return String.valueOf(raw);
    }

    private static String coerceSentiment(String value) {
        if (String.isBlank(value)) return null;
        String v = value.trim().toLowerCase();
        if (v.startsWith('pos')) return 'Positive';
        if (v.startsWith('neg')) return 'Negative';
        if (v.startsWith('neu')) return 'Neutral';
        return null;
    }

    private static void appendToSiteVisit(Id siteVisitId, String summary) {
        List<Site_Visit__c> visits = [
            SELECT Id, Executive_Notes__c FROM Site_Visit__c WHERE Id = :siteVisitId LIMIT 1
        ];
        if (visits.isEmpty()) return;
        Site_Visit__c sv = visits[0];
        String stamp = '[Call transcript ' + String.valueOf(DateTime.now().date()) + '] ';
        String existing = String.isNotBlank(sv.Executive_Notes__c) ? sv.Executive_Notes__c + '\n\n' : '';
        sv.Executive_Notes__c = existing + stamp + summary;
        update sv;
    }
}