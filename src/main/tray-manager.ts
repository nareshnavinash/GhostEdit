import * as path from 'node:path';
import { app, Tray, Menu, nativeImage } from 'electron';
import { configManager } from './config-manager';
import { resolveCLIPath } from './cli-arguments';
import { CLI_PROVIDERS } from '../shared/constants';
import { getCachedDevice } from './device-selector';

let tray: Tray | null = null;
let currentTrayState: 'idle' | 'processing' = 'idle';

interface TrayCallbacks {
  onCorrectLocal: () => void;
  onCorrectCLI: () => void;
  onUndoLastCorrection: () => void;
  onOpenSettings: () => void;
  onOpenHistory: () => void;
}

function resolveAssetPath(filename: string): string {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, filename);
  }
  return path.join(app.getAppPath(), 'assets', filename);
}

function loadTrayIcon(state: 'idle' | 'processing'): Electron.NativeImage {
  const filename = state === 'idle' ? 'MenuBarIconIdle.png' : 'MenuBarIconProcessing.png';
  let icon = nativeImage.createFromPath(resolveAssetPath(filename));

  if (process.platform === 'darwin') {
    // Source PNGs are 44x44 = @2x for 22pt macOS menu bar.
    // Use addRepresentation to register at 2x scale so macOS renders at 22pt.
    // Do NOT set as template image — the icon has its own colors (white ghost face).
    const scaled = nativeImage.createEmpty();
    scaled.addRepresentation({
      buffer: icon.toPNG(),
      width: 22,
      height: 22,
      scaleFactor: 2.0,
    });
    icon = scaled;
  } else if (process.platform === 'win32') {
    // Windows system tray expects 16x16 or 32x32
    icon = icon.resize({ width: 32, height: 32 });
  }
  // Linux: 44x44 PNG works as-is (common tray sizes are 22-48px)

  return icon;
}

export function setTrayState(state: 'idle' | 'processing'): void {
  if (!tray || currentTrayState === state) return;
  currentTrayState = state;
  tray.setImage(loadTrayIcon(state));
}

/**
 * Create and manage the system tray icon and menu.
 */
export function createTray(callbacks: TrayCallbacks): Tray {
  const icon = loadTrayIcon('idle');
  tray = new Tray(icon);
  tray.setToolTip('GhostEdit');

  // On macOS, clicking the tray icon shows the context menu automatically.
  // On Windows/Linux, left-click should also show the menu.
  if (process.platform !== 'darwin') {
    tray.on('click', () => {
      tray?.popUpContextMenu();
    });
  }

  updateMenu(callbacks);
  return tray;
}

/**
 * Rebuild the tray context menu (call after config changes).
 */
export function updateMenu(callbacks: TrayCallbacks): void {
  if (!tray) return;

  const config = configManager.load();
  const cliProviderDef = CLI_PROVIDERS[config.cliProvider];
  const cliFound = cliProviderDef
    ? resolveCLIPath(cliProviderDef.name, config[cliProviderDef.configPathKey] || undefined)
    : null;

  const statusLabel = cliFound ? `CLI (${cliProviderDef?.displayName}): Found` : `CLI (${cliProviderDef?.displayName}): Not found`;

  // Build optional developer-mode inference device line
  const devItems: Electron.MenuItemConstructorOptions[] = [];
  if (config.developerMode) {
    const device = getCachedDevice();
    if (device) {
      devItems.push({
        label: `Inference: ${device.label}`,
        enabled: false,
      });
    }
  }

  const menu = Menu.buildFromTemplate([
    {
      label: 'GhostEdit',
      enabled: false,
    },
    { type: 'separator' },
    {
      label: `Local: Built-in (${config.localModelVariant ?? 'fp32'})`,
      enabled: false,
    },
    {
      label: `CLI: ${cliProviderDef?.displayName ?? 'None'} / ${config.cliModel}`,
      enabled: false,
    },
    {
      label: statusLabel,
      enabled: false,
    },
    ...devItems,
    { type: 'separator' },
    {
      label: `Correct (Local) (${formatAccelerator(config.localHotkeyAccelerator)})`,
      click: callbacks.onCorrectLocal,
    },
    {
      label: `Correct (${cliProviderDef?.displayName ?? 'CLI'}) (${formatAccelerator(config.cliHotkeyAccelerator)})`,
      click: callbacks.onCorrectCLI,
    },
    { type: 'separator' },
    {
      label: `Undo Last Correction (${formatAccelerator(config.undoHotkeyAccelerator)})`,
      click: callbacks.onUndoLastCorrection,
    },
    { type: 'separator' },
    {
      label: 'Settings...',
      click: callbacks.onOpenSettings,
    },
    {
      label: 'History...',
      click: callbacks.onOpenHistory,
    },
    { type: 'separator' },
    {
      label: 'Quit GhostEdit',
      click: () => app.quit(),
    },
  ]);

  tray.setContextMenu(menu);
}

function formatAccelerator(acc: string): string {
  if (!acc) return '';
  return acc
    .replace('CommandOrControl', process.platform === 'darwin' ? '\u2318' : 'Ctrl')
    .replace('Shift', process.platform === 'darwin' ? '\u21E7' : 'Shift')
    .replace('Alt', process.platform === 'darwin' ? '\u2325' : 'Alt')
    .replace(/\+/g, process.platform === 'darwin' ? '' : '+');
}

export function destroyTray(): void {
  if (tray) {
    tray.destroy();
    tray = null;
  }
}
