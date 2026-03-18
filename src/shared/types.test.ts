import { describe, it, expect } from 'vitest';
import { IPC } from './types';
import type { ProviderName, CLIProviderName, CorrectionResult, LocalModelInfo, LocalModelVariant, LocalModelVariantInfo, AppConfig, DiffPreviewMode } from './types';

describe('ProviderName type', () => {
  it('includes local', () => {
    const provider: ProviderName = 'local';
    expect(provider).toBe('local');
  });

  it('includes CLI providers', () => {
    const providers: ProviderName[] = ['claude', 'codex', 'gemini', 'local'];
    expect(providers).toHaveLength(4);
  });
});

describe('CLIProviderName type', () => {
  it('excludes local (compile-time check, runtime sanity)', () => {
    const cliProviders: CLIProviderName[] = ['claude', 'codex', 'gemini'];
    expect(cliProviders).not.toContain('local');
  });
});

describe('CorrectionResult type', () => {
  it('has text and durationMs fields', () => {
    const result: CorrectionResult = { text: 'hello', durationMs: 42 };
    expect(result.text).toBe('hello');
    expect(result.durationMs).toBe(42);
  });
});

describe('LocalModelVariant type', () => {
  it('accepts valid variant values', () => {
    const variants: LocalModelVariant[] = ['q4f16', 'int8', 'fp16', 'fp32'];
    expect(variants).toHaveLength(4);
  });
});

describe('LocalModelVariantInfo type', () => {
  it('has all required fields', () => {
    const info: LocalModelVariantInfo = {
      variant: 'q4f16',
      displayName: 'Q4 F16 (Smallest)',
      sizeMB: 210,
      available: true,
      bundled: true,
    };
    expect(info.variant).toBe('q4f16');
    expect(info.available).toBe(true);
    expect(info.bundled).toBe(true);
  });
});

describe('LocalModelInfo type', () => {
  it('has ready, activeVariant, and variants fields', () => {
    const info: LocalModelInfo = {
      ready: true,
      activeVariant: 'q4f16',
      variants: [
        { variant: 'q4f16', displayName: 'Q4 F16', sizeMB: 210, available: true, bundled: true },
        { variant: 'fp32', displayName: 'FP32', sizeMB: 963, available: false, bundled: false },
      ],
    };
    expect(info.ready).toBe(true);
    expect(info.activeVariant).toBe('q4f16');
    expect(info.variants).toHaveLength(2);
  });
});

describe('IPC channels', () => {
  it('includes SET_PREVIEW_ORIGINAL channel', () => {
    expect(IPC.SET_PREVIEW_ORIGINAL).toBe('set-preview-original');
  });

  it('includes inference IPC channels', () => {
    expect(IPC.INFERENCE_COMMAND).toBe('inference:command');
    expect(IPC.INFERENCE_RESULT).toBe('inference:result');
  });
});

describe('AppConfig type', () => {
  it('includes firstRunComplete field', () => {
    const config: AppConfig = {
      claudePath: '',
      codexPath: '',
      geminiPath: '',
      provider: 'local',
      model: 't5-grammar',
      cliProvider: 'claude',
      cliModel: 'sonnet',
      timeoutSeconds: 60,
      localHotkeyAccelerator: 'CommandOrControl+E',
      cliHotkeyAccelerator: 'CommandOrControl+Shift+E',
      undoHotkeyAccelerator: 'CommandOrControl+Shift+Z',
      launchAtLogin: false,
      historyLimit: 50,
      developerMode: false,
      language: 'auto',
      soundFeedbackEnabled: true,
      notifyOnSuccess: false,
      clipboardOnlyMode: false,
      tonePreset: 'default',
      diffPreviewMode: 'interactive',
      passivePreviewSeconds: 5,
      autoPasteDelaySeconds: 5,
      localModelVariant: 'fp32',
      localModelSpeed: 'fast',
      firstRunComplete: false,
    };
    expect(config.firstRunComplete).toBe(false);
    expect(config.localModelSpeed).toBe('fast');
  });

  it('has localHotkeyAccelerator and cliHotkeyAccelerator fields', () => {
    const config: AppConfig = {
      claudePath: '',
      codexPath: '',
      geminiPath: '',
      provider: 'local',
      model: 't5-grammar',
      cliProvider: 'claude',
      cliModel: 'sonnet',
      timeoutSeconds: 60,
      localHotkeyAccelerator: 'CommandOrControl+E',
      cliHotkeyAccelerator: 'CommandOrControl+Shift+E',
      undoHotkeyAccelerator: 'CommandOrControl+Shift+Z',
      launchAtLogin: false,
      historyLimit: 50,
      developerMode: false,
      language: 'auto',
      soundFeedbackEnabled: true,
      notifyOnSuccess: false,
      clipboardOnlyMode: false,
      tonePreset: 'default',
      diffPreviewMode: 'interactive',
      passivePreviewSeconds: 5,
      autoPasteDelaySeconds: 5,
      localModelVariant: 'fp32',
      localModelSpeed: 'fast',
      firstRunComplete: false,
    };
    expect(config.localHotkeyAccelerator).toBe('CommandOrControl+E');
    expect(config.cliHotkeyAccelerator).toBe('CommandOrControl+Shift+E');
  });

  it('does NOT have a hotkeyAccelerator field in the type', () => {
    const config: AppConfig = {
      claudePath: '',
      codexPath: '',
      geminiPath: '',
      provider: 'local',
      model: 't5-grammar',
      cliProvider: 'claude',
      cliModel: 'sonnet',
      timeoutSeconds: 60,
      localHotkeyAccelerator: 'CommandOrControl+E',
      cliHotkeyAccelerator: 'CommandOrControl+Shift+E',
      undoHotkeyAccelerator: 'CommandOrControl+Shift+Z',
      launchAtLogin: false,
      historyLimit: 50,
      developerMode: false,
      language: 'auto',
      soundFeedbackEnabled: true,
      notifyOnSuccess: false,
      clipboardOnlyMode: false,
      tonePreset: 'default',
      diffPreviewMode: 'interactive',
      passivePreviewSeconds: 5,
      autoPasteDelaySeconds: 5,
      localModelVariant: 'fp32',
      localModelSpeed: 'fast',
      firstRunComplete: false,
    };
    // Runtime check: no hotkeyAccelerator key
    expect(config).not.toHaveProperty('hotkeyAccelerator');
  });
});

describe('DiffPreviewMode type', () => {
  it('accepts all three mode values', () => {
    const modes: DiffPreviewMode[] = ['none', 'passive', 'interactive'];
    expect(modes).toHaveLength(3);
  });
});
