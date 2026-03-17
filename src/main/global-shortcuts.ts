import { globalShortcut } from 'electron';
import { configManager } from './config-manager';
import { DEFAULT_CONFIG } from '../shared/constants';

type ShortcutHandler = () => void;

let registeredLocalAccelerator: string | null = null;
let registeredCliAccelerator: string | null = null;

/**
 * Register both global hotkeys for text correction.
 */
export function registerGlobalShortcuts(localHandler: ShortcutHandler, cliHandler: ShortcutHandler): void {
  const config = configManager.load();
  const localAcc = config.localHotkeyAccelerator || DEFAULT_CONFIG.localHotkeyAccelerator;
  const cliAcc = config.cliHotkeyAccelerator || DEFAULT_CONFIG.cliHotkeyAccelerator;

  if (localAcc === cliAcc) {
    console.warn('[GhostEdit] Local and CLI hotkeys are the same — only local will be registered');
  }

  registerOne(localAcc, localHandler, 'local');
  if (localAcc !== cliAcc) {
    registerOne(cliAcc, cliHandler, 'cli');
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
      else registeredCliAccelerator = accelerator;
    } else {
      console.error(`[GhostEdit] Failed to register ${label} global shortcut: ${accelerator}`);
    }
  } catch (err) {
    console.error(`[GhostEdit] Error registering ${label} shortcut "${accelerator}":`, err);
  }
}

/**
 * Re-register both hotkeys (e.g. after settings change).
 */
export function refreshGlobalShortcuts(localHandler: ShortcutHandler, cliHandler: ShortcutHandler): void {
  unregisterAll();
  registerGlobalShortcuts(localHandler, cliHandler);
}

/**
 * Unregister all global shortcuts.
 */
export function unregisterAll(): void {
  globalShortcut.unregisterAll();
  registeredLocalAccelerator = null;
  registeredCliAccelerator = null;
}
