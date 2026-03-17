import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { AppConfig } from '../shared/types';
import { DEFAULT_CONFIG, DEFAULT_SYSTEM_PROMPT } from '../shared/constants';

// Mock node:os
vi.mock('node:os', () => ({
  default: { homedir: () => '/mock-home' },
  homedir: () => '/mock-home',
}));

// Mock node:fs
const mockExistsSync = vi.fn((_p?: string) => false);
const mockReadFileSync = vi.fn((_p?: string, _e?: string) => '{}');
const mockWriteFileSync = vi.fn((_p?: string, _d?: string, _e?: string) => {});
const mockMkdirSync = vi.fn((_p?: string, _o?: any) => {});

vi.mock('node:fs', () => ({
  default: {
    existsSync: (p: string) => mockExistsSync(p),
    readFileSync: (p: string, e: string) => mockReadFileSync(p, e),
    writeFileSync: (p: string, d: string, e?: string) => mockWriteFileSync(p, d, e),
    mkdirSync: (p: string, o: any) => mockMkdirSync(p, o),
  },
  existsSync: (p: string) => mockExistsSync(p),
  readFileSync: (p: string, e: string) => mockReadFileSync(p, e),
  writeFileSync: (p: string, d: string, e?: string) => mockWriteFileSync(p, d, e),
  mkdirSync: (p: string, o: any) => mockMkdirSync(p, o),
}));

// Helper: fresh import to reset singleton state
async function freshModule() {
  vi.resetModules();
  vi.doMock('node:os', () => ({
    default: { homedir: () => '/mock-home' },
    homedir: () => '/mock-home',
  }));
  vi.doMock('node:fs', () => ({
    default: {
      existsSync: (p: string) => mockExistsSync(p),
      readFileSync: (p: string, e: string) => mockReadFileSync(p, e),
      writeFileSync: (p: string, d: string, e?: string) => mockWriteFileSync(p, d, e),
      mkdirSync: (p: string, o: any) => mockMkdirSync(p, o),
    },
    existsSync: (p: string) => mockExistsSync(p),
    readFileSync: (p: string, e: string) => mockReadFileSync(p, e),
    writeFileSync: (p: string, d: string, e?: string) => mockWriteFileSync(p, d, e),
    mkdirSync: (p: string, o: any) => mockMkdirSync(p, o),
  }));
  const mod = await import('./config-manager');
  return mod.configManager;
}

beforeEach(() => {
  vi.clearAllMocks();
  mockExistsSync.mockReturnValue(false);
});

describe('ConfigManager.load', () => {
  it('migrates hotkeyAccelerator → cliHotkeyAccelerator and sets localHotkeyAccelerator to default', async () => {
    const cm = await freshModule();
    const legacy = JSON.stringify({ hotkeyAccelerator: 'Alt+G', provider: 'claude' });
    mockReadFileSync.mockReturnValue(legacy);

    const config = cm.load();
    expect(config.cliHotkeyAccelerator).toBe('Alt+G');
    expect(config.localHotkeyAccelerator).toBe(DEFAULT_CONFIG.localHotkeyAccelerator);
  });

  it('removes old hotkeyAccelerator key after migration', async () => {
    const cm = await freshModule();
    const legacy = JSON.stringify({ hotkeyAccelerator: 'Alt+G' });
    mockReadFileSync.mockReturnValue(legacy);

    const config = cm.load();
    expect(config).not.toHaveProperty('hotkeyAccelerator');
  });

  it('skips migration when localHotkeyAccelerator already exists', async () => {
    const cm = await freshModule();
    const data = JSON.stringify({
      hotkeyAccelerator: 'Alt+G',
      localHotkeyAccelerator: 'CommandOrControl+J',
      cliHotkeyAccelerator: 'CommandOrControl+K',
    });
    mockReadFileSync.mockReturnValue(data);

    const config = cm.load();
    // Should keep the existing values, not overwrite from hotkeyAccelerator
    expect(config.localHotkeyAccelerator).toBe('CommandOrControl+J');
    expect(config.cliHotkeyAccelerator).toBe('CommandOrControl+K');
  });

  it('preserves existing dual-hotkey config untouched', async () => {
    const cm = await freshModule();
    const data = JSON.stringify({
      localHotkeyAccelerator: 'CommandOrControl+J',
      cliHotkeyAccelerator: 'CommandOrControl+K',
      provider: 'codex',
    });
    mockReadFileSync.mockReturnValue(data);

    const config = cm.load();
    expect(config.localHotkeyAccelerator).toBe('CommandOrControl+J');
    expect(config.cliHotkeyAccelerator).toBe('CommandOrControl+K');
    expect(config.provider).toBe('codex');
  });

  it('merges defaults for missing keys', async () => {
    const cm = await freshModule();
    mockReadFileSync.mockReturnValue(JSON.stringify({ provider: 'claude' }));

    const config = cm.load();
    expect(config.provider).toBe('claude');
    expect(config.timeoutSeconds).toBe(DEFAULT_CONFIG.timeoutSeconds);
    expect(config.localHotkeyAccelerator).toBe(DEFAULT_CONFIG.localHotkeyAccelerator);
  });

  it('migrates cliProvider from provider when provider is a CLI provider', async () => {
    const cm = await freshModule();
    const data = JSON.stringify({ provider: 'gemini', model: 'gemini-2.5-pro' });
    mockReadFileSync.mockReturnValue(data);

    const config = cm.load();
    expect(config.cliProvider).toBe('gemini');
    expect(config.cliModel).toBe('gemini-2.5-pro');
  });

  it('uses default cliProvider when provider is local', async () => {
    const cm = await freshModule();
    const data = JSON.stringify({ provider: 'local' });
    mockReadFileSync.mockReturnValue(data);

    const config = cm.load();
    expect(config.cliProvider).toBe('claude');
    expect(config.cliModel).toBe('sonnet');
  });

  it('preserves existing cliProvider when already set', async () => {
    const cm = await freshModule();
    const data = JSON.stringify({ provider: 'local', cliProvider: 'codex', cliModel: 'o3' });
    mockReadFileSync.mockReturnValue(data);

    const config = cm.load();
    expect(config.cliProvider).toBe('codex');
    expect(config.cliModel).toBe('o3');
  });

  it('migrates localModelVariant from fp32 to int8', async () => {
    const cm = await freshModule();
    const data = JSON.stringify({ localModelVariant: 'fp32' });
    mockReadFileSync.mockReturnValue(data);

    const config = cm.load();
    expect(config.localModelVariant).toBe('int8');
  });

  it('preserves non-fp32 localModelVariant unchanged', async () => {
    const cm = await freshModule();
    const data = JSON.stringify({ localModelVariant: 'fp16' });
    mockReadFileSync.mockReturnValue(data);

    const config = cm.load();
    expect(config.localModelVariant).toBe('fp16');
  });

  it('returns DEFAULT_CONFIG on file read error', async () => {
    const cm = await freshModule();
    mockReadFileSync.mockImplementation(() => { throw new Error('ENOENT'); });

    const config = cm.load();
    expect(config).toEqual(DEFAULT_CONFIG);
  });

  it('caches — second call does not re-read file', async () => {
    const cm = await freshModule();
    mockReadFileSync.mockReturnValue(JSON.stringify({ provider: 'gemini' }));

    cm.load();
    cm.load();
    expect(mockReadFileSync).toHaveBeenCalledTimes(1);
  });
});

describe('ConfigManager.save', () => {
  it('writes JSON to disk via writeFileSync', async () => {
    const cm = await freshModule();
    const config = { ...DEFAULT_CONFIG, provider: 'claude' as const };
    cm.save(config);

    expect(mockWriteFileSync).toHaveBeenCalled();
    const written = JSON.parse(mockWriteFileSync.mock.calls[0][1] as string);
    expect(written.provider).toBe('claude');
  });

  it('updates in-memory cache', async () => {
    const cm = await freshModule();
    const config = { ...DEFAULT_CONFIG, provider: 'codex' as const };
    cm.save(config);

    // Second load should return cached value without reading file
    mockReadFileSync.mockReturnValue(JSON.stringify({ provider: 'gemini' }));
    const loaded = cm.load();
    expect(loaded.provider).toBe('codex');
  });
});

describe('ConfigManager.update', () => {
  it('merges partial into current config', async () => {
    const cm = await freshModule();
    mockReadFileSync.mockReturnValue(JSON.stringify(DEFAULT_CONFIG));

    const updated = cm.update({ provider: 'gemini' });
    expect(updated.provider).toBe('gemini');
    expect(updated.timeoutSeconds).toBe(DEFAULT_CONFIG.timeoutSeconds);
  });
});

describe('ConfigManager.invalidateCache', () => {
  it('forces re-read on next load', async () => {
    const cm = await freshModule();
    mockReadFileSync.mockReturnValue(JSON.stringify({ provider: 'claude' }));

    cm.load();
    expect(mockReadFileSync).toHaveBeenCalledTimes(1);

    cm.invalidateCache();
    cm.load();
    expect(mockReadFileSync).toHaveBeenCalledTimes(2);
  });
});

describe('ConfigManager.ensureDefaults', () => {
  it('creates dir + config + prompt files when missing', async () => {
    const cm = await freshModule();
    mockExistsSync.mockReturnValue(false);

    cm.ensureDefaults();
    expect(mockMkdirSync).toHaveBeenCalled();
    // writeFileSync called twice: once for config, once for prompt
    expect(mockWriteFileSync).toHaveBeenCalledTimes(2);
  });

  it('no-ops when files exist', async () => {
    const cm = await freshModule();
    mockExistsSync.mockReturnValue(true);

    cm.ensureDefaults();
    expect(mockMkdirSync).not.toHaveBeenCalled();
    expect(mockWriteFileSync).not.toHaveBeenCalled();
  });
});

describe('ConfigManager.loadSystemPrompt', () => {
  it('returns custom prompt from file', async () => {
    const cm = await freshModule();
    mockReadFileSync.mockReturnValue('My custom prompt');

    const prompt = cm.loadSystemPrompt();
    expect(prompt).toBe('My custom prompt');
  });

  it('falls back to DEFAULT_SYSTEM_PROMPT on error', async () => {
    const cm = await freshModule();
    mockReadFileSync.mockImplementation(() => { throw new Error('ENOENT'); });

    const prompt = cm.loadSystemPrompt();
    expect(prompt).toBe(DEFAULT_SYSTEM_PROMPT);
  });
});
