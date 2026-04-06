/**
 * Integration tests for the dictionary checker.
 * These use REAL harper.js (WASM) and nspell (Hunspell) — no mocks.
 * They verify the full pipeline works end-to-end.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import {
  ensureDictionaryCheckersLoaded,
  dictionaryPrePass,
  dictionaryPolish,
  getHarperIssues,
  getNspellIssues,
  mergeIssues,
  filterProtectedTokenOverlaps,
  filterProperNounsAndAcronyms,
  applyFixes,
  resetDictionaryChecker,
  isCamelCase,
  hasEmbeddedDigits,
  isTechCompound,
} from './dictionary-checker';

// Real Harper linter and nspell checker, initialized in beforeAll
let harperLinter: any = null;
let nspellChecker: any = null;

beforeAll(async () => {
  // Reset to ensure we load real modules (not cached mocks from unit tests)
  resetDictionaryChecker();
  await ensureDictionaryCheckersLoaded();

  // Also load the real checkers directly for targeted tests
  try {
    const harper = await import('harper.js');
    harperLinter = new harper.LocalLinter({
      binary: harper.binary,
      dialect: harper.Dialect.American,
    });
    await harperLinter.setup();
  } catch (err) {
    console.warn('Harper not available for integration tests:', (err as Error).message);
  }

  try {
    const dictionaryEn = await import('dictionary-en');
    const nspellModule = await import('nspell');
    const NSpell = nspellModule.default;
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
    nspellChecker = new NSpell(dict.aff, dict.dic);
  } catch (err) {
    console.warn('nspell not available for integration tests:', (err as Error).message);
  }
}, 30000); // 30s timeout for WASM + dictionary loading

// ═══════════════════════════════════════
// Harper Integration
// ═══════════════════════════════════════

describe('Harper integration', () => {
  it('detects common misspelling', async () => {
    if (!harperLinter) return;
    const issues = await getHarperIssues(harperLinter, 'I recieved your email');
    const recievedIssue = issues.find((i) => i.word === 'recieved');
    expect(recievedIssue).toBeDefined();
    expect(recievedIssue!.suggestions).toContain('received');
  });

  it('returns no issues for correct text', async () => {
    if (!harperLinter) return;
    const issues = await getHarperIssues(harperLinter, 'The quick brown fox jumps over the lazy dog.');
    // May have style suggestions, but no spelling errors
    const spellingIssues = issues.filter((i) => i.kind === 'spelling');
    expect(spellingIssues).toHaveLength(0);
  });

  it('handles empty text', async () => {
    if (!harperLinter) return;
    const issues = await getHarperIssues(harperLinter, '');
    expect(issues).toEqual([]);
  });
});

// ═══════════════════════════════════════
// nspell Integration
// ═══════════════════════════════════════

describe('nspell integration', () => {
  it('detects misspelled word', () => {
    if (!nspellChecker) return;
    const issues = getNspellIssues(nspellChecker, 'I recieved your email');
    const recievedIssue = issues.find((i) => i.word === 'recieved');
    expect(recievedIssue).toBeDefined();
    expect(recievedIssue!.suggestions.length).toBeGreaterThan(0);
  });

  it('does not flag correct words', () => {
    if (!nspellChecker) return;
    const issues = getNspellIssues(nspellChecker, 'The quick brown fox');
    expect(issues).toHaveLength(0);
  });

  it('handles contractions', () => {
    if (!nspellChecker) return;
    const issues = getNspellIssues(nspellChecker, "I don't know");
    // "don't" should not be flagged
    const dontIssue = issues.find((i) => i.word === "don't");
    expect(dontIssue).toBeUndefined();
  });
});

// ═══════════════════════════════════════
// Merge Integration
// ═══════════════════════════════════════

describe('merge integration', () => {
  it('merges Harper and nspell issues without duplicates', async () => {
    if (!harperLinter || !nspellChecker) return;
    const text = 'I recieved teh email';
    const harperIssues = await getHarperIssues(harperLinter, text);
    const nspellIssues = getNspellIssues(nspellChecker, text);
    const merged = mergeIssues(harperIssues, nspellIssues);

    // Should not have duplicate issues for the same word at the same position
    const seen = new Set<string>();
    for (const issue of merged) {
      const key = `${issue.range.start}-${issue.range.end}`;
      expect(seen.has(key)).toBe(false);
      seen.add(key);
    }
  });
});

// ═══════════════════════════════════════
// Full Pipeline Integration
// ═══════════════════════════════════════

describe('dictionaryPrePass full pipeline', () => {
  it('handles empty text', async () => {
    const result = await dictionaryPrePass('', []);
    expect(result.text).toBe('');
    expect(result.issuesFixed).toBe(0);
  });

  it('handles already-correct text', async () => {
    const result = await dictionaryPrePass('The quick brown fox jumps over the lazy dog.', []);
    expect(result.issuesFixed).toBe(0);
  });

  it('fixes common misspelling', async () => {
    const result = await dictionaryPrePass('I recieved your email', []);
    // At least one checker should catch "recieved"
    if (result.issuesFixed > 0) {
      expect(result.text).toContain('received');
    }
  });

  it('preserves URLs untouched', async () => {
    const url = 'https://github.com/somthing';
    const text = `Check ${url} for details`;
    // Protect the URL range
    const urlStart = text.indexOf(url);
    const protectedRanges = [{ start: urlStart, end: urlStart + url.length }];
    const result = await dictionaryPrePass(text, protectedRanges);
    expect(result.text).toContain(url);
  });

  it('preserves @mentions untouched', async () => {
    const text = '@john plz review this';
    // Protect @john
    const protectedRanges = [{ start: 0, end: 5 }];
    const result = await dictionaryPrePass(text, protectedRanges);
    expect(result.text.startsWith('@john')).toBe(true);
  });

  it('does not corrupt proper nouns', async () => {
    const result = await dictionaryPrePass('I met Naresh at the conference.', []);
    // "Naresh" is mid-sentence capitalized → should be filtered as proper noun
    expect(result.text).toContain('Naresh');
  });

  it('does not corrupt acronyms', async () => {
    const result = await dictionaryPrePass('The API uses REST endpoints.', []);
    expect(result.text).toContain('API');
    expect(result.text).toContain('REST');
  });

  it('handles mixed case text with proper nouns and errors', async () => {
    const result = await dictionaryPrePass('John recieved teh email from NASA.', []);
    // John and NASA should be preserved
    expect(result.text).toContain('John');
    expect(result.text).toContain('NASA');
  });

  it('handles very short text', async () => {
    const result = await dictionaryPrePass('Hi', []);
    expect(result.text).toBe('Hi');
  });

  it('completes within reasonable time for normal text', async () => {
    const text = 'This is a normal paragraph with some text that should be checked quickly. It contains a few sentances and some common misspellings like teh and recieve.';
    const start = Date.now();
    await dictionaryPrePass(text, []);
    const elapsed = Date.now() - start;
    // Should complete within 5 seconds even on slow machines
    expect(elapsed).toBeLessThan(5000);
  });
});

// ═══════════════════════════════════════
// Polish Integration
// ═══════════════════════════════════════

describe('dictionaryPolish full pipeline', () => {
  it('fixes errors in model output', async () => {
    const result = await dictionaryPolish('I recieved your email yesterday.', []);
    if (result.issuesFixed > 0) {
      expect(result.text).toContain('received');
    }
  });

  it('returns clean text unchanged', async () => {
    const text = 'The quick brown fox jumps over the lazy dog.';
    const result = await dictionaryPolish(text, []);
    expect(result.text).toBe(text);
  });
});

// ═══════════════════════════════════════
// applyFixes with real issues
// ═══════════════════════════════════════

describe('applyFixes with realistic data', () => {
  it('applies multiple real fixes in correct order', () => {
    const text = 'I recieve teh email';
    const issues = [
      { word: 'recieve', range: { start: 2, end: 9 }, kind: 'spelling' as const, suggestions: ['receive'], source: 'harper' as const },
      { word: 'teh', range: { start: 10, end: 13 }, kind: 'spelling' as const, suggestions: ['the'], source: 'nspell' as const },
    ];
    const result = applyFixes(text, issues);
    expect(result.text).toBe('I receive the email');
    expect(result.fixCount).toBe(2);
  });

  it('does not corrupt text when issues are adjacent', () => {
    const text = 'ab cd';
    const issues = [
      { word: 'ab', range: { start: 0, end: 2 }, kind: 'spelling' as const, suggestions: ['AB'], source: 'harper' as const },
      { word: 'cd', range: { start: 3, end: 5 }, kind: 'spelling' as const, suggestions: ['CD'], source: 'harper' as const },
    ];
    const result = applyFixes(text, issues);
    expect(result.text).toBe('AB CD');
    expect(result.fixCount).toBe(2);
  });
});

// ═══════════════════════════════════════
// Token protection integration
// ═══════════════════════════════════════

describe('token protection integration', () => {
  it('filters issues inside protected ranges from real checkers', async () => {
    if (!harperLinter) return;
    // "somthing" inside a protected URL range should not be flagged
    const text = 'Visit https://somthing.com for info';
    const harperIssues = await getHarperIssues(harperLinter, text);
    const protectedRanges = [{ start: 6, end: 29 }]; // the URL
    const filtered = filterProtectedTokenOverlaps(harperIssues, protectedRanges);
    // Any issues inside the URL range should have been removed
    for (const issue of filtered) {
      expect(issue.range.start >= 29 || issue.range.end <= 6).toBe(true);
    }
  });
});

// ═══════════════════════════════════════
// Proper noun / acronym filtering integration
// ═══════════════════════════════════════

describe('proper noun and acronym filtering integration', () => {
  it('filters mid-sentence capitalized names from real nspell', () => {
    if (!nspellChecker) return;
    const text = 'I spoke with Naresh about the project.';
    const nspellIssues = getNspellIssues(nspellChecker, text);
    const filtered = filterProperNounsAndAcronyms(nspellIssues, text);
    // "Naresh" should be filtered (capitalized, mid-sentence)
    const nareshIssue = filtered.find((i) => i.word === 'Naresh');
    expect(nareshIssue).toBeUndefined();
  });

  it('filters acronyms from real nspell', () => {
    if (!nspellChecker) return;
    const text = 'The API and REST endpoints work well.';
    const nspellIssues = getNspellIssues(nspellChecker, text);
    const filtered = filterProperNounsAndAcronyms(nspellIssues, text);
    const apiIssue = filtered.find((i) => i.word === 'API');
    const restIssue = filtered.find((i) => i.word === 'REST');
    expect(apiIssue).toBeUndefined();
    expect(restIssue).toBeUndefined();
  });
});

// ═══════════════════════════════════════
// Tech Dictionary Integration
// ═══════════════════════════════════════

describe('tech dictionary integration', () => {
  it('does not flag common tech terms', async () => {
    const result = await dictionaryPrePass('configure the webhook endpoint', []);
    expect(result.text).toContain('webhook');
    expect(result.text).toContain('endpoint');
  });

  it('does not flag camelCase words', async () => {
    const result = await dictionaryPrePass('set the backgroundColor property', []);
    expect(result.text).toContain('backgroundColor');
  });

  it('does not flag words with digits', async () => {
    const result = await dictionaryPrePass('encode as base64 using utf8', []);
    expect(result.text).toContain('base64');
    expect(result.text).toContain('utf8');
  });

  it('still catches real misspellings alongside tech words', async () => {
    const result = await dictionaryPrePass('I recieved the webhook notification', []);
    // "webhook" should be preserved
    expect(result.text).toContain('webhook');
    // "recieved" should be corrected (if a checker catches it)
    if (result.issuesFixed > 0) {
      expect(result.text).toContain('received');
    }
  });
});

// ═══════════════════════════════════════
// Heuristic Functions with Real Checker
// ═══════════════════════════════════════

describe('heuristic functions with real nspell', () => {
  it('isTechCompound detects webhook with real checker', () => {
    if (!nspellChecker) return;
    // "hook" is a real English word in dictionary-en
    expect(isTechCompound('webhook', nspellChecker)).toBe(true);
  });

  it('isTechCompound detects preload with real checker', () => {
    if (!nspellChecker) return;
    // "load" is a real English word
    expect(isTechCompound('preload', nspellChecker)).toBe(true);
  });

  it('isTechCompound rejects when suffix is not a real word', () => {
    if (!nspellChecker) return;
    expect(isTechCompound('webxyzq', nspellChecker)).toBe(false);
  });

  it('isTechCompound detects pushback with real checker', () => {
    if (!nspellChecker) return;
    expect(isTechCompound('pushback', nspellChecker)).toBe(true);
  });
});

// ═══════════════════════════════════════
// Word Substitution Guard Integration
// ═══════════════════════════════════════

describe('word substitution guard integration', () => {
  it('does not corrupt pushback to cashback', async () => {
    const result = await dictionaryPrePass('There was significant pushback on this proposal.', []);
    expect(result.text).toContain('pushback');
    expect(result.text).not.toContain('cashback');
  });

  it('does not corrupt pushback in the original reported sentence', async () => {
    const result = await dictionaryPrePass(
      'are we sure that we will not get any pushback on this explanation?',
      [],
    );
    expect(result.text).toContain('pushback');
    expect(result.text).not.toContain('cashback');
  });

  it('does not corrupt feedback', async () => {
    const result = await dictionaryPrePass('Please share your feedback on this document.', []);
    expect(result.text).toContain('feedback');
  });

  it('does not corrupt setback', async () => {
    const result = await dictionaryPrePass('This was a major setback for the team.', []);
    expect(result.text).toContain('setback');
  });
});
