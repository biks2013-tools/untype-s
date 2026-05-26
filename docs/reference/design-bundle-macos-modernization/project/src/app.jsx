// untype — design canvas root with Tweaks (material strength)

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "material": 0.65
}/*EDITMODE-END*/;

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const strength = t.material;

  // Shared state for the hero prototype interactivity
  const [light, setLight] = React.useState({ recording: false, ops: { R: true, T: false, C: true, I: true }, tab: 'Transcript' });
  const [dark,  setDark]  = React.useState({ recording: true,  ops: { R: true, T: true,  C: true, I: false }, tab: 'Transcript' });

  const themeL = UN_THEMES.light;
  const themeD = UN_THEMES.dark;

  // Sizes — same for both themes so they sit side-by-side cleanly
  const MAIN_W = 1240, MAIN_H = 800;
  const OVERLAY_W = 1180, OVERLAY_H = 720;
  const MENU_W = 880, MENU_H = 560;
  const ONB_W = 980, ONB_H = 700;
  const SET_W = 1180, SET_H = 760;
  const HIST_W = 1240, HIST_H = 780;
  const MINI_W = 560, MINI_H = 380;

  return (
    <React.Fragment>
      <DesignCanvas title="untype — modern macOS redesign" subtitle="Tahoe / Liquid Glass · amber accent · light & dark">

        {/* ─── Hero: Main window directions ─── */}
        <DCSection id="main" title="Main window — three directions" subtitle="Click record button or operator pills to try state. Each direction shown in light & dark.">
          <DCArtboard id="v1-light" label="V1 · Classic Sidebar · light" width={MAIN_W} height={MAIN_H}>
            <UnMainV1 theme={themeL} strength={strength} state={light} setState={setLight} />
          </DCArtboard>
          <DCArtboard id="v1-dark" label="V1 · Classic Sidebar · dark" width={MAIN_W} height={MAIN_H}>
            <UnMainV1 theme={themeD} strength={strength} state={dark} setState={setDark} />
          </DCArtboard>
          <DCArtboard id="v2-light" label="V2 · Unified Glass · light" width={MAIN_W} height={MAIN_H}>
            <UnMainV2 theme={themeL} strength={strength} state={light} setState={setLight} />
          </DCArtboard>
          <DCArtboard id="v2-dark" label="V2 · Unified Glass · dark" width={MAIN_W} height={MAIN_H}>
            <UnMainV2 theme={themeD} strength={strength} state={dark} setState={setDark} />
          </DCArtboard>
          <DCArtboard id="v3-light" label="V3 · Voice-First · light" width={MAIN_W} height={MAIN_H}>
            <UnMainV3 theme={themeL} strength={strength} state={light} setState={setLight} />
          </DCArtboard>
          <DCArtboard id="v3-dark" label="V3 · Voice-First · dark" width={MAIN_W} height={MAIN_H}>
            <UnMainV3 theme={themeD} strength={strength} state={dark} setState={setDark} />
          </DCArtboard>
        </DCSection>

        {/* ─── Recording overlay ─── */}
        <DCSection id="overlay" title="Recording overlay" subtitle="Non-activating floating panel at bottom of screen during push-to-talk.">
          <DCArtboard id="ov-a-light" label="A · Bar · light" width={OVERLAY_W} height={OVERLAY_H}>
            <UnOverlayStage theme={themeL} strength={strength} variant="A" />
          </DCArtboard>
          <DCArtboard id="ov-a-dark" label="A · Bar · dark" width={OVERLAY_W} height={OVERLAY_H}>
            <UnOverlayStage theme={themeD} strength={strength} variant="A" />
          </DCArtboard>
          <DCArtboard id="ov-b-light" label="B · Pill · light" width={OVERLAY_W} height={OVERLAY_H}>
            <UnOverlayStage theme={themeL} strength={strength} variant="B" />
          </DCArtboard>
          <DCArtboard id="ov-b-dark" label="B · Pill · dark" width={OVERLAY_W} height={OVERLAY_H}>
            <UnOverlayStage theme={themeD} strength={strength} variant="B" />
          </DCArtboard>
          <DCArtboard id="ov-c-light" label="C · Card · light" width={OVERLAY_W} height={OVERLAY_H}>
            <UnOverlayStage theme={themeL} strength={strength} variant="C" />
          </DCArtboard>
          <DCArtboard id="ov-c-dark" label="C · Card · dark" width={OVERLAY_W} height={OVERLAY_H}>
            <UnOverlayStage theme={themeD} strength={strength} variant="C" />
          </DCArtboard>
        </DCSection>

        {/* ─── Menubar dropdown ─── */}
        <DCSection id="menubar" title="Menubar dropdown" subtitle="Quick status + operator toggles from the system menu bar.">
          <DCArtboard id="mb-light" label="Light" width={MENU_W} height={MENU_H}>
            <UnMenubarDropdown theme={themeL} strength={strength} />
          </DCArtboard>
          <DCArtboard id="mb-dark" label="Dark" width={MENU_W} height={MENU_H}>
            <UnMenubarDropdown theme={themeD} strength={strength} />
          </DCArtboard>
        </DCSection>

        {/* ─── Onboarding ─── */}
        <DCSection id="onb" title="Onboarding & permissions" subtitle="First-run experience: mic, accessibility, provider credentials.">
          <DCArtboard id="onb-light" label="Light" width={ONB_W} height={ONB_H}>
            <UnOnboarding theme={themeL} strength={strength} />
          </DCArtboard>
          <DCArtboard id="onb-dark" label="Dark" width={ONB_W} height={ONB_H}>
            <UnOnboarding theme={themeD} strength={strength} />
          </DCArtboard>
        </DCSection>

        {/* ─── Settings ─── */}
        <DCSection id="settings" title="Settings · providers & shortcuts" subtitle="macOS Settings-style sidebar with form panes.">
          <DCArtboard id="set-prov-light" label="Providers · light" width={SET_W} height={SET_H}>
            <UnSettingsProviders theme={themeL} strength={strength} />
          </DCArtboard>
          <DCArtboard id="set-prov-dark" label="Providers · dark" width={SET_W} height={SET_H}>
            <UnSettingsProviders theme={themeD} strength={strength} />
          </DCArtboard>
          <DCArtboard id="set-sc-light" label="Shortcuts · light" width={SET_W} height={SET_H}>
            <UnSettingsShortcuts theme={themeL} strength={strength} />
          </DCArtboard>
          <DCArtboard id="set-sc-dark" label="Shortcuts · dark" width={SET_W} height={SET_H}>
            <UnSettingsShortcuts theme={themeD} strength={strength} />
          </DCArtboard>
        </DCSection>

        {/* ─── History ─── */}
        <DCSection id="history" title="Session history" subtitle="Browse past sessions, see raw/refined turns, warnings, and export.">
          <DCArtboard id="hist-light" label="Light" width={HIST_W} height={HIST_H}>
            <UnHistory theme={themeL} strength={strength} />
          </DCArtboard>
          <DCArtboard id="hist-dark" label="Dark" width={HIST_W} height={HIST_H}>
            <UnHistory theme={themeD} strength={strength} />
          </DCArtboard>
        </DCSection>

        {/* ─── Mini ─── */}
        <DCSection id="mini" title="Compact mini window" subtitle="Always-on-top tiny console for ambient sessions.">
          <DCArtboard id="mini-light" label="Light · warm" width={MINI_W} height={MINI_H}>
            <UnMini theme={themeL} strength={strength} recording={false} />
          </DCArtboard>
          <DCArtboard id="mini-rec-light" label="Light · recording" width={MINI_W} height={MINI_H}>
            <UnMini theme={themeL} strength={strength} recording={true} />
          </DCArtboard>
          <DCArtboard id="mini-dark" label="Dark · warm" width={MINI_W} height={MINI_H}>
            <UnMini theme={themeD} strength={strength} recording={false} />
          </DCArtboard>
          <DCArtboard id="mini-rec-dark" label="Dark · recording" width={MINI_W} height={MINI_H}>
            <UnMini theme={themeD} strength={strength} recording={true} />
          </DCArtboard>
        </DCSection>

      </DesignCanvas>

      <TweaksPanel title="Tweaks">
        <TweakSection label="Glass material">
          <TweakSlider
            label="Strength"
            value={Math.round(t.material * 100)}
            min={0} max={100} step={5} unit="%"
            onChange={(v) => setTweak('material', v / 100)}
          />
          <TweakRadio
            label="Preset"
            value={t.material < 0.35 ? 'clear' : t.material > 0.75 ? 'heavy' : 'glass'}
            options={[
              { label: 'Clear', value: 'clear' },
              { label: 'Glass', value: 'glass' },
              { label: 'Heavy', value: 'heavy' },
            ]}
            onChange={(v) => setTweak('material', v === 'clear' ? 0.20 : v === 'glass' ? 0.65 : 0.95)}
          />
        </TweakSection>
      </TweaksPanel>
    </React.Fragment>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
