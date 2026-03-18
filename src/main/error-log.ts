import { randomUUID } from 'node:crypto';
import type { ErrorLogEntry, ProviderName } from '../shared/types';
import { ERROR_LOG_MAX_ENTRIES } from '../shared/constants';

/**
 * In-memory ring buffer for recent errors.
 * Keeps the last N errors so users can review them after HUD dismisses.
 */

const errors: ErrorLogEntry[] = [];

export function appendError(message: string, provider?: ProviderName): void {
  errors.push({
    id: randomUUID(),
    timestamp: new Date().toISOString(),
    message,
    provider,
  });
  if (errors.length > ERROR_LOG_MAX_ENTRIES) {
    errors.shift();
  }
}

export function getErrors(): ErrorLogEntry[] {
  return [...errors];
}
