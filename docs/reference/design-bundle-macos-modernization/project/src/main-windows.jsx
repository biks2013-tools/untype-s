// untype — main window variants
// V1 — Classic Sidebar (a SwiftUI Inspector-style window)
// V2 — Unified Glass (single panel, top toolbar, transcript center)
// V3 — Voice-First Dashboard (record button hero, conversation cards)

// ─── Shared content for all three ─────────────────────────────
const UN_TRANSCRIPT = [
  {
    id: 't1', kind: 'committed',
    raw: "open the bookings folder and rename the screenshot from yesterday command status",
    refined: 'Open the Bookings folder and rename the screenshot from yesterday.',
    operators: ['R', 'C'],
    time: '10:38',
  },
  {
    id: 't2', kind: 'committed',
    raw: "schedule a follow-up with sara for thursday three pm translate to greek command send",
    refined: 'Schedule a follow-up with Sara for Thursday 3:00 pm.',
    translated: 'Προγραμμάτισε μια συνάντηση παρακολούθησης με τη Σάρα την Πέμπτη στις 3 μ.μ.',
    operators: ['R', 'T', 'I'],
    time: '10:41',
  },
  {
    id: 't3', kind: 'partial',
    raw: 'and finally draft the reply to the partnership thread keeping it short and direct',
    operators: ['R'],
    time: 'live',
  },
];

const UN_EVENTS = [
  { t: '10:41:12', k: 'protocol.command',  v: 'send → submit sec_000007', tone: 'accent' },
  { t: '10:41:12', k: 'llm.refine',        v: 'azure · gpt-4o-mini · 412ms', tone: 'ok' },
  { t: '10:41:11', k: 'llm.translate',     v: 'azure · gpt-4o-mini · 380ms', tone: 'ok' },
  { t: '10:41:10', k: 'stt.final',         v: 'soniox · 1.21s · 24 tokens', tone: 'ok' },
  { t: '10:41:02', k: 'audio.input',       v: 'active · peak −18dB · 16kHz', tone: 'ok' },
  { t: '10:40:58', k: 'ptt.press',         v: 'event-tap · ⌃⌥Space', tone: 'accent' },
  { t: '10:40:55', k: 'session.warm',      v: 'recycled · soniox', tone: 'ok' },
];

// ─────────────────────────────────────────────────────────────
// V1 — Classic Sidebar
// Left rail (navigation), main monitor, right settings inspector.
// ─────────────────────────────────────────────────────────────
function UnMainV1({ theme, strength, state, setState }) {
  const { recording, ops, tab } = state;
  const toggleOp = (k) => setState((s) => ({ ...s, ops: { ...s.ops, [k]: !s.ops[k] } }));
  const setTab = (t) => setState((s) => ({ ...s, tab: t }));

  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      <div style={{ padding: '28px 24px 24px', height: 'calc(100% - 26px)', boxSizing: 'border-box' }}>
        <UnGlass theme={theme} strength={strength} radius={22} style={{
          width: '100%', height: '100%', display: 'flex', flexDirection: 'column', overflow: 'hidden',
        }}>
          {/* Window titlebar */}
          <div style={{
            height: 44, padding: '0 14px',
            display: 'flex', alignItems: 'center', gap: 16,
            borderBottom: `1px solid ${theme.divider}`,
            background: theme.chrome,
          }}>
            <UnTrafficLights />
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginLeft: 4 }}>
              <UnBrandMark size={20} theme={theme} />
              <span style={{ fontFamily: UN_FONT_DISPLAY, fontWeight: 600, fontSize: 13, color: theme.text }}>untype</span>
              <span style={{ fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted }}>·  Soniox · hybrid</span>
            </div>
            <div style={{ flex: 1 }}></div>
            <UnRecordButton recording={recording} theme={theme} onClick={() => setState((s) => ({ ...s, recording: !s.recording }))} />
          </div>

          {/* Body */}
          <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
            {/* Left rail */}
            <V1Sidebar theme={theme} strength={strength} />
            {/* Center monitor */}
            <V1Monitor theme={theme} strength={strength} tab={tab} setTab={setTab} recording={recording} ops={ops} toggleOp={toggleOp} />
            {/* Right settings inspector */}
            <V1Inspector theme={theme} strength={strength} />
          </div>
        </UnGlass>
      </div>
    </UnDesktop>
  );
}

function V1Sidebar({ theme, strength }) {
  const items = [
    { i: '●', l: 'Now', sub: 'live', active: true, tone: 'rec' },
    { i: '▤', l: 'History' },
    { i: '◫', l: 'Sessions' },
    { i: '◇', l: 'Templates' },
    { i: '◉', l: 'Events' },
  ];
  const config = [
    { i: '⚙', l: 'Settings' },
    { i: '⌨', l: 'Shortcuts' },
    { i: '◐', l: 'Permissions', tone: 'warn' },
  ];
  return (
    <div style={{
      width: 200, padding: '14px 10px',
      background: theme.sidebar,
      borderRight: `1px solid ${theme.divider}`,
      display: 'flex', flexDirection: 'column', gap: 4,
      fontFamily: UN_FONT_TEXT,
    }}>
      <UnLabel theme={theme} style={{ padding: '6px 10px 4px' }}>Monitor</UnLabel>
      {items.map((it) => (
        <V1SideRow key={it.l} theme={theme} {...it} />
      ))}
      <UnLabel theme={theme} style={{ padding: '14px 10px 4px' }}>Configure</UnLabel>
      {config.map((it) => (
        <V1SideRow key={it.l} theme={theme} {...it} />
      ))}

      <div style={{ flex: 1 }}></div>

      {/* Credential status card */}
      <UnGlass theme={theme} strength={strength} tone="hi" radius={12} style={{ padding: 10 }}>
        <UnLabel theme={theme}>Status</UnLabel>
        <div style={{ marginTop: 6 }}>
          <V1StatusLine theme={theme} k="Microphone" v="granted" tone="ok" />
          <V1StatusLine theme={theme} k="Accessibility" v="trusted" tone="ok" />
          <V1StatusLine theme={theme} k="SONIOX_API_KEY" v="ok · 41d" tone="ok" />
          <V1StatusLine theme={theme} k="AZURE_OAI_KEY" v="warn · 4d" tone="warn" />
        </div>
      </UnGlass>
    </div>
  );
}

function V1SideRow({ i, l, sub, active, tone, theme }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '6px 10px', borderRadius: 8,
      background: active ? theme.accentTint : 'transparent',
      color: active ? theme.text : theme.textMuted,
      fontSize: 13, fontWeight: active ? 600 : 500,
      cursor: 'default',
    }}>
      <span style={{
        width: 18, textAlign: 'center', fontSize: 11,
        color: tone === 'rec' ? theme.recording : tone === 'warn' ? theme.warn : active ? theme.accent : theme.textFaint,
      }}>{i}</span>
      <span style={{ flex: 1 }}>{l}</span>
      {sub && (
        <span style={{
          fontSize: 10, padding: '2px 6px', borderRadius: 4,
          background: tone === 'rec' ? theme.recordingTint : theme.accentTint,
          color: tone === 'rec' ? theme.recording : theme.accent,
          fontWeight: 700, letterSpacing: 0.5, textTransform: 'uppercase',
        }}>{sub}</span>
      )}
    </div>
  );
}

function V1StatusLine({ k, v, tone, theme }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '3px 0', fontSize: 11.5, color: theme.textMuted }}>
      <UnStatusDot tone={tone} theme={theme} size={6} />
      <span style={{ flex: 1, color: theme.textMuted }}>{k}</span>
      <span style={{ fontFamily: UN_FONT_MONO, color: tone === 'warn' ? theme.warn : theme.text, fontSize: 10.5 }}>{v}</span>
    </div>
  );
}

function V1Monitor({ theme, strength, tab, setTab, recording, ops, toggleOp }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0, padding: '16px 18px 18px', gap: 14 }}>
      {/* Top bar: tabs + ops + waveform */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <UnTabs tabs={['Transcript', 'History', 'Events']} active={tab} onChange={setTab} theme={theme} />
        <div style={{ flex: 1 }}></div>
        <UnGlass theme={theme} strength={strength} tone="low" radius={12} style={{
          padding: '4px 10px 4px 4px', display: 'inline-flex', alignItems: 'center', gap: 10,
        }}>
          <UnWaveform theme={theme} recording={recording} bars={28} height={28} />
          <span style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: recording ? theme.recording : theme.textMuted, fontWeight: 600 }}>
            {recording ? '−16dB' : 'silent'}
          </span>
        </UnGlass>
      </div>

      {/* Operator pill row */}
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        <UnOperatorPill letter="R" label="Refine"    on={ops.R} recording={recording} theme={theme} onClick={() => toggleOp('R')} />
        <UnOperatorPill letter="T" label="Translate" on={ops.T} recording={recording} theme={theme} onClick={() => toggleOp('T')} />
        <UnOperatorPill letter="C" label="Clipboard" on={ops.C} recording={recording} theme={theme} onClick={() => toggleOp('C')} />
        <UnOperatorPill letter="I" label="Input"     on={ops.I} recording={recording} theme={theme} onClick={() => toggleOp('I')} />
        <div style={{ flex: 1 }}></div>
        <UnBtn theme={theme} sm icon={<span style={{ fontSize: 11 }}>↗</span>}>Save</UnBtn>
        <UnBtn theme={theme} sm icon={<span style={{ fontSize: 11 }}>⎘</span>}>Copy</UnBtn>
        <UnBtn theme={theme} sm icon={<span style={{ fontSize: 11 }}>✕</span>}>Clear</UnBtn>
      </div>

      {/* Transcript timeline */}
      <UnGlass theme={theme} strength={strength} tone="low" radius={16} style={{
        flex: 1, padding: 14, overflow: 'auto', minHeight: 0,
        display: 'flex', flexDirection: 'column', gap: 12,
      }}>
        {UN_TRANSCRIPT.map((t) => <TranscriptTurn key={t.id} t={t} theme={theme} recording={recording} />)}

        {/* Live partial bubble at the bottom */}
        <div style={{ marginTop: 4, display: 'flex', gap: 10, alignItems: 'flex-start' }}>
          <div style={{ width: 40, paddingTop: 6 }}>
            <UnStatusDot tone={recording ? 'rec' : 'off'} theme={theme} />
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 11, color: theme.textMuted, marginBottom: 4, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase' }}>
              {recording ? 'Live · partial' : 'Idle · waiting for hotkey'}
            </div>
            <div style={{
              fontFamily: UN_FONT_TEXT, fontSize: 15, lineHeight: 1.5,
              color: recording ? theme.text : theme.textFaint,
              fontStyle: recording ? 'normal' : 'italic',
            }}>
              {recording ? 'and finally draft the reply to the partnership thread keeping it short and' : 'Press ⌃⌥Space to dictate, or click Start Listening.'}
              {recording && <span style={{ color: theme.accent, animation: 'unblink 1s steps(2) infinite' }}> ▋</span>}
            </div>
          </div>
        </div>
      </UnGlass>
    </div>
  );
}

function TranscriptTurn({ t, theme, recording }) {
  return (
    <div style={{ display: 'flex', gap: 10, alignItems: 'flex-start' }}>
      <div style={{ width: 40, fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textFaint, paddingTop: 4, textAlign: 'right', flex: '0 0 40px' }}>{t.time}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        {/* Raw */}
        <div style={{
          fontFamily: UN_FONT_TEXT, fontSize: 12.5, color: theme.textMuted,
          lineHeight: 1.55, marginBottom: 6, fontWeight: 400,
        }}>
          <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textFaint, marginRight: 6, fontWeight: 600 }}>RAW</span>
          {t.raw}
        </div>
        {/* Refined */}
        {t.refined && (
          <div style={{
            fontFamily: UN_FONT_TEXT, fontSize: 15, color: theme.text, lineHeight: 1.5, fontWeight: 500,
            paddingLeft: 12, borderLeft: `2px solid ${theme.accent}`,
          }}>
            {t.refined}
          </div>
        )}
        {t.translated && (
          <div style={{
            marginTop: 6, fontFamily: UN_FONT_TEXT, fontSize: 14, color: theme.textMuted, lineHeight: 1.5,
            paddingLeft: 12, borderLeft: `2px solid ${theme.glassStroke}`,
          }}>
            {t.translated}
          </div>
        )}
        {/* Operator badges */}
        <div style={{ display: 'flex', gap: 4, marginTop: 6 }}>
          {t.operators.map((o) => (
            <span key={o} style={{
              width: 18, height: 18, borderRadius: 5, display: 'inline-grid', placeItems: 'center',
              background: theme.accentTint, color: theme.accent,
              fontFamily: UN_FONT_MONO, fontSize: 10, fontWeight: 700,
            }}>{o}</span>
          ))}
          <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10, color: theme.textFaint, marginLeft: 4, alignSelf: 'center' }}>
            sec_{(parseInt(t.id.slice(1)) + 5).toString().padStart(6, '0')}
          </span>
        </div>
      </div>
    </div>
  );
}

function V1Inspector({ theme, strength }) {
  return (
    <div style={{
      width: 280, padding: '16px 14px',
      background: theme.sidebar,
      borderLeft: `1px solid ${theme.divider}`,
      display: 'flex', flexDirection: 'column', gap: 14,
      fontFamily: UN_FONT_TEXT, overflow: 'auto',
    }}>
      <div>
        <UnLabel theme={theme}>Session</UnLabel>
        <UnKV k="State" v={<><UnStatusDot tone="ok" theme={theme} /> listening</>} theme={theme} />
        <UnKV k="Mode" v="hybrid" theme={theme} mono />
        <UnKV k="STT provider" v="soniox" theme={theme} mono />
        <UnKV k="Model" v="stt-rt-preview-v2" theme={theme} mono />
        <UnKV k="Language" v="en · auto" theme={theme} mono />
        <UnKV k="Sample rate" v="16 000 Hz" theme={theme} mono />
        <UnKV k="Endpoint detection" v="on" theme={theme} mono tone="accent" />
      </div>

      <div style={{ borderTop: `1px solid ${theme.divider}`, paddingTop: 12 }}>
        <UnLabel theme={theme}>Refinement</UnLabel>
        <UnKV k="LLM" v="azure-openai" theme={theme} mono />
        <UnKV k="Model" v="gpt-4o-mini" theme={theme} mono />
        <UnKV k="Temperature" v="0.2" theme={theme} mono />
        <UnKV k="Translate target" v="el" theme={theme} mono />
      </div>

      <div style={{ borderTop: `1px solid ${theme.divider}`, paddingTop: 12 }}>
        <UnLabel theme={theme}>Push-to-talk</UnLabel>
        <UnKV k="Hotkey" v={<kbd style={kbdStyle(theme)}>⌃⌥Space</kbd>} theme={theme} />
        <UnKV k="Path" v="event-tap" theme={theme} mono tone="accent" />
        <UnKV k="Warm session" v="enabled" theme={theme} mono />
        <UnKV k="Overlay" v="bottom-center" theme={theme} mono />
      </div>

      <div style={{ borderTop: `1px solid ${theme.divider}`, paddingTop: 12, marginTop: 'auto' }}>
        <UnLabel theme={theme}>Config source</UnLabel>
        <div style={{
          fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.textMuted,
          background: theme.fieldBg, padding: 8, borderRadius: 8,
          border: `1px solid ${theme.divider}`, marginTop: 6,
        }}>
          ~/.tool-agents/untype/.env
        </div>
      </div>
    </div>
  );
}

function kbdStyle(theme) {
  return {
    fontFamily: UN_FONT_MONO, fontSize: 11, fontWeight: 600,
    padding: '2px 6px', borderRadius: 5,
    background: theme.glassHi, color: theme.text,
    border: `1px solid ${theme.glassStroke}`,
    boxShadow: 'inset 0 -1px 0 rgba(0,0,0,0.08)',
  };
}

// ─────────────────────────────────────────────────────────────
// V2 — Unified Glass
// Single panel, top toolbar with everything, transcript center,
// floating bottom-right operator dock.
// ─────────────────────────────────────────────────────────────
function UnMainV2({ theme, strength, state, setState }) {
  const { recording, ops } = state;
  const toggleOp = (k) => setState((s) => ({ ...s, ops: { ...s.ops, [k]: !s.ops[k] } }));
  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      <div style={{ padding: '40px 40px 28px', height: 'calc(100% - 26px)', boxSizing: 'border-box' }}>
        <UnGlass theme={theme} strength={strength} radius={26} style={{
          width: '100%', height: '100%', position: 'relative', overflow: 'hidden',
        }}>
          {/* Unified toolbar */}
          <div style={{
            height: 64, padding: '0 18px',
            display: 'flex', alignItems: 'center', gap: 18,
            borderBottom: `1px solid ${theme.divider}`,
            background: theme.chrome,
          }}>
            <UnTrafficLights />
            <div style={{ width: 8 }}></div>
            <UnBrandMark size={32} theme={theme} />
            <div>
              <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 14, fontWeight: 600, color: theme.text, lineHeight: 1.1 }}>untype</div>
              <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted }}>hybrid · sec_000007</div>
            </div>

            {/* Center status pill */}
            <div style={{ flex: 1, display: 'flex', justifyContent: 'center' }}>
              <UnGlass theme={theme} strength={strength} tone="hi" radius={999} style={{
                padding: '6px 16px 6px 8px',
                display: 'inline-flex', alignItems: 'center', gap: 12,
              }}>
                <div style={{
                  width: 32, height: 32, borderRadius: 999, display: 'grid', placeItems: 'center',
                  background: recording ? theme.recordingTint : theme.accentTint,
                  color: recording ? theme.recording : theme.accent,
                  border: `1px solid ${recording ? theme.recording : theme.accentRing}`,
                  fontFamily: UN_FONT_MONO, fontWeight: 700, fontSize: 12,
                }}>{recording ? '●' : '◐'}</div>
                <div>
                  <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted, lineHeight: 1 }}>{recording ? 'Recording' : 'Listening'}</div>
                  <div style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.text, lineHeight: 1.4 }}>
                    soniox · az-openai · el→en
                  </div>
                </div>
                <div style={{ height: 22, width: 1, background: theme.divider, margin: '0 6px' }}></div>
                <UnWaveform theme={theme} recording={recording} bars={22} height={22} seed={3} />
              </UnGlass>
            </div>

            <UnRecordButton recording={recording} theme={theme} onClick={() => setState((s) => ({ ...s, recording: !s.recording }))} />
          </div>

          {/* Main content area */}
          <div style={{ height: 'calc(100% - 64px)', display: 'flex', minHeight: 0 }}>
            {/* Conversation column */}
            <div style={{ flex: 1, padding: '24px 32px', overflow: 'auto', minWidth: 0 }}>
              <div style={{ maxWidth: 720, margin: '0 auto', display: 'flex', flexDirection: 'column', gap: 22 }}>
                <div style={{
                  fontFamily: UN_FONT_DISPLAY, fontSize: 28, fontWeight: 600, color: theme.text,
                  letterSpacing: -0.6, marginBottom: 4,
                }}>
                  Tuesday, May&nbsp;26
                </div>
                <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 13, color: theme.textMuted, marginTop: -16 }}>
                  Session started 10:32 · 14 turns · 3 protocol commands
                </div>

                {UN_TRANSCRIPT.map((t) => <V2Turn key={t.id} t={t} theme={theme} strength={strength} />)}

                {/* Live bubble */}
                <V2LiveBubble theme={theme} strength={strength} recording={recording} />
              </div>
            </div>

            {/* Right rail with quick info chips */}
            <div style={{
              width: 240, padding: '24px 18px', borderLeft: `1px solid ${theme.divider}`,
              background: theme.glassLow, overflow: 'auto',
              display: 'flex', flexDirection: 'column', gap: 16,
            }}>
              <V2Chip theme={theme} k="Mic"           v="MacBook Air"  tone="ok"  hint="−18dB · active" />
              <V2Chip theme={theme} k="Provider"      v="Soniox"        tone="ok"  hint="ws.soniox.com · 41ms" />
              <V2Chip theme={theme} k="Refiner"       v="Azure OpenAI"  tone="ok"  hint="gpt-4o-mini · 0.2" />
              <V2Chip theme={theme} k="Push-to-talk"  v={<kbd style={kbdStyle(theme)}>⌃⌥Space</kbd>} tone="accent" hint="event-tap" />
              <V2Chip theme={theme} k="Accessibility" v="trusted"       tone="ok" />
              <V2Chip theme={theme} k="Azure key"     v="expires in 4d" tone="warn" hint="rotate now" />
            </div>
          </div>

          {/* Floating operator dock — bottom center */}
          <div style={{
            position: 'absolute', bottom: 22, left: '50%', transform: 'translateX(-50%)',
            display: 'flex', gap: 8,
          }}>
            <UnGlass theme={theme} strength={Math.min(1, strength + 0.15)} tone="hi" radius={999} style={{
              padding: '8px 10px', display: 'inline-flex', gap: 6,
            }}>
              <UnOperatorPill letter="R" label="Refine"    on={ops.R} recording={recording} theme={theme} onClick={() => toggleOp('R')} size="sm" />
              <UnOperatorPill letter="T" label="Translate" on={ops.T} recording={recording} theme={theme} onClick={() => toggleOp('T')} size="sm" />
              <UnOperatorPill letter="C" label="Clipboard" on={ops.C} recording={recording} theme={theme} onClick={() => toggleOp('C')} size="sm" />
              <UnOperatorPill letter="I" label="Input"     on={ops.I} recording={recording} theme={theme} onClick={() => toggleOp('I')} size="sm" />
            </UnGlass>
          </div>
        </UnGlass>
      </div>
    </UnDesktop>
  );
}

function V2Turn({ t, theme, strength }) {
  return (
    <UnGlass theme={theme} strength={strength} tone="hi" radius={18} style={{ padding: 16 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <span style={{
          fontFamily: UN_FONT_MONO, fontSize: 10, fontWeight: 700, color: theme.textMuted,
          padding: '2px 7px', borderRadius: 4, background: theme.glassLow, border: `1px solid ${theme.glassStroke}`,
        }}>sec_{(parseInt(t.id.slice(1)) + 5).toString().padStart(6, '0')}</span>
        <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textFaint }}>{t.time}</span>
        <div style={{ flex: 1 }}></div>
        {t.operators.map((o) => (
          <span key={o} style={{
            width: 18, height: 18, borderRadius: 999, display: 'inline-grid', placeItems: 'center',
            background: theme.accentTint, color: theme.accent,
            fontFamily: UN_FONT_MONO, fontSize: 10, fontWeight: 700,
          }}>{o}</span>
        ))}
      </div>
      <div style={{
        fontFamily: UN_FONT_TEXT, fontSize: 12.5, color: theme.textMuted, fontStyle: 'italic',
        marginBottom: t.refined ? 10 : 0,
      }}>
        “{t.raw}”
      </div>
      {t.refined && (
        <div style={{
          fontFamily: UN_FONT_TEXT, fontSize: 16, lineHeight: 1.5, color: theme.text, fontWeight: 500,
        }}>{t.refined}</div>
      )}
      {t.translated && (
        <div style={{
          marginTop: 8, fontFamily: UN_FONT_TEXT, fontSize: 14, lineHeight: 1.5, color: theme.textMuted,
          padding: '8px 12px', borderRadius: 10,
          background: theme.accentTint, border: `1px solid ${theme.accentRing}`,
        }}>
          <span style={{ fontFamily: UN_FONT_MONO, fontSize: 9.5, color: theme.accent, fontWeight: 700, marginRight: 6 }}>EL</span>
          {t.translated}
        </div>
      )}
    </UnGlass>
  );
}

function V2LiveBubble({ theme, strength, recording }) {
  return (
    <UnGlass theme={theme} strength={strength} tone="low" radius={18} style={{
      padding: 16, border: `1px dashed ${recording ? theme.accentRing : theme.divider}`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
        <UnStatusDot tone={recording ? 'rec' : 'off'} theme={theme} />
        <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase', color: recording ? theme.recording : theme.textFaint }}>
          {recording ? 'Live · partial' : 'Idle'}
        </span>
      </div>
      <div style={{
        fontFamily: UN_FONT_TEXT, fontSize: 16, lineHeight: 1.5,
        color: recording ? theme.text : theme.textFaint, fontStyle: recording ? 'normal' : 'italic',
      }}>
        {recording
          ? 'and finally draft the reply to the partnership thread keeping it short and'
          : 'Press the hotkey or hit Start Listening to begin a session.'}
        {recording && <span style={{ color: theme.accent }}> ▋</span>}
      </div>
    </UnGlass>
  );
}

function V2Chip({ k, v, hint, tone, theme }) {
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 4 }}>
        <UnStatusDot tone={tone} theme={theme} size={6} />
        <UnLabel theme={theme} style={{ textTransform: 'uppercase' }}>{k}</UnLabel>
      </div>
      <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 14, fontWeight: 600, color: theme.text }}>{v}</div>
      {hint && <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted, marginTop: 2 }}>{hint}</div>}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// V3 — Voice-First Dashboard
// Hero record button with circular waveform, single live card,
// recent turns scroll, sticky operator dock at top.
// ─────────────────────────────────────────────────────────────
function UnMainV3({ theme, strength, state, setState }) {
  const { recording, ops } = state;
  const toggleOp = (k) => setState((s) => ({ ...s, ops: { ...s.ops, [k]: !s.ops[k] } }));
  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      <div style={{ padding: '32px 56px 28px', height: 'calc(100% - 26px)', boxSizing: 'border-box' }}>
        <UnGlass theme={theme} strength={strength} radius={28} style={{
          width: '100%', height: '100%', overflow: 'hidden', display: 'flex', flexDirection: 'column',
        }}>
          {/* Header: traffic lights only, brand, operator dock */}
          <div style={{
            height: 56, padding: '0 18px',
            display: 'flex', alignItems: 'center', gap: 16,
            background: theme.chrome,
            borderBottom: `1px solid ${theme.divider}`,
          }}>
            <UnTrafficLights />
            <div style={{ width: 6 }}></div>
            <UnBrandMark size={24} theme={theme} />
            <span style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 14, fontWeight: 600, color: theme.text }}>untype</span>
            <div style={{ flex: 1 }}></div>
            <UnOperatorPill letter="R" label="Refine"    on={ops.R} recording={recording} theme={theme} onClick={() => toggleOp('R')} size="sm" />
            <UnOperatorPill letter="T" label="Translate" on={ops.T} recording={recording} theme={theme} onClick={() => toggleOp('T')} size="sm" />
            <UnOperatorPill letter="C" label="Clipboard" on={ops.C} recording={recording} theme={theme} onClick={() => toggleOp('C')} size="sm" />
            <UnOperatorPill letter="I" label="Input"     on={ops.I} recording={recording} theme={theme} onClick={() => toggleOp('I')} size="sm" />
          </div>

          <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
            {/* Left: hero record + recent turns */}
            <div style={{ flex: 1, padding: '28px 32px', display: 'flex', flexDirection: 'column', gap: 20, minWidth: 0 }}>
              <V3Hero theme={theme} strength={strength} recording={recording} onToggle={() => setState((s) => ({ ...s, recording: !s.recording }))} ops={ops} />

              <div style={{ flex: 1, overflow: 'auto', display: 'flex', flexDirection: 'column', gap: 10, paddingRight: 6 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 2 }}>
                  <span style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 13, fontWeight: 600, color: theme.text }}>Recent turns</span>
                  <span style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.textFaint }}>{UN_TRANSCRIPT.filter((t) => t.kind === 'committed').length} committed</span>
                </div>
                {UN_TRANSCRIPT.filter((t) => t.kind === 'committed').map((t) => (
                  <V3TurnCard key={t.id} t={t} theme={theme} strength={strength} />
                ))}
              </div>
            </div>

            {/* Right: stat strip */}
            <V3StatRail theme={theme} strength={strength} recording={recording} />
          </div>
        </UnGlass>
      </div>
    </UnDesktop>
  );
}

function V3Hero({ theme, strength, recording, onToggle, ops }) {
  return (
    <UnGlass theme={theme} strength={strength} tone="hi" radius={22} style={{
      padding: 20, display: 'flex', alignItems: 'center', gap: 24, minHeight: 168,
    }}>
      {/* Circular record halo */}
      <div onClick={onToggle} style={{
        width: 128, height: 128, borderRadius: 999, position: 'relative',
        display: 'grid', placeItems: 'center',
        background: recording
          ? `radial-gradient(closest-side, ${theme.recording} 0%, #b8332b 60%, #6e1a14 100%)`
          : `radial-gradient(closest-side, ${theme.accentHi} 0%, ${theme.accent} 60%, #8a4906 100%)`,
        boxShadow: recording
          ? `0 0 0 6px ${theme.recordingTint}, 0 0 0 14px rgba(255,90,77,0.10), 0 20px 50px -10px ${theme.recording}`
          : `0 0 0 6px ${theme.accentTint}, 0 0 0 14px rgba(245,163,66,0.08), 0 20px 50px -10px ${theme.accentRing}`,
        cursor: 'pointer', transition: 'all 220ms ease',
      }}>
        {/* inner glass disc */}
        <div style={{
          width: 100, height: 100, borderRadius: 999,
          background: 'rgba(255,255,255,0.10)',
          backdropFilter: 'blur(8px)',
          display: 'grid', placeItems: 'center',
          border: '1px solid rgba(255,255,255,0.25)',
          boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.30), inset 0 -10px 24px rgba(0,0,0,0.20)',
        }}>
          <div style={{
            width: recording ? 28 : 38, height: recording ? 28 : 38,
            borderRadius: recording ? 6 : 999, background: '#fff',
            boxShadow: '0 0 14px rgba(255,255,255,0.45)',
            transition: 'all 240ms ease',
          }}></div>
        </div>
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontFamily: UN_FONT_DISPLAY, fontSize: 11, fontWeight: 700, letterSpacing: 1.2,
          textTransform: 'uppercase', color: recording ? theme.recording : theme.accent,
        }}>
          {recording ? 'Recording · push-to-talk active' : 'Warm session · waiting for hotkey'}
        </div>
        <div style={{
          fontFamily: UN_FONT_DISPLAY, fontSize: 24, fontWeight: 600, color: theme.text,
          letterSpacing: -0.4, marginTop: 6, lineHeight: 1.25,
        }}>
          {recording
            ? '“and finally draft the reply to the partnership thread keeping it short and'
            : 'Hold ⌃⌥Space to dictate.'}
          {recording && <span style={{ color: theme.accent }}> ▋</span>}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginTop: 14 }}>
          <UnWaveform theme={theme} recording={recording} bars={48} height={28} seed={7} />
          <div style={{ display: 'flex', gap: 4 }}>
            {['R','T','C','I'].map((o) => (
              <span key={o} style={{
                width: 22, height: 22, borderRadius: 6, display: 'grid', placeItems: 'center',
                background: ops[o] ? theme.accentTint : 'transparent',
                color: ops[o] ? theme.accent : theme.textFaint,
                border: `1px solid ${ops[o] ? theme.accentRing : theme.divider}`,
                fontFamily: UN_FONT_MONO, fontSize: 11, fontWeight: 700,
              }}>{o}</span>
            ))}
          </div>
        </div>
      </div>
    </UnGlass>
  );
}

function V3TurnCard({ t, theme, strength }) {
  return (
    <UnGlass theme={theme} strength={strength * 0.7} tone="low" radius={14} style={{
      padding: '12px 14px', display: 'flex', alignItems: 'flex-start', gap: 12,
    }}>
      <div style={{ width: 36, paddingTop: 2, flex: '0 0 36px' }}>
        <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textFaint }}>{t.time}</div>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 14.5, color: theme.text, lineHeight: 1.45, fontWeight: 500 }}>
          {t.refined}
        </div>
        {t.translated && (
          <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 13, color: theme.textMuted, lineHeight: 1.45, marginTop: 4 }}>
            {t.translated}
          </div>
        )}
      </div>
      <div style={{ display: 'flex', gap: 3, flex: '0 0 auto' }}>
        {t.operators.map((o) => (
          <span key={o} style={{
            width: 16, height: 16, borderRadius: 4, display: 'grid', placeItems: 'center',
            background: theme.accentTint, color: theme.accent,
            fontFamily: UN_FONT_MONO, fontSize: 9, fontWeight: 700,
          }}>{o}</span>
        ))}
      </div>
    </UnGlass>
  );
}

function V3StatRail({ theme, strength, recording }) {
  const stats = [
    { l: 'Latency', v: '412ms', sub: 'refine · azure', tone: 'ok' },
    { l: 'Turns',   v: '14',    sub: 'this session',   tone: 'accent' },
    { l: 'Audio',   v: recording ? 'active' : 'silent', sub: '−18dB · 16kHz', tone: recording ? 'rec' : 'off' },
    { l: 'Provider',v: 'soniox', sub: 'ws · 41ms',     tone: 'ok' },
  ];
  return (
    <div style={{
      width: 200, padding: '24px 16px',
      background: theme.glassLow,
      borderLeft: `1px solid ${theme.divider}`,
      display: 'flex', flexDirection: 'column', gap: 14,
      overflow: 'auto',
    }}>
      {stats.map((s, i) => (
        <div key={i}>
          <UnLabel theme={theme}>{s.l}</UnLabel>
          <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 22, fontWeight: 600, color: theme.text, marginTop: 4, letterSpacing: -0.5, display: 'flex', alignItems: 'center', gap: 6 }}>
            <UnStatusDot tone={s.tone} theme={theme} />
            {s.v}
          </div>
          <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted, marginTop: 2 }}>{s.sub}</div>
        </div>
      ))}

      <div style={{ borderTop: `1px solid ${theme.divider}`, paddingTop: 12 }}>
        <UnLabel theme={theme}>Hotkey</UnLabel>
        <div style={{ marginTop: 6 }}>
          <kbd style={{ ...kbdStyle(theme), fontSize: 13, padding: '4px 10px' }}>⌃⌥Space</kbd>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  UnMainV1, UnMainV2, UnMainV3, UN_TRANSCRIPT, UN_EVENTS, kbdStyle,
});
