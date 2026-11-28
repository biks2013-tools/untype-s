#!/usr/bin/env bash
# Generates the photorealistic illustration set for the untype deck with image-tool (Azure OpenAI gpt-image-2).
# Re-run to regenerate; existing files are skipped. Style: photorealistic, the BikS2013 palette (ink and
# copper on warm paper: charcoal darks, warm copper / amber accents, cream and paper surfaces), warm light,
# no text, no logos. Nothing teal or cyan.
set -u
cd "$(dirname "$0")"
STYLE="Photorealistic photograph, natural light, shallow depth of field, muted palette of charcoal ink, warm copper and amber accents, cream and warm paper surfaces, warm highlights, no teal, no blue, editorial quality, no text, no letters, no logos, no watermarks."
gen() { # name size prompt
  local name="$1" size="$2" prompt="$3"
  if [ -f "$name.png" ]; then echo "skip $name"; return; fi
  echo "gen  $name"
  image-tool --json generate -p "$prompt $STYLE" -s "$size" --quality high --collision overwrite -o "$name.png" >/dev/null 2>"$name.err" && rm -f "$name.err" || echo "FAILED $name (see $name.err)"
}
gen cover-dictation      1536x1024 "A software engineer in a bright modern Athens office speaks into a small desk microphone beside a MacBook, one hand resting on the keyboard, a charcoal-dark accent wall with a warm copper lamp behind, morning window light."
gen problem-typing       1536x1024 "Close-up from above of tired hands typing on a laptop keyboard late in the evening, a dim warm desk lamp, coffee cup, an empty chat prompt glowing softly on the screen, moody and quiet."
gen voice-waveform       1536x1024 "A studio microphone on a walnut desk with a soft glowing sound-wave ribbon of warm copper light floating in the air in front of it, charcoal-dark background, cinematic macro."
gen hotkey-press         1536x1024 "Extreme macro of a fingertip pressing a single key on a backlit aluminium laptop keyboard, warm amber key backlight, shallow focus, dark surroundings."
gen streaming-audio      1536x1024 "A live audio waveform rendered on a large monitor in a dim recording studio, warm copper and amber traces on a charcoal screen, reflections on the desk, no readable text."
gen llm-network          1536x1024 "Abstract sculpture of glowing copper-tinted glass spheres connected by thin brass rods on a warm cream plaster wall, soft studio light, large empty space on the left."
gen text-delivery        1536x1024 "Macro photograph of a blinking text cursor in an empty document on a bright laptop screen, the screen fills the frame, slight bokeh, warm paper-white tones, clean and calm."
gen module-layout        1536x1024 "Neatly stacked blocks of dark charcoal slate and warm copper metal of different sizes arranged like an architecture model on a cream linen table, soft daylight, minimal."
gen install-terminal     1536x1024 "A MacBook on a tidy oak desk showing a dark terminal window with blurred lines of warm amber output, a plant and a notebook beside it, warm afternoon window light."
gen signing-seal         1536x1024 "A brass padlock resting on a folded cream document with an embossed copper wax seal, dark charcoal stone surface, warm side light, premium and calm."
gen permissions-keys     1536x1024 "Three brass keys on a dark charcoal leather tray on a light wooden desk, one key set apart, soft window light, macro."
gen config-drawers       1536x1024 "A wall of small dark-stained wooden archive drawers with blank cream labels and copper pulls, one drawer half open with folded papers inside, warm library light."
gen prompt-writing       1536x1024 "A fountain pen with dark ink writing on thick cream paper on a walnut desk, a copper pen cap beside it, macro, warm light, the writing is blurred and unreadable."
gen troubleshoot-logs    1536x1024 "An engineer seen from behind studying long scrolling log lines on two monitors in a dim office at night, warm amber glow from the screens, no readable text."
gen guardrails-bridge    1536x1024 "A modern pedestrian bridge with solid weathered-copper steel guard rails crossing over calm water at golden hour, long perspective, no people."
gen closing-athens       1536x1024 "Athens at dusk seen from a glass office window, the Acropolis lit far away in warm gold, deep charcoal sky, warm city lights, a laptop reflection faint in the glass."
gen cover-portrait       1024x1536 "Vertical portrait of a modern desk microphone on a stand in front of a charcoal-dark wall, a MacBook slightly out of focus behind it, warm copper window light from the left."
gen ui-overview          1536x1024 "A designer's desk with a large monitor showing a calm minimal dark application window with a small floating pill-shaped overlay, warm copper accents, out of focus, no readable text."
gen meeting-call         1536x1024 "A laptop on a walnut meeting-room table during a video call, the screen softly out of focus with blurred faces in a grid, a pair of copper-toned headphones and a notebook beside it, charcoal wall behind, warm afternoon light."
gen meeting-notes        1536x1024 "An open cream notebook with blurred handwritten meeting notes and a few printed documents fanned out on a dark charcoal desk, a copper desk lamp casting warm light, a laptop edge in the corner, macro, calm."
echo "done"
