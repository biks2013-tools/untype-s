// untype — shared design tokens + glass primitives
// macOS Tahoe / Liquid Glass aesthetic, warm amber accent.

const UN_FONT_DISPLAY = '"Inter Tight", "SF Pro Display", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';
const UN_FONT_TEXT = '"Inter", "SF Pro Text", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';
const UN_FONT_MONO = '"JetBrains Mono", "SF Mono", ui-monospace, Menlo, monospace';

// Two themes share the same shape; theme picker swaps which one is active.
const UN_THEMES = {
  light: {
    name: 'light',
    desktop: 'radial-gradient(110% 80% at 20% 10%, #ffd9a8 0%, #ffe7c8 30%, #f5d9b8 55%, #e8b682 80%, #c98144 100%)',
    glass: 'rgba(255, 251, 244, 0.62)',
    glassHi: 'rgba(255, 253, 248, 0.78)',
    glassLow: 'rgba(255, 250, 242, 0.42)',
    glassStroke: 'rgba(255, 255, 255, 0.55)',
    glassEdge: 'rgba(120, 70, 20, 0.10)',
    text: '#1f1812',
    textMuted: 'rgba(31, 24, 18, 0.58)',
    textFaint: 'rgba(31, 24, 18, 0.34)',
    fieldBg: 'rgba(255, 252, 245, 0.85)',
    divider: 'rgba(60, 40, 20, 0.10)',
    accent: '#e0851c',           // amber primary
    accentHi: '#f5a342',
    accentTint: 'rgba(224, 133, 28, 0.14)',
    accentRing: 'rgba(224, 133, 28, 0.35)',
    recording: '#e0413a',
    recordingTint: 'rgba(224, 65, 58, 0.16)',
    success: '#239f5a',
    warn: '#cb8a1a',
    sidebar: 'rgba(255, 248, 235, 0.50)',
    chrome: 'rgba(255, 251, 244, 0.78)',
    statusbar: 'rgba(255, 251, 244, 0.55)',
    shadow: '0 30px 80px -20px rgba(60, 30, 10, 0.30), 0 8px 24px -12px rgba(60, 30, 10, 0.20)',
    innerHi: 'inset 0 1px 0 rgba(255, 255, 255, 0.7), inset 0 0 0 1px rgba(255, 255, 255, 0.35)',
  },
  dark: {
    name: 'dark',
    desktop: 'radial-gradient(120% 90% at 25% 15%, #4a2a18 0%, #2a1a12 35%, #1a120c 65%, #0c0805 100%)',
    glass: 'rgba(40, 30, 22, 0.58)',
    glassHi: 'rgba(56, 42, 30, 0.72)',
    glassLow: 'rgba(30, 22, 16, 0.38)',
    glassStroke: 'rgba(255, 220, 180, 0.08)',
    glassEdge: 'rgba(0, 0, 0, 0.40)',
    text: '#f6ecdc',
    textMuted: 'rgba(246, 236, 220, 0.62)',
    textFaint: 'rgba(246, 236, 220, 0.34)',
    fieldBg: 'rgba(20, 14, 10, 0.55)',
    divider: 'rgba(255, 220, 180, 0.08)',
    accent: '#f5a342',
    accentHi: '#ffc572',
    accentTint: 'rgba(245, 163, 66, 0.18)',
    accentRing: 'rgba(245, 163, 66, 0.45)',
    recording: '#ff5a4d',
    recordingTint: 'rgba(255, 90, 77, 0.20)',
    success: '#3ad17a',
    warn: '#f0b94f',
    sidebar: 'rgba(28, 20, 14, 0.50)',
    chrome: 'rgba(30, 22, 16, 0.70)',
    statusbar: 'rgba(20, 14, 10, 0.55)',
    shadow: '0 30px 80px -20px rgba(0, 0, 0, 0.65), 0 8px 24px -12px rgba(0, 0, 0, 0.45)',
    innerHi: 'inset 0 1px 0 rgba(255, 230, 200, 0.10), inset 0 0 0 1px rgba(255, 230, 200, 0.05)',
  },
};

// Material strength tweak: 0 (clear, less blur) → 1 (heavy glass)
function unMaterial(theme, strength = 0.6) {
  const blur = Math.round(14 + strength * 26); // 14..40
  const sat = (130 + strength * 70).toFixed(0); // 130..200
  return {
    background: theme.glass,
    backdropFilter: `blur(${blur}px) saturate(${sat}%)`,
    WebkitBackdropFilter: `blur(${blur}px) saturate(${sat}%)`,
    border: `1px solid ${theme.glassStroke}`,
    boxShadow: `${theme.shadow}, ${theme.innerHi}`,
  };
}

// ─── Mac window chrome ─────────────────────────────────────────
function UnTrafficLights({ inactive = false }) {
  const dot = (color) => ({
    width: 12, height: 12, borderRadius: 999,
    background: inactive ? 'rgba(128,128,128,0.35)' : color,
    boxShadow: inactive ? 'none' : 'inset 0 0 0 0.5px rgba(0,0,0,0.15)',
  });
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
      <div style={dot('#ff5f57')}></div>
      <div style={dot('#febc2e')}></div>
      <div style={dot('#28c840')}></div>
    </div>
  );
}

// Brand mark — "ut" monogram in a softly glowing amber square
function UnBrandMark({ size = 28, theme }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: size * 0.28,
      background: `linear-gradient(155deg, ${theme.accentHi} 0%, ${theme.accent} 100%)`,
      boxShadow: `0 6px 14px -4px ${theme.accentRing}, inset 0 1px 0 rgba(255,255,255,0.45), inset 0 -1px 0 rgba(0,0,0,0.15)`,
      display: 'grid', placeItems: 'center',
      color: '#fff', fontFamily: UN_FONT_DISPLAY,
      fontWeight: 700, fontSize: size * 0.46, letterSpacing: -0.5,
      lineHeight: 1,
    }}>
      <span style={{ transform: 'translateY(-1px)' }}>u</span>
    </div>
  );
}

// ─── Glass panels ──────────────────────────────────────────────
function UnGlass({ theme, strength, radius = 20, style, children, tone = 'base', ...rest }) {
  const mat = unMaterial(theme, strength);
  if (tone === 'hi') mat.background = theme.glassHi;
  if (tone === 'low') mat.background = theme.glassLow;
  return (
    <div style={{ ...mat, borderRadius: radius, position: 'relative', ...style }} {...rest}>
      {children}
    </div>
  );
}

// ─── Operator pill ─────────────────────────────────────────────
// R/T/C/I — glassy pill with live status light
function UnOperatorPill({ letter, label, on, theme, onClick, recording = false, size = 'md' }) {
  const sz = size === 'sm' ? { h: 28, px: 10, fs: 12 } : { h: 36, px: 14, fs: 13 };
  const dotColor = !on ? theme.textFaint : recording ? theme.recording : theme.accent;
  return (
    <button onClick={onClick} style={{
      height: sz.h, padding: `0 ${sz.px}px`,
      display: 'inline-flex', alignItems: 'center', gap: 8,
      borderRadius: 999,
      background: on ? theme.accentTint : theme.glassLow,
      border: `1px solid ${on ? theme.accentRing : theme.glassStroke}`,
      color: on ? theme.text : theme.textMuted,
      fontFamily: UN_FONT_TEXT, fontSize: sz.fs, fontWeight: 600,
      letterSpacing: 0.2,
      backdropFilter: 'blur(12px) saturate(160%)',
      WebkitBackdropFilter: 'blur(12px) saturate(160%)',
      cursor: 'pointer', transition: 'all 140ms ease',
      boxShadow: on
        ? `inset 0 1px 0 rgba(255,255,255,0.20), 0 4px 10px -4px ${theme.accentRing}`
        : 'inset 0 1px 0 rgba(255,255,255,0.10)',
    }}>
      <span style={{
        width: 7, height: 7, borderRadius: 999, background: dotColor,
        boxShadow: on && recording
          ? `0 0 0 3px ${theme.recordingTint}, 0 0 8px ${theme.recording}`
          : on ? `0 0 0 3px ${theme.accentTint}, 0 0 6px ${theme.accent}` : 'none',
        transition: 'all 200ms ease',
      }}></span>
      <span style={{
        fontFamily: UN_FONT_MONO, fontWeight: 700, fontSize: sz.fs,
        color: on ? theme.accent : theme.textMuted,
      }}>{letter}</span>
      <span>{label}</span>
    </button>
  );
}

// ─── Record button — large amber/recording-red action ─────────
function UnRecordButton({ recording, onClick, theme, label }) {
  return (
    <button onClick={onClick} style={{
      height: 44, padding: '0 18px 0 14px',
      display: 'inline-flex', alignItems: 'center', gap: 10,
      borderRadius: 999,
      background: recording
        ? `linear-gradient(180deg, ${theme.recording} 0%, #b8332b 100%)`
        : `linear-gradient(180deg, ${theme.accentHi} 0%, ${theme.accent} 100%)`,
      border: '1px solid rgba(255,255,255,0.20)',
      color: '#fff',
      fontFamily: UN_FONT_TEXT, fontSize: 14, fontWeight: 600,
      letterSpacing: 0.1,
      boxShadow: recording
        ? `0 10px 28px -10px ${theme.recording}, inset 0 1px 0 rgba(255,255,255,0.30)`
        : `0 10px 28px -10px ${theme.accentRing}, inset 0 1px 0 rgba(255,255,255,0.30)`,
      cursor: 'pointer', transition: 'all 160ms ease',
    }}>
      <span style={{
        width: 18, height: 18, borderRadius: recording ? 4 : 999,
        background: '#fff',
        transition: 'all 220ms ease',
        boxShadow: recording ? '0 0 0 2px rgba(255,255,255,0.15), 0 0 14px rgba(255,255,255,0.55)' : 'none',
      }}></span>
      {label || (recording ? 'Stop Recording' : 'Start Listening')}
    </button>
  );
}

// ─── Waveform / level meter ────────────────────────────────────
function UnWaveform({ theme, recording, bars = 36, height = 36, seed = 0 }) {
  // Deterministic pseudo-waveform so it's stable across renders.
  const data = React.useMemo(() => {
    const out = [];
    for (let i = 0; i < bars; i++) {
      const x = (i + seed * 7) * 0.31;
      const v = (Math.sin(x) * 0.4 + Math.sin(x * 2.3) * 0.3 + Math.sin(x * 0.5) * 0.3) * 0.5 + 0.5;
      out.push(Math.max(0.10, Math.min(1, v)));
    }
    return out;
  }, [bars, seed]);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 2, height, padding: '0 4px' }}>
      {data.map((v, i) => (
        <div key={i} style={{
          width: 3, height: `${(recording ? v : v * 0.4) * 100}%`,
          background: recording ? theme.recording : theme.accent,
          opacity: recording ? 0.95 : 0.55,
          borderRadius: 2,
          transition: 'height 220ms ease, opacity 220ms ease',
        }}></div>
      ))}
    </div>
  );
}

// ─── Status dot ────────────────────────────────────────────────
function UnStatusDot({ tone, theme, size = 7 }) {
  const map = {
    ok: theme.success, warn: theme.warn, rec: theme.recording,
    accent: theme.accent, off: theme.textFaint,
  };
  const c = map[tone] || theme.textFaint;
  return <span style={{
    width: size, height: size, borderRadius: 999, background: c,
    boxShadow: `0 0 0 3px ${c}33, 0 0 6px ${c}88`,
    flex: '0 0 auto',
  }}></span>;
}

// ─── Field / label / KV row helpers ────────────────────────────
function UnLabel({ children, theme, style }) {
  return <div style={{
    fontFamily: UN_FONT_TEXT, fontSize: 11, fontWeight: 600,
    letterSpacing: 0.8, textTransform: 'uppercase',
    color: theme.textMuted, ...style,
  }}>{children}</div>;
}

function UnKV({ k, v, theme, mono, tone, style }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      gap: 16, padding: '8px 0', minHeight: 32, ...style,
    }}>
      <span style={{
        fontFamily: UN_FONT_TEXT, fontSize: 13, color: theme.textMuted, fontWeight: 500,
      }}>{k}</span>
      <span style={{
        fontFamily: mono ? UN_FONT_MONO : UN_FONT_TEXT,
        fontSize: mono ? 12 : 13, fontWeight: 500,
        color: tone === 'accent' ? theme.accent : theme.text,
        display: 'inline-flex', alignItems: 'center', gap: 6,
      }}>{v}</span>
    </div>
  );
}

// ─── Generic mac-style button (secondary, segmented) ───────────
function UnBtn({ children, theme, onClick, primary, ghost, sm, icon, style }) {
  const h = sm ? 26 : 30;
  return (
    <button onClick={onClick} style={{
      height: h, padding: `0 ${sm ? 10 : 12}px`,
      display: 'inline-flex', alignItems: 'center', gap: 6,
      borderRadius: 8,
      background: primary ? theme.accent : ghost ? 'transparent' : theme.glassHi,
      color: primary ? '#fff' : theme.text,
      border: ghost ? '1px solid transparent' : `1px solid ${primary ? 'transparent' : theme.glassStroke}`,
      fontFamily: UN_FONT_TEXT, fontSize: sm ? 12 : 13, fontWeight: 500,
      cursor: 'pointer',
      boxShadow: primary ? `0 4px 10px -4px ${theme.accentRing}` : 'inset 0 1px 0 rgba(255,255,255,0.20)',
      ...style,
    }}>{icon}{children}</button>
  );
}

// ─── Tab bar (used inside main windows) ───────────────────────
function UnTabs({ tabs, active, onChange, theme }) {
  return (
    <div style={{
      display: 'inline-flex', padding: 3, borderRadius: 10,
      background: theme.glassLow,
      border: `1px solid ${theme.glassStroke}`,
      boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.15)',
    }}>
      {tabs.map((t) => (
        <button key={t} onClick={() => onChange && onChange(t)} style={{
          padding: '5px 14px', borderRadius: 7,
          background: active === t ? theme.glassHi : 'transparent',
          color: active === t ? theme.text : theme.textMuted,
          border: 'none',
          fontFamily: UN_FONT_TEXT, fontSize: 12, fontWeight: active === t ? 600 : 500,
          cursor: 'pointer',
          boxShadow: active === t ? '0 2px 6px -2px rgba(0,0,0,0.15), inset 0 1px 0 rgba(255,255,255,0.25)' : 'none',
        }}>{t}</button>
      ))}
    </div>
  );
}

// Soft section title used inside settings panes
function UnSectionTitle({ children, theme, sub }) {
  return (
    <div style={{ marginBottom: 10 }}>
      <div style={{ fontFamily: UN_FONT_DISPLAY, fontWeight: 600, fontSize: 14, color: theme.text, letterSpacing: -0.1 }}>{children}</div>
      {sub && <div style={{ fontFamily: UN_FONT_TEXT, fontSize: 12, color: theme.textMuted, marginTop: 2 }}>{sub}</div>}
    </div>
  );
}

// ─── Desktop wallpaper background (used in artboards) ─────────
function UnDesktop({ theme, children, style }) {
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative',
      background: theme.desktop,
      overflow: 'hidden', ...style,
    }}>
      {/* subtle dot-noise + light vignette to give glass something to chew on */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(70% 60% at 80% 90%, rgba(255,255,255,0.10) 0%, transparent 60%), radial-gradient(50% 40% at 10% 100%, rgba(0,0,0,0.18) 0%, transparent 60%)',
        pointerEvents: 'none',
      }}></div>
      {children}
    </div>
  );
}

// Menubar at top of desktop screen — used in some artboards
function UnMenuBar({ theme, strength = 0.7 }) {
  const items = ['untype', 'File', 'Edit', 'View', 'Session', 'Window', 'Help'];
  return (
    <div style={{
      height: 26, padding: '0 12px',
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      background: theme.statusbar,
      backdropFilter: `blur(${20 + strength * 20}px) saturate(180%)`,
      WebkitBackdropFilter: `blur(${20 + strength * 20}px) saturate(180%)`,
      borderBottom: `1px solid ${theme.divider}`,
      fontFamily: UN_FONT_TEXT, fontSize: 13, color: theme.text,
      position: 'relative', zIndex: 5,
    }}>
      <div style={{ display: 'flex', gap: 16, alignItems: 'center' }}>
        <span style={{ fontWeight: 600 }}>{'\u{F8FF}'}</span>
        {items.map((it, i) => (
          <span key={it} style={{ fontWeight: i === 1 ? 600 : 400, color: i === 1 ? theme.text : theme.textMuted }}>{it}</span>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 12, alignItems: 'center', color: theme.textMuted, fontSize: 12 }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: theme.accent, fontWeight: 600 }}>
          <span style={{ width: 6, height: 6, borderRadius: 999, background: theme.accent, boxShadow: `0 0 0 3px ${theme.accentTint}` }}></span>
          ut
        </span>
        <span>Wed 10:42</span>
      </div>
    </div>
  );
}

Object.assign(window, {
  UN_FONT_DISPLAY, UN_FONT_TEXT, UN_FONT_MONO,
  UN_THEMES, unMaterial,
  UnTrafficLights, UnBrandMark, UnGlass,
  UnOperatorPill, UnRecordButton, UnWaveform, UnStatusDot,
  UnLabel, UnKV, UnBtn, UnTabs, UnSectionTitle, UnDesktop, UnMenuBar,
});
