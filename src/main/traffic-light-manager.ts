/**
 * Manages the floating traffic light icon window and the suggestions dropdown window.
 * Handles positioning, show/hide lifecycle, and IPC communication with renderers.
 */

import * as path from 'node:path';
import { BrowserWindow, screen, ipcMain } from 'electron';
import { IPC, type TrafficLightColor, type SpellCheckIssue, type IconPosition } from '../shared/types';
import { applyFixes } from './dictionary-checker';
import * as clipboardManager from './clipboard-manager';
import { clearBuffer } from './keystroke-monitor';
import { clearAnalyzerState, getLastIssues } from './realtime-analyzer';

let trafficLightWin: BrowserWindow | null = null;
let suggestionsWin: BrowserWindow | null = null;
let currentColor: TrafficLightColor = 'green';
let currentIssues: SpellCheckIssue[] = [];
let currentPosition: IconPosition = 'top-right';
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

function computeTrafficLightPosition(): { x: number; y: number } {
  const point = screen.getCursorScreenPoint();
  const display = screen.getDisplayNearestPoint(point);
  const { x, y, width, height } = display.workArea;
  const margin = 16;
  const size = 24;

  switch (currentPosition) {
    case 'top-left':
      return { x: x + margin, y: y + margin };
    case 'top-right':
      return { x: x + width - size - margin, y: y + margin };
    case 'bottom-left':
      return { x: x + margin, y: y + height - size - margin };
    case 'bottom-right':
      return { x: x + width - size - margin, y: y + height - size - margin };
    default:
      return { x: x + width - size - margin, y: y + margin };
  }
}

function computeDropdownPosition(): { x: number; y: number } {
  if (!trafficLightWin || trafficLightWin.isDestroyed()) {
    const point = screen.getCursorScreenPoint();
    const display = screen.getDisplayNearestPoint(point);
    const { x, y, width } = display.workArea;
    return { x: x + width - 320 - 16, y: y + 70 };
  }

  const [tlX, tlY] = trafficLightWin.getPosition();
  const dropdownWidth = 320;
  const dropdownHeight = 300;

  // Position adjacent to traffic light
  if (currentPosition.includes('right')) {
    return { x: tlX - dropdownWidth - 8, y: tlY };
  } else {
    return { x: tlX + 32, y: tlY };
  }
}

function ensureTrafficLightWindow(): BrowserWindow {
  if (trafficLightWin && !trafficLightWin.isDestroyed()) return trafficLightWin;

  const pos = computeTrafficLightPosition();

  const win = new BrowserWindow({
    width: 24,
    height: 24,
    x: pos.x,
    y: pos.y,
    show: false,
    frame: false,
    transparent: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    focusable: false,
    resizable: false,
    hasShadow: false,
    ...(process.platform === 'darwin' ? { type: 'panel' as any } : {}),
    webPreferences: {
      preload: getPreloadPath(),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      backgroundThrottling: false,
    },
  });

  win.loadURL(getRendererURL('traffic-light')).catch((err) => {
    console.error('[GhostEdit] Failed to load traffic light window:', err.message);
  });

  win.on('closed', () => {
    trafficLightWin = null;
  });

  trafficLightWin = win;
  return win;
}

function ensureIPCHandlers(): void {
  if (ipcRegistered) return;
  ipcRegistered = true;

  ipcMain.on(IPC.TRAFFIC_LIGHT_CLICKED, () => {
    if (currentIssues.length > 0) {
      openDropdown(currentIssues);
    }
  });

  ipcMain.handle(IPC.APPLY_FIX, async (_event, index: number) => {
    await applySingleFix(index);
    return { success: true };
  });

  ipcMain.handle(IPC.APPLY_ALL_FIXES, async () => {
    await applyAllFixesHandler();
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

export function initTrafficLight(position: IconPosition): void {
  currentPosition = position;
  ensureIPCHandlers();
}

export function showTrafficLight(): void {
  const win = ensureTrafficLightWindow();
  const pos = computeTrafficLightPosition();
  win.setPosition(pos.x, pos.y);

  const sendUpdate = () => {
    win.webContents.send(IPC.TRAFFIC_LIGHT_UPDATE, { color: currentColor, visible: true });
    if (!win.isVisible()) win.showInactive();
  };

  if (win.webContents.isLoading()) {
    win.webContents.once('did-finish-load', sendUpdate);
  } else {
    sendUpdate();
  }
}

export function hideTrafficLight(): void {
  if (trafficLightWin && !trafficLightWin.isDestroyed()) {
    trafficLightWin.webContents.send(IPC.TRAFFIC_LIGHT_HIDE);
    // Hide after a brief fade-out
    setTimeout(() => {
      if (trafficLightWin && !trafficLightWin.isDestroyed()) {
        trafficLightWin.hide();
      }
    }, 300);
  }
  closeDropdown();
}

export function updateColor(color: TrafficLightColor): void {
  currentColor = color;
  if (trafficLightWin && !trafficLightWin.isDestroyed() && trafficLightWin.isVisible()) {
    trafficLightWin.webContents.send(IPC.TRAFFIC_LIGHT_UPDATE, { color, visible: true });
  }
}

export function updateIssues(issues: SpellCheckIssue[]): void {
  currentIssues = issues;
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

export function closeDropdown(): void {
  if (suggestionsWin && !suggestionsWin.isDestroyed()) {
    suggestionsWin.close();
    suggestionsWin = null;
  }
}

export function setPosition(position: IconPosition): void {
  currentPosition = position;
  if (trafficLightWin && !trafficLightWin.isDestroyed()) {
    const pos = computeTrafficLightPosition();
    trafficLightWin.setPosition(pos.x, pos.y);
  }
}

export function destroyAll(): void {
  if (trafficLightWin && !trafficLightWin.isDestroyed()) {
    trafficLightWin.close();
    trafficLightWin = null;
  }
  if (suggestionsWin && !suggestionsWin.isDestroyed()) {
    suggestionsWin.close();
    suggestionsWin = null;
  }
  currentIssues = [];
  currentColor = 'green';
}

// ── Fix Application ──

async function applySingleFix(index: number): Promise<void> {
  if (index < 0 || index >= currentIssues.length) return;

  try {
    // Capture current line from the focused app
    const lineText = await clipboardManager.captureCurrentLine();
    const issue = currentIssues[index];

    // Find and replace the issue word in the captured line
    const fixedResult = applyFixes(lineText, [issue]);
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
