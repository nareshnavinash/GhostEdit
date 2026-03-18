import React, { useEffect, useState, useCallback } from 'react';
import type { AppConfig, CLIProviderName, TonePreset, DiffPreviewMode, LocalModelInfo, LocalModelVariant, UsageStats, IconPosition } from '../../shared/types';
import { CLI_PROVIDERS, LANGUAGES, DEFAULT_CONFIG, DEFAULT_BUNDLED_VARIANT } from '../../shared/constants';
import HotkeyInput from '../components/HotkeyInput';
import Welcome from '../components/Welcome';

// ── Section definitions ──

type Section = 'general' | 'models' | 'providers' | 'hotkeys' | 'behavior' | 'monitoring' | 'prompt' | 'dictionary' | 'stats';

const SECTIONS: Array<{
  id: Section;
  label: string;
  title: string;
  subtitle: string;
  icon: React.ReactNode;
}> = [
  { id: 'general',    label: 'General',    title: 'General',    subtitle: 'Language, tone, and correction preferences', icon: <GearIcon /> },
  { id: 'models',     label: 'Models',     title: 'Models',     subtitle: 'Local T5 grammar model configuration',       icon: <ChipIcon /> },
  { id: 'providers',  label: 'Providers',  title: 'Providers',  subtitle: 'CLI provider and API configuration',         icon: <CloudIcon /> },
  { id: 'hotkeys',    label: 'Hotkeys',    title: 'Hotkeys',    subtitle: 'Keyboard shortcuts for corrections',         icon: <KeyboardIcon /> },
  { id: 'behavior',   label: 'Behavior',   title: 'Behavior',   subtitle: 'Correction workflow and notifications',      icon: <SlidersIcon /> },
  { id: 'monitoring', label: 'Monitoring', title: 'Real-Time Monitoring', subtitle: 'Passive text analysis and traffic light indicator', icon: <EyeIcon /> },
  { id: 'prompt',     label: 'Prompt',     title: 'System Prompt', subtitle: 'Customize the AI system prompt',          icon: <TextIcon /> },
  { id: 'dictionary', label: 'Dictionary', title: 'Personal Dictionary', subtitle: 'Words to exclude from spell-checking', icon: <BookIcon /> },
  { id: 'stats',      label: 'Statistics', title: 'Usage Statistics', subtitle: 'Your correction history at a glance',  icon: <ChartIcon /> },
];

// ── Main component ──

export default function Settings() {
  const isMac = window.ghostedit.platform === 'darwin';

  const [config, setConfig] = useState<AppConfig>(DEFAULT_CONFIG);
  const [activeSection, setActiveSection] = useState<Section>('general');
  const [cliStatus, setCLIStatus] = useState<Record<string, { found: boolean; path: string | null }>>({});
  const [saved, setSaved] = useState(false);
  const [modelInfo, setModelInfo] = useState<LocalModelInfo>({ ready: false, activeVariant: DEFAULT_BUNDLED_VARIANT, variants: [] });
  const [downloadingVariant, setDownloadingVariant] = useState<LocalModelVariant | null>(null);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [downloadError, setDownloadError] = useState<string | null>(null);
  const [inferenceDevice, setInferenceDevice] = useState<{ device: string; runtime: string; label: string } | null>(null);

  // Prompt editor state
  const [systemPrompt, setSystemPrompt] = useState('');
  const [defaultPrompt, setDefaultPrompt] = useState('');
  const [promptSaved, setPromptSaved] = useState(false);

  // Personal dictionary state
  const [dictWords, setDictWords] = useState<string[]>([]);
  const [newWord, setNewWord] = useState('');
  const [dictSaved, setDictSaved] = useState(false);

  // Usage stats state
  const [stats, setStats] = useState<UsageStats | null>(null);

  useEffect(() => {
    window.ghostedit.getConfig().then(setConfig);
    window.ghostedit.getCLIStatus().then(setCLIStatus);
    window.ghostedit.getLocalModelStatus().then(setModelInfo);
    window.ghostedit.getInferenceDevice().then(setInferenceDevice);

    const removeProgressListener = window.ghostedit.onDownloadVariantProgress((data) => {
      setDownloadProgress(data.progress);
    });
    const removeErrorListener = window.ghostedit.onDownloadVariantError((data) => {
      setDownloadError(data.error);
    });
    return () => { removeProgressListener(); removeErrorListener(); };
  }, []);

  // Load section-specific data when switching
  useEffect(() => {
    if (activeSection === 'prompt') {
      window.ghostedit.getSystemPrompt().then(({ prompt, defaultPrompt: dp }) => {
        setSystemPrompt(prompt);
        setDefaultPrompt(dp);
      });
    } else if (activeSection === 'dictionary') {
      window.ghostedit.getPersonalDictionary().then(setDictWords);
    } else if (activeSection === 'stats') {
      window.ghostedit.getUsageStats().then(setStats);
    }
  }, [activeSection]);

  const save = useCallback(async (updated: AppConfig) => {
    setConfig(updated);
    await window.ghostedit.saveConfig(updated);
    setSaved(true);
    setTimeout(() => setSaved(false), 1500);
  }, []);

  const update = useCallback(
    (partial: Partial<AppConfig>) => {
      setConfig((prev) => {
        const updated = { ...prev, ...partial };
        save(updated);
        return updated;
      });
    },
    [save],
  );

  const handleDownloadVariant = useCallback(async (variant: LocalModelVariant) => {
    if (downloadingVariant) return;
    setDownloadingVariant(variant);
    setDownloadProgress(0);
    setDownloadError(null);
    try {
      const result = await window.ghostedit.downloadModelVariant(variant);
      if (result.success) {
        const info = await window.ghostedit.getLocalModelStatus();
        setModelInfo(info);
        setDownloadError(null);
      } else {
        setDownloadError(result.error || 'Download failed');
      }
    } catch (err: any) {
      setDownloadError(err?.message || 'Download failed');
    } finally {
      setDownloadingVariant(null);
      setDownloadProgress(0);
    }
  }, [downloadingVariant]);

  const handleSavePrompt = useCallback(async () => {
    await window.ghostedit.saveSystemPrompt(systemPrompt);
    setPromptSaved(true);
    setTimeout(() => setPromptSaved(false), 1500);
  }, [systemPrompt]);

  const handleResetPrompt = useCallback(async () => {
    setSystemPrompt(defaultPrompt);
    await window.ghostedit.saveSystemPrompt(defaultPrompt);
    setPromptSaved(true);
    setTimeout(() => setPromptSaved(false), 1500);
  }, [defaultPrompt]);

  const handleAddWord = useCallback(async () => {
    const word = newWord.trim();
    if (!word || dictWords.includes(word)) return;
    const updated = [...dictWords, word].sort();
    setDictWords(updated);
    setNewWord('');
    await window.ghostedit.savePersonalDictionary(updated);
    setDictSaved(true);
    setTimeout(() => setDictSaved(false), 1500);
  }, [newWord, dictWords]);

  const handleRemoveWord = useCallback(async (word: string) => {
    const updated = dictWords.filter((w) => w !== word);
    setDictWords(updated);
    await window.ghostedit.savePersonalDictionary(updated);
  }, [dictWords]);

  // Show onboarding if first run hasn't been completed
  if (!config.firstRunComplete) {
    return (
      <Welcome
        config={config}
        onComplete={(updates) => update(updates)}
      />
    );
  }

  const cliProviderDef = CLI_PROVIDERS[config.cliProvider];
  const cliModels = cliProviderDef?.availableModels ?? [];
  const currentSection = SECTIONS.find((s) => s.id === activeSection)!;

  return (
    <div className="flex flex-col h-screen bg-ghost-bg text-ghost-text">
      {/* Title bar (draggable) — platform-adaptive */}
      <div className={`drag-region h-10 flex items-center shrink-0 border-b border-white/[0.06] ${isMac ? 'pl-[72px]' : 'pl-4'}`}>
        <span className="flex-1 text-[13px] font-medium text-ghost-muted">
          {isMac ? '' : 'GhostEdit Settings'}
        </span>
        {/* Windows/Linux: custom window controls */}
        {!isMac && (
          <div className="no-drag flex items-center gap-1 pr-2">
            <button
              onClick={() => window.ghostedit.windowControls.minimize()}
              className="w-8 h-8 flex items-center justify-center rounded hover:bg-white/10 text-ghost-muted"
              aria-label="Minimize"
            >
              <MinimizeIcon />
            </button>
            <button
              onClick={() => window.ghostedit.windowControls.close()}
              className="w-8 h-8 flex items-center justify-center rounded hover:bg-red-500/80 hover:text-white text-ghost-muted"
              aria-label="Close"
            >
              <CloseIcon />
            </button>
          </div>
        )}
      </div>

      {/* Main: sidebar + content */}
      <div className="flex flex-1 min-h-0">
        {/* Sidebar */}
        <nav className="w-[180px] shrink-0 bg-ghost-sidebar border-r border-white/[0.06] pt-3 px-2 space-y-0.5 overflow-y-auto">
          {SECTIONS.map((section) => (
            <button
              key={section.id}
              onClick={() => setActiveSection(section.id)}
              className={`no-drag w-full flex items-center gap-2.5 px-3 py-[7px] rounded-lg text-[13px] transition-colors ${
                activeSection === section.id
                  ? 'bg-white/10 text-white font-medium'
                  : 'text-ghost-muted hover:bg-white/[0.05] hover:text-white/70'
              }`}
            >
              <span className="w-4 h-4 shrink-0 text-white/40">{section.icon}</span>
              {section.label}
            </button>
          ))}
        </nav>

        {/* Content area */}
        <div className="flex-1 overflow-y-auto px-6 py-5" key={activeSection}>
          <div className="animate-content-in">
            <h2 className="section-title">{currentSection.title}</h2>
            <p className="section-subtitle">{currentSection.subtitle}</p>

            {/* ── General ── */}
            {activeSection === 'general' && (
              <>
                <div className="settings-row">
                  <div>
                    <p className="text-[13px] font-medium">Language</p>
                    <p className="text-[11px] text-ghost-muted">Correction output language</p>
                  </div>
                  <select
                    value={config.language}
                    onChange={(e) => update({ language: e.target.value })}
                    className="input w-40"
                  >
                    {Object.entries(LANGUAGES).map(([code, name]) => (
                      <option key={code} value={code}>{name}</option>
                    ))}
                  </select>
                </div>

                <div className="settings-row">
                  <div>
                    <p className="text-[13px] font-medium">Tone Preset</p>
                    <p className="text-[11px] text-ghost-muted">Writing style for corrections</p>
                  </div>
                  <select
                    value={config.tonePreset}
                    onChange={(e) => update({ tonePreset: e.target.value as TonePreset })}
                    className="input w-40"
                  >
                    <option value="default">Default</option>
                    <option value="casual">Casual</option>
                    <option value="professional">Professional</option>
                    <option value="academic">Academic</option>
                    <option value="slack">Slack</option>
                  </select>
                </div>

                <div className="settings-row">
                  <div>
                    <p className="text-[13px] font-medium">Timeout</p>
                    <p className="text-[11px] text-ghost-muted">Seconds before correction times out</p>
                  </div>
                  <input
                    type="number"
                    min={10}
                    max={300}
                    value={config.timeoutSeconds}
                    onChange={(e) => update({ timeoutSeconds: parseInt(e.target.value) || 60 })}
                    className="input w-20"
                  />
                </div>
              </>
            )}

            {/* ── Models ── */}
            {activeSection === 'models' && (
              <>
                <div className="settings-row">
                  <div>
                    <p className="text-[13px] font-medium">Active Variant</p>
                    <p className="text-[11px] text-ghost-muted">T5 model variant for local corrections</p>
                  </div>
                  <select
                    value={config.localModelVariant ?? DEFAULT_BUNDLED_VARIANT}
                    onChange={(e) => update({ localModelVariant: e.target.value as LocalModelVariant })}
                    className="input w-44"
                  >
                    {modelInfo.variants
                      .filter((v) => v.available)
                      .map((v) => (
                        <option key={v.variant} value={v.variant}>{v.displayName}</option>
                      ))}
                  </select>
                </div>

                <div className="border-b border-ghost-row-border my-2" />

                {/* Variant list */}
                <div className="space-y-0">
                  {modelInfo.variants.map((v) => (
                    <div key={v.variant} className="settings-row">
                      <div className="flex items-center gap-2">
                        <span className="text-[13px] font-medium">{v.displayName}</span>
                        <span className="text-[11px] text-ghost-muted">~{v.sizeMB} MB</span>
                      </div>
                      <div>
                        {v.bundled ? (
                          <span className="bg-green-500/15 text-green-400 text-[11px] font-medium rounded-full px-2.5 py-0.5">Bundled</span>
                        ) : v.available ? (
                          <span className="bg-green-500/15 text-green-400 text-[11px] font-medium rounded-full px-2.5 py-0.5">Downloaded</span>
                        ) : downloadingVariant === v.variant ? (
                          <span className="text-blue-400 text-[11px] font-medium">{downloadProgress}%</span>
                        ) : downloadError && downloadingVariant === null ? (
                          <div className="flex items-center gap-2">
                            <span className="text-ghost-error text-[11px]">Failed</span>
                            <button
                              onClick={() => { setDownloadError(null); handleDownloadVariant(v.variant); }}
                              className="px-3 py-1 rounded-lg bg-ghost-error/20 text-ghost-error text-[12px] font-medium hover:bg-ghost-error/30 transition-colors"
                            >
                              Retry
                            </button>
                          </div>
                        ) : (
                          <button
                            onClick={() => handleDownloadVariant(v.variant)}
                            disabled={!!downloadingVariant}
                            className="px-3 py-1 rounded-lg bg-blue-500/20 text-blue-400 text-[12px] font-medium hover:bg-blue-500/30 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                          >
                            Download
                          </button>
                        )}
                      </div>
                    </div>
                  ))}
                </div>

                {/* Download progress bar */}
                {downloadingVariant && (
                  <div className="w-full bg-white/10 rounded-full h-1.5 mt-3">
                    <div
                      className="bg-blue-500 h-1.5 rounded-full transition-all duration-300"
                      style={{ width: `${downloadProgress}%` }}
                    />
                  </div>
                )}

                {downloadError && !downloadingVariant && (
                  <p className="text-[11px] text-ghost-error mt-2">{downloadError}</p>
                )}

                <p className="text-[11px] text-ghost-muted mt-4">
                  Works offline. First use may take a few seconds to load.
                </p>
              </>
            )}

            {/* ── Providers ── */}
            {activeSection === 'providers' && (
              <>
                <div className="settings-row">
                  <div>
                    <p className="text-[13px] font-medium">Provider</p>
                    <p className="text-[11px] text-ghost-muted">CLI tool for corrections</p>
                  </div>
                  <select
                    value={config.cliProvider}
                    onChange={(e) => {
                      const p = e.target.value as CLIProviderName;
                      update({ cliProvider: p, cliModel: CLI_PROVIDERS[p].defaultModel });
                    }}
                    className="input w-44"
                  >
                    {Object.values(CLI_PROVIDERS).map((p) => (
                      <option key={p.name} value={p.name}>
                        {p.displayName}
                        {cliStatus[p.name]?.found === false ? ' (not found)' : ''}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="settings-row">
                  <div>
                    <p className="text-[13px] font-medium">Model</p>
                    <p className="text-[11px] text-ghost-muted">Model used for CLI corrections</p>
                  </div>
                  <select
                    value={config.cliModel}
                    onChange={(e) => update({ cliModel: e.target.value })}
                    className="input w-44"
                  >
                    {cliModels.map((m) => (
                      <option key={m} value={m}>{m}</option>
                    ))}
                  </select>
                </div>

                <div className="settings-row">
                  <div className="flex-1 mr-4">
                    <p className="text-[13px] font-medium">{cliProviderDef?.displayName ?? ''} CLI Path</p>
                    <p className="text-[11px] text-ghost-muted mb-2">Path to the CLI executable</p>
                    <input
                      type="text"
                      value={config[cliProviderDef?.configPathKey] ?? ''}
                      placeholder="Auto-detect"
                      onChange={(e) => update({ [cliProviderDef?.configPathKey]: e.target.value } as any)}
                      className="input"
                    />
                    <p className="text-[11px] mt-1.5">
                      {cliStatus[config.cliProvider]?.found ? (
                        <span className="text-ghost-success">Found: {cliStatus[config.cliProvider]?.path}</span>
                      ) : (
                        <span className="text-ghost-muted">Not found — install the CLI or set the path manually</span>
                      )}
                    </p>
                  </div>
                </div>
              </>
            )}

            {/* ── Hotkeys ── */}
            {activeSection === 'hotkeys' && (
              <>
                <div className="settings-row">
                  <div className="flex-1 mr-4">
                    <p className="text-[13px] font-medium">Local Model Hotkey</p>
                    <p className="text-[11px] text-ghost-muted mb-2">Triggers correction using the built-in local model</p>
                    <HotkeyInput
                      value={config.localHotkeyAccelerator}
                      onChange={(v) => update({ localHotkeyAccelerator: v })}
                    />
                  </div>
                </div>
                <div className="settings-row">
                  <div className="flex-1 mr-4">
                    <p className="text-[13px] font-medium">CLI Provider Hotkey</p>
                    <p className="text-[11px] text-ghost-muted mb-2">Triggers correction using the configured CLI provider</p>
                    <HotkeyInput
                      value={config.cliHotkeyAccelerator}
                      onChange={(v) => update({ cliHotkeyAccelerator: v })}
                    />
                  </div>
                </div>
                <div className="settings-row">
                  <div className="flex-1 mr-4">
                    <p className="text-[13px] font-medium">Undo Last Correction</p>
                    <p className="text-[11px] text-ghost-muted mb-2">Re-pastes the original text from the most recent correction</p>
                    <HotkeyInput
                      value={config.undoHotkeyAccelerator}
                      onChange={(v) => update({ undoHotkeyAccelerator: v })}
                    />
                  </div>
                </div>
              </>
            )}

            {/* ── Behavior ── */}
            {activeSection === 'behavior' && (
              <>
                <ToggleRow
                  label="Launch at login"
                  description="Start GhostEdit automatically when you log in"
                  checked={config.launchAtLogin}
                  onChange={(v) => update({ launchAtLogin: v })}
                />
                <ToggleRow
                  label="Fast correction mode"
                  description="Use greedy decoding for faster local model corrections (slight quality trade-off)"
                  checked={config.localModelSpeed === 'fast'}
                  onChange={(v) => update({ localModelSpeed: v ? 'fast' : 'quality' })}
                />
                <ToggleRow
                  label="Clipboard-only mode"
                  description="Copy corrected text to clipboard instead of pasting it back"
                  checked={config.clipboardOnlyMode}
                  onChange={(v) => update({ clipboardOnlyMode: v })}
                />
                <div className="settings-row">
                  <div>
                    <p className="text-[13px] font-medium">Diff preview</p>
                    <p className="text-[11px] text-ghost-muted">How to show correction comparisons</p>
                  </div>
                  <select
                    value={config.diffPreviewMode}
                    onChange={(e) => update({ diffPreviewMode: e.target.value as DiffPreviewMode })}
                    className="input w-44"
                  >
                    <option value="none">Off</option>
                    <option value="passive">Passive (auto-close)</option>
                    <option value="interactive">Interactive (accept/reject)</option>
                  </select>
                </div>
                {config.diffPreviewMode === 'interactive' && (
                  <div className="settings-row">
                    <div>
                      <p className="text-[13px] font-medium">Auto-paste delay</p>
                      <p className="text-[11px] text-ghost-muted">
                        Seconds before auto-accepting the preview (0 = manual only)
                      </p>
                    </div>
                    <input
                      type="number"
                      min={0}
                      max={30}
                      value={config.autoPasteDelaySeconds}
                      onChange={(e) => update({ autoPasteDelaySeconds: Number(e.target.value) })}
                      className="input w-20"
                    />
                  </div>
                )}
                {config.diffPreviewMode === 'passive' && (
                  <div className="settings-row">
                    <div>
                      <p className="text-[13px] font-medium">Preview duration</p>
                      <p className="text-[11px] text-ghost-muted">
                        Seconds to show the passive diff overlay
                      </p>
                    </div>
                    <input
                      type="number"
                      min={1}
                      max={30}
                      value={config.passivePreviewSeconds}
                      onChange={(e) => update({ passivePreviewSeconds: Number(e.target.value) })}
                      className="input w-20"
                    />
                  </div>
                )}
                <ToggleRow
                  label="Sound feedback"
                  description="Play a sound when correction completes or fails"
                  checked={config.soundFeedbackEnabled}
                  onChange={(v) => update({ soundFeedbackEnabled: v })}
                />
                <ToggleRow
                  label="Notify on success"
                  description="Show a system notification on successful correction"
                  checked={config.notifyOnSuccess}
                  onChange={(v) => update({ notifyOnSuccess: v })}
                />
                <ToggleRow
                  label="Developer mode"
                  description="Show additional debug information"
                  checked={config.developerMode}
                  onChange={(v) => update({ developerMode: v })}
                />

                {config.developerMode && inferenceDevice && (
                  <div className="rounded-lg bg-white/5 px-3 py-2 text-[11px] text-ghost-muted mt-2">
                    Inference device: <span className="font-mono text-ghost-text">{inferenceDevice.label}</span>
                    <span className="ml-1">({inferenceDevice.runtime} runtime)</span>
                  </div>
                )}

                <div className="border-b border-ghost-row-border my-2" />

                <div className="settings-row">
                  <div>
                    <p className="text-[13px] font-medium">History limit</p>
                    <p className="text-[11px] text-ghost-muted">Maximum number of corrections to keep</p>
                  </div>
                  <input
                    type="number"
                    min={10}
                    max={500}
                    value={config.historyLimit}
                    onChange={(e) => update({ historyLimit: parseInt(e.target.value) || 50 })}
                    className="input w-20"
                  />
                </div>
              </>
            )}

            {/* ── Monitoring ── */}
            {activeSection === 'monitoring' && (
              <>
                <ToggleRow
                  label="Enable real-time monitoring"
                  description="Passively analyze text as you type and show a floating traffic light indicator"
                  checked={config.monitoringEnabled}
                  onChange={(v) => update({ monitoringEnabled: v })}
                />

                {config.monitoringEnabled && (
                  <>
                    <div className="settings-row">
                      <div>
                        <p className="text-[13px] font-medium">Icon position</p>
                        <p className="text-[11px] text-ghost-muted">Screen corner for the traffic light indicator</p>
                      </div>
                      <select
                        value={config.trafficLightPosition}
                        onChange={(e) => update({ trafficLightPosition: e.target.value as IconPosition })}
                        className="input w-40"
                      >
                        <option value="top-right">Top Right</option>
                        <option value="top-left">Top Left</option>
                        <option value="bottom-right">Bottom Right</option>
                        <option value="bottom-left">Bottom Left</option>
                      </select>
                    </div>

                    <div className="settings-row">
                      <div>
                        <p className="text-[13px] font-medium">Inactivity timeout</p>
                        <p className="text-[11px] text-ghost-muted">Seconds of inactivity before hiding the indicator</p>
                      </div>
                      <input
                        type="number"
                        min={1}
                        max={30}
                        value={Math.round(config.trafficLightInactivityMs / 1000)}
                        onChange={(e) => update({ trafficLightInactivityMs: (Number(e.target.value) || 3) * 1000 })}
                        className="input w-20"
                      />
                    </div>

                    <div className="settings-row">
                      <div className="flex-1 mr-4">
                        <p className="text-[13px] font-medium">Correct Line Hotkey</p>
                        <p className="text-[11px] text-ghost-muted mb-2">Captures the current line and runs the full correction pipeline</p>
                        <HotkeyInput
                          value={config.lineHotkeyAccelerator}
                          onChange={(v) => update({ lineHotkeyAccelerator: v })}
                        />
                      </div>
                    </div>

                    <ToggleRow
                      label="Background model refinement"
                      description="Run T5 model in background after idle for deeper analysis (uses more CPU)"
                      checked={config.backgroundModelRefinement}
                      onChange={(v) => update({ backgroundModelRefinement: v })}
                    />

                    {isMac && (
                      <div className="rounded-lg bg-yellow-500/10 border border-yellow-500/20 px-3 py-2 text-[11px] text-yellow-300/80 mt-3">
                        macOS requires Accessibility permission for keystroke monitoring.
                        You will be prompted to grant access when monitoring is first enabled.
                      </div>
                    )}
                  </>
                )}

                <p className="text-[11px] text-ghost-muted mt-4">
                  When enabled, a floating colored circle (green/yellow/red) appears while you type.
                  Click it to see detected issues and apply fixes. The keystroke buffer is kept in memory only and never persisted.
                </p>
              </>
            )}

            {/* ── Prompt ── */}
            {activeSection === 'prompt' && (
              <>
                <textarea
                  value={systemPrompt}
                  onChange={(e) => setSystemPrompt(e.target.value)}
                  className="input w-full h-48 resize-y font-mono text-[12px]"
                  placeholder="Enter a custom system prompt..."
                />
                <div className="flex items-center gap-3 mt-3">
                  <button
                    onClick={handleSavePrompt}
                    className="px-4 py-1.5 rounded-lg bg-blue-500/20 text-blue-400 text-[13px] font-medium hover:bg-blue-500/30 transition-colors"
                  >
                    {promptSaved ? 'Saved!' : 'Save Prompt'}
                  </button>
                  <button
                    onClick={handleResetPrompt}
                    className="px-4 py-1.5 rounded-lg bg-white/5 text-ghost-muted text-[13px] font-medium hover:bg-white/10 transition-colors"
                  >
                    Reset to Default
                  </button>
                </div>
                <p className="text-[11px] text-ghost-muted mt-4">
                  The system prompt is sent to the AI before your text. It controls correction behavior, style, and output format.
                  Changes also apply to CLI providers. Stored in ~/.ghostedit/prompt.txt.
                </p>
              </>
            )}

            {/* ── Dictionary ── */}
            {activeSection === 'dictionary' && (
              <>
                <div className="flex items-center gap-2 mb-4">
                  <input
                    type="text"
                    value={newWord}
                    onChange={(e) => setNewWord(e.target.value)}
                    onKeyDown={(e) => { if (e.key === 'Enter') handleAddWord(); }}
                    placeholder="Add a word..."
                    className="input flex-1"
                  />
                  <button
                    onClick={handleAddWord}
                    disabled={!newWord.trim()}
                    className="px-4 py-2 rounded-lg bg-blue-500/20 text-blue-400 text-[13px] font-medium hover:bg-blue-500/30 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                  >
                    Add
                  </button>
                </div>

                {dictSaved && (
                  <p className="text-[11px] text-ghost-success mb-2">Dictionary updated</p>
                )}

                {dictWords.length === 0 ? (
                  <p className="text-[11px] text-ghost-muted">
                    No custom words yet. Add proper nouns, product names, or jargon that the spell checker flags incorrectly.
                  </p>
                ) : (
                  <div className="flex flex-wrap gap-1.5">
                    {dictWords.map((word) => (
                      <span
                        key={word}
                        className="inline-flex items-center gap-1 bg-white/[0.06] border border-white/[0.08] rounded-lg px-2.5 py-1 text-[12px]"
                      >
                        {word}
                        <button
                          onClick={() => handleRemoveWord(word)}
                          className="text-ghost-muted hover:text-ghost-error ml-0.5"
                          aria-label={`Remove ${word}`}
                        >
                          &times;
                        </button>
                      </span>
                    ))}
                  </div>
                )}

                <p className="text-[11px] text-ghost-muted mt-4">
                  Words in your personal dictionary won't be flagged by the spell checker.
                  Stored in ~/.ghostedit/personal-dictionary.txt.
                </p>
              </>
            )}

            {/* ── Statistics ── */}
            {activeSection === 'stats' && (
              <>
                {stats ? (
                  <div className="space-y-4">
                    {/* Summary cards */}
                    <div className="grid grid-cols-3 gap-3">
                      <StatCard label="Total Corrections" value={stats.totalCorrections} />
                      <StatCard label="Success Rate" value={`${stats.successRate}%`} />
                      <StatCard label="Avg Duration" value={`${stats.avgDurationMs}ms`} />
                    </div>
                    <div className="grid grid-cols-3 gap-3">
                      <StatCard label="Succeeded" value={stats.successfulCorrections} color="green" />
                      <StatCard label="Failed" value={stats.failedCorrections} color="red" />
                      <StatCard label="Words Processed" value={stats.totalWordsProcessed} />
                    </div>

                    {/* By provider */}
                    {Object.keys(stats.correctionsByProvider).length > 0 && (
                      <>
                        <div className="border-b border-ghost-row-border my-2" />
                        <h3 className="text-[13px] font-medium mb-2">By Provider</h3>
                        {Object.entries(stats.correctionsByProvider).map(([provider, count]) => (
                          <div key={provider} className="settings-row">
                            <span className="text-[13px] capitalize">{provider}</span>
                            <span className="text-[13px] text-ghost-muted">{count} corrections</span>
                          </div>
                        ))}
                      </>
                    )}

                    <p className="text-[11px] text-ghost-muted mt-4">
                      All data is computed locally from your correction history. Nothing is sent externally.
                    </p>
                  </div>
                ) : (
                  <p className="text-[11px] text-ghost-muted">Loading statistics...</p>
                )}
              </>
            )}
          </div>
        </div>
      </div>

      {/* Save toast (floating pill) */}
      {saved && (
        <div className="fixed bottom-4 left-1/2 -translate-x-1/2 bg-ghost-success/15 border border-ghost-success/20 text-ghost-success text-xs font-medium rounded-full px-4 py-1.5 animate-content-in">
          Settings saved
        </div>
      )}
    </div>
  );
}

// ── Reusable sub-components ──

const Toggle = React.memo(function Toggle({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          onChange(!checked);
        }
      }}
      className={`relative shrink-0 w-[38px] h-[22px] rounded-full transition-colors duration-200 ${
        checked ? 'bg-blue-500' : 'bg-white/[0.15]'
      }`}
    >
      <span
        className={`absolute top-[3px] left-[3px] w-4 h-4 bg-white rounded-full shadow-sm transition-transform duration-200 ${
          checked ? 'translate-x-4' : ''
        }`}
      />
    </button>
  );
});

const ToggleRow = React.memo(function ToggleRow({
  label,
  description,
  checked,
  onChange,
}: {
  label: string;
  description?: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <div className="settings-row">
      <div>
        <p className="text-[13px] font-medium">{label}</p>
        {description && <p className="text-[11px] text-ghost-muted">{description}</p>}
      </div>
      <Toggle checked={checked} onChange={onChange} />
    </div>
  );
});

function StatCard({ label, value, color }: { label: string; value: string | number; color?: 'green' | 'red' }) {
  const textColor = color === 'green' ? 'text-ghost-success' : color === 'red' ? 'text-ghost-error' : 'text-white/90';
  return (
    <div className="bg-white/[0.04] border border-white/[0.06] rounded-lg px-3 py-3 text-center">
      <p className={`text-lg font-semibold ${textColor}`}>{value}</p>
      <p className="text-[11px] text-ghost-muted mt-0.5">{label}</p>
    </div>
  );
}

// ── Icons (16x16 inline SVGs) ──

function GearIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <circle cx={8} cy={8} r={2.5} />
      <path d="M6.8 1.5h2.4l.3 1.7a5 5 0 0 1 1.2.7l1.6-.6.8 1.4-1.3 1.1a5 5 0 0 1 0 1.4l1.3 1.1-.8 1.4-1.6-.6a5 5 0 0 1-1.2.7l-.3 1.7H6.8l-.3-1.7a5 5 0 0 1-1.2-.7l-1.6.6-.8-1.4 1.3-1.1a5 5 0 0 1 0-1.4L3.9 4.7l.8-1.4 1.6.6a5 5 0 0 1 1.2-.7l.3-1.7Z" />
    </svg>
  );
}

function ChipIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <rect x={4} y={4} width={8} height={8} rx={1.5} />
      <path d="M6.5 1v3M9.5 1v3M6.5 12v3M9.5 12v3M1 6.5h3M1 9.5h3M12 6.5h3M12 9.5h3" />
    </svg>
  );
}

function CloudIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 12.5a3.5 3.5 0 0 1-.5-6.96A5 5 0 0 1 13 7a3 3 0 0 1 .5 5.96" />
      <path d="M4 12.5h9.5" />
    </svg>
  );
}

function KeyboardIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <rect x={1} y={3.5} width={14} height={9} rx={2} />
      <path d="M4 6.5h1M7.5 6.5h1M11 6.5h1M5 9.5h6" />
    </svg>
  );
}

function SlidersIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <path d="M1 4h4M9 4h6M1 8h8M13 8h2M1 12h2M7 12h8" />
      <circle cx={7} cy={4} r={2} />
      <circle cx={11} cy={8} r={2} />
      <circle cx={5} cy={12} r={2} />
    </svg>
  );
}

function TextIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 3h10M8 3v10M5 13h6" />
    </svg>
  );
}

function BookIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 2.5h4.5c1.1 0 1.5.5 1.5 1v10c0-.5-.4-1-1.5-1H2z" />
      <path d="M14 2.5H9.5c-1.1 0-1.5.5-1.5 1v10c0-.5.4-1 1.5-1H14z" />
    </svg>
  );
}

function ChartIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 14V8M6 14V4M10 14V6M14 14V2" />
    </svg>
  );
}

function EyeIcon() {
  return (
    <svg width={16} height={16} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round">
      <path d="M1.5 8s2.5-4.5 6.5-4.5S14.5 8 14.5 8s-2.5 4.5-6.5 4.5S1.5 8 1.5 8z" />
      <circle cx={8} cy={8} r={2} />
    </svg>
  );
}

function MinimizeIcon() {
  return (
    <svg width={12} height={12} viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round">
      <path d="M2 6h8" />
    </svg>
  );
}

function CloseIcon() {
  return (
    <svg width={12} height={12} viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round">
      <path d="M2 2l8 8M10 2l-8 8" />
    </svg>
  );
}
