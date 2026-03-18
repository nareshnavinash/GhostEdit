/**
 * Real-time analysis pipeline.
 * Wires the keystroke buffer to the dictionary checker, debounces analysis,
 * computes traffic light color, and optionally runs background T5 refinement.
 */

import { checkTextForIssues } from './dictionary-checker';
import type { TrafficLightColor, SpellCheckIssue } from '../shared/types';

const DEBOUNCE_MS = 300;
const MIN_CHARS = 3;
const BACKGROUND_IDLE_MS = 1000;
const BACKGROUND_MIN_CHARS = 20;

let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let backgroundTimer: ReturnType<typeof setTimeout> | null = null;
let lastIssues: SpellCheckIssue[] = [];
let lastColor: TrafficLightColor = 'green';
let analyzing = false;

// Callbacks
let onColorChange: ((color: TrafficLightColor) => void) | null = null;
let onIssuesChange: ((issues: SpellCheckIssue[]) => void) | null = null;

export interface AnalyzerCallbacks {
  onColorChange: (color: TrafficLightColor) => void;
  onIssuesChange: (issues: SpellCheckIssue[]) => void;
}

export function initAnalyzer(callbacks: AnalyzerCallbacks): void {
  onColorChange = callbacks.onColorChange;
  onIssuesChange = callbacks.onIssuesChange;
  lastIssues = [];
  lastColor = 'green';
}

export function destroyAnalyzer(): void {
  if (debounceTimer) clearTimeout(debounceTimer);
  if (backgroundTimer) clearTimeout(backgroundTimer);
  debounceTimer = null;
  backgroundTimer = null;
  onColorChange = null;
  onIssuesChange = null;
  lastIssues = [];
  lastColor = 'green';
  analyzing = false;
}

/**
 * Called when the keystroke buffer changes.
 * Debounces 300ms then runs dictionary analysis.
 */
export function onBufferChanged(buffer: string): void {
  // Cancel pending analysis
  if (debounceTimer) clearTimeout(debounceTimer);
  if (backgroundTimer) clearTimeout(backgroundTimer);

  // Too short — set green
  if (buffer.trim().length < MIN_CHARS) {
    if (lastColor !== 'green') {
      lastColor = 'green';
      lastIssues = [];
      onColorChange?.('green');
      onIssuesChange?.([]);
    }
    return;
  }

  debounceTimer = setTimeout(() => {
    runAnalysis(buffer);
  }, DEBOUNCE_MS);
}

async function runAnalysis(text: string): Promise<void> {
  if (analyzing) return;
  analyzing = true;

  try {
    const issues = await checkTextForIssues(text);
    lastIssues = issues;
    const color = computeColor(issues);
    lastColor = color;
    onColorChange?.(color);
    onIssuesChange?.(issues);
  } catch (err) {
    console.error('[GhostEdit] Realtime analysis error:', err);
  } finally {
    analyzing = false;
  }
}

function computeColor(issues: SpellCheckIssue[]): TrafficLightColor {
  if (issues.length === 0) return 'green';

  const hasSpellingOrGrammar = issues.some(
    (i) => i.kind === 'spelling' || i.kind === 'grammar',
  );
  if (hasSpellingOrGrammar) return 'red';

  // Only style issues
  return 'yellow';
}

export function getLastIssues(): SpellCheckIssue[] {
  return lastIssues;
}

export function getLastColor(): TrafficLightColor {
  return lastColor;
}

export function clearAnalyzerState(): void {
  lastIssues = [];
  lastColor = 'green';
  if (debounceTimer) clearTimeout(debounceTimer);
  if (backgroundTimer) clearTimeout(backgroundTimer);
  debounceTimer = null;
  backgroundTimer = null;
}
