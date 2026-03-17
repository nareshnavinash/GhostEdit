import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock config-manager
const mockLoad = vi.fn();
vi.mock('./config-manager', () => ({
  configManager: { load: () => mockLoad() },
}));

// Mock electron globalShortcut
const mockRegister = vi.fn();
const mockUnregisterAll = vi.fn();
vi.mock('electron', () => ({
  globalShortcut: {
    register: (...args: any[]) => mockRegister(...args),
    unregisterAll: () => mockUnregisterAll(),
  },
}));

import { DEFAULT_CONFIG } from '../shared/constants';

// Helper to get a fresh module (resets module-level vars)
async function freshModule() {
  vi.resetModules();
  vi.doMock('./config-manager', () => ({
    configManager: { load: () => mockLoad() },
  }));
  vi.doMock('electron', () => ({
    globalShortcut: {
      register: (...args: any[]) => mockRegister(...args),
      unregisterAll: () => mockUnregisterAll(),
    },
  }));
  return import('./global-shortcuts');
}

beforeEach(() => {
  vi.clearAllMocks();
  mockRegister.mockReturnValue(true);
  mockLoad.mockReturnValue({
    localHotkeyAccelerator: 'CommandOrControl+E',
    cliHotkeyAccelerator: 'CommandOrControl+Shift+E',
  });
});

describe('registerGlobalShortcuts', () => {
  it('registers two shortcuts when accelerators differ', async () => {
    const { registerGlobalShortcuts } = await freshModule();
    const localHandler = vi.fn();
    const cliHandler = vi.fn();

    registerGlobalShortcuts(localHandler, cliHandler);

    expect(mockRegister).toHaveBeenCalledTimes(2);
    expect(mockRegister).toHaveBeenCalledWith('CommandOrControl+E', localHandler);
    expect(mockRegister).toHaveBeenCalledWith('CommandOrControl+Shift+E', cliHandler);
  });

  it('only registers local when both accelerators are the same and logs warning', async () => {
    mockLoad.mockReturnValue({
      localHotkeyAccelerator: 'CommandOrControl+E',
      cliHotkeyAccelerator: 'CommandOrControl+E',
    });
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    const { registerGlobalShortcuts } = await freshModule();
    registerGlobalShortcuts(vi.fn(), vi.fn());

    expect(mockRegister).toHaveBeenCalledTimes(1);
    expect(warnSpy).toHaveBeenCalledWith(expect.stringContaining('same'));
    warnSpy.mockRestore();
  });

  it('uses DEFAULT_CONFIG accelerator when config value is empty', async () => {
    mockLoad.mockReturnValue({
      localHotkeyAccelerator: '',
      cliHotkeyAccelerator: '',
    });

    const { registerGlobalShortcuts } = await freshModule();
    registerGlobalShortcuts(vi.fn(), vi.fn());

    // Both fall back to defaults; defaults differ so both register
    expect(mockRegister).toHaveBeenCalledWith(DEFAULT_CONFIG.localHotkeyAccelerator, expect.any(Function));
    expect(mockRegister).toHaveBeenCalledWith(DEFAULT_CONFIG.cliHotkeyAccelerator, expect.any(Function));
  });

  it('captured local handler is invoked when shortcut fires', async () => {
    const { registerGlobalShortcuts } = await freshModule();
    const localHandler = vi.fn();
    registerGlobalShortcuts(localHandler, vi.fn());

    // Get the handler passed to register for the local shortcut
    const registeredHandler = mockRegister.mock.calls[0][1];
    registeredHandler();
    expect(localHandler).toHaveBeenCalledTimes(1);
  });

  it('captured cli handler is invoked when shortcut fires', async () => {
    const { registerGlobalShortcuts } = await freshModule();
    const cliHandler = vi.fn();
    registerGlobalShortcuts(vi.fn(), cliHandler);

    // CLI is the second call
    const registeredHandler = mockRegister.mock.calls[1][1];
    registeredHandler();
    expect(cliHandler).toHaveBeenCalledTimes(1);
  });

  it('handles register() returning false (logs error, no crash)', async () => {
    mockRegister.mockReturnValue(false);
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    const { registerGlobalShortcuts } = await freshModule();
    registerGlobalShortcuts(vi.fn(), vi.fn());

    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining('Failed to register'));
    errorSpy.mockRestore();
  });

  it('handles register() throwing (logs error, no crash)', async () => {
    mockRegister.mockImplementation(() => { throw new Error('boom'); });
    const errorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    const { registerGlobalShortcuts } = await freshModule();
    registerGlobalShortcuts(vi.fn(), vi.fn());

    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining('Error registering'), expect.any(Error));
    errorSpy.mockRestore();
  });
});

describe('refreshGlobalShortcuts', () => {
  it('calls unregisterAll then re-registers', async () => {
    const { refreshGlobalShortcuts } = await freshModule();
    refreshGlobalShortcuts(vi.fn(), vi.fn());

    expect(mockUnregisterAll).toHaveBeenCalledTimes(1);
    expect(mockRegister).toHaveBeenCalled();
  });
});

describe('unregisterAll', () => {
  it('calls globalShortcut.unregisterAll()', async () => {
    const { unregisterAll } = await freshModule();
    unregisterAll();
    expect(mockUnregisterAll).toHaveBeenCalledTimes(1);
  });
});
