@IsTest
public class MockHttpCallout implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;
    private Map<String, String> responseHeaders;

    public MockHttpCallout(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
        this.responseHeaders = new Map<String, String>();
    }

    public MockHttpCallout(Integer statusCode, String responseBody, Map<String, String> headers) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
        this.responseHeaders = headers;
    }

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(responseBody);
        if (responseHeaders != null) {
            for (String key : responseHeaders.keySet()) {
                res.setHeader(key, responseHeaders.get(key));
            }
        }
        return res;
    }
}