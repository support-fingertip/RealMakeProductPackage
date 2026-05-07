import { LightningElement, api, track } from 'lwc';
import { LANG_TO_LOCALE } from 'c/ariaLangLocale';

const MAX_RECORDING_MS = 60000;

export default class AriaVoiceInput extends LightningElement {

    @api preferredLanguage = 'English';
    @api disabled = false;

    @track state = 'idle';
    @track errorMessage = '';
    @track elapsedLabel = '0:00';

    _recognition = null;
    _timeoutId = null;
    _tickId = null;
    _recordStartedAt = 0;
    _finalTranscript = '';
    _cancelled = false;

    get isSupported() {
        if (typeof window === 'undefined') return false;
        const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
        return typeof SR === 'function';
    }

    get isListening() {
        return this.state === 'listening';
    }

    get isButtonDisabled() {
        return this.disabled || !this.isSupported;
    }

    get buttonClass() {
        const base = 'aria-mic-btn';
        if (this.isButtonDisabled) return `${base} ${base}--disabled`;
        return `${base} ${base}--idle`;
    }

    get buttonTitle() {
        if (!this.isSupported) return 'Voice input not supported in this browser';
        return 'Start voice input';
    }

    get hasError() {
        return this.state === 'error' && !!this.errorMessage;
    }

    handleMicClick(event) {
        event.preventDefault();
        event.stopPropagation();
        if (!this.isSupported) {
            this._emitError('Voice input is not supported in this browser.');
            return;
        }
        this._start();
    }

    handleConfirm(event) {
        event.preventDefault();
        event.stopPropagation();
        this._stop();
    }

    handleCancel(event) {
        event.preventDefault();
        event.stopPropagation();
        this._cancelled = true;
        this._finalTranscript = '';
        if (this._recognition) {
            try { this._recognition.abort(); } catch (e) { /* swallow */ }
        }
        this._clearTimers();
    }

    _start() {
        const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!SR) {
            this._emitError('Voice input is not supported in this browser.');
            return;
        }

        this._finalTranscript = '';
        this._cancelled = false;
        const rec = new SR();
        rec.lang = LANG_TO_LOCALE[this.preferredLanguage] || 'en-IN';
        // continuous=true so a short silence (thinking pause, breath) does not
        // end the session. Recording now stops only on confirm / cancel click
        // or when MAX_RECORDING_MS is reached.
        rec.continuous = true;
        rec.interimResults = false;
        rec.maxAlternatives = 1;

        rec.onresult = (evt) => {
            let transcript = '';
            for (let i = evt.resultIndex; i < evt.results.length; i++) {
                const r = evt.results[i];
                if (r.isFinal) transcript += r[0].transcript;
            }
            if (transcript) {
                this._finalTranscript = (this._finalTranscript + ' ' + transcript).trim();
            }
        };

        rec.onerror = (evt) => {
            this._clearTimers();
            this._recognition = null;
            const code = evt && evt.error;
            if (code === 'aborted') {
                this._setState('idle');
                return;
            }
            this._emitError(this._describeError(code));
        };

        rec.onend = () => {
            this._clearTimers();
            const text = (this._finalTranscript || '').trim();
            const wasCancelled = this._cancelled;
            this._recognition = null;
            this._cancelled = false;
            if (this.state !== 'error') {
                this._setState('idle');
            }
            if (!wasCancelled && text) {
                this.dispatchEvent(new CustomEvent('transcribed', { detail: { text } }));
            }
        };

        try {
            rec.start();
            this._recognition = rec;
            this._recordStartedAt = Date.now();
            this.elapsedLabel = '0:00';
            this.errorMessage = '';
            this._setState('listening');
            this._timeoutId = setTimeout(() => this._stop(), MAX_RECORDING_MS);
            this._tickId = setInterval(() => this._tick(), 1000);
        } catch (err) {
            this._recognition = null;
            this._emitError((err && err.message) || 'Could not start voice input.');
        }
    }

    _stop() {
        if (this._recognition) {
            try { this._recognition.stop(); } catch (e) { /* swallow */ }
        }
        this._clearTimers();
    }

    _tick() {
        const ms = Date.now() - this._recordStartedAt;
        const totalSec = Math.floor(ms / 1000);
        const mm = Math.floor(totalSec / 60);
        const ss = totalSec % 60;
        this.elapsedLabel = `${mm}:${ss < 10 ? '0' : ''}${ss}`;
    }

    _clearTimers() {
        if (this._timeoutId) {
            clearTimeout(this._timeoutId);
            this._timeoutId = null;
        }
        if (this._tickId) {
            clearInterval(this._tickId);
            this._tickId = null;
        }
    }

    _setState(next) {
        const wasListening = this.state === 'listening';
        const nowListening = next === 'listening';
        this.state = next;
        if (wasListening !== nowListening) {
            this.dispatchEvent(new CustomEvent('statechange', {
                detail: { isRecording: nowListening }
            }));
        }
    }

    _emitError(message) {
        const wasListening = this.state === 'listening';
        this.state = 'error';
        this.errorMessage = message;
        if (wasListening) {
            this.dispatchEvent(new CustomEvent('statechange', { detail: { isRecording: false } }));
        }
        this.dispatchEvent(new CustomEvent('voiceerror', { detail: { message } }));
    }

    _describeError(code) {
        switch (code) {
            case 'not-allowed':
            case 'service-not-allowed':
                return 'Microphone access denied. Allow mic access in your browser to use voice input.';
            case 'no-speech':
                return 'No speech detected. Please try again.';
            case 'audio-capture':
                return 'No microphone found on this device.';
            case 'network':
                return 'Network error during voice recognition.';
            default:
                return code ? `Voice input error: ${code}` : 'Voice input failed.';
        }
    }

    disconnectedCallback() {
        this._cancelled = true;
        this._stop();
    }
}