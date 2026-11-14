// The demo video's script: beats (what happens, in order), what is dictated and
// said on screen per language, and the narration per language.
//
// Times are never written by hand. Each beat has a minimum duration (`min`,
// seconds: the shortest the action reads well). The duration actually used is
//   timing[<profile>][<beat id>]  when the profile has one, else  `min`.
// `tools/video.ts fit` writes a profile from recorded narration clips, so the
// picture follows the voice. Loaded by the page (window.UNTYPE_VIDEO) and by
// the tools.
(function (root) {
  const beats = [
    { id: "intro", scene: "intro", min: 5 },
    // Push-to-talk, held
    { id: "hold-press", scene: "dict", min: 8 },
    { id: "hold-release", scene: "dict", min: 9 },
    // Tap: hands-free
    { id: "tap-start", scene: "dict", min: 7 },
    { id: "tap-speak", scene: "dict", min: 9 },
    // Editing while it listens
    { id: "edit-insert", scene: "dict", min: 12 },
    { id: "edit-fix", scene: "dict", min: 11 },
    { id: "edit-finish", scene: "dict", min: 11 },
    // Try again
    { id: "retry-bad", scene: "chat", min: 8 },
    { id: "retry-esc", scene: "chat", min: 6 },
    { id: "retry-send", scene: "chat", min: 10 },
    // Meeting transcript, live
    { id: "meet-start", scene: "meet", min: 9 },
    { id: "meet-live", scene: "meet", min: 15 },
    { id: "meet-channels", scene: "meet", min: 10 },
    // Dictating during the meeting
    { id: "mute-switch", scene: "meet", min: 8 },
    { id: "mute-dictate", scene: "meet", min: 16 },
    { id: "mute-back", scene: "meet", min: 9 },
    { id: "outro", scene: "outro", min: 6 }
  ];

  // What appears on screen (the text being dictated, the meeting's sentences).
  const content = {
    en: {
      docTitle: "Weekly update",
      hold: "Hi Maria, the report is ready and I will send it this afternoon.",
      // The sentence dictated hands-free; `tapWrong` is the word recognised
      // wrongly inside it, `tapRight` what the user types over it.
      tap: " We tested the new version with three teams.",
      tapWrong: "three",
      tapRight: "four",
      // Spoken after the caret was moved behind `insertAfter`.
      insertAfter: "the report",
      insert: " for October",
      finish: " The results look good.",
      chatName: "Nikos",
      chatIncoming: "Can you join the review at ten?",
      chatBad: "Yes I think, no wait, maybe at",
      chatGood: "Yes, I can join at ten.",
      speaker1: "Speaker 1",
      speaker2: "Speaker 2",
      you: "You",
      call: "Call",
      meet1: "Let's start with the launch date.",
      meetYou: "We are on track for the fifteenth.",
      meet2: "The beta feedback is positive so far.",
      meet3: "Can someone write down the action items?",
      meet4: "I will send the numbers tomorrow.",
      meetYou2: "I have noted the action items.",
      noteTitle: "Meeting notes",
      note: "Action items: confirm the launch date, share the beta report."
    },
    el: {
      docTitle: "Εβδομαδιαία ενημέρωση",
      hold: "Γεια σου Μαρία, η αναφορά είναι έτοιμη και θα τη στείλω το απόγευμα.",
      tap: " Δοκιμάσαμε τη νέα έκδοση με τρεις ομάδες.",
      tapWrong: "τρεις",
      tapRight: "τέσσερις",
      insertAfter: "η αναφορά",
      insert: " του Οκτωβρίου",
      finish: " Τα αποτελέσματα είναι καλά.",
      chatName: "Νίκος",
      chatIncoming: "Μπορείς να μπεις στη σύσκεψη στις δέκα;",
      chatBad: "Ναι νομίζω, όχι περίμενε, ίσως στις",
      chatGood: "Ναι, μπορώ στις δέκα.",
      speaker1: "Speaker 1",
      speaker2: "Speaker 2",
      you: "You",
      call: "Call",
      meet1: "Ας ξεκινήσουμε με την ημερομηνία κυκλοφορίας.",
      meetYou: "Είμαστε εντός προγράμματος για τις δεκαπέντε.",
      meet2: "Τα σχόλια από το beta είναι θετικά μέχρι στιγμής.",
      meet3: "Μπορεί κάποιος να σημειώσει τις ενέργειες;",
      meet4: "Θα στείλω τα νούμερα αύριο.",
      meetYou2: "Σημείωσα τις ενέργειες.",
      noteTitle: "Σημειώσεις σύσκεψης",
      note: "Ενέργειες: επιβεβαίωση ημερομηνίας κυκλοφορίας, αποστολή της αναφοράς beta."
    }
  };

  // What the voice says over each beat. One clip per beat:
  // narration/<lang>/<beat id>.(wav|mp3|m4a|aiff).
  const narration = {
    en: {
      "intro": "This is untype: dictation for your Mac, wherever your cursor is.",
      "hold-press": "Hold the hotkey and speak. untype listens at once, and your words are typed where the cursor is, as you say them.",
      "hold-release": "Release the key and the text is finished. No window to switch to, nothing to paste.",
      "tap-start": "For longer text, tap the hotkey instead of holding it. untype keeps listening, hands-free.",
      "tap-speak": "Your hands are free while you speak, and the text keeps arriving.",
      "edit-insert": "And you can edit while it listens. Move the cursor to another place and keep talking: what you say next is written there.",
      "edit-fix": "A word came out wrong? Select it and type over it. untype is still listening.",
      "edit-finish": "Go back to the end, finish your thought, and tap the hotkey again to close the turn.",
      "retry-bad": "And if a sentence goes wrong while you speak,",
      "retry-esc": "press Escape. Everything from this turn is removed.",
      "retry-send": "Tap, say it again, and press Enter: the text is typed and the message is sent.",
      "meet-start": "untype also records your meetings. One click, and both sides of the call are transcribed.",
      "meet-live": "The transcription window shows the transcript while the meeting runs: every speaker of the call, and you, sentence by sentence.",
      "meet-channels": "Show only your microphone, only the call, or both.",
      "mute-switch": "During a meeting you can still dictate. With this switch on, untype keeps your dictation out of the meeting.",
      "mute-dictate": "Hold the hotkey and dictate a note. For as long as you dictate, the meeting gets silence from your microphone, while the call is still recorded.",
      "mute-back": "Release the key, and what you say belongs to the meeting again. Your note never reaches the minutes.",
      "outro": "untype. Speak, and it is written."
    },
    el: {
      "intro": "Αυτό είναι το untype: υπαγόρευση στο Mac σου, όπου κι αν βρίσκεται ο κέρσορας.",
      "hold-press": "Κράτα πατημένο το πλήκτρο και μίλα. Το untype ακούει αμέσως, και οι λέξεις γράφονται εκεί που είναι ο κέρσορας, την ώρα που τις λες.",
      "hold-release": "Άφησε το πλήκτρο και το κείμενο είναι έτοιμο. Χωρίς αλλαγή παραθύρου, χωρίς επικόλληση.",
      "tap-start": "Για μεγαλύτερο κείμενο, πάτα το πλήκτρο μία φορά αντί να το κρατάς. Το untype συνεχίζει να ακούει, με τα χέρια ελεύθερα.",
      "tap-speak": "Τα χέρια σου είναι ελεύθερα όσο μιλάς, και το κείμενο συνεχίζει να γράφεται.",
      "edit-insert": "Και μπορείς να διορθώνεις όσο ακούει. Πήγαινε τον κέρσορα σε άλλο σημείο και συνέχισε να μιλάς: ό,τι πεις γράφεται εκεί.",
      "edit-fix": "Βγήκε λάθος μια λέξη; Επίλεξέ τη και γράψε από πάνω. Το untype ακούει ακόμα.",
      "edit-finish": "Γύρνα στο τέλος, ολοκλήρωσε τη σκέψη σου, και πάτα ξανά το πλήκτρο για να κλείσεις.",
      "retry-bad": "Κι αν μια πρόταση δεν βγει καλά όσο μιλάς,",
      "retry-esc": "πάτα Escape. Ό,τι γράφτηκε σε αυτή την προσπάθεια σβήνεται.",
      "retry-send": "Πάτα, πες το ξανά, και πάτα Enter: το κείμενο γράφεται και το μήνυμα στέλνεται.",
      "meet-start": "Το untype καταγράφει και τις συσκέψεις σου. Ένα κλικ, και οι δύο πλευρές της κλήσης μεταγράφονται.",
      "meet-live": "Το transcription window δείχνει τη μεταγραφή όσο εξελίσσεται η σύσκεψη: κάθε ομιλητή της κλήσης, κι εσένα, πρόταση προς πρόταση.",
      "meet-channels": "Δες μόνο το μικρόφωνό σου, μόνο την κλήση, ή και τα δύο.",
      "mute-switch": "Μέσα στη σύσκεψη μπορείς ακόμα να υπαγορεύεις. Με αυτόν τον διακόπτη, το untype κρατά την υπαγόρευση έξω από τη σύσκεψη.",
      "mute-dictate": "Κράτα το πλήκτρο και υπαγόρευσε μια σημείωση. Όσο υπαγορεύεις, η σύσκεψη παίρνει σιωπή από το μικρόφωνό σου, ενώ η κλήση συνεχίζει να καταγράφεται.",
      "mute-back": "Άφησε το πλήκτρο, και ό,τι λες ανήκει ξανά στη σύσκεψη. Η σημείωσή σου δεν φτάνει ποτέ στα πρακτικά.",
      "outro": "untype. Μίλα, και γράφεται."
    }
  };

  // Duration overrides per profile (seconds per beat id). "neutral" is the
  // picture without a voice; "el" / "en" are written by `tools/video.ts fit`.
  const timing = { neutral: {} };

  const api = { beats, content, narration, timing, fps: 30, width: 1920, height: 1080 };
  root.UNTYPE_VIDEO = api;
  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
})(typeof window !== "undefined" ? window : globalThis);
