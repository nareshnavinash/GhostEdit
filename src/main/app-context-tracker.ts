/**
 * Detects app switches using the active window title.
 * When the user switches away from the app they were typing in,
 * fires a callback so the traffic light and buffer can be cleared.
 */

let contextAppTitle: string | null = null;
let onAppSwitch: (() => void) | null = null;
let checkInProgress = false;
let disabled = false;
let getActiveWindowFn: (() => Promise<{ title: string }>) | null = null;

/**
 * Extract the app name prefix before common separators.
 * "Slack - #general" and "Slack - #random" both return "Slack".
 */
function appNamePrefix(title: string): string {
  for (const sep of [' - ', ' | ', ' — ']) {
    const idx = title.indexOf(sep);
    if (idx > 0) return title.slice(0, idx).trim();
  }
  return title.trim();
}

function isSameApp(a: string, b: string): boolean {
  return appNamePrefix(a) === appNamePrefix(b);
}

function isGhostEditWindow(title: string): boolean {
  const lower = title.toLowerCase();
  return lower.includes('ghostedit') || lower.includes('ghost edit');
}

async function getActiveWindowTitle(): Promise<string | null> {
  if (!getActiveWindowFn) return null;
  try {
    const win = await getActiveWindowFn();
    return win.title ?? null;
  } catch {
    return null;
  }
}

// ── Public API ──

export interface AppContextCallbacks {
  onAppSwitch: () => void;
}

export function initAppContextTracker(callbacks: AppContextCallbacks): void {
  onAppSwitch = callbacks.onAppSwitch;
  contextAppTitle = null;
  checkInProgress = false;
  disabled = false;

  try {
    const nutJs = require('@nut-tree-fork/nut-js');
    getActiveWindowFn = nutJs.getActiveWindow;
    console.log('[GhostEdit] App context tracker initialized');
  } catch (err: any) {
    console.warn('[GhostEdit] Could not load nut-js for app context tracking:', err.message);
    disabled = true;
  }
}

/** Capture the current active window as the "typing context" app. */
export async function markTypingContext(): Promise<void> {
  if (disabled || contextAppTitle !== null) return;

  const title = await getActiveWindowTitle();
  if (title && !isGhostEditWindow(title)) {
    contextAppTitle = title;
  }
}

/** Check if the active window has changed from the stored typing context. */
export async function checkForAppSwitch(): Promise<void> {
  if (disabled || !contextAppTitle || checkInProgress) return;
  checkInProgress = true;

  try {
    const title = await getActiveWindowTitle();
    if (!title) return;
    if (isGhostEditWindow(title)) return;

    if (!isSameApp(title, contextAppTitle)) {
      onAppSwitch?.();
    }
  } finally {
    checkInProgress = false;
  }
}

/** Reset the stored typing context. */
export function clearContext(): void {
  contextAppTitle = null;
}

/** Get the app name of the current typing context (or null if none). */
export function getCurrentAppName(): string | null {
  if (!contextAppTitle) return null;
  return appNamePrefix(contextAppTitle);
}

export function destroyAppContextTracker(): void {
  contextAppTitle = null;
  onAppSwitch = null;
  checkInProgress = false;
  disabled = false;
  getActiveWindowFn = null;
}
