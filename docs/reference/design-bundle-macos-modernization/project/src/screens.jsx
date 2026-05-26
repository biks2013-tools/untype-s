// untype — onboarding & permissions, settings panes, history browser

// ─────────────────────────────────────────────────────────────
// Onboarding — first-run permission + provider setup
// ─────────────────────────────────────────────────────────────
function UnOnboarding({ theme, strength }) {
  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      <div style={{ height: 'calc(100% - 26px)', display: 'grid', placeItems: 'center', padding: 30 }}>
        <UnGlass theme={theme} strength={strength} tone="hi" radius={26} style={{
          width: 'min(880px, 100%)', padding: 36, display: 'flex', flexDirection: 'column', gap: 26,
          position: 'relative', overflow: 'hidden',
        }}>
          {/* Subtle hero glow */}
          <div style={{
            position: 'absolute', inset: -120, top: -240, height: 320,
            background: `radial-gradient(closest-side, ${theme.accent}55, transparent 70%)`,
            filter: 'blur(40px)', pointerEvents: 'none',
          }}></div>

          <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16 }}>
            <UnBrandMark size={56} theme={theme} />
            <div>
              <div style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.accent, fontWeight: 700, letterSpacing: 1.2, textTransform: 'uppercase' }}>welcome</div>
              <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 30, fontWeight: 600, color: theme.text, letterSpacing: -0.7, marginTop: 6, lineHeight: 1.1 }}>
                Hold a key. Speak.<br />Type with your voice.
              </div>
              <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 14, color: theme.textMuted, lineHeight: 1.55, marginTop: 10, maxWidth: 540 }}>
                untype is a Swift-native dictation companion for macOS. Push-to-talk in any app, with optional LLM refinement, translation, and clipboard or focused-input delivery.
              </div>
            </div>
          </div>

          {/* Step cards */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 14 }}>
            <StepCard theme={theme} strength={strength} n="1" title="Microphone access" body="Required for AVAudioEngine to capture input." status="granted" />
            <StepCard theme={theme} strength={strength} n="2" title="Accessibility trust" body="Lets untype install a Quartz event-tap for the push-to-talk hotkey." status="action" />
            <StepCard theme={theme} strength={strength} n="3" title="Provider credentials" body="At least one STT key (Soniox or ElevenLabs) and an LLM key if you want refinement." status="partial" />
          </div>

          {/* Hotkey + actions */}
          <UnGlass theme={theme} strength={strength * 0.7} tone="low" radius={16} style={{
            padding: 18, display: 'flex', alignItems: 'center', gap: 20,
          }}>
            <div style={{ flex: 1 }}>
              <UnLabel theme={theme}>Push-to-talk hotkey</UnLabel>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 8 }}>
                <kbd style={{ ...kbdStyle(theme), fontSize: 15, padding: '6px 12px' }}>⌃</kbd>
                <kbd style={{ ...kbdStyle(theme), fontSize: 15, padding: '6px 12px' }}>⌥</kbd>
                <kbd style={{ ...kbdStyle(theme), fontSize: 15, padding: '6px 12px' }}>Space</kbd>
                <UnBtn theme={theme} sm ghost>Change…</UnBtn>
              </div>
              <div style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.textMuted, marginTop: 8 }}>
                Hold to record, release to submit. Auto-warms a new provider session after each turn.
              </div>
            </div>
            <div style={{
              width: 1, alignSelf: 'stretch', background: theme.divider,
            }}></div>
            <div style={{ flex: 1 }}>
              <UnLabel theme={theme}>Config search path</UnLabel>
              <div style={{
                fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.text, lineHeight: 1.7,
                background: theme.fieldBg, padding: 10, borderRadius: 8,
                border: `1px solid ${theme.divider}`, marginTop: 8,
              }}>
                CLI flag<br />
                <span style={{ color: theme.textMuted }}>./.env</span><br />
                <span style={{ color: theme.accent }}>~/.tool-agents/untype/.env</span><br />
                <span style={{ color: theme.textMuted }}>shell environment</span>
              </div>
            </div>
          </UnGlass>

          {/* Footer actions */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted, flex: 1 }}>
              2 of 3 ready · macOS 14 · Swift 6 · untype 0.4.2
            </div>
            <UnBtn theme={theme} ghost>Skip for now</UnBtn>
            <UnBtn theme={theme} primary>Grant Accessibility</UnBtn>
          </div>
        </UnGlass>
      </div>
    </UnDesktop>
  );
}

function StepCard({ n, title, body, status, theme, strength }) {
  const tone = status === 'granted' ? 'ok' : status === 'action' ? 'warn' : 'accent';
  return (
    <UnGlass theme={theme} strength={strength * 0.7} tone="hi" radius={14} style={{
      padding: 14, display: 'flex', flexDirection: 'column', gap: 8, minHeight: 156,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <span style={{
          width: 22, height: 22, borderRadius: 7, display: 'grid', placeItems: 'center',
          background: theme.accentTint, color: theme.accent,
          fontFamily: UN_FONT_MONO, fontWeight: 700, fontSize: 12,
        }}>{n}</span>
        <span style={{ flex: 1 }}></span>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 6,
          padding: '3px 8px', borderRadius: 999,
          background: tone === 'ok' ? theme.success + '22' : tone === 'warn' ? theme.warn + '22' : theme.accentTint,
          color: tone === 'ok' ? theme.success : tone === 'warn' ? theme.warn : theme.accent,
          fontFamily: UN_FONT_MONO, fontSize: 10, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase',
        }}>
          <UnStatusDot tone={tone === 'ok' ? 'ok' : tone === 'warn' ? 'warn' : 'accent'} theme={theme} size={6} />
          {status}
        </span>
      </div>
      <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 16, fontWeight: 600, color: theme.text, letterSpacing: -0.2 }}>{title}</div>
      <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 12.5, color: theme.textMuted, lineHeight: 1.5 }}>{body}</div>
    </UnGlass>
  );
}

// ─────────────────────────────────────────────────────────────
// Settings — providers & credentials
// macOS Settings.app style: left rail + form column
// ─────────────────────────────────────────────────────────────
function UnSettingsProviders({ theme, strength }) {
  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      <div style={{ padding: '24px 28px', height: 'calc(100% - 26px)', boxSizing: 'border-box' }}>
        <UnGlass theme={theme} strength={strength} radius={22} style={{
          width: '100%', height: '100%', overflow: 'hidden', display: 'flex', flexDirection: 'column',
        }}>
          {/* Titlebar */}
          <div style={{ height: 42, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 14, borderBottom: `1px solid ${theme.divider}`, background: theme.chrome }}>
            <UnTrafficLights />
            <span style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 13, fontWeight: 600, color: theme.text, marginLeft: 6 }}>untype · Settings</span>
            <div style={{ flex: 1 }}></div>
            <UnGlass theme={theme} strength={strength * 0.6} tone="low" radius={8} style={{
              padding: '4px 10px', display: 'inline-flex', alignItems: 'center', gap: 6,
              fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted,
            }}>
              <span style={{ fontSize: 11 }}>⌕</span> Search
            </UnGlass>
          </div>

          <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
            {/* Settings sidebar */}
            <SettingsSidebar theme={theme} active="Providers" />
            {/* Form column */}
            <div style={{ flex: 1, padding: '24px 28px', overflow: 'auto', display: 'flex', flexDirection: 'column', gap: 18 }}>
              <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 24, fontWeight: 600, color: theme.text, letterSpacing: -0.5 }}>Providers & credentials</div>

              {/* STT selector */}
              <UnGlass theme={theme} strength={strength * 0.6} tone="hi" radius={14} style={{ padding: 18 }}>
                <UnSectionTitle theme={theme} sub="Realtime speech-to-text WebSocket provider.">Speech-to-text</UnSectionTitle>
                <ProviderToggleRow theme={theme} options={[
                  { k: 'soniox',     label: 'Soniox',     sub: 'ws.soniox.com', active: true },
                  { k: 'elevenlabs', label: 'ElevenLabs', sub: 'api.elevenlabs.io · realtime' },
                ]} />
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 14 }}>
                  <FieldRow theme={theme} label="Model" v="stt-rt-preview-v2" mono />
                  <FieldRow theme={theme} label="Sample rate" v="16 000 Hz" mono />
                  <FieldRow theme={theme} label="Language hints" v="en, el" mono />
                  <FieldRow theme={theme} label="Endpoint detection" v="on" pill="accent" />
                  <FieldRow theme={theme} label="SONIOX_API_KEY" v="••••••••••••••••••• 41d" mono badge="ok" />
                  <FieldRow theme={theme} label="ELEVENLABS_API_KEY" v="not configured" mono badge="off" />
                </div>
              </UnGlass>

              {/* LLM */}
              <UnGlass theme={theme} strength={strength * 0.6} tone="hi" radius={14} style={{ padding: 18 }}>
                <UnSectionTitle theme={theme} sub="Refinement + translation. Failure is fail-open at the protocol layer.">LLM refiner</UnSectionTitle>
                <ProviderToggleRow theme={theme} options={[
                  { k: 'azure',  label: 'Azure OpenAI', sub: 'Chat Completions · api-key header', active: true },
                  { k: 'google', label: 'Google Gemini', sub: 'generateContent · API key query param' },
                ]} />
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 14 }}>
                  <FieldRow theme={theme} label="Deployment" v="gpt-4o-mini" mono />
                  <FieldRow theme={theme} label="API version" v="2024-08-01-preview" mono />
                  <FieldRow theme={theme} label="Temperature" v="0.2" mono />
                  <FieldRow theme={theme} label="Translation target" v="el  ←→  en" mono pill="accent" />
                  <FieldRow theme={theme} label="AZURE_OAI_KEY" v="••••••• expires 30 May" mono badge="warn" />
                  <FieldRow theme={theme} label="GOOGLE_API_KEY" v="not configured" mono badge="off" />
                </div>
              </UnGlass>

              {/* Accepted-but-unimplemented stubs */}
              <UnGlass theme={theme} strength={strength * 0.5} tone="low" radius={14} style={{ padding: 14 }}>
                <UnLabel theme={theme}>Accepted but unimplemented (raise typed error)</UnLabel>
                <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginTop: 8 }}>
                  {['openai', 'anthropic', 'azure-ai-inference', 'ollama', 'litellm', 'openai-compat'].map((p) => (
                    <span key={p} style={{
                      padding: '4px 10px', borderRadius: 6,
                      background: theme.fieldBg, border: `1px dashed ${theme.divider}`,
                      fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.textMuted,
                    }}>{p}</span>
                  ))}
                </div>
              </UnGlass>
            </div>
          </div>
        </UnGlass>
      </div>
    </UnDesktop>
  );
}

function SettingsSidebar({ theme, active }) {
  const items = [
    { i: '◯', l: 'General' },
    { i: '◉', l: 'Providers' },
    { i: '⌨', l: 'Shortcuts' },
    { i: '◐', l: 'Permissions', tone: 'warn' },
    { i: '◫', l: 'Audio' },
    { i: '✎', l: 'Refinement' },
    { i: '◇', l: 'Overlay' },
    { i: '⚑', l: 'About' },
  ];
  return (
    <div style={{
      width: 200, padding: '14px 10px',
      background: theme.sidebar,
      borderRight: `1px solid ${theme.divider}`,
      display: 'flex', flexDirection: 'column', gap: 2,
    }}>
      {items.map((it) => (
        <div key={it.l} style={{
          display: 'flex', alignItems: 'center', gap: 10, padding: '7px 10px',
          borderRadius: 8,
          background: active === it.l ? theme.accentTint : 'transparent',
          color: active === it.l ? theme.text : theme.textMuted,
          fontFamily: UN_FONT_TEXT, fontSize: 13, fontWeight: active === it.l ? 600 : 500,
        }}>
          <span style={{ width: 18, textAlign: 'center', fontSize: 11, color: it.tone === 'warn' ? theme.warn : active === it.l ? theme.accent : theme.textFaint }}>{it.i}</span>
          <span style={{ flex: 1 }}>{it.l}</span>
          {it.tone === 'warn' && <UnStatusDot tone="warn" theme={theme} size={6} />}
        </div>
      ))}
    </div>
  );
}

function ProviderToggleRow({ options, theme }) {
  return (
    <div style={{ display: 'flex', gap: 10, marginTop: 10 }}>
      {options.map((o) => (
        <div key={o.k} style={{
          flex: 1, padding: 12, borderRadius: 10,
          background: o.active ? theme.accentTint : theme.fieldBg,
          border: `1px solid ${o.active ? theme.accentRing : theme.divider}`,
          display: 'flex', alignItems: 'center', gap: 10,
          boxShadow: o.active ? `0 4px 12px -6px ${theme.accentRing}` : 'none',
        }}>
          <span style={{
            width: 18, height: 18, borderRadius: 999,
            background: o.active ? theme.accent : 'transparent',
            border: `1.5px solid ${o.active ? theme.accent : theme.divider}`,
            boxShadow: o.active ? `inset 0 0 0 4px ${o.active ? '#fff' : 'transparent'}` : 'none',
          }}></span>
          <div style={{ flex: 1 }}>
            <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 13, fontWeight: 600, color: theme.text }}>{o.label}</div>
            <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted, marginTop: 2 }}>{o.sub}</div>
          </div>
        </div>
      ))}
    </div>
  );
}

function FieldRow({ label, v, mono, pill, badge, theme }) {
  return (
    <div>
      <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 11, color: theme.textMuted, marginBottom: 4, fontWeight: 500 }}>{label}</div>
      <div style={{
        height: 32, padding: '0 10px', borderRadius: 8,
        background: theme.fieldBg, border: `1px solid ${theme.divider}`,
        display: 'flex', alignItems: 'center', gap: 8,
        fontFamily: mono ? UN_FONT_MONO : UN_FONT_TEXT,
        fontSize: mono ? 12 : 13,
        color: theme.text,
      }}>
        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{v}</span>
        {pill && <span style={{
          padding: '1px 7px', borderRadius: 4, fontFamily: UN_FONT_MONO, fontSize: 10, fontWeight: 700,
          background: theme.accentTint, color: theme.accent, letterSpacing: 0.4, textTransform: 'uppercase',
        }}>on</span>}
        {badge === 'ok'   && <UnStatusDot tone="ok"   theme={theme} size={6} />}
        {badge === 'warn' && <UnStatusDot tone="warn" theme={theme} size={6} />}
        {badge === 'off'  && <UnStatusDot tone="off"  theme={theme} size={6} />}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Settings — push-to-talk & shortcuts
// ─────────────────────────────────────────────────────────────
function UnSettingsShortcuts({ theme, strength }) {
  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      <div style={{ padding: '24px 28px', height: 'calc(100% - 26px)', boxSizing: 'border-box' }}>
        <UnGlass theme={theme} strength={strength} radius={22} style={{
          width: '100%', height: '100%', overflow: 'hidden', display: 'flex', flexDirection: 'column',
        }}>
          <div style={{ height: 42, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 14, borderBottom: `1px solid ${theme.divider}`, background: theme.chrome }}>
            <UnTrafficLights />
            <span style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 13, fontWeight: 600, color: theme.text, marginLeft: 6 }}>untype · Settings</span>
          </div>
          <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
            <SettingsSidebar theme={theme} active="Shortcuts" />
            <div style={{ flex: 1, padding: '24px 28px', overflow: 'auto', display: 'flex', flexDirection: 'column', gap: 18 }}>
              <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 24, fontWeight: 600, color: theme.text, letterSpacing: -0.5 }}>Push-to-talk & shortcuts</div>

              {/* PTT recorder */}
              <UnGlass theme={theme} strength={strength * 0.6} tone="hi" radius={14} style={{ padding: 18 }}>
                <UnSectionTitle theme={theme} sub="Quartz event-tap path. AppKit monitor used as fallback.">Push-to-talk</UnSectionTitle>
                <div style={{
                  marginTop: 12, padding: 16, borderRadius: 14,
                  background: theme.accentTint, border: `1px dashed ${theme.accentRing}`,
                  display: 'flex', alignItems: 'center', gap: 14,
                }}>
                  <UnStatusDot tone="accent" theme={theme} />
                  <div style={{ flex: 1 }}>
                    <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.accent, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase' }}>Active hotkey</div>
                    <div style={{ marginTop: 6, display: 'flex', gap: 6, alignItems: 'center' }}>
                      <kbd style={{ ...kbdStyle(theme), fontSize: 16, padding: '6px 12px' }}>⌃</kbd>
                      <kbd style={{ ...kbdStyle(theme), fontSize: 16, padding: '6px 12px' }}>⌥</kbd>
                      <kbd style={{ ...kbdStyle(theme), fontSize: 16, padding: '6px 12px' }}>Space</kbd>
                      <span style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.textMuted, marginLeft: 10 }}>installed via CGEvent tap</span>
                    </div>
                  </div>
                  <UnBtn theme={theme}>Record new…</UnBtn>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 14 }}>
                  <FieldRow theme={theme} label="Press to toggle (fallback)" v="off" pill="accent" />
                  <FieldRow theme={theme} label="Auto-warm session" v="enabled" pill="accent" />
                  <FieldRow theme={theme} label="Finalization timeout" v="900 ms" mono />
                  <FieldRow theme={theme} label="Key-repeat guard" v="on" mono pill="accent" />
                </div>
              </UnGlass>

              {/* Operator hotkeys */}
              <UnGlass theme={theme} strength={strength * 0.6} tone="hi" radius={14} style={{ padding: 18 }}>
                <UnSectionTitle theme={theme} sub="Toggle operators live during a recording. These are routed through the same channel as UI switches.">Operator hotkeys</UnSectionTitle>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 12 }}>
                  {[
                    ['R', 'Refine',    '⌃⌥⇧R'],
                    ['T', 'Translate', '⌃⌥⇧T'],
                    ['C', 'Clipboard', '⌃⌥⇧C'],
                    ['I', 'Focused input', '⌃⌥⇧I'],
                  ].map(([k, l, kb]) => (
                    <div key={k} style={{
                      display: 'flex', alignItems: 'center', gap: 12,
                      padding: '8px 12px', borderRadius: 10,
                      background: theme.fieldBg, border: `1px solid ${theme.divider}`,
                    }}>
                      <span style={{
                        width: 28, height: 28, borderRadius: 7, display: 'grid', placeItems: 'center',
                        background: theme.accentTint, color: theme.accent,
                        fontFamily: UN_FONT_MONO, fontWeight: 700, fontSize: 13,
                      }}>{k}</span>
                      <span style={{ flex: 1, fontFamily: UN_FONT_TEXT, fontSize: 13, color: theme.text }}>{l}</span>
                      <kbd style={kbdStyle(theme)}>{kb}</kbd>
                    </div>
                  ))}
                </div>
              </UnGlass>

              {/* Audio device */}
              <UnGlass theme={theme} strength={strength * 0.6} tone="hi" radius={14} style={{ padding: 18 }}>
                <UnSectionTitle theme={theme}>Input device</UnSectionTitle>
                <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 12, marginTop: 12 }}>
                  <FieldRow theme={theme} label="Microphone" v="MacBook Air Microphone (built-in)" />
                  <FieldRow theme={theme} label="Sample rate" v="16 000 Hz" mono pill="accent" />
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 14, padding: 12, borderRadius: 12, background: theme.fieldBg, border: `1px solid ${theme.divider}` }}>
                  <UnStatusDot tone="ok" theme={theme} />
                  <span style={{ fontFamily: UN_FONT_TEXT, fontSize: 13, color: theme.text, flex: 1 }}>Audio · active</span>
                  <UnWaveform theme={theme} recording bars={24} height={22} />
                  <span style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.recording, fontWeight: 600 }}>−16dB</span>
                </div>
              </UnGlass>
            </div>
          </div>
        </UnGlass>
      </div>
    </UnDesktop>
  );
}

// ─────────────────────────────────────────────────────────────
// Session history browser
// ─────────────────────────────────────────────────────────────
function UnHistory({ theme, strength }) {
  const sessions = [
    { id: 's1', date: 'Today · 10:38',     turns: 14, dur: '8m 12s', tags: ['refine','clipboard','input'], active: true },
    { id: 's2', date: 'Today · 09:04',     turns: 8,  dur: '4m 20s', tags: ['refine','translate'] },
    { id: 's3', date: 'Yesterday · 16:22', turns: 21, dur: '12m 04s', tags: ['refine','input'] },
    { id: 's4', date: 'Yesterday · 11:01', turns: 6,  dur: '2m 50s', tags: ['refine'] },
    { id: 's5', date: 'Mon, 23 May',       turns: 31, dur: '18m 33s', tags: ['refine','translate','clipboard','input'] },
    { id: 's6', date: 'Mon, 23 May',       turns: 5,  dur: '1m 41s', tags: ['refine'] },
  ];

  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      <div style={{ padding: '24px 28px', height: 'calc(100% - 26px)', boxSizing: 'border-box' }}>
        <UnGlass theme={theme} strength={strength} radius={22} style={{
          width: '100%', height: '100%', overflow: 'hidden', display: 'flex', flexDirection: 'column',
        }}>
          {/* Titlebar */}
          <div style={{ height: 44, padding: '0 14px', display: 'flex', alignItems: 'center', gap: 14, borderBottom: `1px solid ${theme.divider}`, background: theme.chrome }}>
            <UnTrafficLights />
            <span style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 13, fontWeight: 600, color: theme.text, marginLeft: 6 }}>Session history</span>
            <div style={{ flex: 1 }}></div>
            <UnTabs tabs={['All', 'Refined', 'Translated', 'Warnings']} active="All" theme={theme} />
            <UnGlass theme={theme} strength={strength * 0.6} tone="low" radius={8} style={{
              padding: '4px 10px', display: 'inline-flex', alignItems: 'center', gap: 6,
              fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted, marginLeft: 8,
            }}>
              <span style={{ fontSize: 11 }}>⌕</span> Search transcripts
            </UnGlass>
          </div>

          <div style={{ flex: 1, display: 'flex', minHeight: 0 }}>
            {/* Sessions list */}
            <div style={{ width: 280, background: theme.sidebar, borderRight: `1px solid ${theme.divider}`, padding: 10, overflow: 'auto' }}>
              {sessions.map((s) => <SessionRow key={s.id} s={s} theme={theme} />)}
            </div>

            {/* Session detail */}
            <div style={{ flex: 1, padding: '20px 26px', overflow: 'auto', display: 'flex', flexDirection: 'column', gap: 16 }}>
              <div style={{ display: 'flex', alignItems: 'flex-start', gap: 16 }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.accent, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase' }}>Active session</div>
                  <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 26, fontWeight: 600, color: theme.text, marginTop: 4, letterSpacing: -0.5 }}>Today, 10:38 → 10:46</div>
                  <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 13, color: theme.textMuted, marginTop: 4 }}>
                    soniox · azure-openai · hybrid · 14 turns · 3 protocol commands
                  </div>
                </div>
                <UnBtn theme={theme} icon={<span>⎘</span>}>Copy session</UnBtn>
                <UnBtn theme={theme} icon={<span>↗</span>}>Export JSONL</UnBtn>
              </div>

              {/* Summary stats */}
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 10 }}>
                <StatTile theme={theme} l="Refine"        v="14" sub="100% applied" tone="ok" />
                <StatTile theme={theme} l="Translate"     v="3"  sub="el · 380ms avg" tone="accent" />
                <StatTile theme={theme} l="Clipboard"     v="6" />
                <StatTile theme={theme} l="Input"         v="5" sub="1 ax denied" tone="warn" />
              </div>

              {/* Turn list */}
              <UnGlass theme={theme} strength={strength * 0.6} tone="low" radius={14} style={{ padding: 4, flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
                <div style={{ flex: 1, overflow: 'auto', padding: 12, display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {UN_TRANSCRIPT.filter((t) => t.kind === 'committed').map((t) => <HistoryTurn key={t.id} t={t} theme={theme} />)}
                  <HistoryWarning theme={theme} text="No final transcript received within 900ms — submitted latest partial." />
                </div>
              </UnGlass>
            </div>
          </div>
        </UnGlass>
      </div>
    </UnDesktop>
  );
}

function SessionRow({ s, theme }) {
  return (
    <div style={{
      padding: 12, borderRadius: 10,
      background: s.active ? theme.accentTint : 'transparent',
      border: `1px solid ${s.active ? theme.accentRing : 'transparent'}`,
      marginBottom: 4,
      display: 'flex', flexDirection: 'column', gap: 4,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        {s.active && <UnStatusDot tone="rec" theme={theme} size={6} />}
        <span style={{ fontFamily: UN_FONT_TEXT, fontSize: 12.5, fontWeight: 600, color: theme.text }}>{s.date}</span>
      </div>
      <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted }}>{s.turns} turns · {s.dur}</div>
      <div style={{ display: 'flex', gap: 4, marginTop: 4 }}>
        {s.tags.map((t) => (
          <span key={t} style={{
            padding: '1px 6px', borderRadius: 4,
            background: theme.glassLow, border: `1px solid ${theme.divider}`,
            fontFamily: UN_FONT_MONO, fontSize: 9.5, color: theme.textMuted, fontWeight: 600,
          }}>{t}</span>
        ))}
      </div>
    </div>
  );
}

function StatTile({ l, v, sub, tone, theme }) {
  return (
    <div style={{
      padding: 12, borderRadius: 12,
      background: theme.glassHi, border: `1px solid ${theme.glassStroke}`,
    }}>
      <UnLabel theme={theme}>{l}</UnLabel>
      <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 24, fontWeight: 600, color: theme.text, marginTop: 4, letterSpacing: -0.6, display: 'flex', alignItems: 'center', gap: 8 }}>
        {tone && <UnStatusDot tone={tone} theme={theme} />}{v}
      </div>
      {sub && <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted, marginTop: 2 }}>{sub}</div>}
    </div>
  );
}

function HistoryTurn({ t, theme }) {
  return (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
      <div style={{ width: 60, flex: '0 0 60px', paddingTop: 2 }}>
        <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textFaint }}>{t.time}</div>
        <div style={{ fontFamily: UN_FONT_MONO, fontSize: 9.5, color: theme.textFaint, marginTop: 2 }}>sec_{(parseInt(t.id.slice(1)) + 5).toString().padStart(6, '0')}</div>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted, fontStyle: 'italic', lineHeight: 1.45 }}>
          “{t.raw}”
        </div>
        {t.refined && (
          <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 14, color: theme.text, lineHeight: 1.45, marginTop: 4, paddingLeft: 10, borderLeft: `2px solid ${theme.accent}` }}>
            {t.refined}
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
    </div>
  );
}

function HistoryWarning({ text, theme }) {
  return (
    <div style={{
      display: 'flex', gap: 10, alignItems: 'center',
      padding: '8px 12px', borderRadius: 10,
      background: theme.warn + '15', border: `1px solid ${theme.warn}33`,
    }}>
      <UnStatusDot tone="warn" theme={theme} />
      <span style={{ fontFamily: UN_FONT_TEXT, fontSize: 12.5, color: theme.text, fontWeight: 500 }}>Session warning</span>
      <span style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.textMuted, flex: 1 }}>{text}</span>
    </div>
  );
}

Object.assign(window, { UnOnboarding, UnSettingsProviders, UnSettingsShortcuts, UnHistory });
