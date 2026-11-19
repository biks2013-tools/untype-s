# Plan 073 - The user's dictionary of names, abbreviations and terms

Date: 2026-11-19. FR-77.

## Why
User request: English names, abbreviations and terms the user says often inside Greek speech (for example `biks`,
`BikS2013`) are not written right, and have to be corrected by hand after each dictation. The user wants to teach
untype a few such words now and add more in Settings as they come up. Dictation matters most; use in Refine and
elsewhere is welcome but secondary.

Until now untype sent Soniox only a free-text context from a prompt file (the user's file is empty) and ElevenLabs
key terms from another prompt file.

## What it does
A dictionary kept on the Mac (`~/.tool-agents/untype/dictionary.json`, mode 0600): for each word, how it must be
written and the ways speech recognition has been heard to write it instead.

1. **The speech provider is told to expect the words.** Soniox: `context.terms` in the config frame, next to
   `context.text`. ElevenLabs: appended to the key terms of the prompt file (words of up to 20 characters, 50 key
   terms in all). Google: nothing is sent.
2. **Recognised text is corrected** (`DictionaryCorrector`) before anything else sees it: a heard form becomes the
   word, and the word itself gets its own capitals. Whole words only, whatever the capitals of the recognised text;
   the longest form wins. Applies to partial and final text, so the live text, the model's input and the delivered
   text all carry the word. Works with every provider.
3. **Teach** (Settings → Speech → Dictionary): untype listens for 4 seconds while the user says only that word (a turn
   it starts and discards itself, as for the voice sample). When what was written is not the word, it is stored as a
   heard form. More than a few words heard: nothing is stored.

A changed dictionary restarts the warm push-to-talk session (never during a turn), since the words are sent when the
stream opens.

## Measurement
Soniox `stt-rt-v6`, synthetic speech (macOS voices; the user's own voice was not available), `probe.ts --terms`:

| Audio | Without terms | With terms `biks, BikS2013, cmux` |
|---|---|---|
| Greek sentence (Melina) | BIX2013, BIX, CMax | BikS2013, BikS, cmux |
| English sentence (Samantha) | Biggs2013, Biggs, CMoX | biks2013, biks, cmux |

The request with `context.terms` is accepted, and all three words are recognised. The capitals of `biks` and
`BikS2013` are mixed up between the two; the corrector's capitals rule puts them right.

## Changes
- `UserDictionary.swift` (new): `DictionaryEntry`, `UserDictionary` (add, remove, `noteHeard`, limits: 300 words of
  up to 60 characters), `UserDictionaryStore`, `DictionaryCorrector`.
- `SonioxTranscriberOptions.terms`; `ElevenLabsTranscriberOptions.keyterms(file:dictionary:)`.
- `TranscriptionSessionRuntimeOptions.textCorrector`, applied to provider partials and finals.
- `UntypeRuntimeFactory.makeForUI(dictionary:)`.
- `UntypeUIModel`: `dictionary`, `dictionaryStatus`, `dictionaryTeaching`, add / remove / remove a heard form /
  `teachDictionaryWord`, `alignDictionary`. Settings → Speech → Dictionary.
- `test_scripts/voice-filter/probe.ts`: `--terms`, `--text`.

## Not done
- The dictionary is not given to Refine / Translate as a glossary (they get the corrected text).
- Meeting recordings and the command-line runtime do not use it.
- Nothing is learned from corrections the user types during a dictation.

## Privacy
The words are sent to the speech provider with every dictation. The event log has only counts, never the words.
A dictionary file that cannot be read is reported in Settings and never written over.

## Verification
`swift build`; 483/483 tests (9 new: dictionary, corrector, store, ElevenLabs key terms, Soniox config frame, runtime
correction); the live Soniox measurement above. Settings and Teach were not run in the app.
