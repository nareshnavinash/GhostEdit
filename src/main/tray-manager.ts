import * as path from 'node:path';
import { app, Tray, Menu, nativeImage, clipboard } from 'electron';
import { configManager } from './config-manager';
import { resolveCLIPath } from './cli-arguments';
import { CLI_PROVIDERS } from '../shared/constants';
import { getCachedDevice } from './device-selector';
import { updateStreak } from './history-store';
import { getAvailableUpdate } from './auto-updater';
import type { TrafficLightColor } from '../shared/types';

let tray: Tray | null = null;
let currentTrayState: 'idle' | 'processing' = 'idle';
let currentTrafficColor: TrafficLightColor | null = null;
let currentIssueCount = 0;
let storedCallbacks: TrayCallbacks | null = null;

export interface TrayCallbacks {
  onCorrectLocal: () => void;
  onCorrectCLI: () => void;
  onUndoLastCorrection: () => void;
  onOpenSettings: () => void;
  onOpenHistory: () => void;
  onShowSuggestions?: () => void;
  onDownloadUpdate?: () => void;
  getRecentCorrections?: () => Array<{ original: string; corrected: string; timestamp: number }>;
}

function resolveAssetPath(filename: string): string {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, filename);
  }
  return path.join(app.getAppPath(), 'assets', filename);
}

// ── Dot painting ──

/** BGRA color values for each traffic light color */
const DOT_COLORS: Record<TrafficLightColor, { b: number; g: number; r: number; a: number }> = {
  green:  { b: 94,  g: 197, r: 34,  a: 255 },
  yellow: { b: 8,   g: 179, r: 234, a: 255 },
  red:    { b: 68,  g: 68,  r: 239, a: 255 },
};

const BORDER_COLOR = { b: 30, g: 30, r: 30, a: 255 };

/**
 * Draw a filled circle with a 1px dark border onto a raw BGRA bitmap buffer.
 * The dot is placed at the bottom-right of the 44x44 icon.
 */
function paintDotOnBitmap(
  bitmap: Buffer,
  width: number,
  height: number,
  color: TrafficLightColor,
): void {
  const dotColor = DOT_COLORS[color];
  const cx = 35;
  const cy = 35;
  const innerRadius = 5;
  const outerRadius = 6;

  for (let y = cy - outerRadius; y <= cy + outerRadius; y++) {
    for (let x = cx - outerRadius; x <= cx + outerRadius; x++) {
      if (x < 0 || x >= width || y < 0 || y >= height) continue;
      const dist = Math.sqrt((x - cx) ** 2 + (y - cy) ** 2);
      if (dist <= innerRadius) {
        const offset = (y * width + x) * 4;
        bitmap[offset] = dotColor.b;
        bitmap[offset + 1] = dotColor.g;
        bitmap[offset + 2] = dotColor.r;
        bitmap[offset + 3] = dotColor.a;
      } else if (dist <= outerRadius) {
        const offset = (y * width + x) * 4;
        bitmap[offset] = BORDER_COLOR.b;
        bitmap[offset + 1] = BORDER_COLOR.g;
        bitmap[offset + 2] = BORDER_COLOR.r;
        bitmap[offset + 3] = BORDER_COLOR.a;
      }
    }
  }
}

// ── Icon caching ──

const iconCache = new Map<string, Electron.NativeImage>();
const MAX_CACHE = 8;

function buildTrayIcon(
  baseState: 'idle' | 'processing',
  dotColor: TrafficLightColor | null,
): Electron.NativeImage {
  const cacheKey = `${baseState}-${dotColor ?? 'none'}`;
  const cached = iconCache.get(cacheKey);
  if (cached) return cached;

  const filename = baseState === 'idle' ? 'MenuBarIconIdle.png' : 'MenuBarIconProcessing.png';
  const baseIcon = nativeImage.createFromPath(resolveAssetPath(filename));
  const size = baseIcon.getSize();
  const bitmapBuf = Buffer.from(baseIcon.toBitmap());

  if (dotColor !== null) {
    paintDotOnBitmap(bitmapBuf, size.width, size.height, dotColor);
  }

  let icon = nativeImage.createFromBitmap(bitmapBuf, {
    width: size.width,
    height: size.height,
  });

  if (process.platform === 'darwin') {
    const scaled = nativeImage.createEmpty();
    scaled.addRepresentation({
      buffer: icon.toPNG(),
      width: 22,
      height: 22,
      scaleFactor: 2.0,
    });
    icon = scaled;
  } else if (process.platform === 'win32') {
    icon = icon.resize({ width: 32, height: 32 });
  }

  // Evict oldest if cache full
  if (iconCache.size >= MAX_CACHE) {
    const firstKey = iconCache.keys().next().value;
    if (firstKey !== undefined) iconCache.delete(firstKey);
  }
  iconCache.set(cacheKey, icon);

  return icon;
}

function refreshTrayIcon(): void {
  if (!tray) return;
  const dotColor = currentTrayState === 'processing' ? null : currentTrafficColor;
  tray.setImage(buildTrayIcon(currentTrayState, dotColor));
}

// ── Public API ──

export function setTrayState(state: 'idle' | 'processing'): void {
  if (!tray || currentTrayState === state) return;
  currentTrayState = state;
  refreshTrayIcon();
}

export function setTrayTrafficColor(color: TrafficLightColor | null): void {
  if (currentTrafficColor === color) return;
  currentTrafficColor = color;
  refreshTrayIcon();
}

export function getTrayBounds(): Electron.Rectangle | null {
  if (!tray) return null;
  return tray.getBounds();
}

export function updateTrayIssueCount(count: number): void {
  currentIssueCount = count;
  if (storedCallbacks) updateMenu(storedCallbacks);
}

/**
 * Create and manage the system tray icon and menu.
 */
export function createTray(callbacks: TrayCallbacks): Tray {
  storedCallbacks = callbacks;
  const icon = buildTrayIcon('idle', null);
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
  storedCallbacks = callbacks;

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

  // Build dynamic issues item when monitoring is enabled
  const issueItems: Electron.MenuItemConstructorOptions[] = [];
  if (config.monitoringEnabled) {
    if (currentIssueCount > 0) {
      issueItems.push({
        label: `${currentIssueCount} issue${currentIssueCount === 1 ? '' : 's'} found...`,
        click: () => callbacks.onShowSuggestions?.(),
      });
    } else {
      issueItems.push({
        label: 'No issues',
        enabled: false,
      });
    }
    issueItems.push({ type: 'separator' });
  }

  // Compute streak
  const { streakCount } = updateStreak(config.streakDates ?? []);
  const streakLabel = streakCount >= 3
    ? `\uD83D\uDD25 ${streakCount}-day streak`
    : streakCount === 1
      ? 'Used today'
      : streakCount === 2
        ? '2-day streak'
        : null;

  const menu = Menu.buildFromTemplate([
    {
      label: 'GhostEdit',
      enabled: false,
    },
    ...(streakLabel ? [{ label: streakLabel, enabled: false } as Electron.MenuItemConstructorOptions] : []),
    { type: 'separator' as const },
    ...issueItems,
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
    ...buildRecentCorrectionsSubmenu(callbacks),
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
    ...(getAvailableUpdate() ? [{
      label: `Update available (v${getAvailableUpdate()})`,
      click: () => callbacks.onDownloadUpdate?.(),
    } as Electron.MenuItemConstructorOptions] : []),
    {
      label: 'Quit GhostEdit',
      click: () => app.quit(),
    },
  ]);

  tray.setContextMenu(menu);
}

function buildRecentCorrectionsSubmenu(callbacks: TrayCallbacks): Electron.MenuItemConstructorOptions[] {
  const recent = callbacks.getRecentCorrections?.() ?? [];
  if (recent.length === 0) return [];

  const submenu: Electron.MenuItemConstructorOptions[] = recent.map((entry) => {
    const label = entry.corrected.length > 40
      ? entry.corrected.slice(0, 40) + '...'
      : entry.corrected;
    return {
      label,
      click: () => clipboard.writeText(entry.corrected),
    };
  });

  return [{
    label: 'Recent Corrections',
    submenu,
  }];
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
  storedCallbacks = null;
  currentTrafficColor = null;
  currentIssueCount = 0;
  iconCache.clear();
}
