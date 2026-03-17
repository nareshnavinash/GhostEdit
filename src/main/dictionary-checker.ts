import type { SpellCheckIssue, SpellCheckIssueKind, DictionaryPrePassResult } from '../shared/types';

const MAX_PASSES = 3;

// ── Module-level state ──

let harperLinterPromise: Promise<any> | null = null;
let nspellCheckerPromise: Promise<any> | null = null;

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
}

/** Reset state — used in tests. */
export function resetDictionaryChecker(): void {
  harperLinterPromise = null;
  nspellCheckerPromise = null;
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

    // Apply first suggestion
    const replacement = issue.suggestions[0];
    if (replacement === undefined) continue;
    if (replacement === actual) continue; // No-op replacement

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
 * Run the dictionary polish on model output (same logic as pre-pass).
 * Typically called with empty protectedRanges since tokens are already restored.
 */
export async function dictionaryPolish(
  text: string,
  protectedRanges: Array<{ start: number; end: number }>,
): Promise<DictionaryPrePassResult> {
  return runIterativeFixes(text, protectedRanges);
}
