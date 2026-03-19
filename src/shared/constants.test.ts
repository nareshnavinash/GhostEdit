import { describe, it, expect } from 'vitest';
import { ALL_PROVIDERS, CLI_PROVIDERS, LOCAL_PROVIDER, DEFAULT_CONFIG, MODEL_VARIANTS, VARIANT_ONNX_FILES, DEFAULT_BUNDLED_VARIANT } from './constants';

describe('ALL_PROVIDERS', () => {
  it('contains all 4 providers', () => {
    const keys = Object.keys(ALL_PROVIDERS);
    expect(keys).toContain('claude');
    expect(keys).toContain('codex');
    expect(keys).toContain('gemini');
    expect(keys).toContain('local');
    expect(keys).toHaveLength(4);
  });

  it('local has correct displayName, availableModels, defaultModel', () => {
    const local = ALL_PROVIDERS['local'];
    expect(local.displayName).toBe('Built-in (Offline)');
    expect(local.availableModels).toEqual(['t5-grammar']);
    expect(local.defaultModel).toBe('t5-grammar');
  });
});

describe('LOCAL_PROVIDER', () => {
  it('has correct modelRepoId', () => {
    expect(LOCAL_PROVIDER.modelRepoId).toBe('Xenova/t5-base-grammar-correction');
  });
});

describe('DEFAULT_CONFIG', () => {
  it('uses local as default provider', () => {
    expect(DEFAULT_CONFIG.provider).toBe('local');
  });

  it('uses int8 as default local model variant', () => {
    expect(DEFAULT_CONFIG.localModelVariant).toBe('int8');
  });

  it('sets diffPreviewMode to interactive by default', () => {
    expect(DEFAULT_CONFIG.diffPreviewMode).toBe('interactive');
  });

  it('sets passivePreviewSeconds to 5 by default', () => {
    expect(DEFAULT_CONFIG.passivePreviewSeconds).toBe(5);
  });

  it('has firstRunComplete set to false by default', () => {
    expect(DEFAULT_CONFIG.firstRunComplete).toBe(false);
  });

  it('has localModelSpeed set to fast by default', () => {
    expect(DEFAULT_CONFIG.localModelSpeed).toBe('fast');
  });

  it('has cliProvider set to claude by default', () => {
    expect(DEFAULT_CONFIG.cliProvider).toBe('claude');
  });

  it('has cliModel set to sonnet by default', () => {
    expect(DEFAULT_CONFIG.cliModel).toBe('sonnet');
  });

  it('has localHotkeyAccelerator set to CommandOrControl+E', () => {
    expect(DEFAULT_CONFIG.localHotkeyAccelerator).toBe('CommandOrControl+E');
  });

  it('has cliHotkeyAccelerator set to CommandOrControl+Shift+E', () => {
    expect(DEFAULT_CONFIG.cliHotkeyAccelerator).toBe('CommandOrControl+Shift+E');
  });

  it('does NOT have a hotkeyAccelerator property', () => {
    expect(DEFAULT_CONFIG).not.toHaveProperty('hotkeyAccelerator');
  });

  it('has appToneOverrides default as empty object', () => {
    expect(DEFAULT_CONFIG.appToneOverrides).toEqual({});
  });

  it('has meetingModeEnabled default as true', () => {
    expect(DEFAULT_CONFIG.meetingModeEnabled).toBe(true);
  });

  it('has meetingApps default with common meeting apps', () => {
    expect(DEFAULT_CONFIG.meetingApps).toContain('Zoom');
    expect(DEFAULT_CONFIG.meetingApps).toContain('FaceTime');
    expect(DEFAULT_CONFIG.meetingApps.length).toBeGreaterThanOrEqual(4);
  });

  it('has suppressedSuggestions default as empty object', () => {
    expect(DEFAULT_CONFIG.suppressedSuggestions).toEqual({});
  });
});

describe('CLI_PROVIDERS', () => {
  it('does NOT contain local', () => {
    expect(CLI_PROVIDERS).not.toHaveProperty('local');
  });
});

describe('DEFAULT_BUNDLED_VARIANT', () => {
  it('is int8', () => {
    expect(DEFAULT_BUNDLED_VARIANT).toBe('int8');
  });
});

describe('MODEL_VARIANTS', () => {
  it('contains all 4 variants', () => {
    expect(MODEL_VARIANTS).toHaveLength(4);
    const variantNames = MODEL_VARIANTS.map((v) => v.variant);
    expect(variantNames).toEqual(['q4f16', 'int8', 'fp16', 'fp32']);
  });

  it('each variant has displayName and sizeMB', () => {
    for (const v of MODEL_VARIANTS) {
      expect(v.displayName).toBeTruthy();
      expect(v.sizeMB).toBeGreaterThan(0);
    }
  });

  it('variants are ordered from smallest to largest', () => {
    const sizes = MODEL_VARIANTS.map((v) => v.sizeMB);
    for (let i = 1; i < sizes.length; i++) {
      expect(sizes[i]).toBeGreaterThanOrEqual(sizes[i - 1]);
    }
  });
});

describe('VARIANT_ONNX_FILES', () => {
  it('has entries for all 4 variants', () => {
    const keys = Object.keys(VARIANT_ONNX_FILES);
    expect(keys).toContain('q4f16');
    expect(keys).toContain('int8');
    expect(keys).toContain('fp16');
    expect(keys).toContain('fp32');
  });

  it('each entry has encoder and decoder filenames ending in .onnx', () => {
    for (const [, files] of Object.entries(VARIANT_ONNX_FILES)) {
      expect(files.encoder).toMatch(/\.onnx$/);
      expect(files.decoder).toMatch(/\.onnx$/);
    }
  });

  it('fp32 uses unquantized filenames', () => {
    expect(VARIANT_ONNX_FILES.fp32.encoder).toBe('encoder_model.onnx');
    expect(VARIANT_ONNX_FILES.fp32.decoder).toBe('decoder_model_merged.onnx');
  });
});
