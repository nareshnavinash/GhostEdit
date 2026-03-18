import { describe, it, expect, vi, beforeEach } from 'vitest';

// ── Mocks ──

const mockUUID = vi.fn();
vi.mock('node:crypto', () => ({
  randomUUID: (...args: any[]) => mockUUID(...args),
}));

// Helper to get a fresh module (resets module-level `errors` array)
async function freshModule() {
  vi.resetModules();
  vi.doMock('node:crypto', () => ({
    randomUUID: (...args: any[]) => mockUUID(...args),
  }));
  return import('./error-log');
}

let uuidCounter = 0;

beforeEach(() => {
  vi.clearAllMocks();
  uuidCounter = 0;
  mockUUID.mockImplementation(() => `uuid-${++uuidCounter}`);
});

// ═══════════════════════════════════════
// appendError
// ═══════════════════════════════════════

describe('appendError', () => {
  it('adds entry with id, timestamp, message, and provider', async () => {
    const { appendError, getErrors } = await freshModule();
    appendError('Something went wrong', 'claude');
    const errors = getErrors();
    expect(errors).toHaveLength(1);
    expect(errors[0].id).toBe('uuid-1');
    expect(errors[0].message).toBe('Something went wrong');
    expect(errors[0].provider).toBe('claude');
    expect(errors[0].timestamp).toBeTruthy();
  });

  it('works without provider (undefined)', async () => {
    const { appendError, getErrors } = await freshModule();
    appendError('Generic error');
    const errors = getErrors();
    expect(errors).toHaveLength(1);
    expect(errors[0].provider).toBeUndefined();
  });

  it('stores multiple entries in insertion order', async () => {
    const { appendError, getErrors } = await freshModule();
    appendError('First error', 'claude');
    appendError('Second error', 'gemini');
    appendError('Third error');
    const errors = getErrors();
    expect(errors).toHaveLength(3);
    expect(errors[0].message).toBe('First error');
    expect(errors[1].message).toBe('Second error');
    expect(errors[2].message).toBe('Third error');
  });
});

// ═══════════════════════════════════════
// Ring buffer eviction
// ═══════════════════════════════════════

describe('ring buffer eviction', () => {
  it('evicts oldest entries when exceeding ERROR_LOG_MAX_ENTRIES', async () => {
    vi.resetModules();
    vi.doMock('node:crypto', () => ({
      randomUUID: (...args: any[]) => mockUUID(...args),
    }));
    vi.doMock('../shared/constants', async () => {
      const actual = await vi.importActual<typeof import('../shared/constants')>('../shared/constants');
      return { ...actual, ERROR_LOG_MAX_ENTRIES: 3 };
    });
    const { appendError, getErrors } = await import('./error-log');

    appendError('error-1');
    appendError('error-2');
    appendError('error-3');
    appendError('error-4');

    const errors = getErrors();
    expect(errors).toHaveLength(3);
    expect(errors[0].message).toBe('error-2');
    expect(errors[2].message).toBe('error-4');
  });
});

// ═══════════════════════════════════════
// getErrors
// ═══════════════════════════════════════

describe('getErrors', () => {
  it('returns empty array on fresh module', async () => {
    const { getErrors } = await freshModule();
    expect(getErrors()).toEqual([]);
  });

  it('returns a shallow copy (mutations do not affect internal state)', async () => {
    const { appendError, getErrors } = await freshModule();
    appendError('test error');
    const copy = getErrors();
    copy.pop();
    expect(getErrors()).toHaveLength(1);
  });
});
