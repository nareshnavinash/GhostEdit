import * as path from 'node:path';
import { randomUUID } from 'node:crypto';
import { app, BrowserWindow, ipcMain, screen, Notification } from 'electron';
import { configManager } from './config-manager';
import { createTray, updateMenu, destroyTray, setTrayState } from './tray-manager';
import { registerGlobalShortcuts, refreshGlobalShortcuts, unregisterAll } from './global-shortcuts';
import { registerIPCHandlers } from './ipc-handlers';
import { correctText } from './correction-dispatcher';
import { protectTokens, restoreTokens, bestEffortRestore, placeholdersAreIntact, getPlaceholderRanges, getOriginalTokenRanges, stripLeakedPlaceholders } from './token-preservation';
import { dictionaryPrePass, dictionaryPolish } from './dictionary-checker';
import { appendHistory } from './history-store';
import * as clipboardManager from './clipboard-manager';
import { getCached, putCache, clearCache } from './correction-cache';
import { TONE_PROMPTS } from '../shared/constants';
import type { ProviderName } from '../shared/types';
import { IPC, type WindowType, type CorrectionHistoryEntry } from '../shared/types';
import { errorToUserMessage } from './error-messages';
import { clearDeviceCache } from './device-selector';

// ── Single Instance Lock ──
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    openWindow('settings');
  });
}

// ── Window Management ──
const windows = new Map<WindowType, BrowserWindow>();

function getPreloadPath(): string {
  return path.join(__dirname, '../preload/index.js');
}

function getRendererURL(windowType: WindowType): string {
  if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
    return `${MAIN_WINDOW_VITE_DEV_SERVER_URL}?windowType=${windowType}`;
  }
  return `file://${path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`)}?windowType=${windowType}`;
}

function openWindow(type: WindowType): BrowserWindow {
  const existing = windows.get(type);
  if (existing && !existing.isDestroyed()) {
    existing.show();
    existing.focus();
    return existing;
  }

  const sizeMap: Record<WindowType, { width: number; height: number }> = {
    settings: { width: 680, height: 520 },
    history: { width: 700, height: 500 },
    hud: { width: 300, height: 80 },
    'streaming-preview': { width: 700, height: 400 },
  };

  const size = sizeMap[type];
  const isHud = type === 'hud';
  const isPreview = type === 'streaming-preview';

  const isOverlay = isHud || isPreview;

  const win = new BrowserWindow({
    width: size.width,
    height: size.height,
    show: false,
    frame: !isOverlay,
    transparent: isOverlay,
    alwaysOnTop: isHud || isPreview,
    skipTaskbar: isHud || isPreview,
    focusable: !isHud && !isPreview,
    resizable: !isHud,
    hasShadow: !isHud,
    ...(isOverlay ? {} : { titleBarStyle: 'hiddenInset' as const }),
    ...(process.platform === 'darwin' && !isOverlay ? { vibrancy: 'under-window' as const } : {}),
    webPreferences: {
      preload: getPreloadPath(),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      backgroundThrottling: isHud ? false : undefined,
    },
  });

  win.loadURL(getRendererURL(type)).catch((err) => {
    console.error(`[GhostEdit] Failed to load window "${type}":`, err.message);
  });

  win.once('ready-to-show', () => {
    if (isHud) {
      // HUD window is shown/positioned by showHUD()
    } else if (isPreview) {
      // Preview shows inactive so it doesn't steal focus from the text field
      win.showInactive();
    } else {
      win.show();
    }
  });

  win.on('closed', () => {
    windows.delete(type);
  });

  windows.set(type, win);
  return win;
}

// ── Pooled HUD Window ──
let hudWindow: BrowserWindow | null = null;

function getOrCreateHUD(): BrowserWindow {
  if (hudWindow && !hudWindow.isDestroyed()) return hudWindow;
  // Create a pooled HUD (not tracked in `windows` map, never destroyed until app quits)
  const win = new BrowserWindow({
    width: 300,
    height: 80,
    show: false,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    focusable: false,
    resizable: false,
    hasShadow: false,
    webPreferences: {
      preload: getPreloadPath(),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      backgroundThrottling: false,
    },
  });

  win.loadURL(getRendererURL('hud')).catch((err) => {
    console.error('[GhostEdit] Failed to load HUD:', err.message);
  });

  hudWindow = win;
  return win;
}

// ── HUD Overlay ──
let hudShowTimeout: ReturnType<typeof setTimeout> | null = null;
let hudCloseTimeout: ReturnType<typeof setTimeout> | null = null;

function showHUD(message: string, durationMs = 2000): void {
  if (hudShowTimeout) clearTimeout(hudShowTimeout);
  if (hudCloseTimeout) clearTimeout(hudCloseTimeout);

  const hud = getOrCreateHUD();

  // Position near top-center of the active display
  const point = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(point);
  const { x, y, width, height } = display.workArea;
  hud.setPosition(
    Math.round(x + width / 2 - 150),
    Math.round(y + height * 0.15),
  );

  const sendAndShow = () => {
    hud.webContents.send(IPC.HUD_SHOW, message);
    if (!hud.isVisible()) hud.showInactive();
  };

  if (hud.webContents.isLoading()) {
    hud.webContents.once('did-finish-load', sendAndShow);
  } else {
    sendAndShow();
  }

  hudShowTimeout = setTimeout(() => {
    if (hud && !hud.isDestroyed()) {
      hud.webContents.send(IPC.HUD_HIDE);
      hudCloseTimeout = setTimeout(() => {
        if (hud && !hud.isDestroyed()) {
          hud.close();
          hudWindow = null;
        }
      }, 300);
    }
    hudShowTimeout = null;
  }, durationMs);
}

function hideHUD(): void {
  if (hudShowTimeout) clearTimeout(hudShowTimeout);
  if (hudCloseTimeout) clearTimeout(hudCloseTimeout);
  if (hudWindow && !hudWindow.isDestroyed()) {
    hudWindow.close();
    hudWindow = null;
  }
}

// ── Core Correction Pipeline ──
let correcting = false;

async function performCorrection(providerOverride?: ProviderName, modelOverride?: string): Promise<void> {
  if (correcting) return;
  correcting = true;
  setTrayState('processing');

  const config = configManager.load();
  const effectiveConfig = providerOverride
    ? { ...config, provider: providerOverride, model: modelOverride ?? (providerOverride === 'local' ? 't5-grammar' : config.model) }
    : config;
  const startTime = Date.now();
  let snap: ReturnType<typeof clipboardManager.snapshot> | null = null;
  let selectedText = '';

  try {
    showHUD('Working...');

    // 1. Save clipboard
    snap = clipboardManager.snapshot();

    // 2. Capture selected text
    selectedText = await clipboardManager.captureSelectedText();

    // 3. Build prompt
    let systemPrompt = configManager.loadSystemPrompt();
    const tonePrompt = TONE_PROMPTS[config.tonePreset];
    if (tonePrompt) {
      systemPrompt = tonePrompt;
    }
    if (config.language && config.language !== 'auto') {
      systemPrompt += `\n\nRespond in ${config.language}.`;
    }

    // 4. Token preservation
    const protection = protectTokens(selectedText);

    // 4b. Dictionary pre-pass (fix obvious spelling/grammar before model)
    const placeholderRanges = getPlaceholderRanges(protection.protectedText, protection.tokens);
    const prePassResult = await dictionaryPrePass(protection.protectedText, placeholderRanges);
    const prePassText = prePassResult.text;

    // 5. Check correction cache (using pre-passed text)
    const cached = getCached(prePassText, effectiveConfig.provider, effectiveConfig.model, config.tonePreset, config.language);

    // 6. Diff preview path vs direct path
    if (config.showDiffPreview) {
      // Run correction (same logic as non-preview path)
      let correctedText: string;

      if (cached) {
        correctedText = cached.text;
        if (protection.hasProtectedTokens) {
          if (placeholdersAreIntact(cached.text, protection.tokens)) {
            correctedText = restoreTokens(cached.text, protection.tokens);
          } else {
            correctedText = bestEffortRestore(cached.text, protection.tokens);
          }
        }
      } else {
        const result = await correctText(systemPrompt, prePassText, effectiveConfig);
        putCache(prePassText, effectiveConfig.provider, effectiveConfig.model, config.tonePreset, config.language, result);

        if (protection.hasProtectedTokens) {
          if (placeholdersAreIntact(result.text, protection.tokens)) {
            correctedText = restoreTokens(result.text, protection.tokens);
          } else {
            correctedText = bestEffortRestore(result.text, protection.tokens);
          }
        } else {
          correctedText = result.text;
        }

        const polishRanges = protection.hasProtectedTokens
          ? getOriginalTokenRanges(correctedText, protection.tokens) : [];
        const polished = await dictionaryPolish(correctedText, polishRanges);
        correctedText = polished.text;
      }

      correctedText = stripLeakedPlaceholders(correctedText);

      // Paste corrected text immediately
      if (config.clipboardOnlyMode) {
        clipboardManager.writeToClipboard(correctedText);
      } else {
        await clipboardManager.pasteText(correctedText);
      }
      hideHUD();

      // Show informational diff overlay (non-focusable, auto-dismisses)
      const previewWin = openWindow('streaming-preview');
      await new Promise<void>((resolve) => {
        if (previewWin.webContents.isLoading()) {
          previewWin.webContents.once('did-finish-load', () => resolve());
        } else {
          resolve();
        }
      });
      previewWin.webContents.send(IPC.SET_PREVIEW_ORIGINAL, selectedText);
      previewWin.webContents.send(IPC.STREAMING_DONE, correctedText);

      // Auto-close after 5 seconds
      setTimeout(() => {
        if (!previewWin.isDestroyed()) previewWin.close();
      }, 5000);

      // Log to history
      const entry: CorrectionHistoryEntry = {
        id: randomUUID(),
        timestamp: new Date().toISOString(),
        originalText: selectedText,
        generatedText: correctedText,
        provider: effectiveConfig.provider,
        model: effectiveConfig.model,
        durationMilliseconds: Date.now() - startTime,
        succeeded: true,
      };
      appendHistory(entry, config.historyLimit);
    } else {
      let correctedText: string;

      if (cached) {
        // Use cached result — skip AI entirely
        correctedText = cached.text;
        if (protection.hasProtectedTokens) {
          if (placeholdersAreIntact(cached.text, protection.tokens)) {
            correctedText = restoreTokens(cached.text, protection.tokens);
          } else {
            correctedText = bestEffortRestore(cached.text, protection.tokens);
          }
        }
      } else {
        // Direct correction (non-preview path)
        const result = await correctText(systemPrompt, prePassText, effectiveConfig);

        // Cache the result
        putCache(prePassText, effectiveConfig.provider, effectiveConfig.model, config.tonePreset, config.language, result);

        // Restore tokens
        if (protection.hasProtectedTokens) {
          if (placeholdersAreIntact(result.text, protection.tokens)) {
            correctedText = restoreTokens(result.text, protection.tokens);
          } else {
            correctedText = bestEffortRestore(result.text, protection.tokens);
          }
        } else {
          correctedText = result.text;
        }

        // Dictionary polish on model output
        const polishRanges = protection.hasProtectedTokens
          ? getOriginalTokenRanges(correctedText, protection.tokens) : [];
        const polished = await dictionaryPolish(correctedText, polishRanges);
        correctedText = polished.text;
      }

      correctedText = stripLeakedPlaceholders(correctedText);

      // Paste back or copy to clipboard
      if (config.clipboardOnlyMode) {
        clipboardManager.writeToClipboard(correctedText);
        showHUD('Copied to clipboard!');
      } else {
        await clipboardManager.pasteText(correctedText);
        showHUD('Done!');
      }

      // Success notification
      if (config.notifyOnSuccess) {
        new Notification({ title: 'GhostEdit', body: 'Correction applied.' }).show();
      }

      // Log to history
      const entry: CorrectionHistoryEntry = {
        id: randomUUID(),
        timestamp: new Date().toISOString(),
        originalText: selectedText,
        generatedText: correctedText,
        provider: effectiveConfig.provider,
        model: effectiveConfig.model,
        durationMilliseconds: Date.now() - startTime,
        succeeded: true,
      };
      appendHistory(entry, config.historyLimit);
    }
  } catch (err: any) {
    const message = errorToUserMessage(err, config.developerMode);
    console.error('Correction error:', err);
    showHUD(`Error: ${message}`, config.developerMode ? 8000 : 5000);

    // Native notification for errors
    new Notification({ title: 'GhostEdit', body: message }).show();

    const entry: CorrectionHistoryEntry = {
      id: randomUUID(),
      timestamp: new Date().toISOString(),
      originalText: selectedText,
      generatedText: '',
      provider: effectiveConfig.provider,
      model: effectiveConfig.model,
      durationMilliseconds: Date.now() - startTime,
      succeeded: false,
    };
    appendHistory(entry, config.historyLimit);
  } finally {
    // In clipboardOnlyMode the corrected text lives on the clipboard —
    // restoring the old snapshot would overwrite it.
    if (snap && !config.clipboardOnlyMode) {
      setTimeout(() => {
        if (snap) clipboardManager.restore(snap);
      }, 2000);
    }
    setTrayState('idle');
    correcting = false;
  }
}

// ── App Lifecycle ──

// Hide dock icon on macOS (tray-only app)
if (process.platform === 'darwin') {
  app.dock?.hide();
}

app.whenReady().then(() => {
  console.log('[GhostEdit] App ready');

  configManager.ensureDefaults();

  registerIPCHandlers(openWindow);

  // Cross-platform window controls (for non-macOS title bar buttons)
  ipcMain.on('window-close', (event) => {
    BrowserWindow.fromWebContents(event.sender)?.close();
  });
  ipcMain.on('window-minimize', (event) => {
    BrowserWindow.fromWebContents(event.sender)?.minimize();
  });

  ipcMain.handle(IPC.ACCEPT_CORRECTION, async (_event, text: string) => {
    const config = configManager.load();
    if (config.clipboardOnlyMode) {
      clipboardManager.writeToClipboard(text);
    } else {
      await clipboardManager.pasteText(text);
    }
    return { success: true };
  });

  ipcMain.handle(IPC.REJECT_CORRECTION, () => {
    return { success: true };
  });

  ipcMain.handle(IPC.REGENERATE_CORRECTION, async () => {
    performCorrection();
    return { success: true };
  });

  // Create tray
  createTray({
    onCorrectLocal: () => performCorrection('local'),
    onCorrectCLI: () => {
      const c = configManager.load();
      performCorrection(c.cliProvider, c.cliModel);
    },
    onOpenSettings: () => openWindow('settings'),
    onOpenHistory: () => openWindow('history'),
  });

  // Register global hotkeys
  registerGlobalShortcuts(
    () => performCorrection('local'),
    () => {
      const c = configManager.load();
      performCorrection(c.cliProvider, c.cliModel);
    },
  );

  // Refresh tray/hotkey when config changes
  ipcMain.on('config-changed', () => {
    configManager.invalidateCache();
    clearCache(); // Invalidate correction cache on config change
    clearDeviceCache(); // Re-probe device on next correction if model variant changed
    updateMenu({
      onCorrectLocal: () => performCorrection('local'),
      onCorrectCLI: () => {
        const c = configManager.load();
        performCorrection(c.cliProvider, c.cliModel);
      },
      onOpenSettings: () => openWindow('settings'),
      onOpenHistory: () => openWindow('history'),
    });
    refreshGlobalShortcuts(
      () => performCorrection('local'),
      () => {
        const c = configManager.load();
        performCorrection(c.cliProvider, c.cliModel);
      },
    );
  });

  // Only open settings on first run (lazy settings)
  const config = configManager.load();
  if (!config.firstRunComplete) {
    openWindow('settings');
  }

  console.log('[GhostEdit] Startup complete');
}).catch((err) => {
  console.error('[GhostEdit] Fatal error:', err);
});

app.on('will-quit', () => {
  unregisterAll();
  destroyTray();
});

app.on('window-all-closed', () => {
  // Don't quit — tray app stays running
});

// Vite HMR declarations
declare const MAIN_WINDOW_VITE_DEV_SERVER_URL: string | undefined;
declare const MAIN_WINDOW_VITE_NAME: string;
