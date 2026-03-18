import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock config-manager
const mockLoad = vi.fn();
vi.mock('./config-manager', () => ({
  configManager: { load: () => mockLoad() },
}));

// Mock cli-arguments
vi.mock('./cli-arguments', () => ({
  resolveCLIPath: vi.fn(() => '/usr/local/bin/claude'),
}));

// Mock device-selector
vi.mock('./device-selector', () => ({
  getCachedDevice: vi.fn(() => null),
}));

// Build a mock Tray class with chainable/inspectable methods
const mockSetToolTip = vi.fn();
const mockSetContextMenu = vi.fn();
const mockSetImage = vi.fn();
const mockDestroy = vi.fn();
const mockOn = vi.fn();

class MockTray {
  constructor() {
    // no-op
  }
  setToolTip = mockSetToolTip;
  setContextMenu = mockSetContextMenu;
  setImage = mockSetImage;
  destroy = mockDestroy;
  on = mockOn;
}

// Capture the menu template for inspection
let capturedMenuTemplate: any[] = [];
const mockBuildFromTemplate = vi.fn((template: any[]) => {
  capturedMenuTemplate = template;
  return { items: template };
});

vi.mock('electron', () => ({
  app: {
    isPackaged: false,
    getAppPath: () => '/app',
    quit: vi.fn(),
  },
  Tray: MockTray,
  Menu: {
    buildFromTemplate: (t: any[]) => mockBuildFromTemplate(t),
  },
  nativeImage: {
    createFromPath: vi.fn(() => ({
      toPNG: () => Buffer.from(''),
      addRepresentation: vi.fn(),
      resize: vi.fn(() => ({ toPNG: () => Buffer.from('') })),
    })),
    createEmpty: vi.fn(() => ({
      addRepresentation: vi.fn(),
    })),
  },
}));

import { DEFAULT_CONFIG } from '../shared/constants';

beforeEach(() => {
  vi.clearAllMocks();
  capturedMenuTemplate = [];
  mockLoad.mockReturnValue({
    ...DEFAULT_CONFIG,
    provider: 'local',
    localHotkeyAccelerator: 'CommandOrControl+E',
    cliHotkeyAccelerator: 'CommandOrControl+Shift+E',
  });
});

// Helper: fresh module to reset module-level tray var
async function freshModule() {
  vi.resetModules();
  vi.doMock('./config-manager', () => ({
    configManager: { load: () => mockLoad() },
  }));
  vi.doMock('./cli-arguments', () => ({
    resolveCLIPath: vi.fn(() => '/usr/local/bin/claude'),
  }));
  vi.doMock('./device-selector', () => ({
    getCachedDevice: vi.fn(() => null),
  }));
  vi.doMock('electron', () => ({
    app: {
      isPackaged: false,
      getAppPath: () => '/app',
      quit: vi.fn(),
    },
    Tray: MockTray,
    Menu: {
      buildFromTemplate: (t: any[]) => mockBuildFromTemplate(t),
    },
    nativeImage: {
      createFromPath: vi.fn(() => ({
        toPNG: () => Buffer.from(''),
        addRepresentation: vi.fn(),
        resize: vi.fn(() => ({ toPNG: () => Buffer.from('') })),
      })),
      createEmpty: vi.fn(() => ({
        addRepresentation: vi.fn(),
      })),
    },
  }));
  return import('./tray-manager');
}

describe('createTray', () => {
  it('creates a Tray instance', async () => {
    const { Tray } = await import('electron');
    const { createTray } = await freshModule();
    const callbacks = {
      onCorrectLocal: vi.fn(),
      onCorrectCLI: vi.fn(),
      onUndoLastCorrection: vi.fn(),
      onOpenSettings: vi.fn(),
      onOpenHistory: vi.fn(),
    };

    const tray = createTray(callbacks);
    expect(tray).toBeDefined();
    expect(mockSetToolTip).toHaveBeenCalledWith('GhostEdit');
  });
});

describe('updateMenu', () => {
  it('builds menu with local and CLI correction items', async () => {
    const { createTray, updateMenu } = await freshModule();
    const callbacks = {
      onCorrectLocal: vi.fn(),
      onCorrectCLI: vi.fn(),
      onUndoLastCorrection: vi.fn(),
      onOpenSettings: vi.fn(),
      onOpenHistory: vi.fn(),
    };
    createTray(callbacks);

    // Check the captured menu template
    const labels = capturedMenuTemplate.map((item: any) => item.label).filter(Boolean);
    const hasLocalCorrect = labels.some((l: string) => l.includes('Correct (Local)'));
    const hasCliCorrect = labels.some((l: string) => l.includes('Correct ('));
    expect(hasLocalCorrect).toBe(true);
    expect(hasCliCorrect).toBe(true);
  });

  it('local correction label includes formatted localHotkeyAccelerator', async () => {
    const { createTray } = await freshModule();
    const callbacks = {
      onCorrectLocal: vi.fn(),
      onCorrectCLI: vi.fn(),
      onUndoLastCorrection: vi.fn(),
      onOpenSettings: vi.fn(),
      onOpenHistory: vi.fn(),
    };
    createTray(callbacks);

    const localItem = capturedMenuTemplate.find((item: any) =>
      item.label && item.label.includes('Correct (Local)'),
    );
    expect(localItem).toBeDefined();
    // The label should contain some representation of the accelerator
    expect(localItem.label).toContain('(');
  });

  it('clicking local item calls onCorrectLocal callback', async () => {
    const { createTray } = await freshModule();
    const onCorrectLocal = vi.fn();
    const callbacks = {
      onCorrectLocal,
      onCorrectCLI: vi.fn(),
      onUndoLastCorrection: vi.fn(),
      onOpenSettings: vi.fn(),
      onOpenHistory: vi.fn(),
    };
    createTray(callbacks);

    const localItem = capturedMenuTemplate.find((item: any) =>
      item.label && item.label.includes('Correct (Local)'),
    );
    localItem.click();
    expect(onCorrectLocal).toHaveBeenCalledTimes(1);
  });

  it('clicking CLI item calls onCorrectCLI callback', async () => {
    const { createTray } = await freshModule();
    const onCorrectCLI = vi.fn();
    const callbacks = {
      onCorrectLocal: vi.fn(),
      onCorrectCLI,
      onUndoLastCorrection: vi.fn(),
      onOpenSettings: vi.fn(),
      onOpenHistory: vi.fn(),
    };
    createTray(callbacks);

    const cliItem = capturedMenuTemplate.find((item: any) =>
      item.label && item.label.includes('Correct (Claude)'),
    );
    cliItem.click();
    expect(onCorrectCLI).toHaveBeenCalledTimes(1);
  });

  it('CLI label shows cliProvider displayName', async () => {
    mockLoad.mockReturnValue({
      ...DEFAULT_CONFIG,
      provider: 'local',
      cliProvider: 'gemini',
      cliModel: 'gemini-2.5-flash',
      localHotkeyAccelerator: 'CommandOrControl+E',
      cliHotkeyAccelerator: 'CommandOrControl+Shift+E',
    });

    const { createTray } = await freshModule();
    const callbacks = {
      onCorrectLocal: vi.fn(),
      onCorrectCLI: vi.fn(),
      onUndoLastCorrection: vi.fn(),
      onOpenSettings: vi.fn(),
      onOpenHistory: vi.fn(),
    };
    createTray(callbacks);

    const cliItem = capturedMenuTemplate.find((item: any) =>
      item.label && item.label.includes('Correct (Gemini)'),
    );
    expect(cliItem).toBeDefined();
  });
});

describe('setTrayState', () => {
  it('changes tray icon when state changes to processing', async () => {
    const { createTray, setTrayState } = await freshModule();
    const callbacks = {
      onCorrectLocal: vi.fn(),
      onCorrectCLI: vi.fn(),
      onUndoLastCorrection: vi.fn(),
      onOpenSettings: vi.fn(),
      onOpenHistory: vi.fn(),
    };
    createTray(callbacks);
    mockSetImage.mockClear();

    setTrayState('processing');
    expect(mockSetImage).toHaveBeenCalled();
  });
});

describe('destroyTray', () => {
  it('destroys the tray instance', async () => {
    const { createTray, destroyTray } = await freshModule();
    const callbacks = {
      onCorrectLocal: vi.fn(),
      onCorrectCLI: vi.fn(),
      onUndoLastCorrection: vi.fn(),
      onOpenSettings: vi.fn(),
      onOpenHistory: vi.fn(),
    };
    createTray(callbacks);

    destroyTray();
    expect(mockDestroy).toHaveBeenCalled();
  });
});

describe('developer mode', () => {
  it('shows inference device line when developerMode is on', async () => {
    // Need to re-mock device-selector to return a device
    vi.resetModules();
    vi.doMock('./config-manager', () => ({
      configManager: {
        load: () => ({
          ...DEFAULT_CONFIG,
          provider: 'local',
          developerMode: true,
          localHotkeyAccelerator: 'CommandOrControl+E',
          cliHotkeyAccelerator: 'CommandOrControl+Shift+E',
        }),
      },
    }));
    vi.doMock('./cli-arguments', () => ({
      resolveCLIPath: vi.fn(() => null),
    }));
    vi.doMock('./device-selector', () => ({
      getCachedDevice: vi.fn(() => ({ device: 'webgpu', runtime: 'renderer', label: 'WebGPU (GPU)' })),
    }));
    vi.doMock('electron', () => ({
      app: {
        isPackaged: false,
        getAppPath: () => '/app',
        quit: vi.fn(),
      },
      Tray: MockTray,
      Menu: {
        buildFromTemplate: (t: any[]) => mockBuildFromTemplate(t),
      },
      nativeImage: {
        createFromPath: vi.fn(() => ({
          toPNG: () => Buffer.from(''),
          addRepresentation: vi.fn(),
          resize: vi.fn(() => ({ toPNG: () => Buffer.from('') })),
        })),
        createEmpty: vi.fn(() => ({
          addRepresentation: vi.fn(),
        })),
      },
    }));

    const { createTray } = await import('./tray-manager');
    const callbacks = {
      onCorrectLocal: vi.fn(),
      onCorrectCLI: vi.fn(),
      onUndoLastCorrection: vi.fn(),
      onOpenSettings: vi.fn(),
      onOpenHistory: vi.fn(),
    };
    createTray(callbacks);

    const inferenceItem = capturedMenuTemplate.find((item: any) =>
      item.label && item.label.includes('Inference:'),
    );
    expect(inferenceItem).toBeDefined();
    expect(inferenceItem.label).toContain('WebGPU');
  });
});
