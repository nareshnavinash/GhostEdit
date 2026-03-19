/**
 * Manages the suggestions dropdown window and traffic light state via tray icon.
 * The floating traffic light window has been removed; the colored dot now
 * appears on the menu-bar tray icon instead.
 */

import * as path from 'node:path';
import { BrowserWindow, screen, ipcMain } from 'electron';
import { IPC, type TrafficLightColor, type SpellCheckIssue } from '../shared/types';
import { applyFixes } from './dictionary-checker';
import * as clipboardManager from './clipboard-manager';
import { clearBuffer } from './keystroke-monitor';
import { clearAnalyzerState } from './realtime-analyzer';
import { setTrayTrafficColor, getTrayBounds, updateTrayIssueCount } from './tray-manager';
import { configManager } from './config-manager';

let suggestionsWin: BrowserWindow | null = null;
let currentColor: TrafficLightColor = 'green';
let currentIssues: SpellCheckIssue[] = [];
let ipcRegistered = false;

function getPreloadPath(): string {
  return path.join(__dirname, '../preload/index.js');
}

declare const MAIN_WINDOW_VITE_DEV_SERVER_URL: string | undefined;
declare const MAIN_WINDOW_VITE_NAME: string;

function getRendererURL(windowType: string): string {
  if (MAIN_WINDOW_VITE_DEV_SERVER_URL) {
    return `${MAIN_WINDOW_VITE_DEV_SERVER_URL}?windowType=${windowType}`;
  }
  return `file://${path.join(__dirname, `../renderer/${MAIN_WINDOW_VITE_NAME}/index.html`)}?windowType=${windowType}`;
}

function computeDropdownPosition(): { x: number; y: number } {
  const bounds = getTrayBounds();

  if (bounds && bounds.width > 0 && bounds.height > 0) {
    const dropdownWidth = 320;
    // macOS/Linux: tray at top, position below
    if (process.platform !== 'win32') {
      return {
        x: Math.round(bounds.x + bounds.width / 2 - dropdownWidth / 2),
        y: bounds.y + bounds.height + 4,
      };
    }
    // Windows: tray at bottom, position above
    const dropdownHeight = 300;
    return {
      x: Math.round(bounds.x + bounds.width / 2 - dropdownWidth / 2),
      y: bounds.y - dropdownHeight - 4,
    };
  }

  // Fallback: top-right of screen
  const point = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(point);
  const { x, y, width } = display.workArea;
  return { x: x + width - 320 - 16, y: y + 8 };
}

function ensureIPCHandlers(): void {
  if (ipcRegistered) return;
  ipcRegistered = true;

  ipcMain.handle(IPC.APPLY_FIX, async (_event, index: number, suggestionIndex?: number) => {
    await applySingleFix(index, suggestionIndex);
    return { success: true };
  });

  ipcMain.handle(IPC.APPLY_ALL_FIXES, async () => {
    await applyAllFixesHandler();
    return { success: true };
  });

  ipcMain.handle(IPC.DISMISS_SUGGESTION, async (_event, index: number) => {
    await dismissSuggestion(index);
    return { success: true };
  });

  ipcMain.handle(IPC.CHECK_ACCESSIBILITY, () => {
    if (process.platform === 'darwin') {
      try {
        const { systemPreferences } = require('electron');
        return { trusted: systemPreferences.isTrustedAccessibilityClient(false) };
      } catch {
        return { trusted: false };
      }
    }
    return { trusted: true };
  });
}

// ── Public API ──

export function initSuggestionsIPC(): void {
  ensureIPCHandlers();
}

export function updateColor(color: TrafficLightColor): void {
  currentColor = color;
  setTrayTrafficColor(color);
}

export function updateIssues(issues: SpellCheckIssue[]): void {
  currentIssues = issues;
  updateTrayIssueCount(issues.length);
  // If dropdown is open, update it
  if (suggestionsWin && !suggestionsWin.isDestroyed() && suggestionsWin.isVisible()) {
    suggestionsWin.webContents.send(IPC.SUGGESTIONS_UPDATE, issues);
  }
}

export function openDropdown(issues: SpellCheckIssue[]): void {
  currentIssues = issues;

  if (suggestionsWin && !suggestionsWin.isDestroyed()) {
    suggestionsWin.webContents.send(IPC.SUGGESTIONS_UPDATE, issues);
    if (!suggestionsWin.isVisible()) suggestionsWin.show();
    suggestionsWin.focus();
    return;
  }

  const pos = computeDropdownPosition();

  const win = new BrowserWindow({
    width: 320,
    height: 300,
    x: pos.x,
    y: pos.y,
    show: false,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    focusable: true,
    resizable: false,
    hasShadow: true,
    webPreferences: {
      preload: getPreloadPath(),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      backgroundThrottling: false,
    },
  });

  win.loadURL(getRendererURL('suggestions')).catch((err) => {
    console.error('[GhostEdit] Failed to load suggestions dropdown:', err.message);
  });

  const sendData = () => {
    win.webContents.send(IPC.SUGGESTIONS_UPDATE, issues);
    win.show();
    win.focus();
  };

  if (win.webContents.isLoading()) {
    win.webContents.once('did-finish-load', sendData);
  } else {
    win.once('ready-to-show', sendData);
  }

  win.on('blur', () => {
    // Auto-hide when user clicks elsewhere
    setTimeout(() => {
      if (win && !win.isDestroyed()) {
        win.hide();
      }
    }, 150);
  });

  win.on('closed', () => {
    suggestionsWin = null;
  });

  suggestionsWin = win;
}

export function showSuggestionsFromTray(): void {
  if (currentIssues.length > 0) {
    openDropdown(currentIssues);
  }
}

export function closeDropdown(): void {
  if (suggestionsWin && !suggestionsWin.isDestroyed()) {
    suggestionsWin.close();
    suggestionsWin = null;
  }
}

export function destroyAll(): void {
  if (suggestionsWin && !suggestionsWin.isDestroyed()) {
    suggestionsWin.close();
    suggestionsWin = null;
  }
  currentIssues = [];
  currentColor = 'green';
  setTrayTrafficColor(null);
}

// ── Fix Application ──

async function dismissSuggestion(index: number): Promise<void> {
  if (index < 0 || index >= currentIssues.length) return;

  const issue = currentIssues[index];
  const config = configManager.load();
  const suppressed = { ...(config.suppressedSuggestions ?? {}) };
  suppressed[issue.word] = (suppressed[issue.word] ?? 0) + 1;
  configManager.save({ ...config, suppressedSuggestions: suppressed });

  // Remove from current issues
  currentIssues = currentIssues.filter((_, i) => i !== index);

  if (suggestionsWin && !suggestionsWin.isDestroyed()) {
    suggestionsWin.webContents.send(IPC.SUGGESTIONS_UPDATE, currentIssues);
  }
  const newColor: TrafficLightColor = currentIssues.length === 0 ? 'green'
    : currentIssues.some((i) => i.kind === 'spelling' || i.kind === 'grammar') ? 'red' : 'yellow';
  updateColor(newColor);
  updateTrayIssueCount(currentIssues.length);
}

async function applySingleFix(index: number, suggestionIndex?: number): Promise<void> {
  if (index < 0 || index >= currentIssues.length) return;

  try {
    // Capture current line from the focused app
    const lineText = await clipboardManager.captureCurrentLine();
    const issue = currentIssues[index];

    // If a specific suggestion alternative was chosen, swap it in
    const fixIssue = (suggestionIndex != null && suggestionIndex > 0 && suggestionIndex < issue.suggestions.length)
      ? { ...issue, suggestions: [issue.suggestions[suggestionIndex], ...issue.suggestions.filter((_, i) => i !== suggestionIndex)] }
      : issue;

    // Find and replace the issue word in the captured line
    const fixedResult = applyFixes(lineText, [fixIssue]);
    if (fixedResult.fixCount > 0) {
      await clipboardManager.pasteText(fixedResult.text);
    }

    // Remove applied fix from issues
    currentIssues = currentIssues.filter((_, i) => i !== index);
    clearBuffer();
    clearAnalyzerState();

    // Update dropdown and color
    if (suggestionsWin && !suggestionsWin.isDestroyed()) {
      suggestionsWin.webContents.send(IPC.SUGGESTIONS_UPDATE, currentIssues);
    }
    const newColor: TrafficLightColor = currentIssues.length === 0 ? 'green'
      : currentIssues.some((i) => i.kind === 'spelling' || i.kind === 'grammar') ? 'red' : 'yellow';
    updateColor(newColor);
  } catch (err) {
    console.error('[GhostEdit] Failed to apply single fix:', err);
  }
}

async function applyAllFixesHandler(): Promise<void> {
  if (currentIssues.length === 0) return;

  try {
    const lineText = await clipboardManager.captureCurrentLine();
    const fixedResult = applyFixes(lineText, currentIssues);
    if (fixedResult.fixCount > 0) {
      await clipboardManager.pasteText(fixedResult.text);
    }

    currentIssues = [];
    clearBuffer();
    clearAnalyzerState();

    if (suggestionsWin && !suggestionsWin.isDestroyed()) {
      suggestionsWin.webContents.send(IPC.SUGGESTIONS_UPDATE, []);
    }
    updateColor('green');
  } catch (err) {
    console.error('[GhostEdit] Failed to apply all fixes:', err);
  }
}
