import type { SpellCheckIssue, SpellCheckIssueKind, DictionaryPrePassResult } from '../shared/types';
import { configManager } from './config-manager';
import techDictionaryRaw from './data/tech-dictionary.txt?raw';

const MAX_PASSES = 3;

// ── Module-level state ──

let harperLinterPromise: Promise<any> | null = null;
let nspellCheckerPromise: Promise<any> | null = null;
let techDictionaryLoaded = false;
let personalDictionaryLoaded = false;

// ── Initialization ──

async function initHarper(): Promise<any> {
  const harper = await import('harper.js');
  const linter = new harper.LocalLinter({
    binary: harper.binary,
    dialect: harper.Dialect.American,
  });
  await linter.setup();
  return linter;
}

async function initNspell(): Promise<any> {
  const dictionaryEn = await import('dictionary-en');
  const nspellModule = await import('nspell');
  const NSpell = nspellModule.default;

  // dictionary-en v3+ exports { aff, dic } directly as default
  // Older versions use a callback pattern: default(cb) => cb(err, { aff, dic })
  let dict: { aff: any; dic: any };
  if (typeof dictionaryEn.default === 'function') {
    dict = await new Promise<{ aff: any; dic: any }>((resolve, reject) => {
      (dictionaryEn.default as any)((err: Error | null, result: any) => {
        if (err) reject(err);
        else resolve(result);
      });
    });
  } else {
    dict = dictionaryEn.default as any;
  }

  return new NSpell(dict.aff, dict.dic);
}

/** Pre-warm both checkers at app startup (fire-and-forget). */
export function preWarmDictionaryChecker(): void {
  ensureDictionaryCheckersLoaded().catch((err) => {
    console.warn('[GhostEdit] Dictionary checker pre-warm failed:', err.message);
  });
}

/** Initialize both checkers. Idempotent: safe to call multiple times. */
export async function ensureDictionaryCheckersLoaded(): Promise<void> {
  const [harperResult, nspellResult] = await Promise.allSettled([
    harperLinterPromise ?? (harperLinterPromise = initHarper()),
    nspellCheckerPromise ?? (nspellCheckerPromise = initNspell()),
  ]);

  if (harperResult.status === 'rejected') {
    console.warn('[GhostEdit] Harper init failed:', harperResult.reason?.message);
    harperLinterPromise = null; // Allow retry
  }
  if (nspellResult.status === 'rejected') {
    console.warn('[GhostEdit] nspell init failed:', nspellResult.reason?.message);
    nspellCheckerPromise = null; // Allow retry
  }

  // Load tech dictionary words into nspell (before personal so personal can override)
  if (!techDictionaryLoaded && nspellResult.status === 'fulfilled') {
    loadTechDictionaryIntoNspell(nspellResult.value);
  }

  // Load personal dictionary words into nspell
  if (!personalDictionaryLoaded && nspellResult.status === 'fulfilled') {
    loadPersonalDictionaryIntoNspell();
  }
}

/** Load built-in tech dictionary words into nspell checker. */
function loadTechDictionaryIntoNspell(checker: any): void {
  const words = techDictionaryRaw
    .split('\n')
    .map((w) => w.trim())
    .filter((w) => w.length > 0);
  for (const word of words) {
    checker.add(word);
  }
  techDictionaryLoaded = true;
}

/** Load personal dictionary words into nspell checker. */
function loadPersonalDictionaryIntoNspell(): void {
  if (!nspellCheckerPromise) return;
  nspellCheckerPromise.then((checker) => {
    const words = configManager.loadPersonalDictionary();
    for (const word of words) {
      checker.add(word);
    }
    personalDictionaryLoaded = true;
  }).catch(() => {});
}

/** Reload personal dictionary (call after dictionary changes). */
export function reloadPersonalDictionary(): void {
  personalDictionaryLoaded = false;
  if (nspellCheckerPromise) {
    loadPersonalDictionaryIntoNspell();
  }
}

/** Reset state — used in tests. */
export function resetDictionaryChecker(): void {
  harperLinterPromise = null;
  nspellCheckerPromise = null;
  techDictionaryLoaded = false;
}

// ── Harper Issue Extraction ──

function categorizeHarperLint(lint: any): SpellCheckIssueKind {
  const kind: string = lint.lint_kind();
  const lower = kind.toLowerCase();
  if (lower.includes('spell') || lower.includes('mispell')) return 'spelling';
  if (lower.includes('capitaliz') || lower.includes('grammar') || lower.includes('sentence')
    || lower.includes('wrong') || lower.includes('an_a') || lower.includes('number')
    || lower.includes('plural') || lower.includes('tense')) return 'grammar';
  return 'style';
}

export async function getHarperIssues(linter: any, text: string): Promise<SpellCheckIssue[]> {
  const lints = await linter.lint(text);
  const issues: SpellCheckIssue[] = [];

  for (const lint of lints) {
    const span = lint.span();
    const suggestions: string[] = [];

    for (const sug of lint.suggestions()) {
      if (sug.kind() === 1) {
        // kind === 1 means "Remove"
        suggestions.push('');
      } else {
        const replacement = sug.get_replacement_text();
        if (replacement != null) suggestions.push(replacement);
      }
    }

    // Only include issues that have at least one suggestion
    if (suggestions.length > 0) {
      issues.push({
        word: text.slice(span.start, span.end),
        range: { start: span.start, end: span.end },
        kind: categorizeHarperLint(lint),
        suggestions,
        source: 'harper',
      });
    }
  }

  return issues;
}

// ── Tech Word Heuristics ──

const COMPOUND_PREFIXES = [
  // Tech prefixes
  'web', 'micro', 'multi', 'auto', 'pre', 'un', 're', 'sub',
  'super', 'over', 'under', 'cross', 'inter', 'semi', 'non',
  'meta', 'pseudo', 'cyber', 'dev',
  // Common English compound-forming prefixes
  'push', 'pull', 'call', 'fall', 'feed', 'kick', 'set', 'pay',
  'cut', 'drop', 'roll', 'back', 'down', 'out', 'up',
];

/** Detect camelCase words like `backgroundColor`, `userId`. */
export function isCamelCase(word: string): boolean {
  return /^[a-z]+[A-Z]/.test(word);
}

/** Detect words with embedded digits like `utf8`, `base64`, `h264`. */
export function hasEmbeddedDigits(word: string): boolean {
  return /[a-zA-Z]/.test(word) && /\d/.test(word);
}

/** Detect tech compound words where prefix + real English suffix. */
export function isTechCompound(word: string, checker: any): boolean {
  const lower = word.toLowerCase();
  for (const prefix of COMPOUND_PREFIXES) {
    if (lower.startsWith(prefix) && lower.length > prefix.length) {
      const suffix = lower.slice(prefix.length);
      if (suffix.length >= 3 && checker.correct(suffix)) {
        return true;
      }
    }
  }
  return false;
}

/** Returns true if the word should be skipped as a tech/code word. */
function shouldSkipAsTechWord(word: string, checker: any): boolean {
  return isCamelCase(word) || hasEmbeddedDigits(word) || isTechCompound(word, checker);
}

// ── nspell Issue Extraction ──

export function getNspellIssues(checker: any, text: string): SpellCheckIssue[] {
  const issues: SpellCheckIssue[] = [];
  const wordRegex = /[a-zA-Z'\u2019]+/g;
  let match: RegExpExecArray | null;

  while ((match = wordRegex.exec(text)) !== null) {
    const word = match[0];
    const start = match.index;
    const end = start + word.length;

    // Skip single-character words
    if (word.length <= 1) continue;

    // Skip words that are just apostrophes
    if (/^['\u2019]+$/.test(word)) continue;

    // Skip tech/code words (camelCase, embedded digits, tech compounds)
    if (shouldSkipAsTechWord(word, checker)) continue;

    if (!checker.correct(word)) {
      const suggestions: string[] = checker.suggest(word);
      if (suggestions.length > 0) {
        issues.push({
          word,
          range: { start, end },
          kind: 'spelling',
          suggestions: suggestions.slice(0, 5),
          source: 'nspell',
        });
      }
    }
  }

  return issues;
}

// ── Merge Strategy ──

export function mergeIssues(
  harperIssues: SpellCheckIssue[],
  nspellIssues: SpellCheckIssue[],
): SpellCheckIssue[] {
  const merged = [...harperIssues];

  for (const nIssue of nspellIssues) {
    const overlaps = harperIssues.some(
      (h) => nIssue.range.start < h.range.end && nIssue.range.end > h.range.start,
    );
    if (!overlaps) {
      merged.push(nIssue);
    }
  }

  return merged;
}

// ── Filtering ──

export function filterProtectedTokenOverlaps(
  issues: SpellCheckIssue[],
  protectedRanges: Array<{ start: number; end: number }>,
): SpellCheckIssue[] {
  if (protectedRanges.length === 0) return issues;

  return issues.filter((issue) => {
    return !protectedRanges.some(
      (r) => issue.range.start < r.end && issue.range.end > r.start,
    );
  });
}

export function filterProperNounsAndAcronyms(
  issues: SpellCheckIssue[],
  text: string,
): SpellCheckIssue[] {
  return issues.filter((issue) => {
    // Only filter spelling issues (grammar/style issues on capitalized words are valid)
    if (issue.kind !== 'spelling') return true;

    const word = issue.word;

    // Filter acronyms: 2+ consecutive uppercase letters (e.g., "API", "NASA")
    if (/^[A-Z]{2,}$/.test(word)) return false;

    // Filter proper nouns: capitalized word NOT at sentence start
    if (/^[A-Z][a-z]/.test(word)) {
      const start = issue.range.start;
      if (start === 0) return true; // Text start, keep it
      const before = text.slice(Math.max(0, start - 3), start);
      const isSentenceStart = /[.!?]\s+$/.test(before) || /^\s*$/.test(text.slice(0, start));
      if (!isSentenceStart) return false;
    }

    return true;
  });
}

export function filterTechWords(
  issues: SpellCheckIssue[],
  text: string,
  nspellChecker: any | null,
): SpellCheckIssue[] {
  return issues.filter((issue) => {
    // Look at the full token in the original text containing this issue range
    const fullTokenRegex = /[a-zA-Z0-9]+/g;
    let tokenMatch: RegExpExecArray | null;
    while ((tokenMatch = fullTokenRegex.exec(text)) !== null) {
      const tStart = tokenMatch.index;
      const tEnd = tStart + tokenMatch[0].length;
      // Check if this token contains the issue range
      if (tStart <= issue.range.start && tEnd >= issue.range.end) {
        const fullToken = tokenMatch[0];
        if (isCamelCase(fullToken) || hasEmbeddedDigits(fullToken)) return false;
        if (nspellChecker && isTechCompound(fullToken, nspellChecker)) return false;
        break;
      }
    }

    return true;
  });
}

// ── Suggestion Safety ──

/** Compute Levenshtein edit distance between two strings. */
export function levenshteinDistance(a: string, b: string): number {
  const la = a.length;
  const lb = b.length;
  const dp: number[] = Array.from({ length: lb + 1 }, (_, i) => i);
  for (let i = 1; i <= la; i++) {
    let prev = dp[0];
    dp[0] = i;
    for (let j = 1; j <= lb; j++) {
      const tmp = dp[j];
      dp[j] = a[i - 1] === b[j - 1] ? prev : 1 + Math.min(prev, dp[j], dp[j - 1]);
      prev = tmp;
    }
  }
  return dp[lb];
}

/**
 * Check whether an nspell suggestion is safe to auto-apply.
 * Rejects suggestions that change both the first AND second character,
 * which indicates a semantically unrelated word (e.g. pushback -> cashback).
 */
export function isSafeNspellSuggestion(original: string, suggestion: string): boolean {
  const o = original.toLowerCase();
  const s = suggestion.toLowerCase();

  // Reject if both first and second characters differ
  if (o[0] !== s[0] && o.length > 1 && s.length > 1 && o[1] !== s[1]) return false;

  // Reject if edit distance exceeds reasonable threshold
  const dist = levenshteinDistance(o, s);
  const maxDist = o.length <= 6 ? 2 : o.length <= 10 ? 3 : 4;
  if (dist > maxDist) return false;

  // Reject if length difference is too large
  const maxLenDiff = o.length < 8 ? 2 : 3;
  if (Math.abs(o.length - s.length) > maxLenDiff) return false;

  return true;
}

// ── Fix Application ──

export function applyFixes(
  text: string,
  issues: SpellCheckIssue[],
): { text: string; fixCount: number } {
  if (issues.length === 0) return { text, fixCount: 0 };

  // Sort by position DESCENDING (highest first) to preserve earlier indices
  const sorted = [...issues].sort((a, b) => b.range.start - a.range.start);
  let result = text;
  let fixCount = 0;

  for (const issue of sorted) {
    // Verify the word still matches at expected position (guard against drift)
    const actual = result.slice(issue.range.start, issue.range.end);
    if (actual !== issue.word) continue;

    // Apply first suggestion, but guard nspell suggestions against wild substitutions
    const replacement = issue.suggestions[0];
    if (replacement === undefined) continue;
    if (replacement === actual) continue; // No-op replacement
    if (issue.source === 'nspell' && !isSafeNspellSuggestion(issue.word, replacement)) continue;

    result = result.slice(0, issue.range.start) + replacement + result.slice(issue.range.end);
    fixCount++;
  }

  return { text: result, fixCount };
}

// ── Iterative Pre-Pass / Polish ──

async function runIterativeFixes(
  text: string,
  protectedRanges: Array<{ start: number; end: number }>,
): Promise<DictionaryPrePassResult> {
  await ensureDictionaryCheckersLoaded(); // Lazy init on first use

  // Graceful degradation: if neither checker loaded, return text unchanged
  const harperLinter = harperLinterPromise ? await harperLinterPromise.catch(() => null) : null;
  const nspellChecker = nspellCheckerPromise ? await nspellCheckerPromise.catch(() => null) : null;

  if (!harperLinter && !nspellChecker) {
    return { text, issuesFixed: 0, passes: 0 };
  }

  let currentText = text;
  let totalFixed = 0;
  let passCount = 0;

  for (let pass = 0; pass < MAX_PASSES; pass++) {
    passCount++;

    // Gather issues from both checkers
    const harperIssues = harperLinter ? await getHarperIssues(harperLinter, currentText) : [];
    const nspellIssues = nspellChecker ? getNspellIssues(nspellChecker, currentText) : [];

    // Merge: Harper primary, nspell fills gaps
    let merged = mergeIssues(harperIssues, nspellIssues);

    // Filter out issues overlapping protected tokens
    merged = filterProtectedTokenOverlaps(merged, protectedRanges);

    // Filter proper nouns and acronyms
    merged = filterProperNounsAndAcronyms(merged, currentText);

    // Filter tech words (camelCase, embedded digits, tech compounds)
    merged = filterTechWords(merged, currentText, nspellChecker);

    if (merged.length === 0) break;

    // Apply fixes
    const { text: fixedText, fixCount } = applyFixes(currentText, merged);

    totalFixed += fixCount;

    if (fixCount === 0 || fixedText === currentText) break;

    currentText = fixedText;
  }

  return { text: currentText, issuesFixed: totalFixed, passes: passCount };
}

/**
 * Run the dictionary pre-pass on text.
 * Performs up to 3 iterative passes of fix -> re-check -> fix.
 * Protected token ranges are skipped.
 */
export async function dictionaryPrePass(
  text: string,
  protectedRanges: Array<{ start: number; end: number }>,
): Promise<DictionaryPrePassResult> {
  return runIterativeFixes(text, protectedRanges);
}

/**
 * Check text for issues without applying fixes.
 * Returns raw SpellCheckIssue[] for display in the traffic light / suggestions UI.
 */
export async function checkTextForIssues(text: string): Promise<SpellCheckIssue[]> {
  await ensureDictionaryCheckersLoaded();

  const harperLinter = harperLinterPromise ? await harperLinterPromise.catch(() => null) : null;
  const nspellChecker = nspellCheckerPromise ? await nspellCheckerPromise.catch(() => null) : null;

  if (!harperLinter && !nspellChecker) return [];

  const harperIssues = harperLinter ? await getHarperIssues(harperLinter, text) : [];
  const nspellIssues = nspellChecker ? getNspellIssues(nspellChecker, text) : [];

  let merged = mergeIssues(harperIssues, nspellIssues);
  merged = filterProperNounsAndAcronyms(merged, text);
  merged = filterTechWords(merged, text, nspellChecker);

  return merged;
}

/**
 * Run the dictionary polish on model output (same logic as pre-pass).
 * Typically called with empty protectedRanges since tokens are already restored.
 */
export async function dictionaryPolish(
  text: string,
  protectedRanges: Array<{ start: number; end: number }>,
): Promise<DictionaryPrePassResult> {
  return runIterativeFixes(text, protectedRanges);
}
