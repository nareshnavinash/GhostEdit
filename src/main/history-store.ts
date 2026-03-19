import * as fs from 'node:fs';
import type { CorrectionHistoryEntry, UsageStats } from '../shared/types';
import { configManager } from './config-manager';

/**
 * Port of CorrectionHistoryStore.swift.
 * Uses an in-memory cache with debounced async writes to avoid
 * blocking the main thread on every correction.
 */

let cache: CorrectionHistoryEntry[] | null = null;
let writeTimer: ReturnType<typeof setTimeout> | null = null;

const DEBOUNCE_MS = 500;

function ensureLoaded(): CorrectionHistoryEntry[] {
  if (cache === null) {
    const filePath = configManager.historyPath;
    try {
      const raw = fs.readFileSync(filePath, 'utf-8');
      cache = JSON.parse(raw) as CorrectionHistoryEntry[];
    } catch {
      cache = [];
    }
  }
  return cache;
}

function schedulePersist(): void {
  if (writeTimer) clearTimeout(writeTimer);
  writeTimer = setTimeout(() => {
    writeTimer = null;
    if (cache === null) return;
    const filePath = configManager.historyPath;
    fs.promises
      .writeFile(filePath, JSON.stringify(cache, null, 2), 'utf-8')
      .catch((err) => {
        console.error('[GhostEdit] Failed to persist history:', err);
      });
  }, DEBOUNCE_MS);
}

export function loadHistory(): CorrectionHistoryEntry[] {
  return ensureLoaded();
}

export function appendHistory(entry: CorrectionHistoryEntry, historyLimit?: number): void {
  const entries = ensureLoaded();
  entries.push(entry);
  const limit = historyLimit ?? configManager.load().historyLimit;
  if (entries.length > limit) {
    cache = entries.slice(entries.length - limit);
  }
  schedulePersist();
}

export function clearHistory(): void {
  cache = [];
  schedulePersist();
}

export function lastSuccessfulEntry(): CorrectionHistoryEntry | null {
  const entries = ensureLoaded();
  for (let i = entries.length - 1; i >= 0; i--) {
    if (entries[i].succeeded) return entries[i];
  }
  return null;
}

/**
 * Record today's date in the streak and return the current streak length.
 * Keeps only the last 90 dates to avoid unbounded growth.
 */
export function updateStreak(streakDates: string[]): { streakDates: string[]; streakCount: number } {
  const today = new Date().toISOString().split('T')[0];
  const dates = new Set(streakDates);
  dates.add(today);

  // Sort descending and compute consecutive day streak from today
  const sorted = [...dates].sort().reverse();
  let streakCount = 0;
  const now = new Date(today);

  for (let i = 0; i < sorted.length; i++) {
    const expected = new Date(now);
    expected.setDate(expected.getDate() - i);
    const expectedStr = expected.toISOString().split('T')[0];
    if (sorted[i] === expectedStr) {
      streakCount++;
    } else {
      break;
    }
  }

  // Keep only last 90 entries
  const trimmed = sorted.slice(0, 90);

  return { streakDates: trimmed, streakCount };
}

export interface TodayStats {
  count: number;
  spellingFixes: number;
  grammarFixes: number;
  successRate: number;
}

export function getTodayStats(): TodayStats {
  const entries = ensureLoaded();
  const today = new Date().toISOString().split('T')[0];
  const todayEntries = entries.filter((e) => e.timestamp.startsWith(today));

  if (todayEntries.length === 0) {
    return { count: 0, spellingFixes: 0, grammarFixes: 0, successRate: 0 };
  }

  const succeeded = todayEntries.filter((e) => e.succeeded).length;
  const successRate = Math.round((succeeded / todayEntries.length) * 100);

  // Estimate spelling vs grammar by diffing original and corrected text
  let spellingFixes = 0;
  let grammarFixes = 0;
  for (const entry of todayEntries) {
    if (!entry.succeeded || !entry.originalText || !entry.generatedText) continue;
    const origWords = entry.originalText.split(/\s+/);
    const genWords = entry.generatedText.split(/\s+/);
    if (origWords.length === genWords.length) {
      // Same word count: likely spelling fixes
      spellingFixes++;
    } else {
      // Word count changed: likely grammar/restructuring
      grammarFixes++;
    }
  }

  return { count: todayEntries.length, spellingFixes, grammarFixes, successRate };
}

export function computeUsageStats(): UsageStats {
  const entries = ensureLoaded();
  const successful = entries.filter((e) => e.succeeded);
  const failed = entries.filter((e) => !e.succeeded);
  const totalDurationMs = successful.reduce((sum, e) => sum + e.durationMilliseconds, 0);
  const totalWordsProcessed = successful.reduce(
    (sum, e) => sum + (e.originalText ? e.originalText.split(/\s+/).length : 0),
    0,
  );

  const correctionsByProvider: Record<string, number> = {};
  for (const entry of entries) {
    const key = entry.provider;
    correctionsByProvider[key] = (correctionsByProvider[key] || 0) + 1;
  }

  const correctionsByDate: Record<string, number> = {};
  for (const entry of entries) {
    const date = entry.timestamp.split('T')[0];
    correctionsByDate[date] = (correctionsByDate[date] || 0) + 1;
  }

  return {
    totalCorrections: entries.length,
    successfulCorrections: successful.length,
    failedCorrections: failed.length,
    successRate: entries.length > 0 ? Math.round((successful.length / entries.length) * 100) : 0,
    totalDurationMs,
    avgDurationMs: successful.length > 0 ? Math.round(totalDurationMs / successful.length) : 0,
    totalWordsProcessed,
    correctionsByProvider,
    correctionsByDate,
  };
}
