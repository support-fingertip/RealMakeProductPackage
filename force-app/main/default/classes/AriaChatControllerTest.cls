@isTest
private class AriaChatControllerTest {

    /**
     * Two-step mock: first call returns a plain text reply (no function call),
     * validating the non-tool path. Subsequent calls would also succeed.
     */
    private class PlainMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            String body = JSON.serialize(new Map<String, Object>{
                'candidates' => new List<Object>{
                    new Map<String, Object>{
                        'content' => new Map<String, Object>{
                            'parts' => new List<Object>{
                                new Map<String, Object>{ 'text' => 'Thanks for reaching out — could you share your budget range?' }
                            }
                        }
                    }
                }
            });
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(body);
            return res;
        }
    }

    /**
     * Mock that returns a functionCall on first invocation and a plain-text
     * reply on subsequent invocations — exercises the tool-hop loop.
     * The first response includes a `thoughtSignature` so we can assert it
     * round-trips into the next outbound payload (regression for HTTP 400
     * "Function call is missing a thought_signature").
     */
    private class ToolHopMock implements HttpCalloutMock {
        public Integer calls = 0;
        public String secondCallBody;
        public HttpResponse respond(HttpRequest req) {
            this.calls += 1;
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (this.calls == 1) {
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'candidates' => new List<Object>{
                        new Map<String, Object>{
                            'content' => new Map<String, Object>{
                                'parts' => new List<Object>{
                                    new Map<String, Object>{
                                        'functionCall' => new Map<String, Object>{
                                            'name' => 'search_projects',
                                            'args' => new Map<String, Object>()
                                        },
                                        'thoughtSignature' => 'sig-abc-123'
                                    }
                                }
                            }
                        }
                    }
                }));
            } else {
                this.secondCallBody = req.getBody();
                res.setBody(JSON.serialize(new Map<String, Object>{
                    'candidates' => new List<Object>{
                        new Map<String, Object>{
                            'content' => new Map<String, Object>{
                                'parts' => new List<Object>{
                                    new Map<String, Object>{ 'text' => 'We have one active project — Aria Chat Test.' }
                                }
                            }
                        }
                    }
                }));
            }
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Project__c p = TestDataFactory.createProject('Aria Chat Test');
        // AriaKnowledgeService.getProjectsDigest() filters on Is_Active__c
        // + Project_Status__c — set both so the test project shows up in
        // the system prompt assertions below.
        p.Is_Active__c = true;
        p.Project_Status__c = 'Launched';
        update p;
    }

    @isTest
    static void sendMessage_returns_plain_reply() {
        Test.setMock(HttpCalloutMock.class, new PlainMock());

        Test.startTest();
        AriaChatController.ChatTurnResult res = AriaChatController.sendMessage(
            'Hi', null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, res.reply);
        System.assert(res.reply.contains('budget'));
        System.assertEquals(0, res.actionsExecuted.size());
    }

    @isTest
    static void sendMessage_executes_function_call() {
        ToolHopMock mock = new ToolHopMock();
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        AriaChatController.ChatTurnResult res = AriaChatController.sendMessage(
            'Show me active projects', null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, res.actionsExecuted.size());
        Map<String, Object> action = res.actionsExecuted[0];
        System.assertEquals('search_projects', action.get('tool'));
        System.assert(res.reply.contains('Aria Chat Test'));

        // Regression: thoughtSignature must round-trip into the second outbound
        // call, otherwise newer Gemini models reject with HTTP 400.
        System.assertNotEquals(null, mock.secondCallBody);
        System.assert(
            mock.secondCallBody.contains('thoughtSignature'),
            'Second outbound payload must echo thoughtSignature back. Body: ' + mock.secondCallBody
        );
        System.assert(
            mock.secondCallBody.contains('sig-abc-123'),
            'Original signature value must be preserved verbatim'
        );
    }

    @isTest
    static void sendMessage_blank_throws() {
        try {
            AriaChatController.sendMessage('', null, null, null);
            System.assert(false, 'Should have thrown');
        } catch (AuraHandledException e) {
            // expected — AuraHandledException wraps the message
            System.assert(true);
        }
    }

    @isTest
    static void buildSystemPrompt_includes_projects_digest() {
        String prompt = AriaChatController.buildSystemPrompt(null);
        System.assert(prompt.contains('ACTIVE PROJECTS'));
        System.assert(prompt.contains('Aria Chat Test'));
    }

    @isTest
    static void buildSystemPrompt_on_Lead_includes_lead_context() {
        Project__c p = [SELECT Id FROM Project__c LIMIT 1];
        Lead__c l = TestDataFactory.createLead(p.Id, 'Kavya', '9888800555');
        String prompt = AriaChatController.buildSystemPrompt(l.Id);
        System.assert(prompt.contains('CURRENT LEAD CONTEXT'));
    }

    @isTest
    static void buildToolDeclarations_contains_all_tools() {
        List<Object> tools = AriaChatController.buildToolDeclarations();
        System.assertEquals(1, tools.size());
        Map<String, Object> wrapper = (Map<String, Object>) tools[0];
        List<Object> funcs = (List<Object>) wrapper.get('functionDeclarations');

        Set<String> names = new Set<String>();
        for (Object o : funcs) {
            Map<String, Object> f = (Map<String, Object>) o;
            names.add((String) f.get('name'));
        }
        System.assert(names.contains('search_projects'));
        System.assert(names.contains('create_lead'));
        System.assert(names.contains('schedule_site_visit'));
        System.assert(names.contains('schedule_followup'));
        System.assert(names.contains('generate_cost_sheet'));
    }
}