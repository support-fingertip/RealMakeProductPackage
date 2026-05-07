import { LightningElement, api, track } from 'lwc';
import sendMessage from '@salesforce/apex/GeminiChatController.sendMessage';

export default class AiChatBot extends LightningElement {

    @api dashboardContext = '';

    @track isChatOpen = false;
    @track messages = [];
    @track userInput = '';
    @track isTyping = false;

    messageIdCounter = 0;

    get showWelcome() {
        return this.messages.length === 0;
    }

    get chatBtnClass() {
        return `chat-floating-btn${this.isChatOpen ? ' chat-floating-btn--active' : ''}`;
    }

    get sendBtnClass() {
        return `send-btn${this.userInput.trim() ? ' send-btn--active' : ''}`;
    }

    get isSendDisabled() {
        return !this.userInput.trim() || this.isTyping;
    }

    toggleChat() {
        this.isChatOpen = !this.isChatOpen;
        if (this.isChatOpen) {
            this.focusInput();
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

    handleChipClick(event) {
        const text = event.currentTarget.dataset.text;
        if (text) {
            this.userInput = text;
            this.handleSendMessage();
        }
    }

    async handleSendMessage() {
        const text = this.userInput.trim();
        if (!text || this.isTyping) return;

        this.addMessage(text, 'user');
        this.userInput = '';
        this.isTyping = true;
        this.scrollToBottom();

        try {
            const history = this.buildConversationHistory();
            const response = await sendMessage({
                userMessage: text,
                conversationHistory: history,
                dashboardContext: this.dashboardContext || ''
            });
            this.addMessage(response, 'ai');
        } catch (error) {
            const errMsg = error?.body?.message || 'Something went wrong. Please try again.';
            this.addMessage(errMsg, 'ai');
        } finally {
            this.isTyping = false;
            this.scrollToBottom();
        }
    }

    addMessage(text, sender) {
        const now = new Date();
        const timestamp = now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        this.messageIdCounter++;

        const isAi = sender === 'ai';

        this.messages = [
            ...this.messages,
            {
                id: `msg-${this.messageIdCounter}`,
                text: text,
                formattedHtml: isAi ? this.formatAiResponse(text) : '',
                sender: sender,
                timestamp: timestamp,
                isAi: isAi,
                isUser: sender === 'user',
                containerClass: `msg-container msg-container--${sender}`,
                bubbleClass: `msg-bubble msg-bubble--${sender}`
            }
        ];
    }

    formatAiResponse(text) {
        if (!text) return '';

        let html = text;

        // Escape HTML entities first
        html = html.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

        // Convert **bold** to <strong>
        html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');

        // Convert *italic* to <em> (but not inside bold)
        html = html.replace(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/g, '<em>$1</em>');

        // Convert ### heading to styled div
        html = html.replace(/^###\s*(.+)$/gm, '<div class="ai-heading">$1</div>');
        html = html.replace(/^##\s*(.+)$/gm, '<div class="ai-heading">$1</div>');

        // Convert numbered lists (1. 2. 3.)
        html = html.replace(/^(\d+)\.\s+(.+)$/gm, '<div class="ai-list-item"><span class="ai-list-num">$1.</span> $2</div>');

        // Convert bullet points (- or * at start of line)
        html = html.replace(/^[-*]\s+(.+)$/gm, '<div class="ai-list-item"><span class="ai-bullet"></span>$1</div>');

        // Convert line breaks to <br>
        html = html.replace(/\n\n/g, '<br><br>');
        html = html.replace(/\n/g, '<br>');

        return html;
    }

    buildConversationHistory() {
        if (this.messages.length === 0) return null;

        const history = this.messages.map(msg => ({
            role: msg.sender === 'user' ? 'user' : 'model',
            parts: [{ text: msg.text }]
        }));

        return JSON.stringify(history);
    }

    scrollToBottom() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const container = this.refs.messageContainer;
            if (container) {
                container.scrollTop = container.scrollHeight;
            }
        }, 100);
    }

    focusInput() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const input = this.refs.chatInput;
            if (input) {
                input.focus();
            }
        }, 300);
    }
}