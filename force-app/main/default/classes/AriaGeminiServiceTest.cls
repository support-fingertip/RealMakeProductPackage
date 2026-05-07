@isTest
private class AriaGeminiServiceTest {

    /** Minimal HttpCalloutMock that returns a queued response for any POST. */
    private class GeminiMock implements HttpCalloutMock {
        private Integer status;
        private String body;
        public GeminiMock(Integer s, String b) { this.status = s; this.body = b; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(this.status);
            res.setBody(this.body);
            res.setHeader('Content-Type', 'application/json');
            return res;
        }
    }

    @isTest
    static void chat_returns_text_response() {
        String body = JSON.serialize(new Map<String, Object>{
            'candidates' => new List<Object>{
                new Map<String, Object>{
                    'finishReason' => 'STOP',
                    'content' => new Map<String, Object>{
                        'parts' => new List<Object>{
                            new Map<String, Object>{ 'text' => 'Hello there!' }
                        }
                    }
                }
            }
        });
        Test.setMock(HttpCalloutMock.class, new GeminiMock(200, body));

        Test.startTest();
        AriaGeminiService.ChatResponse res = AriaGeminiService.callGemini(
            'system', new List<Object>(), 'Hi', null
        );
        Test.stopTest();

        System.assertEquals('Hello there!', res.text);
        System.assertEquals(false, res.hasFunctionCall());
    }

    @isTest
    static void chat_parses_functionCall() {
        String body = JSON.serialize(new Map<String, Object>{
            'candidates' => new List<Object>{
                new Map<String, Object>{
                    'content' => new Map<String, Object>{
                        'parts' => new List<Object>{
                            new Map<String, Object>{
                                'functionCall' => new Map<String, Object>{
                                    'name' => 'search_projects',
                                    'args' => new Map<String, Object>{ 'city' => 'Hyderabad' }
                                }
                            }
                        }
                    }
                }
            }
        });
        Test.setMock(HttpCalloutMock.class, new GeminiMock(200, body));

        Test.startTest();
        List<Object> tools = new List<Object>{
            new Map<String, Object>{ 'functionDeclarations' => new List<Object>() }
        };
        AriaGeminiService.ChatResponse res = AriaGeminiService.callGemini('sys', null, 'find projects', tools);
        Test.stopTest();

        System.assert(res.hasFunctionCall());
        System.assertEquals('search_projects', res.functionCallName);
        System.assertEquals('Hyderabad', res.functionCallArgs.get('city'));
    }

    @isTest
    static void chat_error_status_throws() {
        Test.setMock(HttpCalloutMock.class, new GeminiMock(400, '{"error":"bad"}'));

        Test.startTest();
        try {
            AriaGeminiService.callGemini('sys', null, 'Hi', null);
            System.assert(false, 'Should have thrown');
        } catch (AriaGeminiService.AriaGeminiException e) {
            System.assert(e.getMessage().contains('HTTP 400'));
        }
        Test.stopTest();
    }

    @isTest
    static void empty_user_message_throws() {
        try {
            AriaGeminiService.callGemini('sys', null, null, null);
            System.assert(false, 'Should have thrown');
        } catch (AriaGeminiService.AriaGeminiException e) {
            System.assert(e.getMessage().contains('required'));
        }
    }

    @isTest
    static void uploadFile_returns_uri() {
        String body = JSON.serialize(new Map<String, Object>{
            'file' => new Map<String, Object>{
                'uri' => 'https://gen.example/files/xyz',
                'mimeType' => 'audio/mpeg',
                'name' => 'files/xyz'
            }
        });
        Test.setMock(HttpCalloutMock.class, new GeminiMock(200, body));

        Test.startTest();
        Blob data = Blob.valueOf('fake-audio');
        AriaGeminiService.UploadedFile f = AriaGeminiService.uploadFile(data, 'audio/mpeg', 'sample');
        Test.stopTest();

        System.assertEquals('https://gen.example/files/xyz', f.uri);
    }

    @isTest
    static void uploadFile_empty_blob_throws() {
        try {
            AriaGeminiService.uploadFile(null, 'audio/mpeg', 'x');
            System.assert(false, 'Should have thrown');
        } catch (AriaGeminiService.AriaGeminiException e) {
            System.assert(e.getMessage().contains('empty'));
        }
    }

    @isTest
    static void callGeminiWithFile_happy_path() {
        String body = JSON.serialize(new Map<String, Object>{
            'candidates' => new List<Object>{
                new Map<String, Object>{
                    'content' => new Map<String, Object>{
                        'parts' => new List<Object>{
                            new Map<String, Object>{ 'text' => '{"transcript":"hi"}' }
                        }
                    }
                }
            }
        });
        Test.setMock(HttpCalloutMock.class, new GeminiMock(200, body));

        AriaGeminiService.UploadedFile f = new AriaGeminiService.UploadedFile();
        f.uri = 'https://gen.example/files/x';
        f.mimeType = 'audio/mpeg';

        Test.startTest();
        AriaGeminiService.ChatResponse res = AriaGeminiService.callGeminiWithFile('prompt', f, 'audio/mpeg');
        Test.stopTest();

        System.assert(res.text.contains('transcript'));
    }
}