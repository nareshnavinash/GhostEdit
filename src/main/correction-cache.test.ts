import { describe, it, expect, beforeEach } from 'vitest';
import { getCached, putCache, clearCache } from './correction-cache';

beforeEach(() => {
  clearCache();
});

describe('correction-cache', () => {
  it('returns null for uncached entries', () => {
    expect(getCached('hello', 'local', 't5-grammar', 'default', 'auto')).toBeNull();
  });

  it('stores and retrieves cached corrections', () => {
    const result = { text: 'Hello.', durationMs: 100 };
    putCache('hello', 'local', 't5-grammar', 'default', 'auto', result);

    const cached = getCached('hello', 'local', 't5-grammar', 'default', 'auto');
    expect(cached).toEqual(result);
  });

  it('distinguishes entries by provider', () => {
    putCache('hello', 'local', 't5-grammar', 'default', 'auto', { text: 'A', durationMs: 10 });
    putCache('hello', 'claude', 'sonnet', 'default', 'auto', { text: 'B', durationMs: 20 });

    expect(getCached('hello', 'local', 't5-grammar', 'default', 'auto')?.text).toBe('A');
    expect(getCached('hello', 'claude', 'sonnet', 'default', 'auto')?.text).toBe('B');
  });

  it('distinguishes entries by tone', () => {
    putCache('hello', 'local', 't5-grammar', 'casual', 'auto', { text: 'casual', durationMs: 10 });
    putCache('hello', 'local', 't5-grammar', 'professional', 'auto', { text: 'pro', durationMs: 10 });

    expect(getCached('hello', 'local', 't5-grammar', 'casual', 'auto')?.text).toBe('casual');
    expect(getCached('hello', 'local', 't5-grammar', 'professional', 'auto')?.text).toBe('pro');
  });

  it('clears all entries', () => {
    putCache('a', 'local', 't5', 'default', 'en', { text: 'A', durationMs: 5 });
    putCache('b', 'local', 't5', 'default', 'en', { text: 'B', durationMs: 5 });

    clearCache();

    expect(getCached('a', 'local', 't5', 'default', 'en')).toBeNull();
    expect(getCached('b', 'local', 't5', 'default', 'en')).toBeNull();
  });

  it('evicts oldest entry when at capacity', () => {
    // Fill cache to max (100)
    for (let i = 0; i < 100; i++) {
      putCache(`text-${i}`, 'local', 't5', 'default', 'en', { text: `result-${i}`, durationMs: 1 });
    }

    // First entry should still exist
    expect(getCached('text-0', 'local', 't5', 'default', 'en')).not.toBeNull();

    // Add one more to trigger eviction
    putCache('text-100', 'local', 't5', 'default', 'en', { text: 'result-100', durationMs: 1 });

    // First entry should be evicted
    expect(getCached('text-0', 'local', 't5', 'default', 'en')).toBeNull();
    // New entry should exist
    expect(getCached('text-100', 'local', 't5', 'default', 'en')?.text).toBe('result-100');
    // Second entry should still exist
    expect(getCached('text-1', 'local', 't5', 'default', 'en')).not.toBeNull();
  });
});
