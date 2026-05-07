@isTest
private class PdfToSvgControllerTest {

    private class ConvertApiMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('convertapi.com/convert')) {
                res.setStatusCode(200);
                res.setBody('{"ConversionCost":1,"Files":[{"FileName":"test.svg","FileExt":"svg","FileSize":100,"Url":"https://v2.convertapi.com/d/test123/test.svg"}]}');
            } else if (req.getEndpoint().contains('convertapi.com/d/')) {
                res.setStatusCode(200);
                res.setBody('<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0L100 100" stroke="black"/></svg>');
            } else {
                res.setStatusCode(404);
                res.setBody('Not Found');
            }
            return res;
        }
    }

    @isTest
    static void testConvertPdfToSvg() {
        Test.setMock(HttpCalloutMock.class, new ConvertApiMock());

        String base64Data = EncodingUtil.base64Encode(Blob.valueOf('fake pdf content'));

        Test.startTest();
        List<Map<String, String>> result = PdfToSvgController.convertPdfToSvg(base64Data, 'test.pdf');
        Test.stopTest();

        System.assertEquals(1, result.size(), 'Should return 1 SVG page');
        System.assertEquals('test.svg', result[0].get('fileName'));
        System.assert(result[0].get('svgContent').contains('<path'), 'SVG should contain path elements');
    }

    @isTest
    static void testEmptyInput() {
        Boolean thrown = false;
        Test.startTest();
        try {
            PdfToSvgController.convertPdfToSvg('', 'test.pdf');
        } catch (Exception e) {
            thrown = true;
        }
        Test.stopTest();
        
    }
}