/**
 * Auto-update integration using electron-updater.
 * Checks for updates on app start (silently) and exposes state
 * for the tray menu to show an "Update available" item.
 */

let updateAvailable: string | null = null;
let onUpdateAvailable: ((version: string) => void) | null = null;

export interface AutoUpdaterCallbacks {
  onUpdateAvailable: (version: string) => void;
}

export function initAutoUpdater(callbacks: AutoUpdaterCallbacks): void {
  onUpdateAvailable = callbacks.onUpdateAvailable;

  try {
    const { autoUpdater } = require('electron-updater');

    autoUpdater.autoDownload = false;
    autoUpdater.autoInstallOnAppQuit = false;

    autoUpdater.on('update-available', (info: { version: string }) => {
      updateAvailable = info.version;
      onUpdateAvailable?.(info.version);
      console.log(`[GhostEdit] Update available: v${info.version}`);
    });

    autoUpdater.on('error', (err: Error) => {
      console.warn('[GhostEdit] Auto-updater error:', err.message);
    });

    // Check silently on startup
    autoUpdater.checkForUpdates().catch((err: Error) => {
      console.warn('[GhostEdit] Update check failed:', err.message);
    });
  } catch (err: any) {
    console.warn('[GhostEdit] electron-updater not available:', err.message);
  }
}

export function getAvailableUpdate(): string | null {
  return updateAvailable;
}

export function downloadAndInstall(): void {
  try {
    const { autoUpdater } = require('electron-updater');
    autoUpdater.downloadUpdate().then(() => {
      autoUpdater.quitAndInstall(false, true);
    });
  } catch (err: any) {
    console.error('[GhostEdit] Failed to download update:', err.message);
  }
}
