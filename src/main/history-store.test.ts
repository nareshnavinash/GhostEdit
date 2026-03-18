import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import type { CorrectionHistoryEntry } from '../shared/types';

// ── Mocks ──

const mockReadFileSync = vi.fn();
const mockWriteFile = vi.fn().mockResolvedValue(undefined);

vi.mock('node:fs', () => ({
  readFileSync: (...args: any[]) => mockReadFileSync(...args),
  promises: {
    writeFile: (...args: any[]) => mockWriteFile(...args),
  },
}));

const mockHistoryPath = '/mock/.ghostedit/history.json';
const mockHistoryLimit = 50;

vi.mock('./config-manager', () => ({
  configManager: {
    get historyPath() { return mockHistoryPath; },
    load: () => ({ historyLimit: mockHistoryLimit }),
  },
}));

// Helper: fresh module resets module-level cache and writeTimer
async function freshModule() {
  vi.resetModules();
  vi.doMock('node:fs', () => ({
    readFileSync: (...args: any[]) => mockReadFileSync(...args),
    promises: {
      writeFile: (...args: any[]) => mockWriteFile(...args),
    },
  }));
  vi.doMock('./config-manager', () => ({
    configManager: {
      get historyPath() { return mockHistoryPath; },
      load: () => ({ historyLimit: mockHistoryLimit }),
    },
  }));
  return import('./history-store');
}

function makeEntry(overrides?: Partial<CorrectionHistoryEntry>): CorrectionHistoryEntry {
  return {
    id: 'entry-1',
    timestamp: '2025-01-15T10:00:00.000Z',
    originalText: 'teh quick fox',
    generatedText: 'the quick fox',
    provider: 'local',
    model: 't5-grammar',
    durationMilliseconds: 150,
    succeeded: true,
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers();
  // Default: file not found
  mockReadFileSync.mockImplementation(() => { throw Object.assign(new Error('ENOENT'), { code: 'ENOENT' }); });
});

afterEach(() => {
  vi.useRealTimers();
});

// ═══════════════════════════════════════
// loadHistory
// ═══════════════════════════════════════

describe('loadHistory', () => {
  it('reads from configManager.historyPath on first call', async () => {
    const entries = [makeEntry()];
    mockReadFileSync.mockReturnValue(JSON.stringify(entries));
    const { loadHistory } = await freshModule();

    const result = loadHistory();
    expect(mockReadFileSync).toHaveBeenCalledWith(mockHistoryPath, 'utf-8');
    expect(result).toEqual(entries);
  });

  it('caches result — second call does not re-read file', async () => {
    mockReadFileSync.mockReturnValue(JSON.stringify([makeEntry()]));
    const { loadHistory } = await freshModule();

    loadHistory();
    loadHistory();
    expect(mockReadFileSync).toHaveBeenCalledTimes(1);
  });

  it('returns [] when file throws (ENOENT)', async () => {
    const { loadHistory } = await freshModule();
    expect(loadHistory()).toEqual([]);
  });

  it('returns [] when file has invalid JSON', async () => {
    mockReadFileSync.mockReturnValue('not valid json {{{');
    const { loadHistory } = await freshModule();
    expect(loadHistory()).toEqual([]);
  });
});

// ═══════════════════════════════════════
// appendHistory
// ═══════════════════════════════════════

describe('appendHistory', () => {
  it('appends entry to cache (visible in next loadHistory())', async () => {
    const { appendHistory, loadHistory } = await freshModule();
    const entry = makeEntry();
    appendHistory(entry);
    expect(loadHistory()).toContainEqual(entry);
  });

  it('trims to historyLimit from config when exceeded', async () => {
    vi.resetModules();
    vi.doMock('node:fs', () => ({
      readFileSync: (...args: any[]) => mockReadFileSync(...args),
      promises: { writeFile: (...args: any[]) => mockWriteFile(...args) },
    }));
    vi.doMock('./config-manager', () => ({
      configManager: {
        get historyPath() { return mockHistoryPath; },
        load: () => ({ historyLimit: 2 }),
      },
    }));
    const mod = await import('./history-store');

    mod.appendHistory(makeEntry({ id: 'e1' }));
    mod.appendHistory(makeEntry({ id: 'e2' }));
    mod.appendHistory(makeEntry({ id: 'e3' }));

    const result = mod.loadHistory();
    expect(result).toHaveLength(2);
    expect(result[0].id).toBe('e2');
    expect(result[1].id).toBe('e3');
  });

  it('uses explicit historyLimit parameter when provided', async () => {
    const { appendHistory, loadHistory } = await freshModule();
    appendHistory(makeEntry({ id: 'e1' }), 1);
    appendHistory(makeEntry({ id: 'e2' }), 1);
    const result = loadHistory();
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('e2');
  });

  it('does NOT write immediately (debounced)', async () => {
    const { appendHistory } = await freshModule();
    appendHistory(makeEntry());
    expect(mockWriteFile).not.toHaveBeenCalled();
  });

  it('debounce resets on rapid appends — only one write after final 500ms window', async () => {
    const { appendHistory } = await freshModule();
    appendHistory(makeEntry({ id: 'e1' }));
    vi.advanceTimersByTime(300);
    appendHistory(makeEntry({ id: 'e2' }));
    vi.advanceTimersByTime(300);
    appendHistory(makeEntry({ id: 'e3' }));

    // Still no write
    expect(mockWriteFile).not.toHaveBeenCalled();

    // After the debounce window
    await vi.advanceTimersByTimeAsync(500);
    expect(mockWriteFile).toHaveBeenCalledTimes(1);
  });
});

// ═══════════════════════════════════════
// clearHistory
// ═══════════════════════════════════════

describe('clearHistory', () => {
  it('empties cache; loadHistory() returns []', async () => {
    const { appendHistory, clearHistory, loadHistory } = await freshModule();
    appendHistory(makeEntry());
    clearHistory();
    expect(loadHistory()).toEqual([]);
  });

  it('schedules persist of empty array after debounce', async () => {
    const { clearHistory } = await freshModule();
    clearHistory();
    await vi.advanceTimersByTimeAsync(500);
    expect(mockWriteFile).toHaveBeenCalledWith(
      mockHistoryPath,
      JSON.stringify([], null, 2),
      'utf-8',
    );
  });
});

// ═══════════════════════════════════════
// lastSuccessfulEntry
// ═══════════════════════════════════════

describe('lastSuccessfulEntry', () => {
  it('returns null for empty history', async () => {
    const { lastSuccessfulEntry } = await freshModule();
    expect(lastSuccessfulEntry()).toBeNull();
  });

  it('returns null when all entries are failed', async () => {
    const { appendHistory, lastSuccessfulEntry } = await freshModule();
    appendHistory(makeEntry({ succeeded: false, id: 'f1' }));
    appendHistory(makeEntry({ succeeded: false, id: 'f2' }));
    expect(lastSuccessfulEntry()).toBeNull();
  });

  it('returns the most recent succeeded: true entry', async () => {
    const { appendHistory, lastSuccessfulEntry } = await freshModule();
    appendHistory(makeEntry({ id: 's1', succeeded: true }));
    appendHistory(makeEntry({ id: 'f1', succeeded: false }));
    appendHistory(makeEntry({ id: 's2', succeeded: true }));
    appendHistory(makeEntry({ id: 'f2', succeeded: false }));
    expect(lastSuccessfulEntry()?.id).toBe('s2');
  });
});

// ═══════════════════════════════════════
// computeUsageStats
// ═══════════════════════════════════════

describe('computeUsageStats', () => {
  it('returns zeroed stats for empty history', async () => {
    const { computeUsageStats } = await freshModule();
    const stats = computeUsageStats();
    expect(stats.totalCorrections).toBe(0);
    expect(stats.successRate).toBe(0);
    expect(stats.avgDurationMs).toBe(0);
  });

  it('computes correct totalCorrections and successRate', async () => {
    const { appendHistory, computeUsageStats } = await freshModule();
    appendHistory(makeEntry({ succeeded: true, id: 's1' }));
    appendHistory(makeEntry({ succeeded: true, id: 's2' }));
    appendHistory(makeEntry({ succeeded: false, id: 'f1' }));

    const stats = computeUsageStats();
    expect(stats.totalCorrections).toBe(3);
    expect(stats.successfulCorrections).toBe(2);
    expect(stats.failedCorrections).toBe(1);
    expect(stats.successRate).toBe(67); // Math.round(2/3 * 100) = 67
  });

  it('computes avgDurationMs from successful entries only', async () => {
    const { appendHistory, computeUsageStats } = await freshModule();
    appendHistory(makeEntry({ succeeded: true, durationMilliseconds: 100, id: 's1' }));
    appendHistory(makeEntry({ succeeded: true, durationMilliseconds: 200, id: 's2' }));
    appendHistory(makeEntry({ succeeded: false, durationMilliseconds: 9999, id: 'f1' }));

    const stats = computeUsageStats();
    expect(stats.avgDurationMs).toBe(150); // (100 + 200) / 2
  });

  it('groups correctionsByProvider and correctionsByDate correctly', async () => {
    const { appendHistory, computeUsageStats } = await freshModule();
    appendHistory(makeEntry({ provider: 'claude', timestamp: '2025-01-15T10:00:00Z', id: 'e1' }));
    appendHistory(makeEntry({ provider: 'claude', timestamp: '2025-01-15T11:00:00Z', id: 'e2' }));
    appendHistory(makeEntry({ provider: 'local', timestamp: '2025-01-16T10:00:00Z', id: 'e3' }));

    const stats = computeUsageStats();
    expect(stats.correctionsByProvider).toEqual({ claude: 2, local: 1 });
    expect(stats.correctionsByDate).toEqual({ '2025-01-15': 2, '2025-01-16': 1 });
  });
});
