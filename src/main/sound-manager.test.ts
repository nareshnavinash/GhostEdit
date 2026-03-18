import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ── Mocks ──

const mockExecFile = vi.fn();
vi.mock('node:child_process', () => ({
  execFile: (...args: any[]) => mockExecFile(...args),
}));

let originalPlatform: string;

beforeEach(() => {
  vi.clearAllMocks();
  originalPlatform = process.platform;
  // Default: execFile succeeds silently
  mockExecFile.mockImplementation((...args: any[]) => {
    const cb = args[args.length - 1];
    if (typeof cb === 'function') cb(null);
  });
});

afterEach(() => {
  Object.defineProperty(process, 'platform', { value: originalPlatform });
});

function setPlatform(p: string) {
  Object.defineProperty(process, 'platform', { value: p });
}

// ═══════════════════════════════════════
// playSuccessSound
// ═══════════════════════════════════════

describe('playSuccessSound', () => {
  it('macOS: calls afplay with Glass.aiff', async () => {
    setPlatform('darwin');
    const { playSuccessSound } = await import('./sound-manager');
    playSuccessSound();
    expect(mockExecFile).toHaveBeenCalledWith(
      'afplay',
      ['/System/Library/Sounds/Glass.aiff'],
      expect.any(Function),
    );
  });

  it('Windows: calls PowerShell with Asterisk.Play()', async () => {
    vi.resetModules();
    vi.doMock('node:child_process', () => ({
      execFile: (...args: any[]) => mockExecFile(...args),
    }));
    setPlatform('win32');
    const { playSuccessSound } = await import('./sound-manager');
    playSuccessSound();
    expect(mockExecFile).toHaveBeenCalledWith(
      'powershell',
      expect.arrayContaining([expect.stringContaining('Asterisk.Play()')]),
      expect.any(Function),
    );
  });

  it('Linux: calls paplay with complete.oga', async () => {
    vi.resetModules();
    vi.doMock('node:child_process', () => ({
      execFile: (...args: any[]) => mockExecFile(...args),
    }));
    setPlatform('linux');
    const { playSuccessSound } = await import('./sound-manager');
    playSuccessSound();
    expect(mockExecFile).toHaveBeenCalledWith(
      'paplay',
      ['/usr/share/sounds/freedesktop/stereo/complete.oga'],
      expect.any(Function),
    );
  });
});

// ═══════════════════════════════════════
// playErrorSound
// ═══════════════════════════════════════

describe('playErrorSound', () => {
  it('macOS: calls afplay with Basso.aiff', async () => {
    setPlatform('darwin');
    const { playErrorSound } = await import('./sound-manager');
    playErrorSound();
    expect(mockExecFile).toHaveBeenCalledWith(
      'afplay',
      ['/System/Library/Sounds/Basso.aiff'],
      expect.any(Function),
    );
  });

  it('Windows: calls PowerShell with Hand.Play()', async () => {
    vi.resetModules();
    vi.doMock('node:child_process', () => ({
      execFile: (...args: any[]) => mockExecFile(...args),
    }));
    setPlatform('win32');
    const { playErrorSound } = await import('./sound-manager');
    playErrorSound();
    expect(mockExecFile).toHaveBeenCalledWith(
      'powershell',
      expect.arrayContaining([expect.stringContaining('Hand.Play()')]),
      expect.any(Function),
    );
  });

  it('Linux: calls paplay with dialog-error.oga', async () => {
    vi.resetModules();
    vi.doMock('node:child_process', () => ({
      execFile: (...args: any[]) => mockExecFile(...args),
    }));
    setPlatform('linux');
    const { playErrorSound } = await import('./sound-manager');
    playErrorSound();
    expect(mockExecFile).toHaveBeenCalledWith(
      'paplay',
      ['/usr/share/sounds/freedesktop/stereo/dialog-error.oga'],
      expect.any(Function),
    );
  });
});

// ═══════════════════════════════════════
// Error handling
// ═══════════════════════════════════════

describe('error handling', () => {
  it('logs console.warn on execFile error (does not throw)', async () => {
    setPlatform('darwin');
    mockExecFile.mockImplementation((...args: any[]) => {
      const cb = args[args.length - 1];
      if (typeof cb === 'function') cb(new Error('no audio device'));
    });
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    const { playSuccessSound } = await import('./sound-manager');
    expect(() => playSuccessSound()).not.toThrow();
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining('[GhostEdit]'),
      expect.any(String),
    );

    warnSpy.mockRestore();
  });
});
