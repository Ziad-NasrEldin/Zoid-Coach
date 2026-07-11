let sanitizedWhatsAppMeetingEvaluationJSON = #"""
{
  "thresholds": { "minimumPrecision": 0.85, "minimumRecall": 0.85 },
  "cases": [
    { "id": "light-english-direct", "appearance": "light", "language": "english", "conversation": "direct", "messageShape": "plain", "text": "Meet with Alex tomorrow at 4 PM for 45 minutes. Location: Studio 2", "expectsCandidate": true, "expectsClarification": false },
    { "id": "dark-english-call-link", "appearance": "dark", "language": "english", "conversation": "direct", "messageShape": "plain", "text": "Planning meeting Tuesday at 10:30 AM for 30 minutes https://meet.example.test/sanitized", "expectsCandidate": true, "expectsClarification": false },
    { "id": "light-arabic-direct", "appearance": "light", "language": "arabic", "conversation": "direct", "messageShape": "plain", "text": "خلينا نتقابل بكرة الساعة ٣:٣٠ م لمدة ٤٥ دقيقة", "expectsCandidate": true, "expectsClarification": false },
    { "id": "dark-arabic-group", "appearance": "dark", "language": "arabic", "conversation": "group", "messageShape": "plain", "text": "فريق المشروع: اجتماع الخميس الساعة ١١:٠٠ ص لمدة ٣٠ دقيقة", "expectsCandidate": true, "expectsClarification": false },
    { "id": "light-english-group", "appearance": "light", "language": "english", "conversation": "group", "messageShape": "plain", "text": "Project group: Meet with Noor and Sam Friday at 2 PM for 1 hour.", "expectsCandidate": true, "expectsClarification": false },
    { "id": "dark-english-quoted", "appearance": "dark", "language": "english", "conversation": "direct", "messageShape": "quoted", "text": "Quoted: Can we meet tomorrow at 9 AM? Reply: Yes, that works.", "expectsCandidate": true, "expectsClarification": false },
    { "id": "light-arabic-quoted", "appearance": "light", "language": "arabic", "conversation": "group", "messageShape": "quoted", "text": "رسالة مقتبسة: موعد بكرة الساعة ٢ م لمدة ٦٠ دقيقة. الرد: مناسب.", "expectsCandidate": true, "expectsClarification": false },
    { "id": "dark-english-ambiguous-time", "appearance": "dark", "language": "english", "conversation": "direct", "messageShape": "ambiguousDate", "text": "Can we meet tomorrow at 3 to discuss the proposal?", "expectsCandidate": true, "expectsClarification": true },
    { "id": "light-english-date-without-meeting", "appearance": "light", "language": "english", "conversation": "group", "messageShape": "plain", "text": "Tomorrow at 4 I will upload the three design files.", "expectsCandidate": false, "expectsClarification": false },
    { "id": "dark-arabic-date-without-time", "appearance": "dark", "language": "arabic", "conversation": "direct", "messageShape": "ambiguousDate", "text": "بكرة نراجع قائمة المهام بعد ما تخلص.", "expectsCandidate": false, "expectsClarification": false },
    { "id": "light-english-historical-quote", "appearance": "light", "language": "english", "conversation": "direct", "messageShape": "quoted", "text": "Quoted: The meeting notes contain 12 decisions. Reply: I read them.", "expectsCandidate": false, "expectsClarification": false }
  ]
}
"""#
