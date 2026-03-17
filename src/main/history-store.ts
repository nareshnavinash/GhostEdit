import * as fs from 'node:fs';
import type { CorrectionHistoryEntry } from '../shared/types';
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
