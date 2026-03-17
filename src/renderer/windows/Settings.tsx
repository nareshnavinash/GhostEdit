import React, { useEffect, useState, useCallback } from 'react';
import type { AppConfig, ProviderName, CLIProviderName, TonePreset, LocalModelInfo, LocalModelVariant } from '../../shared/types';
import { ALL_PROVIDERS, CLI_PROVIDERS, LANGUAGES, DEFAULT_CONFIG, DEFAULT_BUNDLED_VARIANT } from '../../shared/constants';
import HotkeyInput from '../components/HotkeyInput';
import Welcome from '../components/Welcome';

type Tab = 'general' | 'hotkey' | 'behavior';

export default function Settings() {
  const [config, setConfig] = useState<AppConfig>(DEFAULT_CONFIG);
  const [activeTab, setActiveTab] = useState<Tab>('general');
  const [cliStatus, setCLIStatus] = useState<Record<string, { found: boolean; path: string | null }>>({});
  const [saved, setSaved] = useState(false);
  const [modelInfo, setModelInfo] = useState<LocalModelInfo>({ ready: false, activeVariant: DEFAULT_BUNDLED_VARIANT, variants: [] });
  const [downloadingVariant, setDownloadingVariant] = useState<LocalModelVariant | null>(null);
  const [downloadProgress, setDownloadProgress] = useState(0);
  const [inferenceDevice, setInferenceDevice] = useState<{ device: string; runtime: string; label: string } | null>(null);

  useEffect(() => {
    window.ghostedit.getConfig().then(setConfig);
    window.ghostedit.getCLIStatus().then(setCLIStatus);
    window.ghostedit.getLocalModelStatus().then(setModelInfo);
    window.ghostedit.getInferenceDevice().then(setInferenceDevice);

    const removeProgressListener = window.ghostedit.onDownloadVariantProgress((data) => {
      setDownloadProgress(data.progress);
    });
    return () => { removeProgressListener(); };
  }, []);

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
    try {
      const result = await window.ghostedit.downloadModelVariant(variant);
      if (result.success) {
        // Refresh model info after successful download
        const info = await window.ghostedit.getLocalModelStatus();
        setModelInfo(info);
      }
    } finally {
      setDownloadingVariant(null);
      setDownloadProgress(0);
    }
  }, [downloadingVariant]);

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

  const formatHotkey = (acc: string) =>
    acc
      .replace('CommandOrControl', process.platform === 'darwin' ? '\u2318' : 'Ctrl')
      .replace('Shift', process.platform === 'darwin' ? '\u21E7' : 'Shift')
      .replace('Alt', process.platform === 'darwin' ? '\u2325' : 'Alt')
      .replace(/\+/g, process.platform === 'darwin' ? ' ' : '+');

  return (
    <div className="flex flex-col h-screen bg-ghost-bg text-ghost-text">
      {/* Title bar */}
      <div className="drag-region h-10 flex items-center justify-center pl-[72px] border-b border-white/10 shrink-0">
        <span className="text-sm font-medium text-ghost-muted">GhostEdit Settings</span>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-white/10 shrink-0">
        {(['general', 'hotkey', 'behavior'] as Tab[]).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`no-drag flex-1 py-2.5 text-sm font-medium capitalize transition-colors ${
              activeTab === tab
                ? 'text-white border-b-2 border-blue-400'
                : 'text-ghost-muted hover:text-white'
            }`}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {activeTab === 'general' && (
          <>
            {/* Hotkey info */}
            <div className="rounded-lg bg-white/5 px-3 py-2 text-xs text-ghost-muted space-y-1">
              <div>Local: <span className="font-mono text-ghost-text">{formatHotkey(config.localHotkeyAccelerator)}</span></div>
              <div>CLI: <span className="font-mono text-ghost-text">{formatHotkey(config.cliHotkeyAccelerator)}</span></div>
              <span className="ml-1">(change in Hotkey tab)</span>
            </div>

            {/* Local Model section */}
            <div className="rounded-lg bg-white/5 p-3 space-y-3">
              <div>
                <p className="text-sm font-medium">Local Model</p>
                <p className="text-xs text-ghost-muted">T5 Grammar Correction — triggered by local hotkey</p>
              </div>

              {/* Active variant selector */}
              <Field label="Active Variant">
                <select
                  value={config.localModelVariant ?? DEFAULT_BUNDLED_VARIANT}
                  onChange={(e) => update({ localModelVariant: e.target.value as LocalModelVariant })}
                  className="input"
                >
                  {modelInfo.variants
                    .filter((v) => v.available)
                    .map((v) => (
                      <option key={v.variant} value={v.variant}>
                        {v.displayName}
                      </option>
                    ))}
                </select>
              </Field>

              {/* Variant list */}
              <div className="space-y-2">
                {modelInfo.variants.map((v) => (
                  <div key={v.variant} className="flex items-center justify-between text-xs py-1">
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{v.displayName}</span>
                      <span className="text-ghost-muted">~{v.sizeMB} MB</span>
                    </div>
                    <div>
                      {v.bundled ? (
                        <span className="text-green-400 font-medium">Bundled</span>
                      ) : v.available ? (
                        <span className="text-green-400 font-medium">Downloaded</span>
                      ) : downloadingVariant === v.variant ? (
                        <span className="text-blue-400 font-medium">{downloadProgress}%</span>
                      ) : (
                        <button
                          onClick={() => handleDownloadVariant(v.variant)}
                          disabled={!!downloadingVariant}
                          className="px-2 py-0.5 rounded bg-blue-500/20 text-blue-400 hover:bg-blue-500/30 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
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
                <div className="w-full bg-white/10 rounded-full h-1.5">
                  <div
                    className="bg-blue-500 h-1.5 rounded-full transition-all duration-300"
                    style={{ width: `${downloadProgress}%` }}
                  />
                </div>
              )}

              <p className="text-xs text-ghost-muted">
                Works offline. First use may take a few seconds to load.
              </p>
            </div>

            {/* CLI Provider section */}
            <div className="rounded-lg bg-white/5 p-3 space-y-3">
              <div>
                <p className="text-sm font-medium">CLI Provider</p>
                <p className="text-xs text-ghost-muted">Triggered by CLI hotkey</p>
              </div>

              <Field label="Provider">
                <select
                  value={config.cliProvider}
                  onChange={(e) => {
                    const p = e.target.value as CLIProviderName;
                    update({ cliProvider: p, cliModel: CLI_PROVIDERS[p].defaultModel });
                  }}
                  className="input"
                >
                  {Object.values(CLI_PROVIDERS).map((p) => (
                    <option key={p.name} value={p.name}>
                      {p.displayName}
                      {cliStatus[p.name]?.found === false ? ' (not found)' : ''}
                    </option>
                  ))}
                </select>
              </Field>

              <Field label="Model">
                <select
                  value={config.cliModel}
                  onChange={(e) => update({ cliModel: e.target.value })}
                  className="input"
                >
                  {cliModels.map((m) => (
                    <option key={m} value={m}>
                      {m}
                    </option>
                  ))}
                </select>
              </Field>

              <Field label={`${cliProviderDef?.displayName ?? ''} CLI Path`}>
                <input
                  type="text"
                  value={config[cliProviderDef?.configPathKey] ?? ''}
                  placeholder="Auto-detect"
                  onChange={(e) => update({ [cliProviderDef?.configPathKey]: e.target.value } as any)}
                  className="input"
                />
                <p className="text-xs text-ghost-muted mt-1">
                  {cliStatus[config.cliProvider]?.found
                    ? `Found: ${cliStatus[config.cliProvider]?.path}`
                    : 'Not found — install the CLI or set the path manually'}
                </p>
              </Field>
            </div>

            {/* Language */}
            <Field label="Language">
              <select
                value={config.language}
                onChange={(e) => update({ language: e.target.value })}
                className="input"
              >
                {Object.entries(LANGUAGES).map(([code, name]) => (
                  <option key={code} value={code}>
                    {name}
                  </option>
                ))}
              </select>
            </Field>

            {/* Tone */}
            <Field label="Tone Preset">
              <select
                value={config.tonePreset}
                onChange={(e) => update({ tonePreset: e.target.value as TonePreset })}
                className="input"
              >
                <option value="default">Default</option>
                <option value="casual">Casual</option>
                <option value="professional">Professional</option>
                <option value="academic">Academic</option>
                <option value="slack">Slack</option>
              </select>
            </Field>

            {/* Timeout */}
            <Field label="Timeout (seconds)">
              <input
                type="number"
                min={10}
                max={300}
                value={config.timeoutSeconds}
                onChange={(e) => update({ timeoutSeconds: parseInt(e.target.value) || 60 })}
                className="input w-24"
              />
            </Field>
          </>
        )}

        {activeTab === 'hotkey' && (
          <>
            <Field label="Local Model Hotkey">
              <HotkeyInput
                value={config.localHotkeyAccelerator}
                onChange={(v) => update({ localHotkeyAccelerator: v })}
              />
              <p className="text-xs text-ghost-muted mt-1">Triggers correction using the built-in local model</p>
            </Field>
            <Field label="CLI Provider Hotkey">
              <HotkeyInput
                value={config.cliHotkeyAccelerator}
                onChange={(v) => update({ cliHotkeyAccelerator: v })}
              />
              <p className="text-xs text-ghost-muted mt-1">Triggers correction using the configured CLI provider</p>
            </Field>
          </>
        )}

        {activeTab === 'behavior' && (
          <>
            <Toggle
              label="Fast correction mode"
              description="Use greedy decoding for faster local model corrections (slight quality trade-off)"
              checked={config.localModelSpeed === 'fast'}
              onChange={(v) => update({ localModelSpeed: v ? 'fast' : 'quality' })}
            />
            <Toggle
              label="Clipboard-only mode"
              description="Copy corrected text to clipboard instead of pasting it back"
              checked={config.clipboardOnlyMode}
              onChange={(v) => update({ clipboardOnlyMode: v })}
            />
            <Toggle
              label="Show diff preview"
              description="Show a side-by-side diff before accepting corrections"
              checked={config.showDiffPreview}
              onChange={(v) => update({ showDiffPreview: v })}
            />
            <Toggle
              label="Sound feedback"
              description="Play a sound when correction completes"
              checked={config.soundFeedbackEnabled}
              onChange={(v) => update({ soundFeedbackEnabled: v })}
            />
            <Toggle
              label="Notify on success"
              description="Show a system notification on successful correction"
              checked={config.notifyOnSuccess}
              onChange={(v) => update({ notifyOnSuccess: v })}
            />
            <Toggle
              label="Developer mode"
              description="Show additional debug information"
              checked={config.developerMode}
              onChange={(v) => update({ developerMode: v })}
            />

            {config.developerMode && inferenceDevice && (
              <div className="rounded-lg bg-white/5 px-3 py-2 text-xs text-ghost-muted">
                Inference device: <span className="font-mono text-ghost-text">{inferenceDevice.label}</span>
                <span className="ml-1">({inferenceDevice.runtime} runtime)</span>
              </div>
            )}

            <Field label="History limit">
              <input
                type="number"
                min={10}
                max={500}
                value={config.historyLimit}
                onChange={(e) => update({ historyLimit: parseInt(e.target.value) || 50 })}
                className="input w-24"
              />
            </Field>
          </>
        )}
      </div>

      {/* Save indicator */}
      {saved && (
        <div className="shrink-0 text-center py-2 text-sm text-ghost-success bg-ghost-success/10">
          Settings saved
        </div>
      )}
    </div>
  );
}

// ── Reusable sub-components ──

const Field = React.memo(function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="block text-sm font-medium text-ghost-text mb-1">{label}</label>
      {children}
    </div>
  );
});

const Toggle = React.memo(function Toggle({
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
    <div className="flex items-start justify-between gap-4 py-1">
      <div>
        <p className="text-sm font-medium">{label}</p>
        {description && <p className="text-xs text-ghost-muted">{description}</p>}
      </div>
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
        className={`relative shrink-0 w-10 h-5 rounded-full transition-colors ${
          checked ? 'bg-blue-500' : 'bg-white/20'
        }`}
      >
        <span
          className={`absolute top-0.5 left-0.5 w-4 h-4 bg-white rounded-full transition-transform ${
            checked ? 'translate-x-5' : ''
          }`}
        />
      </button>
    </div>
  );
});
