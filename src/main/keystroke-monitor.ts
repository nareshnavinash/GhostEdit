/**
 * Global keystroke capture via uiohook-napi.
 * Maintains a best-effort text buffer from keystrokes and tracks typing activity.
 */

const MAX_BUFFER = 500;
const INACTIVITY_DEFAULT_MS = 3000;

let uIOhookInstance: any = null;
let started = false;

// Buffer state
let buffer = '';
let lastKeystrokeTime = 0;
let inactivityTimer: ReturnType<typeof setTimeout> | null = null;
let typingActive = false;
let inactivityMs = INACTIVITY_DEFAULT_MS;

// Callbacks
let onBufferChange: ((buffer: string) => void) | null = null;
let onTypingStarted: (() => void) | null = null;
let onTypingStopped: (() => void) | null = null;

// Printable keycode → character map (US layout, best-effort)
// uiohook uses scan codes (not virtual key codes).
// All entries use hex to avoid collisions between decimal and hex literals.
const KEYCODE_MAP = new Map<number, [string, string]>([
  // Numbers
  [0x02, ['1', '!']], [0x03, ['2', '@']], [0x04, ['3', '#']], [0x05, ['4', '$']],
  [0x06, ['5', '%']], [0x07, ['6', '^']], [0x08, ['7', '&']], [0x09, ['8', '*']],
  [0x0A, ['9', '(']], [0x0B, ['0', ')']],
  // Letters (a-z)
  [0x1E, ['a', 'A']], [0x30, ['b', 'B']], [0x2E, ['c', 'C']], [0x20, ['d', 'D']],
  [0x12, ['e', 'E']], [0x21, ['f', 'F']], [0x22, ['g', 'G']], [0x23, ['h', 'H']],
  [0x17, ['i', 'I']], [0x24, ['j', 'J']], [0x25, ['k', 'K']], [0x26, ['l', 'L']],
  [0x32, ['m', 'M']], [0x31, ['n', 'N']], [0x18, ['o', 'O']], [0x19, ['p', 'P']],
  [0x10, ['q', 'Q']], [0x13, ['r', 'R']], [0x1F, ['s', 'S']], [0x14, ['t', 'T']],
  [0x16, ['u', 'U']], [0x2F, ['v', 'V']], [0x11, ['w', 'W']], [0x2D, ['x', 'X']],
  [0x15, ['y', 'Y']], [0x2C, ['z', 'Z']],
  // Punctuation
  [0x33, [';', ':']], [0x34, ["'", '"']], [0x35, ['`', '~']],
  [0x2B, ['\\', '|']], [0x27, [',', '<']], [0x28, ['.', '>']], [0x29, ['/', '?']],
  [0x0C, ['-', '_']], [0x0D, ['=', '+']],
  [0x1A, ['[', '{']], [0x1B, [']', '}']],
]);

// Special keycodes
const KC_SPACE = 0x39;
const KC_BACKSPACE = 0x0E;
const KC_DELETE = 0x53;
const KC_ENTER = 0x1C;
const KC_TAB = 0x0F;
// Navigation keys that invalidate buffer context
const KC_LEFT = 0xCB;
const KC_RIGHT = 0xCD;
const KC_UP = 0xC8;
const KC_DOWN = 0xD0;
const KC_HOME = 0xC7;
const KC_END = 0xCF;
const KC_ESCAPE = 0x01;
// Modifier masks
const MASK_CTRL = 1 << 1;
const MASK_META = 1 << 3;

function getUIOhook() {
  if (!uIOhookInstance) {
    try {
      const mod = require('uiohook-napi');
      uIOhookInstance = mod.uIOhook;
    } catch (err: any) {
      console.error('[GhostEdit] Failed to load uiohook-napi:', err.message);
      throw err;
    }
  }
  return uIOhookInstance;
}

function handleKeyDown(event: any): void {
  const keycode = event.keycode;
  const shift = !!(event.shiftKey || (event.mask && (event.mask & (1 << 0))));
  const ctrl = !!(event.ctrlKey || (event.mask && (event.mask & MASK_CTRL)));
  const meta = !!(event.metaKey || (event.mask && (event.mask & MASK_META)));
  const hasModifier = ctrl || meta;

  // Cmd/Ctrl combos that invalidate buffer
  if (hasModifier) {
    // Cmd+A, Cmd+Z, Cmd+V invalidate the buffer
    const isA = keycode === 0x1E;
    const isZ = keycode === 0x2C;
    const isV = keycode === 0x2F;
    if (isA || isZ || isV) {
      buffer = '';
      emitBufferChange();
    }
    // Skip all modifier combos (not typing)
    return;
  }

  // Navigation keys → clear buffer (cursor context lost)
  if (keycode === KC_LEFT || keycode === KC_RIGHT || keycode === KC_UP || keycode === KC_DOWN
    || keycode === KC_HOME || keycode === KC_END || keycode === KC_ESCAPE) {
    buffer = '';
    emitBufferChange();
    return;
  }

  // Track typing activity
  markTyping();

  // Backspace
  if (keycode === KC_BACKSPACE) {
    if (buffer.length > 0) {
      buffer = buffer.slice(0, -1);
      emitBufferChange();
    }
    return;
  }

  // Delete — clear buffer (context unreliable)
  if (keycode === KC_DELETE) {
    buffer = '';
    emitBufferChange();
    return;
  }

  // Enter
  if (keycode === KC_ENTER) {
    buffer += '\n';
    trimBuffer();
    emitBufferChange();
    return;
  }

  // Tab
  if (keycode === KC_TAB) {
    buffer += '\t';
    trimBuffer();
    emitBufferChange();
    return;
  }

  // Space
  if (keycode === KC_SPACE) {
    buffer += ' ';
    trimBuffer();
    emitBufferChange();
    return;
  }

  // Printable character
  const mapping = KEYCODE_MAP.get(keycode);
  if (mapping) {
    buffer += shift ? mapping[1] : mapping[0];
    trimBuffer();
    emitBufferChange();
  }
}

function trimBuffer(): void {
  if (buffer.length > MAX_BUFFER) {
    buffer = buffer.slice(buffer.length - MAX_BUFFER);
  }
}

function markTyping(): void {
  lastKeystrokeTime = Date.now();

  if (!typingActive) {
    typingActive = true;
    onTypingStarted?.();
  }

  // Reset inactivity timer
  if (inactivityTimer) clearTimeout(inactivityTimer);
  inactivityTimer = setTimeout(() => {
    typingActive = false;
    onTypingStopped?.();
    inactivityTimer = null;
  }, inactivityMs);
}

function emitBufferChange(): void {
  onBufferChange?.(buffer);
}

// ── Public API ──

export interface MonitoringCallbacks {
  onBufferChange: (buffer: string) => void;
  onTypingStarted: () => void;
  onTypingStopped: () => void;
}

export function startMonitoring(callbacks: MonitoringCallbacks, inactivityTimeout?: number): void {
  if (started) return;

  onBufferChange = callbacks.onBufferChange;
  onTypingStarted = callbacks.onTypingStarted;
  onTypingStopped = callbacks.onTypingStopped;
  inactivityMs = inactivityTimeout ?? INACTIVITY_DEFAULT_MS;

  try {
    const hook = getUIOhook();
    hook.on('keydown', handleKeyDown);
    hook.start();
    started = true;
    console.log('[GhostEdit] Keystroke monitoring started');
  } catch (err) {
    console.error('[GhostEdit] Could not start keystroke monitoring:', err);
  }
}

export function stopMonitoring(): void {
  if (!started) return;

  try {
    const hook = getUIOhook();
    hook.removeListener('keydown', handleKeyDown);
    hook.stop();
  } catch {
    // Swallow — might already be stopped
  }

  if (inactivityTimer) {
    clearTimeout(inactivityTimer);
    inactivityTimer = null;
  }

  started = false;
  typingActive = false;
  buffer = '';
  onBufferChange = null;
  onTypingStarted = null;
  onTypingStopped = null;
  console.log('[GhostEdit] Keystroke monitoring stopped');
}

export function getBuffer(): string {
  return buffer;
}

export function clearBuffer(): void {
  buffer = '';
  emitBufferChange();
}

export function isTyping(): boolean {
  return typingActive;
}

export function isMonitoringStarted(): boolean {
  return started;
}
