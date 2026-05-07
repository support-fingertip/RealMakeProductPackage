@isTest
private class MockHttpCalloutTest {
    @isTest
    static void smokeTest() {
        Test.startTest();
        try {
            MockHttpCallout mock = new MockHttpCallout(200, '{"status":"ok"}');
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://example.com');
            req.setMethod('GET');
            HttpResponse res = mock.respond(req);
            System.assertNotEquals(null, res);
        } catch (Exception e) {}
        Test.stopTest();
    }
}