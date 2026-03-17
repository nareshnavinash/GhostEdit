import React, { useState } from 'react';
import type { AppConfig, ProviderName, CLIProviderName } from '../../shared/types';
import { ALL_PROVIDERS, CLI_PROVIDERS } from '../../shared/constants';

interface WelcomeProps {
  config: AppConfig;
  onComplete: (updates: Partial<AppConfig>) => void;
}

const STEPS = [
  {
    title: 'GhostEdit lives in your menu bar',
    description:
      'Look for the "G" icon in your menu bar at the top of your screen. Right-click it to access Settings, History, and more.',
  },
  {
    title: 'Select text anywhere, then press your hotkey',
    description: null, // dynamic — will show the configured hotkey
  },
  {
    title: 'Choose your AI provider',
    description: null, // dynamic — provider picker
  },
];

export default function Welcome({ config, onComplete }: WelcomeProps) {
  const [step, setStep] = useState(0);
  const [selectedProvider, setSelectedProvider] = useState<ProviderName>(config.provider);

  const isLast = step === STEPS.length - 1;

  const handleNext = () => {
    if (isLast) {
      if (selectedProvider === 'local') {
        onComplete({ firstRunComplete: true });
      } else {
        onComplete({
          firstRunComplete: true,
          cliProvider: selectedProvider as CLIProviderName,
          cliModel: CLI_PROVIDERS[selectedProvider]?.defaultModel ?? 'sonnet',
        });
      }
    } else {
      setStep(step + 1);
    }
  };

  const formatHotkey = (acc: string) =>
    acc
      .replace('CommandOrControl', process.platform === 'darwin' ? '\u2318' : 'Ctrl')
      .replace('Shift', process.platform === 'darwin' ? '\u21E7' : 'Shift')
      .replace('Alt', process.platform === 'darwin' ? '\u2325' : 'Alt')
      .replace(/\+/g, process.platform === 'darwin' ? ' ' : '+');

  return (
    <div className="flex flex-col h-screen bg-ghost-bg text-ghost-text">
      {/* Title bar drag region */}
      <div className="drag-region h-10 shrink-0 pl-[72px]" />

      <div className="flex-1 flex flex-col items-center justify-center px-8">
        {/* Step indicator */}
        <div className="flex items-center gap-2 mb-8">
          {STEPS.map((_, i) => (
            <div
              key={i}
              className={`w-2 h-2 rounded-full transition-colors ${
                i === step ? 'bg-blue-400' : i < step ? 'bg-blue-400/40' : 'bg-white/20'
              }`}
            />
          ))}
        </div>

        {/* Step content */}
        <h2 className="text-xl font-semibold text-center mb-3">{STEPS[step].title}</h2>

        {step === 0 && (
          <p className="text-sm text-ghost-muted text-center max-w-sm">
            {STEPS[0].description}
          </p>
        )}

        {step === 1 && (
          <div className="text-center space-y-3">
            <div>
              <p className="text-xs text-ghost-muted mb-1">Local Model</p>
              <div className="inline-block px-4 py-2 rounded-lg bg-white/10 text-lg font-mono">
                {formatHotkey(config.localHotkeyAccelerator)}
              </div>
            </div>
            <div>
              <p className="text-xs text-ghost-muted mb-1">CLI Provider</p>
              <div className="inline-block px-4 py-2 rounded-lg bg-white/10 text-lg font-mono">
                {formatHotkey(config.cliHotkeyAccelerator)}
              </div>
            </div>
            <p className="text-sm text-ghost-muted max-w-sm">
              Select any text in any app, press a hotkey, and GhostEdit will correct it and paste the result back.
            </p>
          </div>
        )}

        {step === 2 && (
          <div className="w-full max-w-xs space-y-2">
            {Object.values(ALL_PROVIDERS).map((p) => (
              <button
                key={p.name}
                onClick={() => setSelectedProvider(p.name)}
                className={`w-full text-left px-4 py-3 rounded-lg text-sm transition-colors ${
                  selectedProvider === p.name
                    ? 'bg-blue-500/20 text-blue-400 ring-1 ring-blue-400/50'
                    : 'bg-white/5 text-ghost-muted hover:bg-white/10'
                }`}
              >
                <span className="font-medium">{p.displayName}</span>
                {p.name === 'local' && (
                  <span className="block text-xs text-ghost-muted mt-0.5">Works offline, no API key needed</span>
                )}
              </button>
            ))}
            <p className="text-xs text-ghost-muted text-center pt-1">
              You can change this later in Settings.
            </p>
          </div>
        )}
      </div>

      {/* Bottom navigation */}
      <div className="flex items-center justify-between px-8 py-6 shrink-0">
        <button
          onClick={() => setStep(Math.max(0, step - 1))}
          disabled={step === 0}
          className="px-4 py-2 rounded text-sm text-ghost-muted hover:text-white disabled:opacity-0 transition-all"
        >
          Back
        </button>
        <button
          onClick={handleNext}
          className="px-6 py-2 rounded-lg text-sm font-medium bg-blue-500 text-white hover:bg-blue-600 transition-colors"
        >
          {isLast ? 'Get Started' : 'Next'}
        </button>
      </div>
    </div>
  );
}
