# Plan 057 — Overlay meeting cards: the name in full, live words, Return / Esc

## Request
The overlay must be very easy to work with, self-explanatory, compact and exact. Renaming a meeting must show what it was renamed to, and the name must be confirmed either with the button or with Return.

## What the user sees
- **Saved card.** A green caption says what happened ("Meeting saved", "Renamed", "Ended · 3 min silence", "Not renamed"); under it the meeting's name in full, on up to two lines (its date until it has a name). Two labelled buttons: **Open** (the transcript) and **Name** (**Rename** once it has a name). The card stays 12 s, and for as long as the mouse is on it.
- **Naming card.** "Listening" with level bars; under it "Say the topic and who was there", replaced by the words as they are heard. **Done ↩** uses them, **Cancel esc** keeps the current name; Return and Esc do the same as the buttons. Listening also ends by itself after a 4 s pause.
- **After Done.** The card answers at once with "Making the name…" and keeps the words, then becomes the saved card with "Renamed" and the new name.

- **Tray in plain words.** Hovering the chips opens the tray, which says what a dictation does right now ("Refines and translates to English" / "Typed at cursor, copied"). With the mouse on a chip or control the two lines become its name and what it does (the chip's colour already says whether it is on); the chip gets a white ring. Nothing floats over the open tray.
- **Readable chips.** A chip that is off is dark with a white letter, one that is on is amber; both read on light and dark windows alike, at rest too.
- **One look.** The tray and the cards share the same dark surface, border and corners.
- **Human date.** An unnamed meeting shows "Today 22:38" instead of the folder's date stamp.

## Decisions
- **Labels instead of icons and tooltips.** The cards' buttons carry their word and their key; they have no tooltip, which would cover the card.
- **Return / Esc without taking the focus.** The overlay never becomes the key window, so the keys are caught with a Quartz event tap that exists only while the card listens (`UntypeNamingKeyTap`). It is separate from the push-to-talk hotkey monitors, swallows only Return / Enter / Esc without modifiers, and lets everything else through. When macOS refuses the tap the buttons show no key and still work.
- **Live words.** `MeetingLiveText` (pure) builds the text heard so far from Soniox's final and non-final tokens; the naming stream reports it after every result frame.
- **Same panel size.** The overlay stays 248 × 84 pt; the saved and naming cards use the full width and the height above the chips. The recording card, the tray, the trace and the chips are unchanged.

## Verification
- Unit tests `liveTextKeepsFinalWordsAndReplacesPendingOnes`, `overlaySummarySaysWhatADictationDoes`, `friendlyDateReadsTheFolderDateAsPeopleSayIt`; full suite.
- Rendered snapshots of every overlay state, light and dark.
- On device: see `Issues - Pending Items.md`.
