import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import sendMessage from '@salesforce/apex/AriaChatController.sendMessage';
import submitSiteVisit from '@salesforce/apex/AriaLeadFormController.submitSiteVisit';
import submitFollowup from '@salesforce/apex/AriaLeadFormController.submitFollowup';
import getWelcomeMetrics from '@salesforce/apex/AriaAgentMetricsService.getWelcomeMetrics';
import getLeadMetrics from '@salesforce/apex/AriaAgentMetricsService.getLeadMetrics';
import { LANG_TO_LOCALE } from 'c/ariaLangLocale';

const REVEAL_MIN_CHARS = 40;
const REVEAL_WORD_MS = 60;
const TTS_STORAGE_KEY = 'aria.ttsEnabled';
const VOICE_STORAGE_PREFIX = 'aria.ttsVoice.';
const VOICE_TEST_SAMPLES = {
    English:   'Hello, I am Aria. How can I help you today?',
    Hindi:     'नमस्ते, मैं आरिया हूँ। मैं आपकी कैसे मदद कर सकती हूँ?',
    Telugu:    'హలో, నేను ఆరియా. నేను మీకు ఎలా సహాయం చేయగలను?',
    Tamil:     'வணக்கம், நான் ஆரியா. நான் உங்களுக்கு எப்படி உதவ முடியும்?',
    Kannada:   'ನಮಸ್ಕಾರ, ನಾನು ಆರಿಯಾ. ನಾನು ನಿಮಗೆ ಹೇಗೆ ಸಹಾಯ ಮಾಡಬಹುದು?',
    Malayalam: 'ഹലോ, ഞാൻ ആരിയ. എനിക്ക് നിങ്ങളെ എങ്ങനെ സഹായിക്കാനാകും?',
    Marathi:   'नमस्कार, मी आरिया आहे. मी तुमची कशी मदत करू शकते?'
};

const WELCOME_TEXT =
    "Hi! I'm Aria, your personal property advisor. How can I help today?";

const WRITE_TOOLS = new Set([
    'create_lead', 'schedule_site_visit', 'generate_cost_sheet',
    'schedule_followup', 'initiate_booking', 'block_unit',
    'cancel_booking', 'raise_complaint'
]);

const LANG_OPTIONS = [
    { label: 'English',   value: 'English' },
    { label: 'Hindi',     value: 'Hindi' },
    { label: 'Telugu',    value: 'Telugu' },
    { label: 'Tamil',     value: 'Tamil' },
    { label: 'Kannada',   value: 'Kannada' },
    { label: 'Malayalam', value: 'Malayalam' },
    { label: 'Marathi',   value: 'Marathi' }
];

export default class AriaChatBot extends NavigationMixin(LightningElement) {

    // Auto-set when the LWC is dropped on a Lead record page.
    @api recordId;

    // Admin-configurable via App Manager when adding Aria as a Utility Item.
    // When true: no floating launcher, panel is always visible, fills the
    // utility-bar popup instead of floating.
    @api isInUtilityBar = false;

    @track isChatOpen = false;
    @track messages = [];
    @track userInput = '';
    @track isTyping = false;
    @track showWelcomeActions = true;

    // Modal flags
    @track preferredLanguage = 'English';
    @track welcomeMetrics = null;
    @track leadMetrics = null;

    @track showLeadForm = false;
    @track showSiteVisitForm = false;
    @track showFollowupForm = false;

    @track isVoiceRecording = false;
    @track ttsEnabled = false;
    @track isVoicePickerOpen = false;
    @track selectedVoiceName = '';

    // Site visit mini-form state
    @track svScheduledAt = '';
    @track svMode = 'On Site';
    @track svIsSubmitting = false;
    @track svError = '';

    // Follow-up mini-form state
    @track fuDueAt = '';
    @track fuSubject = 'Follow-up call';
    @track fuNotes = '';
    @track fuIsSubmitting = false;
    @track fuError = '';

    // Gemini wire-format history (separate from UI messages so server gets accurate tool history)
    geminiHistory = [];
    messageIdCounter = 0;

    // Active word-by-word reveal timers, keyed by message id.
    _revealTimers = {};

    // Cached list of SpeechSynthesis voices. Browsers populate this
    // asynchronously — see _loadVoices() for the voiceschanged hook.
    _voices = [];

    // ════════════════════════════════════════════════════════════
    // Lifecycle
    // ════════════════════════════════════════════════════════════

    connectedCallback() {
        try {
            this.ttsEnabled = localStorage.getItem(TTS_STORAGE_KEY) === '1';
        } catch (e) { /* storage may be blocked — fall back to default off */ }

        this._loadVoices();

        // In utility-bar mode the chat has no launcher — it's always open.
        if (this.isInUtilityBar) {
            this.isChatOpen = true;
        }

        if (this.recordId) {
            // Lead-only metrics; if the record isn't a Lead the Apex method
            // returns null and we fall back to the personal workload view.
            this._loadLeadMetrics(/* initialGreeting */ true);
        } else {
            if (this.messages.length === 0) {
                this._pushUi(WELCOME_TEXT, 'ai');
            }
            this._loadWelcomeMetrics();
        }
    }

    async _loadWelcomeMetrics() {
        try {
            this.welcomeMetrics = await getWelcomeMetrics();
        } catch (e) {
            this.welcomeMetrics = null;
        }
    }

    async _loadLeadMetrics(initialGreeting) {
        try {
            const m = await getLeadMetrics({ leadId: this.recordId });
            if (m) {
                this.leadMetrics = m;
                if (initialGreeting && this.messages.length === 0) {
                    this._pushUi(this._buildLeadGreeting(m), 'ai');
                }
            } else {
                // Not a Lead record — fall back to personal metrics.
                if (initialGreeting && this.messages.length === 0) {
                    this._pushUi(WELCOME_TEXT, 'ai');
                }
                this._loadWelcomeMetrics();
            }
        } catch (e) {
            this.leadMetrics = null;
            if (initialGreeting && this.messages.length === 0) {
                this._pushUi(WELCOME_TEXT, 'ai');
            }
            this._loadWelcomeMetrics();
        }
    }

    _buildLeadGreeting(m) {
        const name = m.full_name || m.lead_name || 'this lead';
        const suggestion = m.readiness && m.readiness.suggestion;
        if (suggestion) {
            return `Ready to help with ${name}. ${suggestion}`;
        }
        return `Ready to help with ${name}. What would you like to do?`;
    }

    _refreshMetrics() {
        if (this.recordId && this.leadMetrics) {
            this._loadLeadMetrics(/* initialGreeting */ false);
        } else {
            this._loadWelcomeMetrics();
        }
    }

    get languageOptions() { return LANG_OPTIONS; }
    get hasWelcomeMetrics() { return !this.leadMetrics && this.welcomeMetrics != null; }
    get hasLeadMetrics() { return this.leadMetrics != null; }

    // ════════════════════════════════════════════════════════════
    // Getters
    // ════════════════════════════════════════════════════════════

    get panelTitle() {
        return 'Aria';
    }

    get panelSubtitle() {
        return this.recordId
            ? 'Context-aware guidance on this lead'
            : 'Ask about projects, units, bookings';
    }

    get chatBtnClass() {
        return `aria-floating-btn${this.isChatOpen ? ' aria-floating-btn--active' : ''}`;
    }

    get panelClass() {
        return this.isInUtilityBar ? 'aria-panel aria-panel--utility' : 'aria-panel';
    }

    get showFloatingLauncher() {
        return !this.isInUtilityBar;
    }

    get sendBtnClass() {
        return `aria-send-btn${this.userInput.trim() ? ' aria-send-btn--active' : ''}`;
    }

    get isSendDisabled() {
        return !this.userInput.trim() || this.isTyping;
    }

    get welcomeActions() {
        const acts = [
            { id: 'a-lead', kind: 'lead',     label: 'Create New Lead',
              hint: 'Guided form — pick state, project, BHK, budget' }
        ];
        if (this.recordId) {
            acts.push({ id: 'a-sv', kind: 'sitevisit', label: 'Schedule Site Visit',
                        hint: 'Pick a date and mode' });
            acts.push({ id: 'a-fu', kind: 'followup',  label: 'Schedule Follow-up',
                        hint: 'Pick a due date and notes' });
            acts.push({ id: 'a-info', kind: 'info', label: 'Suggestions for this Lead',
                        hint: 'Ask Aria for the next best action' });
        } else {
            acts.push({ id: 'a-info', kind: 'info', label: 'Get Information',
                        hint: 'Ask about projects, units or pricing' });
        }
        return acts;
    }

    // ════════════════════════════════════════════════════════════
    // Action button handlers
    // ════════════════════════════════════════════════════════════

    handleActionButtonClick(event) {
        const kind = event.currentTarget.dataset.kind;
        switch (kind) {
            case 'lead':
                this.showLeadForm = true;
                break;
            case 'sitevisit':
                this._resetSiteVisitForm();
                this.showSiteVisitForm = true;
                break;
            case 'followup':
                this._resetFollowupForm();
                this.showFollowupForm = true;
                break;
            case 'info':
                this.showWelcomeActions = false;
                if (this.recordId) {
                    // On Lead pages, ask for NBA right away
                    this.userInput = "What's the next best action for this lead?";
                    this.handleSendMessage();
                } else {
                    this._focusInput();
                }
                break;
            default:
                break;
        }
    }

    // ════════════════════════════════════════════════════════════
    // Lead form (modal child component)
    // ════════════════════════════════════════════════════════════

    handleLeadFormCancel() {
        this.showLeadForm = false;
    }

    handleLeadFormCreated(event) {
        this.showLeadForm = false;
        this.showWelcomeActions = false;
        const { leadId, action, message } = event.detail;
        this._pushUi(`✓ ${message || 'Lead created'} (${action})`, 'ai');
        if (leadId) {
            this._pushAction({ label: 'Open Lead', detail: 'View the new lead record', recordId: leadId });
        }
    }

    // ════════════════════════════════════════════════════════════
    // Site Visit mini-form (inline)
    // ════════════════════════════════════════════════════════════

    get visitModeOptions() {
        return [
            { label: 'On Site',  value: 'On Site'  },
            { label: 'Virtual',  value: 'Virtual'  }
        ];
    }
    handleSvDateChange(event)  { this.svScheduledAt = event.target.value; }
    handleSvModeChange(event)  { this.svMode = event.detail.value; }
    handleSvCancel()           { this.showSiteVisitForm = false; }

    async handleSvSubmit() {
        if (!this.svScheduledAt) {
            this.svError = 'Please pick a date and time.';
            return;
        }
        this.svIsSubmitting = true;
        this.svError = '';
        try {
            const r = await submitSiteVisit({
                leadId: this.recordId,
                projectId: null,                 // service falls back to lead's project
                scheduledIso: new Date(this.svScheduledAt).toISOString(),
                mode: this.svMode
            });
            this.showSiteVisitForm = false;
            this.showWelcomeActions = false;
            this._pushUi(`✓ ${r.message || 'Site visit scheduled'}`, 'ai');
            if (r.site_visit_id) {
                this._pushAction({ label: 'Open Site Visit', detail: 'View the new site visit', recordId: r.site_visit_id });
            }
        } catch (e) {
            this.svError = this._formatError(e);
        } finally {
            this.svIsSubmitting = false;
        }
    }

    _resetSiteVisitForm() {
        this.svScheduledAt = '';
        this.svMode = 'On Site';
        this.svError = '';
    }

    // ════════════════════════════════════════════════════════════
    // Follow-up mini-form (inline)
    // ════════════════════════════════════════════════════════════

    handleFuDateChange(event)    { this.fuDueAt = event.target.value; }
    handleFuSubjectChange(event) { this.fuSubject = event.target.value; }
    handleFuNotesChange(event)   { this.fuNotes = event.target.value; }
    handleFuCancel()             { this.showFollowupForm = false; }

    async handleFuSubmit() {
        if (!this.fuDueAt) {
            this.fuError = 'Please pick a due date.';
            return;
        }
        this.fuIsSubmitting = true;
        this.fuError = '';
        try {
            const r = await submitFollowup({
                leadId: this.recordId,
                dueIso: new Date(this.fuDueAt).toISOString(),
                subject: this.fuSubject,
                notes: this.fuNotes
            });
            this.showFollowupForm = false;
            this.showWelcomeActions = false;
            this._pushUi(`✓ ${r.message || 'Follow-up scheduled'}`, 'ai');
            if (r.followup_id) {
                this._pushAction({ label: 'Open Follow-up', detail: 'View the new follow-up', recordId: r.followup_id });
            }
        } catch (e) {
            this.fuError = this._formatError(e);
        } finally {
            this.fuIsSubmitting = false;
        }
    }

    _resetFollowupForm() {
        this.fuDueAt = '';
        this.fuSubject = 'Follow-up call';
        this.fuNotes = '';
        this.fuError = '';
    }

    // ════════════════════════════════════════════════════════════
    // Chat
    // ════════════════════════════════════════════════════════════

    toggleChat() {
        this.isChatOpen = !this.isChatOpen;
        if (this.isChatOpen) {
            this._focusInput();
        } else {
            this._cancelSpeech();
            this._cancelAllReveals();
        }
    }

    handleLanguageChange(event) {
        this.preferredLanguage = event.target.value;
        // If the voice picker is open, refresh it for the new language's
        // saved preference so Play test / Save target the right language.
        if (this.isVoicePickerOpen) {
            this.selectedVoiceName = this._getSavedVoiceName(this.preferredLanguage) || '';
        }
    }

    handleTtsToggle() {
        this.ttsEnabled = !this.ttsEnabled;
        try {
            localStorage.setItem(TTS_STORAGE_KEY, this.ttsEnabled ? '1' : '0');
        } catch (e) { /* ignore */ }
        if (!this.ttsEnabled) {
            this._cancelSpeech();
            this.isVoicePickerOpen = false;
        }
    }

    get ttsBtnClass() {
        return this.ttsEnabled
            ? 'aria-tts-btn aria-tts-btn--on'
            : 'aria-tts-btn';
    }

    get ttsBtnTitle() {
        return this.ttsEnabled ? 'Disable voice output' : 'Enable voice output';
    }

    // ─── Voice picker ──────────────────────────────────────────

    handleGearClick() {
        // Open the popover and seed selectedVoiceName from the saved preference
        // for the current language (empty string = Auto).
        this.selectedVoiceName = this._getSavedVoiceName(this.preferredLanguage) || '';
        this.isVoicePickerOpen = !this.isVoicePickerOpen;
    }

    handleVoicePickerClose() {
        this.isVoicePickerOpen = false;
    }

    // Stops clicks inside the popover from bubbling to outside-click handlers.
    handleVoicePickerInsideClick(event) {
        event.stopPropagation();
    }

    handleVoiceSelect(event) {
        this.selectedVoiceName = event.target.value || '';
    }

    handleVoiceTest() {
        const sample = VOICE_TEST_SAMPLES[this.preferredLanguage] || VOICE_TEST_SAMPLES.English;
        const locale = LANG_TO_LOCALE[this.preferredLanguage] || 'en-IN';
        try {
            if (!window.speechSynthesis) return;
            window.speechSynthesis.cancel();
            const u = new SpeechSynthesisUtterance(sample);
            u.lang = locale;
            // Explicitly use the voice currently selected in the picker
            // (not the saved one) so Play test previews the pending choice.
            const voice = this._findVoiceByName(this.selectedVoiceName)
                       || this._pickVoice(locale);
            if (voice) u.voice = voice;
            u.rate = 1.0;
            u.pitch = 1.05;
            window.speechSynthesis.speak(u);
        } catch (e) { /* ignore */ }
    }

    handleVoicePickerSave() {
        this._setSavedVoiceName(this.preferredLanguage, this.selectedVoiceName);
        this.isVoicePickerOpen = false;
    }

    get voiceOptions() {
        // Voices whose lang prefix matches the currently selected language.
        const locale = LANG_TO_LOCALE[this.preferredLanguage] || 'en-IN';
        const lang = locale.toLowerCase().split('-')[0];
        const matches = (this._voices || []).filter(v => {
            const vl = (v.lang || '').toLowerCase();
            return vl === lang || vl.startsWith(lang + '-') || vl.startsWith(lang + '_');
        });
        return matches.map(v => ({
            name: v.name,
            label: `${v.name} (${v.lang})`
        }));
    }

    get voicePickerHasVoices() {
        return this.voiceOptions.length > 0;
    }

    _getSavedVoiceName(langLabel) {
        try {
            return localStorage.getItem(VOICE_STORAGE_PREFIX + langLabel) || '';
        } catch (e) { return ''; }
    }

    _setSavedVoiceName(langLabel, voiceName) {
        try {
            if (voiceName) {
                localStorage.setItem(VOICE_STORAGE_PREFIX + langLabel, voiceName);
            } else {
                localStorage.removeItem(VOICE_STORAGE_PREFIX + langLabel);
            }
        } catch (e) { /* ignore */ }
    }

    _findVoiceByName(name) {
        if (!name || !this._voices) return null;
        return this._voices.find(v => v.name === name) || null;
    }

    handleTileClick(event) {
        const key = event.currentTarget.dataset.tile;
        const queries = {
            // Welcome dashboard (no recordId)
            overdue_followups: 'Show my overdue follow-ups.',
            visits_today:      'What site visits do I have today?',
            new_leads:         'Show the leads I created today.',
            stale_leads:       'Which of my leads are stale?',
            // Lead dashboard (on Lead record page)
            lead_followups:    "Show this lead's follow-ups.",
            lead_site_visits:  "Show this lead's site visits.",
            lead_cost_sheets:  "Show this lead's cost sheets.",
            lead_bookings:     "Show this lead's bookings."
        };
        const q = queries[key];
        if (q) {
            this.userInput = q;
            this.handleSendMessage();
        }
    }

    handleChipClick(event) {
        const text = event.currentTarget.dataset.text;
        if (text) {
            this.userInput = text;
            this.handleSendMessage();
        }
    }

    handleInputChange(event) {
        this.userInput = event.target.value;
    }

    handleKeyPress(event) {
        if (event.key === 'Enter' && !this.isSendDisabled) {
            this.handleSendMessage();
        }
    }

    handleTranscribed(event) {
        const text = (event.detail && event.detail.text || '').trim();
        if (!text) return;
        this.userInput = text;
        // Defer focus until after LWC remounts the text input (hidden while recording).
        setTimeout(() => {
            const input = this.refs && this.refs.chatInput;
            if (input && typeof input.focus === 'function') input.focus();
        }, 0);
    }

    handleVoiceError(event) {
        const msg = event.detail && event.detail.message;
        if (msg) this._pushUi(msg, 'ai');
    }

    handleVoiceStateChange(event) {
        this.isVoiceRecording = !!(event.detail && event.detail.isRecording);
        if (this.isVoiceRecording) {
            // Don't talk over the user while they're dictating.
            this._cancelSpeech();
            this._cancelAllReveals();
        }
    }

    get isNotVoiceRecording() {
        return !this.isVoiceRecording;
    }

    handleOpenRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
    }

    async handleSendMessage() {
        const text = this.userInput.trim();
        if (!text || this.isTyping) return;

        this._cancelSpeech();
        this._cancelAllReveals();

        this.showWelcomeActions = false;
        this._pushUi(text, 'user');
        this.userInput = '';
        this.isTyping = true;
        this._scrollToBottom();

        try {
            const response = await sendMessage({
                userMessage: text,
                conversationHistoryJson: JSON.stringify(this.geminiHistory),
                recordId: this.recordId || null,
                preferredLanguage: this.preferredLanguage || 'English'
            });

            if (response.updatedHistory) {
                this.geminiHistory = response.updatedHistory;
            }

            this._pushUi(response.reply, 'ai');

            if (Array.isArray(response.actionsExecuted) && response.actionsExecuted.length) {
                let didWrite = false;
                for (const act of response.actionsExecuted) {
                    if (act && act.tool === 'get_hot_leads' && act.result && Array.isArray(act.result.leads) && act.result.leads.length) {
                        this._pushHotLeadsList(act.result.leads);
                        continue;
                    }
                    const card = this._buildActionCard(act);
                    if (card) this._pushAction(card);
                    if (act && WRITE_TOOLS.has(act.tool)) didWrite = true;
                }
                if (didWrite) this._refreshMetrics();
            }
        } catch (error) {
            const errMsg = (error && error.body && error.body.message) || 'Something went wrong. Please try again.';
            this._pushUi(errMsg, 'ai');
        } finally {
            this.isTyping = false;
            this._scrollToBottom();
        }
    }

    // ════════════════════════════════════════════════════════════
    // Internal helpers
    // ════════════════════════════════════════════════════════════

    _pushUi(text, sender) {
        if (!text) return;
        this.messageIdCounter += 1;
        const id = `msg-${this.messageIdCounter}`;
        const now = new Date();
        const timestamp = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

        // Parse CHOICES: [opt1 | opt2 | opt3] for quick-reply chips (AI only)
        let displayText = text;
        let chips = [];
        if (sender === 'ai') {
            const choicesMatch = text.match(/CHOICES:\s*\[([^\]]+)\]/i);
            if (choicesMatch) {
                displayText = text.replace(choicesMatch[0], '').trim();
                chips = choicesMatch[1].split('|').map((c, i) => ({
                    id: `chip-${this.messageIdCounter}-${i}`,
                    text: c.trim()
                }));
            }
        }

        const shouldReveal = sender === 'ai'
            && displayText.length > REVEAL_MIN_CHARS
            && !this._prefersReducedMotion();

        this.messages = [
            ...this.messages,
            {
                id,
                text: displayText,
                displayedText: shouldReveal ? '' : displayText,
                sender,
                timestamp,
                isAi: sender === 'ai',
                isUser: sender === 'user',
                isAction: false,
                hasChips: chips.length > 0,
                chips,
                containerClass: `aria-msg-container aria-msg-container--${sender}`,
                bubbleClass: `aria-msg-bubble aria-msg-bubble--${sender}`
            }
        ];

        if (shouldReveal) {
            this._revealMessage(id, displayText);
        }
        // Only speak once the user has actually opened the chat — avoids
        // the welcome greeting blurting out on page load.
        if (sender === 'ai' && this.isChatOpen) {
            this._speak(displayText);
        }
    }

    _pushAction(card) {
        this.messageIdCounter += 1;
        this.messages = [
            ...this.messages,
            {
                id: `msg-${this.messageIdCounter}`,
                sender: 'action',
                isAi: false,
                isUser: false,
                isAction: true,
                containerClass: 'aria-msg-container aria-msg-container--action',
                bubbleClass: 'aria-action-card',
                actionLabel: card.label,
                actionDetail: card.detail,
                actionRecordId: card.recordId
            }
        ];
    }

    _pushHotLeadsList(leads) {
        this.messageIdCounter += 1;
        const rows = leads.map((l, i) => ({
            rowId: `hotlead-${this.messageIdCounter}-${i}`,
            leadId: l.lead_id,
            title: l.full_name || l.lead_name || l.lead_id,
            subtitle: [l.project, l.lead_status].filter(Boolean).join(' · '),
            nextAction: (l.next_action || '').replace(/_/g, ' '),
            suggestion: l.suggestion || '',
            tier: l.tier || ''
        }));
        this.messages = [
            ...this.messages,
            {
                id: `msg-${this.messageIdCounter}`,
                sender: 'action',
                isAi: false,
                isUser: false,
                isAction: false,
                isHotLeadsList: true,
                hotLeads: rows,
                containerClass: 'aria-msg-container aria-msg-container--action',
                bubbleClass: 'aria-action-card'
            }
        ];
    }

    _buildActionCard(act) {
        if (!act || !act.result) return null;
        const r = act.result;
        if (r.error) return null;

        switch (act.tool) {
            case 'create_lead':
                return r.lead_id ? { label: 'Open Lead', detail: r.message || 'Lead created', recordId: r.lead_id } : null;
            case 'schedule_site_visit':
                return r.site_visit_id ? { label: 'Open Site Visit', detail: r.message || 'Site visit scheduled', recordId: r.site_visit_id } : null;
            case 'generate_cost_sheet':
                return r.cost_sheet_id ? { label: 'Open Cost Sheet', detail: r.message || 'Cost sheet drafted', recordId: r.cost_sheet_id } : null;
            case 'schedule_followup':
                return r.followup_id ? { label: 'Open Follow-up', detail: r.message || 'Follow-up scheduled', recordId: r.followup_id } : null;
            default:
                return null;
        }
    }

    _scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const container = this.refs.messageContainer;
            if (container) container.scrollTop = container.scrollHeight;
        }, 80);
    }

    // ─── Progressive-reveal helpers ─────────────────────────────

    _prefersReducedMotion() {
        try {
            return window.matchMedia
                && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        } catch (e) {
            return false;
        }
    }

    _revealMessage(id, fullText) {
        // Split on whitespace, KEEPING separators so word boundaries render
        // correctly when we slice. words[] interleaves tokens and whitespace.
        const tokens = fullText.split(/(\s+)/);
        let idx = 0;
        let shown = '';
        const tick = () => {
            if (!this._revealTimers[id]) return; // cancelled
            if (idx >= tokens.length) {
                this._finalizeReveal(id, fullText);
                return;
            }
            shown += tokens[idx];
            idx += 1;
            this._updateMessageDisplayedText(id, shown);
            const container = this.refs && this.refs.messageContainer;
            if (container) container.scrollTop = container.scrollHeight;
            // Skip the timer delay on whitespace-only tokens so the next word
            // appears without a visible extra pause.
            const nextDelay = /^\s+$/.test(tokens[idx - 1]) ? 0 : REVEAL_WORD_MS;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._revealTimers[id] = setTimeout(tick, nextDelay);
        };
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._revealTimers[id] = setTimeout(tick, 0);
    }

    _finalizeReveal(id, fullText) {
        if (this._revealTimers[id]) {
            clearTimeout(this._revealTimers[id]);
            delete this._revealTimers[id];
        }
        this._updateMessageDisplayedText(id, fullText);
    }

    _cancelAllReveals() {
        const ids = Object.keys(this._revealTimers);
        for (const id of ids) {
            clearTimeout(this._revealTimers[id]);
            delete this._revealTimers[id];
            const msg = this.messages.find(m => m.id === id);
            if (msg) this._updateMessageDisplayedText(id, msg.text);
        }
    }

    _updateMessageDisplayedText(id, text) {
        this.messages = this.messages.map(m =>
            m.id === id ? { ...m, displayedText: text } : m
        );
    }

    // ─── Text-to-speech helpers ────────────────────────────────

    _speak(text) {
        if (!this.ttsEnabled || !text) return;
        if (typeof window === 'undefined' || !window.speechSynthesis) return;
        try {
            window.speechSynthesis.cancel();
            const u = new SpeechSynthesisUtterance(text);
            const locale = LANG_TO_LOCALE[this.preferredLanguage] || 'en-IN';
            u.lang = locale;
            const voice = this._pickVoice(locale);
            if (voice) u.voice = voice;
            u.rate = 1.0;
            // Slight pitch lift makes any voice land a touch more feminine
            // for devices that have no explicit female voice installed.
            u.pitch = 1.05;
            window.speechSynthesis.speak(u);
        } catch (e) { /* TTS should never break chat */ }
    }

    _cancelSpeech() {
        try {
            if (window.speechSynthesis) window.speechSynthesis.cancel();
        } catch (e) { /* ignore */ }
    }

    // Loads installed SpeechSynthesis voices. Chrome/Edge populate this
    // asynchronously, so we refresh on the voiceschanged event.
    _loadVoices() {
        if (typeof window === 'undefined' || !window.speechSynthesis) return;
        const synth = window.speechSynthesis;
        const refresh = () => {
            try { this._voices = synth.getVoices() || []; }
            catch (e) { /* ignore */ }
        };
        refresh();
        try {
            if (typeof synth.addEventListener === 'function') {
                synth.addEventListener('voiceschanged', refresh);
            } else {
                synth.onvoiceschanged = refresh;
            }
        } catch (e) { /* ignore */ }
    }

    // Picks the best available voice for the requested BCP-47 locale,
    // preferring voices that sound female. Priority order:
    //   1. exact-locale female    2. exact-locale any
    //   3. lang-prefix female     4. lang-prefix any
    //   5. any female             6. whatever is available
    _pickVoice(locale) {
        const voices = this._voices;
        if (!voices || !voices.length) return null;

        // User's explicit choice wins — if it's still installed.
        const savedName = this._getSavedVoiceName(this.preferredLanguage);
        if (savedName) {
            const saved = this._findVoiceByName(savedName);
            if (saved) return saved;
        }

        const loc  = (locale || 'en-IN').toLowerCase();
        const lang = loc.split('-')[0];

        // Heuristic: these substrings appear in female-voice names across
        // Windows (Zira/Heera/Hazel/Susan), macOS (Samantha/Karen/Tessa/
        // Fiona/Moira/Veena), Google (UK/US Female, Indian English female),
        // and ChromeOS/Android (Kalpana/Leela/Sowmya/Amala/etc.).
        const femaleRe = /female|woman|samantha|heera|zira|susan|hazel|tessa|fiona|moira|karen|veena|kalpana|leela|sowmya|amala|priya|divya|aarti|pallavi|anjali|isha|amy|joanna|salli|ivy|kendra|google uk english female|google us english/i;

        const byLocale = voices.filter(v => (v.lang || '').toLowerCase() === loc);
        const byLang = voices.filter(v => {
            const vl = (v.lang || '').toLowerCase();
            return vl === lang || vl.startsWith(lang + '-') || vl.startsWith(lang + '_');
        });

        const female = (pool) => pool.find(v => femaleRe.test(v.name || ''));

        return female(byLocale)
            || byLocale[0]
            || female(byLang)
            || byLang[0]
            || female(voices)
            || voices[0]
            || null;
    }

    _focusInput() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const input = this.refs.chatInput;
            if (input) input.focus();
        }, 250);
    }

    _formatError(e) {
        if (!e) return 'Something went wrong.';
        if (e.body && e.body.message) return e.body.message;
        if (e.message) return e.message;
        return JSON.stringify(e);
    }
}