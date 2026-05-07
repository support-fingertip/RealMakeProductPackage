/**
 * @description Low-level wrapper around the Google Gemini REST API.
 *
 * Two capabilities:
 *   1. callGemini(...)  — chat / function-calling (generateContent)
 *   2. uploadFile(...)  — upload audio for transcription (Files API)
 *
 * Endpoint + API key are defined as constants below (matches the original
 * GeminiChatController pattern). To rotate the key or change models, edit
 * GEMINI_ENDPOINT / UPLOAD_ENDPOINT / API_KEY directly.
 */
public with sharing class AriaGeminiService {

    private static final String GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';
    private static final String UPLOAD_ENDPOINT = 'https://generativelanguage.googleapis.com/upload/v1beta/files';
    private static final String API_KEY = 'AIzaSyBPPiYyWUEP4byaEjYA9nPnynSazJFe3fM';
    // private static final String API_KEY = 'AIzaSyAqM-buT8O5De94VojRWC7gPcmTuVmEdlE';
    private static final Integer DEFAULT_TIMEOUT_MS = 60000;

    public class AriaGeminiException extends Exception {}

    // ════════════════════════════════════════════════════════════
    // DTOs
    // ════════════════════════════════════════════════════════════

    public class ChatResponse {
        public String text;
        public String functionCallName;
        public Map<String, Object> functionCallArgs;
        public String finishReason;
        public String rawBody;
        // The exact `parts` array Gemini returned for the model turn. We must
        // round-trip these verbatim into history (preserving fields like
        // `thoughtSignature`) — otherwise newer Gemini models reject the
        // follow-up call with HTTP 400 "missing thought_signature".
        public List<Object> modelContentParts;

        public Boolean hasFunctionCall() {
            return String.isNotBlank(this.functionCallName);
        }
    }

    public class UploadedFile {
        public String uri;
        public String mimeType;
        public String name;
    }

    // ════════════════════════════════════════════════════════════
    // CHAT / FUNCTION CALLING
    // ════════════════════════════════════════════════════════════

    public static ChatResponse callGemini(
        String systemPrompt,
        List<Object> history,
        String userMessage,
        List<Object> tools
    ) {
        if (String.isBlank(userMessage) && (history == null || history.isEmpty())) {
            throw new AriaGeminiException('At least one user message is required.');
        }

        String endpoint = GEMINI_ENDPOINT + '?key=' + API_KEY;
        Map<String, Object> body = buildChatBody(systemPrompt, history, userMessage, tools);

        HttpResponse res = doPost(endpoint, JSON.serialize(body), DEFAULT_TIMEOUT_MS);

        if (res.getStatusCode() != 200) {
            throw new AriaGeminiException(
                'Gemini chat call failed: HTTP ' + res.getStatusCode()
                + ' — ' + truncate(res.getBody(), 500)
            );
        }

        return parseChatResponse(res.getBody());
    }

    public static ChatResponse callGeminiWithFile(String prompt, UploadedFile file, String mimeType) {
        if (file == null || String.isBlank(file.uri)) {
            throw new AriaGeminiException('Uploaded file URI is required.');
        }

        List<Object> parts = new List<Object>{
            new Map<String, Object>{ 'text' => prompt },
            new Map<String, Object>{
                'fileData' => new Map<String, Object>{
                    'mimeType' => mimeType != null ? mimeType : file.mimeType,
                    'fileUri' => file.uri
                }
            }
        };

        Map<String, Object> userContent = new Map<String, Object>{
            'role' => 'user',
            'parts' => parts
        };

        Map<String, Object> body = new Map<String, Object>{
            'contents' => new List<Object>{ userContent }
        };

        String endpoint = GEMINI_ENDPOINT + '?key=' + API_KEY;
        HttpResponse res = doPost(endpoint, JSON.serialize(body), DEFAULT_TIMEOUT_MS);

        if (res.getStatusCode() != 200) {
            throw new AriaGeminiException(
                'Gemini file call failed: HTTP ' + res.getStatusCode()
                + ' — ' + truncate(res.getBody(), 500)
            );
        }
        return parseChatResponse(res.getBody());
    }

    // ════════════════════════════════════════════════════════════
    // FILES API (for audio transcription)
    // ════════════════════════════════════════════════════════════

    public static UploadedFile uploadFile(Blob content, String mimeType, String displayName) {
        if (content == null || content.size() == 0) {
            throw new AriaGeminiException('Upload content is empty.');
        }
        if (String.isBlank(mimeType)) {
            throw new AriaGeminiException('MIME type is required.');
        }

        String url = UPLOAD_ENDPOINT + '?key=' + API_KEY + '&uploadType=media';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod('POST');
        req.setHeader('Content-Type', mimeType);
        if (String.isNotBlank(displayName)) {
            req.setHeader('X-Goog-Upload-File-Name', displayName);
        }
        req.setBodyAsBlob(content);
        req.setTimeout(DEFAULT_TIMEOUT_MS);

        HttpResponse res = sendRequest(req);
        if (res.getStatusCode() != 200) {
            throw new AriaGeminiException(
                'Gemini file upload failed: HTTP ' + res.getStatusCode()
                + ' — ' + truncate(res.getBody(), 500)
            );
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> file = (Map<String, Object>) parsed.get('file');
        if (file == null) {
            throw new AriaGeminiException('Unexpected Files API response: ' + truncate(res.getBody(), 500));
        }

        UploadedFile out = new UploadedFile();
        out.uri = (String) file.get('uri');
        out.mimeType = (String) file.get('mimeType');
        out.name = (String) file.get('name');
        return out;
    }

    // ════════════════════════════════════════════════════════════
    // REQUEST CONSTRUCTION
    // ════════════════════════════════════════════════════════════

    private static Map<String, Object> buildChatBody(
        String systemPrompt,
        List<Object> history,
        String userMessage,
        List<Object> tools
    ) {
        List<Object> contents = new List<Object>();
        if (history != null && !history.isEmpty()) {
            contents.addAll(history);
        }
        if (String.isNotBlank(userMessage)) {
            contents.add(new Map<String, Object>{
                'role' => 'user',
                'parts' => new List<Object>{
                    new Map<String, Object>{ 'text' => userMessage }
                }
            });
        }

        Map<String, Object> body = new Map<String, Object>{
            'contents' => contents
        };

        if (String.isNotBlank(systemPrompt)) {
            body.put('systemInstruction', new Map<String, Object>{
                'parts' => new List<Object>{
                    new Map<String, Object>{ 'text' => systemPrompt }
                }
            });
        }

        if (tools != null && !tools.isEmpty()) {
            body.put('tools', tools);
        }

        body.put('generationConfig', new Map<String, Object>{
            'temperature' => 0.3,
            'maxOutputTokens' => 512
        });

        return body;
    }

    // ════════════════════════════════════════════════════════════
    // RESPONSE PARSING
    // ════════════════════════════════════════════════════════════

    private static ChatResponse parseChatResponse(String rawBody) {
        ChatResponse out = new ChatResponse();
        out.rawBody = rawBody;

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(rawBody);
        List<Object> candidates = (List<Object>) parsed.get('candidates');
        if (candidates == null || candidates.isEmpty()) {
            out.text = '';
            return out;
        }

        Map<String, Object> candidate = (Map<String, Object>) candidates[0];
        out.finishReason = (String) candidate.get('finishReason');

        Map<String, Object> content = (Map<String, Object>) candidate.get('content');
        if (content == null) {
            return out;
        }
        List<Object> parts = (List<Object>) content.get('parts');
        if (parts == null) {
            return out;
        }
        // Save the raw parts so callers can echo them back into history
        // verbatim — required to round-trip thoughtSignature on newer models.
        out.modelContentParts = parts;

        List<String> textSegments = new List<String>();
        for (Object p : parts) {
            Map<String, Object> part = (Map<String, Object>) p;
            if (part.containsKey('functionCall') && part.get('functionCall') != null) {
                Map<String, Object> fc = (Map<String, Object>) part.get('functionCall');
                out.functionCallName = (String) fc.get('name');
                Object args = fc.get('args');
                out.functionCallArgs = args instanceof Map<String, Object>
                    ? (Map<String, Object>) args
                    : new Map<String, Object>();
                return out;
            } else if (part.containsKey('text') && part.get('text') != null) {
                textSegments.add((String) part.get('text'));
            }
        }

        out.text = String.join(textSegments, '\n');
        return out;
    }

    // ════════════════════════════════════════════════════════════
    // HTTP helpers (mockable)
    // ════════════════════════════════════════════════════════════

    private static HttpResponse doPost(String endpoint, String body, Integer timeoutMs) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(body);
        req.setTimeout(timeoutMs);
        return sendRequest(req);
    }

    @TestVisible
    private static HttpResponse sendRequest(HttpRequest req) {
        return new Http().send(req);
    }

    private static String truncate(String s, Integer max) {
        if (s == null) return '';
        return s.length() > max ? s.substring(0, max) : s;
    }
}