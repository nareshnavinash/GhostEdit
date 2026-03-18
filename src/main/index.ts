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
import { appendHistory, lastSuccessfulEntry } from './history-store';
import * as clipboardManager from './clipboard-manager';
import { getCached, putCache, clearCache } from './correction-cache';
import { TONE_PROMPTS } from '../shared/constants';
import type { ProviderName } from '../shared/types';
import { IPC, type WindowType, type CorrectionHistoryEntry } from '../shared/types';
import { errorToUserMessage } from './error-messages';
import { clearDeviceCache } from './device-selector';
import { playSuccessSound, playErrorSound } from './sound-manager';
import { appendError } from './error-log';

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

  const isOverlay = isHud; // Preview is now interactive, not a passive overlay

  const win = new BrowserWindow({
    width: size.width,
    height: size.height,
    show: false,
    frame: !isHud && !isPreview,
    transparent: isHud || isPreview,
    alwaysOnTop: isHud || isPreview,
    skipTaskbar: isHud,
    focusable: !isHud,
    resizable: !isHud,
    hasShadow: !isHud,
    ...(isHud || isPreview ? {} : { titleBarStyle: 'hiddenInset' as const }),
    ...(process.platform === 'darwin' && !isHud && !isPreview ? { vibrancy: 'under-window' as const } : {}),
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

// ── Passive Preview Window ──
let passivePreviewWin: BrowserWindow | null = null;
let passivePreviewTimer: ReturnType<typeof setTimeout> | null = null;

function openPassivePreviewWindow(): BrowserWindow {
  // Close previous passive preview if still open
  if (passivePreviewWin && !passivePreviewWin.isDestroyed()) {
    passivePreviewWin.close();
    passivePreviewWin = null;
  }
  if (passivePreviewTimer) {
    clearTimeout(passivePreviewTimer);
    passivePreviewTimer = null;
  }

  const point = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(point);
  const { x, y, width, height } = display.workArea;

  const win = new BrowserWindow({
    width: 700,
    height: 400,
    x: Math.round(x + width / 2 - 350),
    y: Math.round(y + height / 2 - 200),
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

  win.loadURL(getRendererURL('streaming-preview')).catch((err) => {
    console.error('[GhostEdit] Failed to load passive preview:', err.message);
  });

  passivePreviewWin = win;
  return win;
}

// ── Core Correction Pipeline ──
let correcting = false;
let pendingPreviewDecision: { resolve: (accepted: boolean) => void } | null = null;

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

    // 6. Run correction (shared logic for both paths)
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

    // 7. Three-way branch: interactive / passive / none
    if (config.diffPreviewMode === 'interactive') {
      hideHUD();

      // Show interactive diff preview — wait for user decision
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
      previewWin.webContents.send(IPC.SET_PREVIEW_CONFIG, {
        autoPasteDelaySeconds: config.autoPasteDelaySeconds,
        diffPreviewMode: 'interactive',
        passivePreviewSeconds: 0,
      });

      // Wait for Accept/Reject (or window close = reject)
      const accepted = await new Promise<boolean>((resolve) => {
        pendingPreviewDecision = { resolve };
        previewWin.on('closed', () => {
          if (pendingPreviewDecision) {
            pendingPreviewDecision.resolve(false);
            pendingPreviewDecision = null;
          }
        });
      });

      // Close preview window first (before pasting) so focus returns to the original app
      if (!previewWin.isDestroyed()) previewWin.close();

      if (accepted) {
        // On macOS, hide Electron so the previously-focused app regains focus
        if (process.platform === 'darwin') {
          app.hide();
          await new Promise((r) => setTimeout(r, 150));
        }
        if (config.clipboardOnlyMode) {
          clipboardManager.writeToClipboard(correctedText);
        } else {
          await clipboardManager.pasteText(correctedText);
        }
        if (config.soundFeedbackEnabled) playSuccessSound();
        if (config.notifyOnSuccess) {
          new Notification({ title: 'GhostEdit', body: 'Correction applied.' }).show();
        }
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
        succeeded: accepted,
        rejected: !accepted,
      };
      appendHistory(entry, config.historyLimit);

    } else if (config.diffPreviewMode === 'passive') {
      // Paste first, then show non-focusable overlay
      hideHUD();

      if (config.clipboardOnlyMode) {
        clipboardManager.writeToClipboard(correctedText);
      } else {
        await clipboardManager.pasteText(correctedText);
      }

      if (config.soundFeedbackEnabled) playSuccessSound();
      if (config.notifyOnSuccess) {
        new Notification({ title: 'GhostEdit', body: 'Correction applied.' }).show();
      }

      // Show passive preview overlay (non-focusable, auto-closes)
      const passiveWin = openPassivePreviewWindow();
      const sendPassiveData = () => {
        passiveWin.webContents.send(IPC.SET_PREVIEW_ORIGINAL, selectedText);
        passiveWin.webContents.send(IPC.STREAMING_DONE, correctedText);
        passiveWin.webContents.send(IPC.SET_PREVIEW_CONFIG, {
          autoPasteDelaySeconds: 0,
          diffPreviewMode: 'passive',
          passivePreviewSeconds: config.passivePreviewSeconds,
        });
        passiveWin.showInactive();
      };

      if (passiveWin.webContents.isLoading()) {
        passiveWin.webContents.once('did-finish-load', sendPassiveData);
      } else {
        sendPassiveData();
      }

      // Auto-close after passivePreviewSeconds
      passivePreviewTimer = setTimeout(() => {
        if (passivePreviewWin && !passivePreviewWin.isDestroyed()) {
          passivePreviewWin.close();
          passivePreviewWin = null;
        }
        passivePreviewTimer = null;
      }, config.passivePreviewSeconds * 1000);

      // Log to history (always applied)
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
      // Direct paste (non-preview path)
      if (config.clipboardOnlyMode) {
        clipboardManager.writeToClipboard(correctedText);
        showHUD('Copied to clipboard!');
      } else {
        await clipboardManager.pasteText(correctedText);
        showHUD('Done!');
      }

      if (config.soundFeedbackEnabled) playSuccessSound();
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

    if (config.soundFeedbackEnabled) playErrorSound();
    appendError(message, effectiveConfig.provider);

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

// ── Undo Last Correction ──

async function undoLastCorrection(): Promise<void> {
  const entry = lastSuccessfulEntry();
  if (!entry) {
    showHUD('Nothing to undo');
    return;
  }

  const config = configManager.load();
  if (config.clipboardOnlyMode) {
    clipboardManager.writeToClipboard(entry.originalText);
    showHUD('Original text copied to clipboard');
  } else {
    await clipboardManager.pasteText(entry.originalText);
    showHUD('Undo: original text restored');
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

  ipcMain.handle(IPC.ACCEPT_CORRECTION, async (_event, _text: string) => {
    if (pendingPreviewDecision) {
      pendingPreviewDecision.resolve(true);
      pendingPreviewDecision = null;
    }
    return { success: true };
  });

  ipcMain.handle(IPC.REJECT_CORRECTION, () => {
    if (pendingPreviewDecision) {
      pendingPreviewDecision.resolve(false);
      pendingPreviewDecision = null;
    }
    return { success: true };
  });

  ipcMain.handle(IPC.REGENERATE_CORRECTION, async () => {
    performCorrection();
    return { success: true };
  });

  const trayCallbacks = {
    onCorrectLocal: () => performCorrection('local'),
    onCorrectCLI: () => {
      const c = configManager.load();
      performCorrection(c.cliProvider, c.cliModel);
    },
    onUndoLastCorrection: () => undoLastCorrection(),
    onOpenSettings: () => openWindow('settings'),
    onOpenHistory: () => openWindow('history'),
  };

  // Create tray
  createTray(trayCallbacks);

  // Register global hotkeys
  registerGlobalShortcuts(
    () => performCorrection('local'),
    () => {
      const c = configManager.load();
      performCorrection(c.cliProvider, c.cliModel);
    },
    () => undoLastCorrection(),
  );

  // Refresh tray/hotkey when config changes
  ipcMain.on('config-changed', () => {
    configManager.invalidateCache();
    clearCache(); // Invalidate correction cache on config change
    clearDeviceCache(); // Re-probe device on next correction if model variant changed

    // Wire up launch at login
    const updatedConfig = configManager.load();
    app.setLoginItemSettings({ openAtLogin: updatedConfig.launchAtLogin });

    updateMenu(trayCallbacks);
    refreshGlobalShortcuts(
      () => performCorrection('local'),
      () => {
        const c = configManager.load();
        performCorrection(c.cliProvider, c.cliModel);
      },
      () => undoLastCorrection(),
    );
  });

  // Apply launch at login setting
  const config = configManager.load();
  app.setLoginItemSettings({ openAtLogin: config.launchAtLogin });

  // Only open settings on first run (lazy settings)
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
