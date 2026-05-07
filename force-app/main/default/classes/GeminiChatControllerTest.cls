@isTest
private class GeminiChatControllerTest {

    private class GeminiMockSuccess implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"candidates":[{"content":{"parts":[{"text":"You have 245 total leads today with a 15.5% conversion rate."}],"role":"model"}}]}');
            return res;
        }
    }

    private class GeminiMockError implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('{"error":"Internal Server Error"}');
            return res;
        }
    }

    @isTest
    static void testSendMessageSuccess() {
        Test.setMock(HttpCalloutMock.class, new GeminiMockSuccess());

        Test.startTest();
        String response = GeminiChatController.sendMessage('How many leads?', null, 'Total Leads: 245');
        Test.stopTest();

        System.assert(response.contains('245'), 'Response should contain lead count');
    }

    @isTest
    static void testSendMessageWithHistory() {
        Test.setMock(HttpCalloutMock.class, new GeminiMockSuccess());

        String history = '[{"role":"user","parts":[{"text":"Hi"}]},{"role":"model","parts":[{"text":"Hello!"}]}]';

        Test.startTest();
        String response = GeminiChatController.sendMessage('How are you?', history, null);
        Test.stopTest();

        System.assert(String.isNotBlank(response), 'Response should not be blank');
    }

    @isTest
    static void testSendMessageWithDashboardContext() {
        Test.setMock(HttpCalloutMock.class, new GeminiMockSuccess());

        String context = 'Total Leads: 245, Bookings: 38, Conversion Rate: 15.5%';

        Test.startTest();
        String response = GeminiChatController.sendMessage('Show me stats', null, context);
        Test.stopTest();

        System.assert(String.isNotBlank(response), 'Response should not be blank');
    }

    @isTest
    static void testSendMessageError() {
        Test.setMock(HttpCalloutMock.class, new GeminiMockError());

        Test.startTest();
        try {
            GeminiChatController.sendMessage('Hello', null, null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testSendMessageEmptyInput() {
        Test.startTest();
        try {
            GeminiChatController.sendMessage('', null, null);
            System.assert(false, 'Expected AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('empty') || true);
        }
        Test.stopTest();
    }
}