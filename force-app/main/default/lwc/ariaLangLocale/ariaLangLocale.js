// Shared mapping from the chatbot's language selector labels to BCP-47
// locale codes used by both SpeechRecognition (voice input) and
// SpeechSynthesis (voice output). Module-only LWC — no template.
const LANG_TO_LOCALE = {
    English:   'en-IN',
    Hindi:     'hi-IN',
    Telugu:    'te-IN',
    Tamil:     'ta-IN',
    Kannada:   'kn-IN',
    Malayalam: 'ml-IN',
    Marathi:   'mr-IN'
};

export { LANG_TO_LOCALE };