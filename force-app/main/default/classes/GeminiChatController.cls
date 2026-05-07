public with sharing class GeminiChatController {

    private static final String GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';
    private static final String API_KEY = 'AIzaSyBPPiYyWUEP4byaEjYA9nPnynSazJFe3fM';

    private static final String SYSTEM_PROMPT = 'You are an intelligent Sales Forecaster AI Assistant embedded inside a Real Estate CRM application. '
        + 'Your role is to help sales teams analyze their pipeline, predict future leads, site visits, and bookings, and provide data-driven insights. '
        + 'You have access to the current dashboard data provided below. Use this data to answer questions accurately. '
        + 'Always respond with specific numbers from the data when available. '
        + 'Keep responses concise and actionable. Do NOT use markdown formatting like ** or ## or * for bullets. '
        + 'Use plain text only. For lists, use simple dashes (- ) or numbered lists (1. 2. 3.). '
        + 'For emphasis, just use CAPS or write clearly without special formatting. '
        + 'If asked about predictions or forecasts, use the forecast data provided to give specific numbers.';

    @AuraEnabled
    public static String sendMessage(String userMessage, String conversationHistory, String dashboardContext) {
        if (String.isBlank(userMessage)) {
            throw new AuraHandledException('Message cannot be empty.');
        }

        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(GEMINI_ENDPOINT + '?key=' + API_KEY);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(30000);

            String body = buildRequestBody(userMessage, conversationHistory, dashboardContext);
            req.setBody(body);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                return parseResponse(res.getBody());
            } else {
                throw new AuraHandledException('AI service returned an error. Please try again.');
            }
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Unable to reach AI service. Please try again later.');
        }
    }

    private static String buildRequestBody(String userMessage, String conversationHistory, String dashboardContext) {
        List<Object> contents = new List<Object>();

        if (String.isNotBlank(conversationHistory)) {
            List<Object> history = (List<Object>) JSON.deserializeUntyped(conversationHistory);
            contents.addAll(history);
        }

        Map<String, Object> userPart = new Map<String, Object>{
            'text' => userMessage
        };
        Map<String, Object> userContent = new Map<String, Object>{
            'role' => 'user',
            'parts' => new List<Object>{ userPart }
        };
        contents.add(userContent);

        // Build system instruction with dashboard context
        String fullSystemPrompt = SYSTEM_PROMPT;
        if (String.isNotBlank(dashboardContext)) {
            fullSystemPrompt += '\n\nCURRENT DASHBOARD DATA:\n' + dashboardContext;
        }

        Map<String, Object> systemPart = new Map<String, Object>{
            'text' => fullSystemPrompt
        };
        Map<String, Object> systemInstruction = new Map<String, Object>{
            'parts' => new List<Object>{ systemPart }
        };

        Map<String, Object> requestBody = new Map<String, Object>{
            'contents' => contents,
            'systemInstruction' => systemInstruction
        };

        return JSON.serialize(requestBody);
    }

    private static String parseResponse(String responseBody) {
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        List<Object> candidates = (List<Object>) result.get('candidates');

        if (candidates != null && !candidates.isEmpty()) {
            Map<String, Object> candidate = (Map<String, Object>) candidates[0];
            Map<String, Object> content = (Map<String, Object>) candidate.get('content');
            List<Object> parts = (List<Object>) content.get('parts');

            if (parts != null && !parts.isEmpty()) {
                Map<String, Object> part = (Map<String, Object>) parts[0];
                return (String) part.get('text');
            }
        }

        return 'I could not generate a response. Please try again.';
    }
}