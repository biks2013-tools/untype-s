// untype — peripheral surfaces: overlay, menubar dropdown, compact mini

// ─────────────────────────────────────────────────────────────
// Recording overlay — non-activating floating panel at bottom of screen
// Three variants: A (bar), B (pill), C (card).
// Each artboard shows a desktop slice with the overlay positioned.
// ─────────────────────────────────────────────────────────────
function UnOverlayStage({ theme, strength, variant }) {
  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      {/* A "ghost" app window in the back to show the non-activating overlay */}
      <div style={{ position: 'absolute', inset: '46px 60px 120px 60px' }}>
        <UnGlass theme={theme} strength={strength * 0.6} radius={18} style={{ width: '100%', height: '100%', opacity: 0.85 }}>
          <div style={{ height: 38, padding: '0 12px', display: 'flex', alignItems: 'center', gap: 10, borderBottom: `1px solid ${theme.divider}`, background: theme.chrome }}>
            <UnTrafficLights inactive />
            <span style={{ fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted, marginLeft: 6 }}>Mail — Drafts</span>
          </div>
          <div style={{ padding: '18px 22px', fontFamily: UN_FONT_TEXT, fontSize: 13, color: theme.textMuted, lineHeight: 1.6 }}>
            <div style={{ fontWeight: 600, fontSize: 14, color: theme.text, marginBottom: 6 }}>Re: Partnership renewal</div>
            <div>Hi Alex,</div>
            <div style={{ marginTop: 8 }}>Thanks for the note. Quick reply — </div>
            <div style={{ display: 'inline-block', height: 14, width: 2, background: theme.accent, animation: 'unblink 1s steps(2) infinite', verticalAlign: 'middle' }}></div>
          </div>
        </UnGlass>
      </div>

      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 28, display: 'flex', justifyContent: 'center' }}>
        {variant === 'A' && <OverlayBar theme={theme} strength={strength} />}
        {variant === 'B' && <OverlayPill theme={theme} strength={strength} />}
        {variant === 'C' && <OverlayCard theme={theme} strength={strength} />}
      </div>
    </UnDesktop>
  );
}

function OverlayBar({ theme, strength }) {
  return (
    <UnGlass theme={theme} strength={Math.min(1, strength + 0.2)} tone="hi" radius={18} style={{
      width: 'min(680px, 80%)', padding: '14px 18px',
      display: 'flex', flexDirection: 'column', gap: 10,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <UnStatusDot tone="rec" theme={theme} />
        <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, letterSpacing: 0.6, color: theme.recording, fontWeight: 700, textTransform: 'uppercase' }}>recording</span>
        <span style={{ fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted }}>·  Soniox · sec_000007</span>
        <div style={{ flex: 1 }}></div>
        <UnWaveform theme={theme} recording bars={20} height={20} />
      </div>
      <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 16, color: theme.text, lineHeight: 1.45, fontWeight: 500 }}>
        and finally draft the reply to the partnership thread keeping it short
        <span style={{ color: theme.accent }}> ▋</span>
      </div>
      {/* Bottom operator row */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 2 }}>
        <div style={{ display: 'flex', gap: 4 }}>
          {[['R',true],['T',false],['C',true],['I',true]].map(([k, on]) => (
            <span key={k} style={{
              width: 22, height: 22, borderRadius: 6, display: 'grid', placeItems: 'center',
              background: on ? theme.accentTint : 'transparent',
              color: on ? theme.accent : theme.textFaint,
              border: `1px solid ${on ? theme.accentRing : theme.divider}`,
              fontFamily: UN_FONT_MONO, fontSize: 11, fontWeight: 700,
            }}>{k}</span>
          ))}
        </div>
        <div style={{ flex: 1 }}></div>
        <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted, marginRight: 4 }}>release ⌃⌥Space to submit</span>
      </div>
    </UnGlass>
  );
}

function OverlayPill({ theme, strength }) {
  return (
    <UnGlass theme={theme} strength={Math.min(1, strength + 0.25)} tone="hi" radius={999} style={{
      maxWidth: '88%', padding: '8px 18px 8px 10px',
      display: 'inline-flex', alignItems: 'center', gap: 14,
    }}>
      <div style={{
        width: 32, height: 32, borderRadius: 999, display: 'grid', placeItems: 'center',
        background: `linear-gradient(180deg, ${theme.recording}, #b8332b)`, color: '#fff',
        fontFamily: UN_FONT_MONO, fontWeight: 800, fontSize: 11,
        boxShadow: `0 0 0 4px ${theme.recordingTint}`,
      }}>REC</div>
      <UnWaveform theme={theme} recording bars={16} height={22} />
      <div style={{
        fontFamily: UN_FONT_TEXT, fontSize: 14, color: theme.text, fontWeight: 500,
        maxWidth: 360, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
      }}>
        and finally draft the reply to the partnership
      </div>
      <div style={{ display: 'flex', gap: 3 }}>
        {[['R',true],['T',false],['C',true],['I',true]].map(([k, on]) => (
          <span key={k} style={{
            width: 18, height: 18, borderRadius: 5, display: 'grid', placeItems: 'center',
            background: on ? theme.accent : 'transparent',
            color: on ? '#fff' : theme.textFaint,
            border: `1px solid ${on ? theme.accent : theme.divider}`,
            fontFamily: UN_FONT_MONO, fontSize: 10, fontWeight: 700,
          }}>{k}</span>
        ))}
      </div>
    </UnGlass>
  );
}

function OverlayCard({ theme, strength }) {
  return (
    <UnGlass theme={theme} strength={Math.min(1, strength + 0.2)} tone="hi" radius={22} style={{
      width: 'min(520px, 78%)', padding: 16, display: 'flex', flexDirection: 'column', gap: 12,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{
          width: 36, height: 36, borderRadius: 999, display: 'grid', placeItems: 'center',
          background: theme.recordingTint, border: `1.5px solid ${theme.recording}`,
        }}>
          <div style={{ width: 12, height: 12, borderRadius: 3, background: theme.recording }}></div>
        </div>
        <div>
          <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 13, fontWeight: 600, color: theme.text, lineHeight: 1.1 }}>Push-to-talk</div>
          <div style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted }}>soniox · 1.21s · sec_000007</div>
        </div>
        <div style={{ flex: 1 }}></div>
        <UnWaveform theme={theme} recording bars={14} height={22} />
      </div>
      <div style={{
        fontFamily: UN_FONT_TEXT, fontSize: 17, color: theme.text, lineHeight: 1.45, fontWeight: 500,
        padding: '10px 12px', borderRadius: 12, background: theme.glassLow,
        border: `1px solid ${theme.divider}`,
      }}>
        and finally draft the reply to the partnership thread keeping it short
        <span style={{ color: theme.accent }}> ▋</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <div style={{ display: 'flex', gap: 4 }}>
          {[['R','Refine',true],['T','Translate',false],['C','Clipboard',true],['I','Input',true]].map(([k,l,on]) => (
            <UnOperatorPill key={k} letter={k} label={l} on={on} recording theme={theme} size="sm" />
          ))}
        </div>
        <div style={{ flex: 1 }}></div>
        <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted }}>release to submit</span>
      </div>
    </UnGlass>
  );
}

// ─────────────────────────────────────────────────────────────
// Menubar dropdown — small mac-style popover from menubar
// ─────────────────────────────────────────────────────────────
function UnMenubarDropdown({ theme, strength }) {
  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      {/* Spotlight on the "ut" menubar item */}
      <div style={{
        position: 'absolute', top: 6, right: 78, width: 38, height: 18,
        borderRadius: 6, background: theme.accentTint,
        border: `1px solid ${theme.accentRing}`,
      }}></div>

      {/* Dropdown popover */}
      <div style={{
        position: 'absolute', top: 34, right: 28, width: 340,
      }}>
        <UnGlass theme={theme} strength={Math.min(1, strength + 0.2)} radius={16} tone="hi" style={{ padding: 14, display: 'flex', flexDirection: 'column', gap: 12 }}>
          {/* Title block */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <UnBrandMark size={32} theme={theme} />
            <div>
              <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 14, fontWeight: 600, color: theme.text }}>untype</div>
              <div style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.textMuted, display: 'flex', alignItems: 'center', gap: 4 }}>
                <UnStatusDot tone="accent" theme={theme} size={6} /> warm · soniox
              </div>
            </div>
            <div style={{ flex: 1 }}></div>
            <UnBtn theme={theme} sm primary>Listen</UnBtn>
          </div>

          {/* Hotkey */}
          <UnGlass theme={theme} strength={strength * 0.6} tone="low" radius={10} style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted, flex: 1 }}>Push to talk</span>
            <kbd style={kbdStyle(theme)}>⌃⌥Space</kbd>
          </UnGlass>

          {/* Operator toggles */}
          <div>
            <UnLabel theme={theme} style={{ marginBottom: 6 }}>Operators</UnLabel>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6 }}>
              {[['R','Refine',true],['T','Translate',false],['C','Clipboard',true],['I','Input',true]].map(([k,l,on]) => (
                <UnOperatorPill key={k} letter={k} label={l} on={on} theme={theme} size="sm" />
              ))}
            </div>
          </div>

          {/* Last activity */}
          <div>
            <UnLabel theme={theme} style={{ marginBottom: 6 }}>Last turn · 10:41</UnLabel>
            <div style={{
              fontFamily: UN_FONT_TEXT, fontSize: 13, color: theme.text, lineHeight: 1.45,
              padding: '8px 10px', borderRadius: 9, background: theme.glassLow,
              border: `1px solid ${theme.divider}`,
            }}>
              Schedule a follow-up with Sara for Thursday 3:00 pm.
            </div>
          </div>

          {/* Footer rows */}
          <div style={{ borderTop: `1px solid ${theme.divider}`, paddingTop: 8, display: 'flex', flexDirection: 'column', gap: 2, fontFamily: UN_FONT_TEXT, fontSize: 12 }}>
            <MenuRow theme={theme} l="Open Window…"     k="⌘1" />
            <MenuRow theme={theme} l="Session History"  k="⌘Y" />
            <MenuRow theme={theme} l="Settings…"        k="⌘," />
            <MenuRow theme={theme} l="Permissions"      tone="warn" badge="action" />
            <MenuRow theme={theme} l="Quit untype"      k="⌘Q" />
          </div>
        </UnGlass>
      </div>
    </UnDesktop>
  );
}

function MenuRow({ l, k, tone, badge, theme }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px',
      borderRadius: 7, color: tone === 'warn' ? theme.warn : theme.text,
    }}>
      <span style={{ flex: 1 }}>{l}</span>
      {badge && (
        <span style={{
          padding: '1px 7px', borderRadius: 999,
          background: theme.warn + '22', color: theme.warn,
          fontFamily: UN_FONT_MONO, fontSize: 10, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase',
        }}>{badge}</span>
      )}
      {k && <span style={{ fontFamily: UN_FONT_MONO, fontSize: 11, color: theme.textMuted }}>{k}</span>}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Compact mini window — always-on-top tiny console
// ─────────────────────────────────────────────────────────────
function UnMini({ theme, strength, recording = true }) {
  return (
    <UnDesktop theme={theme}>
      <UnMenuBar theme={theme} strength={strength} />
      <div style={{ height: 'calc(100% - 26px)', display: 'grid', placeItems: 'center', padding: 30 }}>
        <UnGlass theme={theme} strength={Math.min(1, strength + 0.15)} tone="hi" radius={20} style={{
          width: 440, padding: 16, display: 'flex', flexDirection: 'column', gap: 12,
        }}>
          {/* Mini titlebar */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <UnTrafficLights />
            <div style={{ flex: 1 }}></div>
            <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted }}>mini</span>
          </div>

          {/* Status row */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <UnBrandMark size={36} theme={theme} />
            <div style={{ flex: 1 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <UnStatusDot tone={recording ? 'rec' : 'accent'} theme={theme} />
                <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, fontWeight: 700, letterSpacing: 0.7, textTransform: 'uppercase', color: recording ? theme.recording : theme.accent }}>
                  {recording ? 'recording' : 'warm'}
                </span>
                <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: theme.textMuted }}>·  soniox</span>
              </div>
              <div style={{ fontFamily: UN_FONT_DISPLAY, fontSize: 17, fontWeight: 600, color: theme.text, marginTop: 2, letterSpacing: -0.3 }}>
                sec_000007 · {recording ? '0:04' : 'idle'}
              </div>
            </div>
            <UnRecordButton recording={recording} theme={theme} />
          </div>

          {/* Live partial */}
          <UnGlass theme={theme} strength={strength * 0.5} tone="low" radius={12} style={{ padding: 10 }}>
            <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 13, color: recording ? theme.text : theme.textFaint, lineHeight: 1.4, fontStyle: recording ? 'normal' : 'italic' }}>
              {recording
                ? 'draft the reply keeping it short'
                : 'press ⌃⌥Space'}
              {recording && <span style={{ color: theme.accent }}> ▋</span>}
            </div>
          </UnGlass>

          {/* Operator strip + waveform */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{ display: 'flex', gap: 4 }}>
              {[['R',true],['T',false],['C',true],['I',true]].map(([k, on]) => (
                <span key={k} style={{
                  width: 22, height: 22, borderRadius: 6, display: 'grid', placeItems: 'center',
                  background: on ? theme.accentTint : 'transparent',
                  color: on ? theme.accent : theme.textFaint,
                  border: `1px solid ${on ? theme.accentRing : theme.divider}`,
                  fontFamily: UN_FONT_MONO, fontSize: 11, fontWeight: 700,
                }}>{k}</span>
              ))}
            </div>
            <div style={{ flex: 1 }}></div>
            <UnWaveform theme={theme} recording={recording} bars={20} height={22} />
            <span style={{ fontFamily: UN_FONT_MONO, fontSize: 10.5, color: recording ? theme.recording : theme.textMuted, fontWeight: 600 }}>
              {recording ? '−18dB' : 'silent'}
            </span>
          </div>
        </UnGlass>
      </div>
    </UnDesktop>
  );
}

Object.assign(window, { UnOverlayStage, UnMenubarDropdown, UnMini });
