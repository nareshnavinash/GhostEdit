import { clipboard } from 'electron';

/**
 * Clipboard-based text capture and paste-back.
 * Port of ClipboardManager.swift, adapted for Electron's clipboard API
 * plus native key simulation via nut.js.
 *
 * Flow: save clipboard → simulate Cmd/Ctrl+C → read → process → write → simulate Cmd/Ctrl+V → restore
 */

// nut.js is loaded lazily to avoid crashes if not installed
let nutKeyboard: any = null;
let nutKey: any = null;

function getNut() {
  if (!nutKeyboard) {
    try {
      const nut = require('@nut-tree-fork/nut-js');
      nutKeyboard = nut.keyboard;
      nutKey = nut.Key;
    } catch (err: any) {
      console.error('[GhostEdit] Failed to load @nut-tree-fork/nut-js:', err);
      const wrapped = new Error(`Key simulation failed: ${err?.message || err}`);
      (wrapped as any).cause = err;
      throw wrapped;
    }
  }
  return { keyboard: nutKeyboard, Key: nutKey };
}

/** Pre-load nut.js at startup (fire-and-forget). */
export function preWarm(): void {
  try {
    getNut();
  } catch {
    // Swallowed on purpose — prewarm is best-effort
  }
}

interface ClipboardSnapshot {
  text: string;
  html: string;
}

/** Save current clipboard contents */
export function snapshot(): ClipboardSnapshot {
  return {
    text: clipboard.readText() || '',
    html: clipboard.readHTML() || '',
  };
}

/** Restore clipboard from a snapshot */
export function restore(snap: ClipboardSnapshot): void {
  if (snap.html) {
    clipboard.write({ text: snap.text, html: snap.html });
  } else {
    clipboard.writeText(snap.text);
  }
}

/** Small delay to let clipboard propagate */
function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Platform-adaptive timing constants.
// Windows clipboard propagation is slower than macOS/Linux.
const isWindows = process.platform === 'win32';
const POLL_INTERVAL   = isWindows ? 10 : 5;    // ms between clipboard polls
const MAX_POLL_WAIT   = isWindows ? 300 : 200;  // max ms to wait for clipboard
const PRE_PASTE_DELAY  = isWindows ? 40 : 20;   // ms after clipboard.writeText()
const POST_PASTE_DELAY = isWindows ? 80 : 50;   // ms after simulating Ctrl+V

/**
 * Simulate Cmd+C (macOS) or Ctrl+C (Windows/Linux) to copy selected text.
 * Returns the copied text.
 */
export async function captureSelectedText(): Promise<string> {
  const { keyboard, Key } = getNut();

  // Clear clipboard first to detect if copy actually worked
  clipboard.writeText('');

  const modifier = process.platform === 'darwin' ? Key.LeftSuper : Key.LeftControl;
  await keyboard.pressKey(modifier, Key.C);
  await keyboard.releaseKey(modifier, Key.C);

  // Poll clipboard until text appears (faster than a flat wait)
  let elapsed = 0;
  let text = '';
  while (elapsed < MAX_POLL_WAIT) {
    await delay(POLL_INTERVAL);
    elapsed += POLL_INTERVAL;
    text = clipboard.readText();
    if (text) break;
  }
  if (!text) {
    throw new Error('No text was captured. Make sure text is selected.');
  }
  return text;
}

/**
 * Write text to clipboard and simulate Cmd+V / Ctrl+V to paste.
 */
export async function pasteText(text: string): Promise<void> {
  const { keyboard, Key } = getNut();

  clipboard.writeText(text);
  await delay(PRE_PASTE_DELAY);

  const modifier = process.platform === 'darwin' ? Key.LeftSuper : Key.LeftControl;
  await keyboard.pressKey(modifier, Key.V);
  await keyboard.releaseKey(modifier, Key.V);

  await delay(POST_PASTE_DELAY);
}

/**
 * Select and copy the current line from the focused app.
 * macOS: Cmd+Left → Cmd+Shift+Right → Cmd+C
 * Windows/Linux: Home → Shift+End → Ctrl+C
 * The line remains selected after capture, so a subsequent pasteText() replaces it.
 */
export async function captureCurrentLine(): Promise<string> {
  const { keyboard, Key } = getNut();

  // Clear clipboard to detect if copy worked
  clipboard.writeText('');

  if (process.platform === 'darwin') {
    // Move to line start
    await keyboard.pressKey(Key.LeftSuper, Key.Left);
    await keyboard.releaseKey(Key.LeftSuper, Key.Left);
    await delay(20);
    // Select to line end
    await keyboard.pressKey(Key.LeftSuper, Key.LeftShift, Key.Right);
    await keyboard.releaseKey(Key.LeftSuper, Key.LeftShift, Key.Right);
    await delay(20);
    // Copy
    await keyboard.pressKey(Key.LeftSuper, Key.C);
    await keyboard.releaseKey(Key.LeftSuper, Key.C);
  } else {
    // Move to line start
    await keyboard.pressKey(Key.Home);
    await keyboard.releaseKey(Key.Home);
    await delay(20);
    // Select to line end
    await keyboard.pressKey(Key.LeftShift, Key.End);
    await keyboard.releaseKey(Key.LeftShift, Key.End);
    await delay(20);
    // Copy
    await keyboard.pressKey(Key.LeftControl, Key.C);
    await keyboard.releaseKey(Key.LeftControl, Key.C);
  }

  // Poll clipboard until text appears
  let elapsed = 0;
  let text = '';
  while (elapsed < MAX_POLL_WAIT) {
    await delay(POLL_INTERVAL);
    elapsed += POLL_INTERVAL;
    text = clipboard.readText();
    if (text) break;
  }
  if (!text) {
    throw new Error('No line text was captured. Make sure the cursor is in a text field.');
  }
  return text;
}

/**
 * Clipboard-only mode: just write to clipboard, don't simulate paste.
 */
export function writeToClipboard(text: string): void {
  clipboard.writeText(text);
}
