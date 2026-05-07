/**
 * @description Aria — conversational pre-sales & sales assistant.
 *
 * This controller is the single @AuraEnabled entry point for the ariaChatBot
 * LWC. One call per turn:
 *
 *   1. Assemble the system prompt (Aria persona + live org context)
 *   2. Ship the conversation to Gemini with tool declarations
 *   3. If Gemini responds with a functionCall → execute via AriaActionService,
 *      append the functionResponse to history and go back to step 2
 *      (max TOOL_CALL_HOPS iterations to prevent runaway loops)
 *   4. Return the final natural-language reply plus any side-effects the bot
 *      performed so the UI can render action cards (e.g. "Lead L-00123 created")
 */
public with sharing class AriaChatController {

    // Hard cap on consecutive tool hops per turn. 3 is plenty: typical
    // flow is search → create → confirm, or read → act → confirm.
    private static final Integer TOOL_CALL_HOPS = 5;

    // Write-tools perform DML inside AriaActionService.dispatch. Apex forbids
    // a second HTTP callout once the transaction has uncommitted DML, so we
    // short-circuit the tool-hop loop for these and synthesise the final
    // reply from the tool's own `message` field (already user-facing).
    private static final Set<String> WRITE_TOOLS = new Set<String>{
        'create_lead', 'schedule_site_visit', 'generate_cost_sheet',
        'schedule_followup', 'initiate_booking', 'block_unit',
        'cancel_booking', 'raise_complaint'
    };

    // The full Aria persona. Kept verbatim from product requirements so that
    // any future tuning happens in one place.
    @TestVisible
    private static final String ARIA_PERSONA =
        'You are Aria, a real estate pre-sales & sales AI inside a CRM. '
      + 'You help sales executives qualify leads, find records, and close bookings. '

      // ── BEHAVIOUR ──
      + '\n\nBEHAVIOUR:'
      + '\n- Keep replies under 60 words. Lists are OK but keep them short.'
      + '\n- Ask ONE question at a time. End every reply with a question or action suggestion.'
      + '\n- Use the customer\'s name once you know it. Be warm but efficient.'
      + '\n- NEVER invent project names, codes, prices or IDs. Always look up via a tool first.'
      + '\n- When the user gives a discrete choice question, end with: CHOICES: [option1 | option2 | option3]'

      // ── TOOL-CALLING — MANDATORY ──
      + '\n\nTOOL RULES (follow strictly):'
      + '\n1. If the user mentions ANY identifier (LD-XXXX, BK-XXXX, mobile, email, unit number, project name) — call search_everything(query) FIRST. NEVER say "I could not find" without calling a tool.'
      + '\n2. For "move to booking" / "booking status" — call get_booking_status(lead_id). Explain the next step it returns.'
      + '\n3. For EMI / loan questions — call calculate_emi or calculate_loan_eligibility.'
      + '\n4. For "my performance" / "how am I doing" — call my_performance.'
      + '\n5. For "overdue" / "pending" / "stale" — call get_overdue_followups or get_stale_leads.'
      + '\n5b. For "hot leads" / "which leads should I focus on" / "leads to move to booking" / "who is close to closing" — call get_hot_leads.'
      + '\n6. For "funnel" / "conversion" — call get_funnel_analysis.'
      + '\n7. For "send brochure" / "send cost sheet" — call the send tool.'
      + '\n8. For "cancel booking" — call cancel_booking after confirming the reason.'
      + '\n9. For "complaint" / "issue" — call raise_complaint.'
      + '\n10. For cost breakdown (no cost sheet yet) — call get_cost_breakdown(unit_id).'

      // ── OBJECTION HANDLING ──
      + '\n\nOBJECTION HANDLING:'
      + '\n- "Too expensive" → ROI, appreciation, flexible payment plans, loan options.'
      + '\n- "Will think" → limited inventory, price revision upcoming.'
      + '\n- "Not ready" → ask timeline, schedule follow-up.'
      + '\n- "Seen others" → ask what they liked/disliked, position strengths.'

      // ── FORMAT ──
      + '\n\nFORMAT: Plain text only. No ** or ## markdown. Use - for lists, numbers for steps.'

      // ── FEW-SHOT EXAMPLES ──
      + '\n\nEXAMPLE TURNS:'
      + '\nUser: "LD-000466" → Call search_everything("LD-000466") → Report result.'
      + '\nUser: "9988776600" → Call search_everything("9988776600") → Report result.'
      + '\nUser: "move lead to booking" → Call get_booking_status(lead_id) → Explain next step.'
      + '\nUser: "EMI for 50 lakh 8.5% 20 years" → Call calculate_emi(5000000, 8.5, 240) → Report.'
      + '\nUser: "how am I doing this month" → Call my_performance(30) → Report counts + rate.'
      + '\nUser: "what 2BHK under 80 lakhs" → Call check_unit_availability with bhk=2BHK budget_max=8000000.';

    // ════════════════════════════════════════════════════════════
    // DTOs
    // ════════════════════════════════════════════════════════════

    public class ChatTurnResult {
        @AuraEnabled public String reply;
        @AuraEnabled public List<Map<String, Object>> actionsExecuted;
        @AuraEnabled public List<Object> updatedHistory;
    }

    // ════════════════════════════════════════════════════════════
    // ENTRY POINT
    // ════════════════════════════════════════════════════════════

    /**
     * @param userMessage            Latest user message.
     * @param conversationHistoryJson JSON-encoded list of prior history entries
     *                                (same shape the Gemini API expects — role +
     *                                parts). Pass null or empty on the first turn.
     * @param recordId               Optional — if the LWC is placed on a Lead
     *                                record page, pass the Lead Id so Aria can
     *                                personalise with getLeadContext().
     */
    @AuraEnabled
    public static ChatTurnResult sendMessage(
        String userMessage,
        String conversationHistoryJson,
        Id recordId,
        String preferredLanguage
    ) {
        if (String.isBlank(userMessage)) {
            throw new AuraHandledException('Message cannot be empty.');
        }

        try {
            List<Object> history = parseHistory(conversationHistoryJson);
            String systemPrompt = buildSystemPrompt(recordId);

            // Language support — Gemini handles translation natively
            if (String.isNotBlank(preferredLanguage) && !'English'.equalsIgnoreCase(preferredLanguage)) {
                systemPrompt += '\n\nIMPORTANT: Reply in ' + preferredLanguage + '. '
                    + 'Use ' + preferredLanguage + ' script. Keep numbers in digits.';
            }

            List<Object> tools = buildToolDeclarations();

            // Append the user turn before the first call so subsequent
            // functionResponse entries sit in the right order.
            history.add(new Map<String, Object>{
                'role'  => 'user',
                'parts' => new List<Object>{
                    new Map<String, Object>{ 'text' => userMessage }
                }
            });

            List<Map<String, Object>> actionsExecuted = new List<Map<String, Object>>();
            String finalText = '';

            for (Integer hop = 0; hop < TOOL_CALL_HOPS + 1; hop++) {
                // On hop 0 we just sent the user message. On later hops we
                // sent a functionResponse. callGemini() with an empty
                // userMessage means "continue from the last history entry".
                AriaGeminiService.ChatResponse res = AriaGeminiService.callGemini(
                    systemPrompt, history, null, tools
                );

                if (res.hasFunctionCall()) {
                    // Record the model's functionCall in history. We MUST echo
                    // the original parts verbatim — newer Gemini models attach
                    // a `thoughtSignature` to each functionCall part and reject
                    // the next request with HTTP 400 if it isn't present.
                    List<Object> echoParts = res.modelContentParts != null
                        ? res.modelContentParts
                        : new List<Object>{
                            new Map<String, Object>{
                                'functionCall' => new Map<String, Object>{
                                    'name' => res.functionCallName,
                                    'args' => res.functionCallArgs
                                }
                            }
                        };
                    history.add(new Map<String, Object>{
                        'role'  => 'model',
                        'parts' => echoParts
                    });

                    // Execute and capture the result
                    Map<String, Object> actionResult;
                    try {
                        actionResult = AriaActionService.dispatch(
                            res.functionCallName, res.functionCallArgs
                        );
                    } catch (Exception ex) {
                        actionResult = new Map<String, Object>{
                            'error' => ex.getMessage()
                        };
                    }

                    actionsExecuted.add(new Map<String, Object>{
                        'tool'   => res.functionCallName,
                        'args'   => res.functionCallArgs,
                        'result' => actionResult
                    });

                    // Feed the functionResponse back so Gemini can incorporate it.
                    // The REST API uses the "user" role for tool results, with a
                    // functionResponse part.
                    history.add(new Map<String, Object>{
                        'role'  => 'user',
                        'parts' => new List<Object>{
                            new Map<String, Object>{
                                'functionResponse' => new Map<String, Object>{
                                    'name'     => res.functionCallName,
                                    'response' => actionResult
                                }
                            }
                        }
                    });

                    // Write tools have just performed DML. Apex forbids any
                    // further HTTP callout in this transaction, so we cannot
                    // loop back to Gemini for a natural-language wrap-up.
                    // Synthesise the reply from the tool's own user-facing
                    // message (and any error) instead.
                    if (WRITE_TOOLS.contains(res.functionCallName)) {
                        finalText = synthesiseWriteReply(res.functionCallName, actionResult);
                        if (String.isNotBlank(finalText)) {
                            history.add(new Map<String, Object>{
                                'role'  => 'model',
                                'parts' => new List<Object>{
                                    new Map<String, Object>{ 'text' => finalText }
                                }
                            });
                        }
                        break;
                    }

                    // Read-only tool — safe to loop for another Gemini call
                    continue;
                }

                // No function call — this is the natural-language answer
                finalText = res.text;
                if (String.isNotBlank(finalText)) {
                    history.add(new Map<String, Object>{
                        'role'  => 'model',
                        'parts' => new List<Object>{
                            new Map<String, Object>{ 'text' => finalText }
                        }
                    });
                }
                break;
            }

            if (String.isBlank(finalText)) {
                finalText = 'I ran into an issue forming a reply. Could you rephrase that?';
            }

            ChatTurnResult out = new ChatTurnResult();
            out.reply = finalText;
            out.actionsExecuted = actionsExecuted;
            out.updatedHistory = history;
            return out;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Aria failed to respond: ' + e.getMessage());
        }
    }

    // ════════════════════════════════════════════════════════════
    // PROMPT + TOOL SCHEMA
    // ════════════════════════════════════════════════════════════

    @TestVisible
    private static String buildSystemPrompt(Id recordId) {
        String prompt = ARIA_PERSONA;

        // Inject today's date and the user's timezone so Gemini can resolve
        // natural-language times ("today evening 4 pm", "tomorrow", "next Monday")
        // instead of guessing. Without this, Gemini falls back to whatever
        // date / offset the schema example nudges it toward, and schedules land
        // on the wrong day and/or are treated as UTC.
        TimeZone tz = UserInfo.getTimeZone();
        String tzId = tz.getID();
        DateTime nowUtc = DateTime.now();
        String todayIso  = nowUtc.format('yyyy-MM-dd', tzId);
        String timeIso   = nowUtc.format('HH:mm', tzId);
        String dayOfWeek = nowUtc.format('EEEE', tzId);
        String tzOffset  = currentTzOffsetString();

        prompt += '\n\nCURRENT CONTEXT:'
               +  '\n- Today is ' + todayIso + ' (' + dayOfWeek + ')'
               +  '\n- Current local time: ' + timeIso + ' ' + tzId + ' (offset ' + tzOffset + ')'
               +  '\n- Interpret user phrases like "today", "tomorrow", "this evening", "4 pm" in THIS timezone.'
               +  '\n- For scheduling tools, emit ISO-8601 datetimes WITH the offset above — e.g. '
               +  todayIso + 'T16:00:00' + tzOffset + ' for "today 4 pm". NEVER use Z (UTC).'
               +  '\n- NEVER schedule a site visit or follow-up for a time earlier than the current local time shown above. '
               +  'If the user asks for a past time (e.g. "yesterday", "2 hours ago", or today at a time already passed), '
               +  'politely refuse and ask for a future time instead of calling the scheduling tool.';

        // Always include a compact projects digest — tiny payload, big value
        prompt += '\n\nACTIVE PROJECTS (use these exact names/codes — never invent):\n'
               + JSON.serialize(AriaKnowledgeService.getProjectsDigest());

        // Record-aware context. When recordId is null (Home / App / normal
        // tab placement), skip this block entirely — Aria works as a generic
        // assistant, identical to pre-existing behaviour.
        if (recordId != null) {
            if (String.valueOf(recordId).startsWith(leadKeyPrefix())) {
                // Lead specialisation — includes history + NBA hint.
                Map<String, Object> leadCtx = AriaKnowledgeService.getLeadContext(recordId);
                if (leadCtx != null) {
                    prompt += '\n\nCURRENT LEAD CONTEXT (Aria is opened on this Lead record):\n'
                            + JSON.serialize(leadCtx);
                    Map<String, Object> nba = AriaKnowledgeService.getNextBestAction(recordId);
                    prompt += '\n\nNEXT BEST ACTION HINT: ' + JSON.serialize(nba);
                }
            } else {
                // Generic fallback — works on Booking / Site Visit / Cost Sheet /
                // Project / Unit / any custom object.
                Map<String, Object> ctx = AriaKnowledgeService.getRecordContext(recordId);
                if (ctx != null) {
                    String label = (String) ctx.get('sobject_label');
                    prompt += '\n\nCURRENT ' + (String.isNotBlank(label) ? label.toUpperCase() : 'RECORD')
                            + ' CONTEXT (Aria is opened on this record):\n'
                            + JSON.serialize(ctx);
                }
            }
        }

        return prompt;
    }

    @TestVisible
    private static List<Object> buildToolDeclarations() {
        // Gemini tool schema — subset of JSON Schema. Keep property lists
        // lean so the model doesn't hallucinate required fields.
        List<Object> functions = new List<Object>();

        // —— UNIVERSAL SEARCH (try this FIRST when the user mentions any identifier) ——
        functions.add(new Map<String, Object>{
            'name'        => 'search_everything',
            'description' => 'Search across Leads, Bookings, Cost Sheets, Units and Projects for any identifier the user provides — auto-number names (LD-000466, BK-000123, CS-000045), mobile numbers, emails, project/unit names, or free-text fragments. Always call this BEFORE saying a record cannot be found.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'query' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Any identifier the user mentioned verbatim' }
                },
                'required' => new List<Object>{ 'query' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'find_lead',
            'description' => 'Find a lead by auto-number name (LD-XXXXXX), mobile, email or partial name. Returns full lead context (status, tier, recent follow-ups, site visits, cost sheets).',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'query' => new Map<String, Object>{ 'type' => 'string' }
                },
                'required' => new List<Object>{ 'query' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'search_projects',
            'description' => 'List active real-estate projects with code, city, status and unit counts. Use before discussing any specific project to get the canonical name and code.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>()
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'get_project_details',
            'description' => 'Full detail card for one project (amenities, RERA, price band, possession date).',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'project_id'   => new Map<String, Object>{ 'type' => 'string', 'description' => 'Salesforce Id of the Project__c' },
                    'project_code' => new Map<String, Object>{ 'type' => 'string', 'description' => 'Alternate lookup — Project_Code__c' }
                }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'check_unit_availability',
            'description' => 'List available units for a project optionally filtered by BHK type and budget window.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'project_id'   => new Map<String, Object>{ 'type' => 'string' },
                    'project_code' => new Map<String, Object>{ 'type' => 'string' },
                    'bhk_type'     => new Map<String, Object>{ 'type' => 'string', 'description' => 'One of 1BHK, 2BHK, 3BHK, 4BHK, Studio' },
                    'budget_min'   => new Map<String, Object>{ 'type' => 'number' },
                    'budget_max'   => new Map<String, Object>{ 'type' => 'number' }
                }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'create_lead',
            'description' => 'Create a new lead. Requires project_code, mobile and a name. Runs through the existing dedup matrix.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'first_name'         => new Map<String, Object>{ 'type' => 'string' },
                    'last_name'          => new Map<String, Object>{ 'type' => 'string' },
                    'mobile'             => new Map<String, Object>{ 'type' => 'string' },
                    'email'              => new Map<String, Object>{ 'type' => 'string' },
                    'project_code'       => new Map<String, Object>{ 'type' => 'string' },
                    'bhk_preference'     => new Map<String, Object>{ 'type' => 'string' },
                    'budget_range'       => new Map<String, Object>{ 'type' => 'string' },
                    'purchase_purpose'   => new Map<String, Object>{ 'type' => 'string', 'description' => 'Self-Use / Investment / Rent' },
                    'purchase_timeline'  => new Map<String, Object>{ 'type' => 'string' },
                    'preferred_language' => new Map<String, Object>{ 'type' => 'string' }
                },
                'required' => new List<Object>{ 'mobile', 'project_code' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'schedule_site_visit',
            'description' => 'Schedule a site visit for an existing lead. Uses lead\'s project if project_id not supplied.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'lead_id'      => new Map<String, Object>{ 'type' => 'string' },
                    'project_id'   => new Map<String, Object>{ 'type' => 'string' },
                    'project_code' => new Map<String, Object>{ 'type' => 'string' },
                    'scheduled_at' => new Map<String, Object>{ 'type' => 'string', 'description' => 'ISO-8601 datetime in the user\'s LOCAL timezone with the offset shown in CURRENT CONTEXT (e.g. ' + DateTime.now().format('yyyy-MM-dd', UserInfo.getTimeZone().getID()) + 'T16:00:00' + currentTzOffsetString() + '). NEVER use Z or UTC — use the offset above.' },
                    'mode'         => new Map<String, Object>{ 'type' => 'string', 'description' => 'On Site / Virtual' }
                },
                'required' => new List<Object>{ 'lead_id', 'scheduled_at' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'generate_cost_sheet',
            'description' => 'Draft a cost sheet for a lead + unit with an optional percentage discount on the base price.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'lead_id'           => new Map<String, Object>{ 'type' => 'string' },
                    'unit_id'           => new Map<String, Object>{ 'type' => 'string' },
                    'payment_plan_type' => new Map<String, Object>{ 'type' => 'string' },
                    'discount_percent'  => new Map<String, Object>{ 'type' => 'number' }
                },
                'required' => new List<Object>{ 'lead_id', 'unit_id' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'schedule_followup',
            'description' => 'Create a follow-up task for an existing lead.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'lead_id'  => new Map<String, Object>{ 'type' => 'string' },
                    'due_date' => new Map<String, Object>{ 'type' => 'string', 'description' => 'ISO-8601 datetime in the user\'s LOCAL timezone with the offset shown in CURRENT CONTEXT (e.g. ' + DateTime.now().format('yyyy-MM-dd', UserInfo.getTimeZone().getID()) + 'T10:00:00' + currentTzOffsetString() + ') OR a date-only YYYY-MM-DD. NEVER use Z or UTC.' },
                    'subject'  => new Map<String, Object>{ 'type' => 'string' },
                    'notes'    => new Map<String, Object>{ 'type' => 'string' }
                },
                'required' => new List<Object>{ 'lead_id', 'due_date' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'get_lead_history',
            'description' => 'Fetch recent follow-ups, site visits and cost sheets for a lead.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'lead_id' => new Map<String, Object>{ 'type' => 'string' }
                },
                'required' => new List<Object>{ 'lead_id' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'get_next_best_action',
            'description' => 'Return a rule-based NBA suggestion for a lead — useful for internal sales exec conversations.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'lead_id' => new Map<String, Object>{ 'type' => 'string' }
                },
                'required' => new List<Object>{ 'lead_id' }
            }
        });

        functions.add(fn('get_hot_leads',
            'Returns up to top_n (default 5) of the current user\'s leads ranked by how close they are to booking. Uses cost-sheet stage, site-visit progress, lead-score tier and recency. Call this when the user asks "which leads should I focus on today", "hot leads", "leads to move to booking fast", "who is close to closing". Present the list with each lead\'s next_action so the exec knows exactly what to do.',
            new String[]{ 'top_n' }, null));

        // —— BOOKING FLOW TOOLS ——
        functions.add(new Map<String, Object>{
            'name'        => 'get_booking_status',
            'description' => 'Diagnose exactly what is needed to move a lead to booking. Returns one of: needs_cost_sheet, awaiting_internal_approval, awaiting_customer_acceptance, ready_to_book, already_booked, cost_sheet_not_progressed. Explain the next_action to the user.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'lead_id' => new Map<String, Object>{ 'type' => 'string' }
                },
                'required' => new List<Object>{ 'lead_id' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'initiate_booking',
            'description' => 'Create a Booking from a cost sheet that is in "Accepted by Customer" status. Requires booking_amount (at least the project minimum) and payment_mode (Cash / Cheque / Online). Only call this AFTER confirming the customer has paid and the cost sheet status is ready_to_book.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'cost_sheet_id'   => new Map<String, Object>{ 'type' => 'string' },
                    'booking_amount'  => new Map<String, Object>{ 'type' => 'number' },
                    'payment_mode'    => new Map<String, Object>{ 'type' => 'string' },
                    'transaction_ref' => new Map<String, Object>{ 'type' => 'string' }
                },
                'required' => new List<Object>{ 'cost_sheet_id', 'booking_amount' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'get_payment_schedule',
            'description' => 'Return the payment schedule lines for a booking — useful for explaining EMI / milestone payments.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'booking_id' => new Map<String, Object>{ 'type' => 'string' }
                },
                'required' => new List<Object>{ 'booking_id' }
            }
        });

        functions.add(new Map<String, Object>{
            'name'        => 'block_unit',
            'description' => 'Soft-reserve a unit for a lead while they decide on booking. Default block duration is 7 days. Fails if the unit is not currently Available.',
            'parameters'  => new Map<String, Object>{
                'type' => 'object',
                'properties' => new Map<String, Object>{
                    'lead_id'    => new Map<String, Object>{ 'type' => 'string' },
                    'unit_id'    => new Map<String, Object>{ 'type' => 'string' },
                    'block_days' => new Map<String, Object>{ 'type' => 'number' },
                    'reason'     => new Map<String, Object>{ 'type' => 'string' }
                },
                'required' => new List<Object>{ 'lead_id', 'unit_id' }
            }
        });

        // —— FINANCE CALCULATORS (Phase 2) ——
        functions.add(fn('calculate_emi',
            'Monthly EMI, total interest + total payable. Standard reducing-balance formula.',
            new String[]{ 'principal', 'annual_rate_pct', 'tenure_months' },
            new String[]{ 'principal', 'annual_rate_pct', 'tenure_months' }
        ));
        functions.add(fn('calculate_loan_eligibility',
            'Max home loan from monthly income (FOIR 50%). Optional: existing_emi, annual_rate_pct, tenure_months.',
            new String[]{ 'monthly_income', 'existing_emi', 'annual_rate_pct', 'tenure_months' },
            new String[]{ 'monthly_income' }
        ));
        functions.add(fn('get_cost_breakdown',
            'Itemised unit cost: base + floor rise + PLC + amenity + infra + doc + maintenance + GST + stamp duty + registration = grand total.',
            new String[]{ 'unit_id' },
            new String[]{ 'unit_id' }
        ));

        // —— AGENT METRICS (Phase 2) ——
        functions.add(fn('my_performance',
            'The current user\'s leads, site visits, cost sheets and bookings in the last N days with conversion rate.',
            new String[]{ 'range_days' },
            null
        ));
        functions.add(fn('get_overdue_followups',
            'List of follow-ups past their due date for the current user.',
            new String[]{},
            null
        ));
        functions.add(fn('get_stale_leads',
            'Leads owned by the current user with no activity in the last N days (default 7). Excludes Booked/Lost/Unqualified.',
            new String[]{ 'days' },
            null
        ));
        functions.add(fn('explain_lead_score',
            'Shows the lead\'s score, tier and which scoring rules exist. Helps the exec understand why a lead is Hot/Warm/Cold.',
            new String[]{ 'lead_id' },
            new String[]{ 'lead_id' }
        ));

        // —— ORG WRAPPERS (Phase 3) ——
        functions.add(fn('get_funnel_analysis',
            'Lead-to-Booking conversion funnel (counts + rates per stage). Optionally filter by project_id and range_days.',
            new String[]{ 'project_id', 'range_days' },
            null
        ));
        functions.add(fn('cancel_booking',
            'Cancel a booking and release the unit back to Available. Ask user for the reason before calling.',
            new String[]{ 'booking_id' },
            new String[]{ 'booking_id' }
        ));
        functions.add(fn('raise_complaint',
            'Create a post-sales complaint linked to a booking. Escalation matrix applies automatically.',
            new String[]{ 'booking_id', 'category', 'priority', 'subject', 'description' },
            new String[]{ 'booking_id' }
        ));
        functions.add(fn('get_demand_aging',
            'Outstanding demands aging report by project — buckets by days overdue.',
            new String[]{ 'project_id' },
            new String[]{ 'project_id' }
        ));
        functions.add(fn('get_snag_aging',
            'Snag aging report by project — buckets by days since raised.',
            new String[]{ 'project_id' },
            new String[]{ 'project_id' }
        ));
        functions.add(fn('preview_lead_assignment',
            'Preview which user the next lead will be assigned to via round-robin for a project.',
            new String[]{ 'project_id', 'project_code', 'assignment_type' },
            null
        ));

        return new List<Object>{
            new Map<String, Object>{ 'functionDeclarations' => functions }
        };
    }

    /**
     * @description Helper to build a tool declaration concisely. All properties
     *              are typed as 'string' (Gemini coerces numbers from strings).
     */
    private static Map<String, Object> fn(
        String name, String description, String[] props, String[] required
    ) {
        Map<String, Object> properties = new Map<String, Object>();
        for (String p : props) {
            properties.put(p, new Map<String, Object>{ 'type' => 'string' });
        }
        Map<String, Object> params = new Map<String, Object>{
            'type' => 'object',
            'properties' => properties
        };
        if (required != null && required.size() > 0) {
            params.put('required', required);
        }
        return new Map<String, Object>{
            'name'        => name,
            'description' => description,
            'parameters'  => params
        };
    }

    // ════════════════════════════════════════════════════════════
    // HELPERS
    // ════════════════════════════════════════════════════════════

    /**
     * @description Build a user-facing reply after a write tool has executed,
     *              without calling Gemini again (Apex forbids callouts after
     *              the DML the tool just performed). Uses the tool's own
     *              `message` field — every write tool already returns one.
     */
    private static String synthesiseWriteReply(String toolName, Map<String, Object> result) {
        if (result == null) return 'Action completed.';
        Object err = result.get('error');
        if (err != null && String.isNotBlank(String.valueOf(err))) {
            return 'That didn\'t go through — ' + String.valueOf(err);
        }
        Object msg = result.get('message');
        if (msg != null && String.isNotBlank(String.valueOf(msg))) {
            return String.valueOf(msg);
        }
        // Tool didn't include a message — build a sensible default.
        switch on toolName {
            when 'create_lead'          { return 'Lead created.'; }
            when 'schedule_site_visit'  { return 'Site visit scheduled.'; }
            when 'generate_cost_sheet'  { return 'Cost sheet drafted.'; }
            when 'schedule_followup'    { return 'Follow-up scheduled.'; }
            when 'initiate_booking'     { return 'Booking initiated.'; }
            when 'block_unit'           { return 'Unit blocked.'; }
            when 'cancel_booking'       { return 'Booking cancelled.'; }
            when 'raise_complaint'      { return 'Complaint raised.'; }
            when else                   { return 'Done.'; }
        }
    }

    private static List<Object> parseHistory(String historyJson) {
        if (String.isBlank(historyJson)) {
            return new List<Object>();
        }
        try {
            return (List<Object>) JSON.deserializeUntyped(historyJson);
        } catch (Exception e) {
            return new List<Object>();
        }
    }

    private static String leadKeyPrefix() {
        return Lead__c.SObjectType.getDescribe().getKeyPrefix();
    }

    // Returns the running user's current UTC offset as "+HH:MM" / "-HH:MM".
    // Used both in the system prompt and in tool-schema examples so Gemini
    // emits local times Apex can parse unambiguously.
    @TestVisible
    private static String currentTzOffsetString() {
        Integer offsetMin = UserInfo.getTimeZone().getOffset(DateTime.now()) / (60 * 1000);
        String sign = offsetMin >= 0 ? '+' : '-';
        Integer absMin = Math.abs(offsetMin);
        Integer hh = absMin / 60;
        Integer mm = Math.mod(absMin, 60);
        return sign
             + String.valueOf(hh).leftPad(2, '0')
             + ':'
             + String.valueOf(mm).leftPad(2, '0');
    }
}