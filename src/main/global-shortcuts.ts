import { globalShortcut } from 'electron';
import { configManager } from './config-manager';
import { DEFAULT_CONFIG } from '../shared/constants';

type ShortcutHandler = () => void;

let registeredLocalAccelerator: string | null = null;
let registeredCliAccelerator: string | null = null;
let registeredUndoAccelerator: string | null = null;
let registeredLineAccelerator: string | null = null;

/**
 * Register all global hotkeys for text correction, undo, and line correction.
 */
export function registerGlobalShortcuts(
  localHandler: ShortcutHandler,
  cliHandler: ShortcutHandler,
  undoHandler: ShortcutHandler,
  lineHandler?: ShortcutHandler,
): void {
  const config = configManager.load();
  const localAcc = config.localHotkeyAccelerator || DEFAULT_CONFIG.localHotkeyAccelerator;
  const cliAcc = config.cliHotkeyAccelerator || DEFAULT_CONFIG.cliHotkeyAccelerator;
  const undoAcc = config.undoHotkeyAccelerator || DEFAULT_CONFIG.undoHotkeyAccelerator;
  const lineAcc = config.lineHotkeyAccelerator || DEFAULT_CONFIG.lineHotkeyAccelerator;

  if (localAcc === cliAcc) {
    console.warn('[GhostEdit] Local and CLI hotkeys are the same — only local will be registered');
  }

  registerOne(localAcc, localHandler, 'local');
  if (localAcc !== cliAcc) {
    registerOne(cliAcc, cliHandler, 'cli');
  }
  if (undoAcc && undoAcc !== localAcc && undoAcc !== cliAcc) {
    registerOne(undoAcc, undoHandler, 'undo');
  }
  if (lineHandler && lineAcc && lineAcc !== localAcc && lineAcc !== cliAcc && lineAcc !== undoAcc) {
    registerOne(lineAcc, lineHandler, 'line');
  }
}

function registerOne(accelerator: string, handler: ShortcutHandler, label: string): void {
  if (!accelerator) {
    console.warn(`[GhostEdit] No ${label} hotkey accelerator configured`);
    return;
  }

  try {
    const success = globalShortcut.register(accelerator, handler);
    if (success) {
      if (label === 'local') registeredLocalAccelerator = accelerator;
      else if (label === 'cli') registeredCliAccelerator = accelerator;
      else if (label === 'undo') registeredUndoAccelerator = accelerator;
      else if (label === 'line') registeredLineAccelerator = accelerator;
    } else {
      console.error(`[GhostEdit] Failed to register ${label} global shortcut: ${accelerator}`);
    }
  } catch (err) {
    console.error(`[GhostEdit] Error registering ${label} shortcut "${accelerator}":`, err);
  }
}

/**
 * Re-register all hotkeys (e.g. after settings change).
 */
export function refreshGlobalShortcuts(
  localHandler: ShortcutHandler,
  cliHandler: ShortcutHandler,
  undoHandler: ShortcutHandler,
  lineHandler?: ShortcutHandler,
): void {
  unregisterAll();
  registerGlobalShortcuts(localHandler, cliHandler, undoHandler, lineHandler);
}

/**
 * Unregister all global shortcuts.
 */
export function unregisterAll(): void {
  globalShortcut.unregisterAll();
  registeredLocalAccelerator = null;
  registeredCliAccelerator = null;
  registeredUndoAccelerator = null;
  registeredLineAccelerator = null;
}
