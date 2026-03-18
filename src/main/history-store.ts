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
