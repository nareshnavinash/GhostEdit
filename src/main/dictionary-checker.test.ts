import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { SpellCheckIssue } from '../shared/types';

// ── Mocks ──

const mockLint = vi.fn();
const mockSetup = vi.fn().mockResolvedValue(undefined);

vi.mock('harper.js', () => ({
  LocalLinter: vi.fn().mockImplementation(function (this: any) {
    this.lint = mockLint;
    this.setup = mockSetup;
  }),
  binary: 'mock-binary',
  Dialect: { American: 0 },
}));

const mockCorrect = vi.fn((_word: string) => true);
const mockSuggest = vi.fn((_word: string): string[] => []);
const mockAdd = vi.fn((_word: string) => {});

vi.mock('nspell', () => ({
  default: vi.fn().mockImplementation(function (this: any) {
    this.correct = (w: string) => mockCorrect(w);
    this.suggest = (w: string) => mockSuggest(w);
    this.add = (w: string) => mockAdd(w);
  }),
}));

vi.mock('dictionary-en', () => ({
  default: vi.fn((cb: (err: Error | null, result: any) => void) =>
    cb(null, { aff: Buffer.from(''), dic: Buffer.from('') }),
  ),
}));

vi.mock('./data/tech-dictionary.txt?raw', () => ({
  default: 'webhook\nmicroservice\nkubernetes\n',
}));

// Helper to get a fresh module (resets module-level state)
async function freshModule() {
  vi.resetModules();
  vi.doMock('harper.js', () => ({
    LocalLinter: vi.fn().mockImplementation(function (this: any) {
      this.lint = mockLint;
      this.setup = mockSetup;
    }),
    binary: 'mock-binary',
    Dialect: { American: 0 },
  }));
  vi.doMock('nspell', () => ({
    default: vi.fn().mockImplementation(function (this: any) {
      this.correct = (w: string) => mockCorrect(w);
      this.suggest = (w: string) => mockSuggest(w);
      this.add = (w: string) => mockAdd(w);
    }),
  }));
  vi.doMock('dictionary-en', () => ({
    default: vi.fn((cb: (err: Error | null, result: any) => void) =>
      cb(null, { aff: Buffer.from(''), dic: Buffer.from('') }),
    ),
  }));
  vi.doMock('./data/tech-dictionary.txt?raw', () => ({
    default: 'webhook\nmicroservice\nkubernetes\n',
  }));
  return import('./dictionary-checker');
}

// Helper: create a mock Harper lint object
function makeLint(opts: {
  start: number;
  end: number;
  kind?: string;
  suggestions?: Array<{ kind: number; text: string | null }>;
}) {
  return {
    span: () => ({ start: opts.start, end: opts.end }),
    lint_kind: () => opts.kind ?? 'Spelling',
    message: () => 'mock message',
    suggestions: () =>
      (opts.suggestions ?? []).map((s) => ({
        kind: () => s.kind,
        get_replacement_text: () => s.text,
      })),
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockLint.mockReset();
  mockCorrect.mockImplementation(() => true);
  mockSuggest.mockImplementation(() => []);
  mockAdd.mockReset();
});

// ═══════════════════════════════════════
// getHarperIssues
// ═══════════════════════════════════════

describe('getHarperIssues', () => {
  it('returns empty array for text with no issues', async () => {
    const { getHarperIssues } = await freshModule();
    const linter = { lint: vi.fn().mockResolvedValue([]) };
    const issues = await getHarperIssues(linter, 'Hello world');
    expect(issues).toEqual([]);
  });

  it('extracts spelling issues with suggestions', async () => {
    const { getHarperIssues } = await freshModule();
    const lint = makeLint({
      start: 0, end: 3,
      kind: 'Spelling',
      suggestions: [{ kind: 0, text: 'the' }],
    });
    const linter = { lint: vi.fn().mockResolvedValue([lint]) };
    const issues = await getHarperIssues(linter, 'teh world');
    expect(issues).toHaveLength(1);
    expect(issues[0].word).toBe('teh');
    expect(issues[0].kind).toBe('spelling');
    expect(issues[0].suggestions).toEqual(['the']);
    expect(issues[0].source).toBe('harper');
    expect(issues[0].range).toEqual({ start: 0, end: 3 });
  });

  it('extracts grammar issues', async () => {
    const { getHarperIssues } = await freshModule();
    const lint = makeLint({
      start: 10, end: 11,
      kind: 'Capitalization',
      suggestions: [{ kind: 0, text: 'A' }],
    });
    const linter = { lint: vi.fn().mockResolvedValue([lint]) };
    const issues = await getHarperIssues(linter, 'This is a example.');
    expect(issues[0].kind).toBe('grammar');
  });

  it('handles "Remove" suggestions (kind=1) as empty string', async () => {
    const { getHarperIssues } = await freshModule();
    const lint = makeLint({
      start: 5, end: 9,
      kind: 'Grammar',
      suggestions: [{ kind: 1, text: null }],
    });
    const linter = { lint: vi.fn().mockResolvedValue([lint]) };
    const issues = await getHarperIssues(linter, 'Hello very world');
    expect(issues[0].suggestions).toEqual(['']);
  });

  it('skips lints with no suggestions', async () => {
    const { getHarperIssues } = await freshModule();
    const lint = makeLint({ start: 0, end: 3, suggestions: [] });
    const linter = { lint: vi.fn().mockResolvedValue([lint]) };
    const issues = await getHarperIssues(linter, 'teh world');
    expect(issues).toEqual([]);
  });

  it('maps span positions correctly', async () => {
    const { getHarperIssues } = await freshModule();
    // 'Hello this wrold end' — 'wrold' starts at index 11, ends at 16
    const lint = makeLint({
      start: 11, end: 16,
      suggestions: [{ kind: 0, text: 'world' }],
    });
    const linter = { lint: vi.fn().mockResolvedValue([lint]) };
    const issues = await getHarperIssues(linter, 'Hello this wrold end');
    expect(issues[0].range).toEqual({ start: 11, end: 16 });
    expect(issues[0].word).toBe('wrold');
  });

  it('handles multiple lints', async () => {
    const { getHarperIssues } = await freshModule();
    const lints = [
      makeLint({ start: 0, end: 3, suggestions: [{ kind: 0, text: 'the' }] }),
      makeLint({ start: 4, end: 9, suggestions: [{ kind: 0, text: 'quick' }] }),
    ];
    const linter = { lint: vi.fn().mockResolvedValue(lints) };
    const issues = await getHarperIssues(linter, 'teh quikc fox');
    expect(issues).toHaveLength(2);
  });
});

// ═══════════════════════════════════════
// getNspellIssues
// ═══════════════════════════════════════

describe('getNspellIssues', () => {
  it('returns empty array when all words are correct', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockReturnValue(true);
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'Hello world');
    expect(issues).toEqual([]);
  });

  it('identifies misspelled words', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockImplementation((w) => w !== 'teh');
    mockSuggest.mockImplementation((w) => (w === 'teh' ? ['the'] : []));
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'teh world');
    expect(issues).toHaveLength(1);
    expect(issues[0].word).toBe('teh');
    expect(issues[0].suggestions).toEqual(['the']);
    expect(issues[0].kind).toBe('spelling');
    expect(issues[0].source).toBe('nspell');
  });

  it('calculates correct character ranges', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockImplementation((w) => w !== 'teh');
    mockSuggest.mockImplementation((w) => (w === 'teh' ? ['the'] : []));
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'Hello teh world');
    expect(issues[0].range).toEqual({ start: 6, end: 9 });
  });

  it('skips single-character words', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockReturnValue(false);
    mockSuggest.mockReturnValue(['a']);
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'I a');
    expect(issues).toEqual([]);
  });

  it('caps suggestions at 5', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockImplementation((w) => w !== 'wrld');
    mockSuggest.mockReturnValue(['world', 'wield', 'wild', 'weld', 'ward', 'word', 'weird']);
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'wrld');
    expect(issues[0].suggestions).toHaveLength(5);
  });

  it('skips words with no suggestions', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockReturnValue(false);
    mockSuggest.mockReturnValue([]);
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'xyzzy');
    expect(issues).toEqual([]);
  });

  it('handles multiple misspelled words', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockImplementation((w) => !['teh', 'wrld'].includes(w));
    mockSuggest.mockImplementation((w) => {
      if (w === 'teh') return ['the'];
      if (w === 'wrld') return ['world'];
      return [];
    });
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'teh wrld');
    expect(issues).toHaveLength(2);
    expect(issues[0].word).toBe('teh');
    expect(issues[1].word).toBe('wrld');
  });
});

// ═══════════════════════════════════════
// mergeIssues
// ═══════════════════════════════════════

describe('mergeIssues', () => {
  const harper = (start: number, end: number): SpellCheckIssue => ({
    word: 'x', range: { start, end }, kind: 'spelling', suggestions: ['y'], source: 'harper',
  });
  const nspell = (start: number, end: number): SpellCheckIssue => ({
    word: 'x', range: { start, end }, kind: 'spelling', suggestions: ['y'], source: 'nspell',
  });

  it('returns all Harper issues when no nspell issues', async () => {
    const { mergeIssues } = await freshModule();
    const result = mergeIssues([harper(0, 4), harper(10, 14)], []);
    expect(result).toHaveLength(2);
  });

  it('returns all nspell issues when no Harper issues', async () => {
    const { mergeIssues } = await freshModule();
    const result = mergeIssues([], [nspell(0, 4), nspell(10, 14)]);
    expect(result).toHaveLength(2);
  });

  it('keeps non-overlapping nspell issues', async () => {
    const { mergeIssues } = await freshModule();
    const result = mergeIssues([harper(0, 4)], [nspell(10, 14)]);
    expect(result).toHaveLength(2);
  });

  it('drops nspell issues that overlap Harper issues', async () => {
    const { mergeIssues } = await freshModule();
    const result = mergeIssues([harper(5, 10)], [nspell(7, 12)]);
    expect(result).toHaveLength(1);
    expect(result[0].source).toBe('harper');
  });

  it('handles exact range overlap', async () => {
    const { mergeIssues } = await freshModule();
    const result = mergeIssues([harper(5, 10)], [nspell(5, 10)]);
    expect(result).toHaveLength(1);
    expect(result[0].source).toBe('harper');
  });

  it('handles partial overlap (nspell starts inside Harper)', async () => {
    const { mergeIssues } = await freshModule();
    const result = mergeIssues([harper(5, 10)], [nspell(8, 13)]);
    expect(result).toHaveLength(1);
    expect(result[0].source).toBe('harper');
  });

  it('keeps nspell issue adjacent but not overlapping', async () => {
    const { mergeIssues } = await freshModule();
    const result = mergeIssues([harper(5, 10)], [nspell(10, 15)]);
    expect(result).toHaveLength(2);
  });
});

// ═══════════════════════════════════════
// filterProtectedTokenOverlaps
// ═══════════════════════════════════════

describe('filterProtectedTokenOverlaps', () => {
  const issue = (start: number, end: number): SpellCheckIssue => ({
    word: 'x', range: { start, end }, kind: 'spelling', suggestions: ['y'], source: 'harper',
  });

  it('returns all issues when no protected ranges', async () => {
    const { filterProtectedTokenOverlaps } = await freshModule();
    const result = filterProtectedTokenOverlaps([issue(0, 4), issue(10, 14)], []);
    expect(result).toHaveLength(2);
  });

  it('filters issues inside protected ranges', async () => {
    const { filterProtectedTokenOverlaps } = await freshModule();
    const result = filterProtectedTokenOverlaps([issue(10, 14)], [{ start: 8, end: 20 }]);
    expect(result).toHaveLength(0);
  });

  it('keeps issues outside protected ranges', async () => {
    const { filterProtectedTokenOverlaps } = await freshModule();
    const result = filterProtectedTokenOverlaps([issue(0, 4)], [{ start: 10, end: 20 }]);
    expect(result).toHaveLength(1);
  });

  it('handles partial overlap', async () => {
    const { filterProtectedTokenOverlaps } = await freshModule();
    const result = filterProtectedTokenOverlaps([issue(8, 12)], [{ start: 10, end: 20 }]);
    expect(result).toHaveLength(0);
  });

  it('handles empty issues array', async () => {
    const { filterProtectedTokenOverlaps } = await freshModule();
    const result = filterProtectedTokenOverlaps([], [{ start: 0, end: 10 }]);
    expect(result).toEqual([]);
  });
});

// ═══════════════════════════════════════
// filterProperNounsAndAcronyms
// ═══════════════════════════════════════

describe('filterProperNounsAndAcronyms', () => {
  const spelling = (word: string, start: number): SpellCheckIssue => ({
    word, range: { start, end: start + word.length }, kind: 'spelling', suggestions: ['x'], source: 'nspell',
  });
  const grammar = (word: string, start: number): SpellCheckIssue => ({
    word, range: { start, end: start + word.length }, kind: 'grammar', suggestions: ['x'], source: 'harper',
  });

  it('filters acronyms (2+ uppercase)', async () => {
    const { filterProperNounsAndAcronyms } = await freshModule();
    const result = filterProperNounsAndAcronyms(
      [spelling('NASA', 6)],
      'I saw NASA yesterday',
    );
    expect(result).toHaveLength(0);
  });

  it('keeps lowercase misspellings', async () => {
    const { filterProperNounsAndAcronyms } = await freshModule();
    const result = filterProperNounsAndAcronyms(
      [spelling('teh', 0)],
      'teh quick fox',
    );
    expect(result).toHaveLength(1);
  });

  it('filters capitalized mid-sentence words (proper nouns)', async () => {
    const { filterProperNounsAndAcronyms } = await freshModule();
    const result = filterProperNounsAndAcronyms(
      [spelling('Naresh', 6)],
      'I saw Naresh yesterday',
    );
    expect(result).toHaveLength(0);
  });

  it('keeps capitalized words at sentence start', async () => {
    const { filterProperNounsAndAcronyms } = await freshModule();
    const result = filterProperNounsAndAcronyms(
      [spelling('Teh', 0)],
      'Teh quick fox',
    );
    expect(result).toHaveLength(1);
  });

  it('keeps capitalized words after sentence-ending punctuation', async () => {
    const { filterProperNounsAndAcronyms } = await freshModule();
    const result = filterProperNounsAndAcronyms(
      [spelling('Naresh', 7)],
      'Hello. Naresh is here.',
    );
    expect(result).toHaveLength(1);
  });

  it('does not filter grammar issues on capitalized words', async () => {
    const { filterProperNounsAndAcronyms } = await freshModule();
    const result = filterProperNounsAndAcronyms(
      [grammar('Naresh', 6)],
      'I saw Naresh yesterday',
    );
    expect(result).toHaveLength(1);
  });

  it('handles single uppercase letter (not acronym)', async () => {
    const { filterProperNounsAndAcronyms } = await freshModule();
    const result = filterProperNounsAndAcronyms(
      [spelling('I', 5)],
      'Then I went.',
    );
    // 'I' is length 1, so it passes the /^[A-Z]{2,}$/ filter and is kept
    expect(result).toHaveLength(1);
  });
});

// ═══════════════════════════════════════
// applyFixes
// ═══════════════════════════════════════

describe('applyFixes', () => {
  const issue = (word: string, start: number, suggestion: string): SpellCheckIssue => ({
    word,
    range: { start, end: start + word.length },
    kind: 'spelling',
    suggestions: [suggestion],
    source: 'harper',
  });

  it('returns unchanged text for empty issues', async () => {
    const { applyFixes } = await freshModule();
    const result = applyFixes('Hello world', []);
    expect(result).toEqual({ text: 'Hello world', fixCount: 0 });
  });

  it('applies single fix', async () => {
    const { applyFixes } = await freshModule();
    const result = applyFixes('teh world', [issue('teh', 0, 'the')]);
    expect(result.text).toBe('the world');
    expect(result.fixCount).toBe(1);
  });

  it('applies multiple non-overlapping fixes', async () => {
    const { applyFixes } = await freshModule();
    const result = applyFixes('teh wrld', [
      issue('teh', 0, 'the'),
      issue('wrld', 4, 'world'),
    ]);
    expect(result.text).toBe('the world');
    expect(result.fixCount).toBe(2);
  });

  it('skips fix when word no longer matches at expected position', async () => {
    const { applyFixes } = await freshModule();
    // The word at position 0..3 is "teh", but we claim it's "foo"
    const badIssue: SpellCheckIssue = {
      word: 'foo', range: { start: 0, end: 3 },
      kind: 'spelling', suggestions: ['bar'], source: 'harper',
    };
    const result = applyFixes('teh world', [badIssue]);
    expect(result.text).toBe('teh world');
    expect(result.fixCount).toBe(0);
  });

  it('handles fix that changes text length', async () => {
    const { applyFixes } = await freshModule();
    const result = applyFixes('dont do that', [issue('dont', 0, "don't")]);
    expect(result.text).toBe("don't do that");
    expect(result.fixCount).toBe(1);
  });

  it('applies fixes in reverse position order', async () => {
    const { applyFixes } = await freshModule();
    // Both fixes should work even though the second one changes text length
    const result = applyFixes('I recieve teh email', [
      issue('recieve', 2, 'receive'),
      issue('teh', 10, 'the'),
    ]);
    expect(result.text).toBe('I receive the email');
    expect(result.fixCount).toBe(2);
  });

  it('handles empty string suggestion (removal)', async () => {
    const { applyFixes } = await freshModule();
    const result = applyFixes('Hello  world', [
      { word: ' ', range: { start: 5, end: 6 }, kind: 'style', suggestions: [''], source: 'harper' },
    ]);
    expect(result.text).toBe('Hello world');
    expect(result.fixCount).toBe(1);
  });
});

// ═══════════════════════════════════════
// dictionaryPrePass (end-to-end with mocks)
// ═══════════════════════════════════════

describe('dictionaryPrePass', () => {
  it('returns unchanged text when both checkers failed to load', async () => {
    vi.resetModules();
    vi.doMock('harper.js', () => { throw new Error('no harper'); });
    vi.doMock('nspell', () => { throw new Error('no nspell'); });
    vi.doMock('dictionary-en', () => ({
      default: vi.fn((cb: any) => cb(new Error('no dict'))),
    }));
    vi.doMock('./data/tech-dictionary.txt?raw', () => ({
      default: 'webhook\nmicroservice\nkubernetes\n',
    }));
    const mod = await import('./dictionary-checker');
    await mod.ensureDictionaryCheckersLoaded();
    const result = await mod.dictionaryPrePass('Hello world', []);
    expect(result.text).toBe('Hello world');
    expect(result.issuesFixed).toBe(0);
    expect(result.passes).toBe(0);
  });

  it('fixes text in single pass when issues found', async () => {
    const mod = await freshModule();
    // Set up Harper to find one issue
    mockLint.mockResolvedValue([
      makeLint({ start: 0, end: 3, suggestions: [{ kind: 0, text: 'the' }] }),
    ]);
    await mod.ensureDictionaryCheckersLoaded();
    const result = await mod.dictionaryPrePass('teh world', []);
    expect(result.text).toBe('the world');
    expect(result.issuesFixed).toBe(1);
    expect(result.passes).toBeGreaterThanOrEqual(1);
  });

  it('stops early when no fixes in a pass', async () => {
    const mod = await freshModule();
    mockLint.mockResolvedValue([]);
    await mod.ensureDictionaryCheckersLoaded();
    const result = await mod.dictionaryPrePass('Hello world', []);
    expect(result.text).toBe('Hello world');
    expect(result.issuesFixed).toBe(0);
    expect(result.passes).toBe(1);
  });

  it('preserves protected token ranges', async () => {
    const mod = await freshModule();
    // Harper flags position 4..7 which is inside a protected range
    mockLint.mockResolvedValue([
      makeLint({ start: 4, end: 7, suggestions: [{ kind: 0, text: 'fix' }] }),
    ]);
    await mod.ensureDictionaryCheckersLoaded();
    const result = await mod.dictionaryPrePass('xxx teh yyy', [{ start: 3, end: 8 }]);
    // The issue overlaps the protected range, so it should NOT be fixed
    expect(result.text).toBe('xxx teh yyy');
    expect(result.issuesFixed).toBe(0);
  });

  it('gracefully degrades with only nspell available', async () => {
    vi.resetModules();
    vi.doMock('harper.js', () => { throw new Error('no harper'); });
    vi.doMock('nspell', () => ({
      default: vi.fn().mockImplementation(function (this: any) {
        this.correct = (w: string) => mockCorrect(w);
        this.suggest = (w: string) => mockSuggest(w);
        this.add = (w: string) => mockAdd(w);
      }),
    }));
    vi.doMock('dictionary-en', () => ({
      default: vi.fn((cb: (err: Error | null, result: any) => void) =>
        cb(null, { aff: Buffer.from(''), dic: Buffer.from('') }),
      ),
    }));
    vi.doMock('./data/tech-dictionary.txt?raw', () => ({
      default: 'webhook\nmicroservice\nkubernetes\n',
    }));
    mockCorrect.mockImplementation((w) => w !== 'teh');
    mockSuggest.mockImplementation((w) => (w === 'teh' ? ['the'] : []));

    const mod = await import('./dictionary-checker');
    await mod.ensureDictionaryCheckersLoaded();
    const result = await mod.dictionaryPrePass('teh world', []);
    expect(result.text).toBe('the world');
    expect(result.issuesFixed).toBe(1);
  });
});

// ═══════════════════════════════════════
// dictionaryPolish
// ═══════════════════════════════════════

describe('dictionaryPolish', () => {
  it('fixes errors in model output', async () => {
    const mod = await freshModule();
    mockLint.mockResolvedValue([
      makeLint({ start: 0, end: 3, suggestions: [{ kind: 0, text: 'the' }] }),
    ]);
    await mod.ensureDictionaryCheckersLoaded();
    const result = await mod.dictionaryPolish('teh corrected text', []);
    expect(result.text).toBe('the corrected text');
  });

  it('does not correct words inside restored token ranges', async () => {
    const mod = await freshModule();
    // nspell flags "eng" from "#eng-development" and suggests "egg"
    mockCorrect.mockImplementation((w) => w !== 'eng');
    mockSuggest.mockImplementation((w) => (w === 'eng' ? ['egg'] : []));
    mockLint.mockResolvedValue([]);
    await mod.ensureDictionaryCheckersLoaded();

    // Protected range covers the entire "#eng-development" token
    const text = 'post in #eng-development channel';
    const protectedRanges = [{ start: 8, end: 24 }]; // "#eng-development"
    const result = await mod.dictionaryPolish(text, protectedRanges);
    expect(result.text).toBe(text); // unchanged
  });
});

// ═══════════════════════════════════════
// Initialization
// ═══════════════════════════════════════

describe('initialization', () => {
  it('preWarmDictionaryChecker fires without blocking', async () => {
    const mod = await freshModule();
    // Should not throw
    mod.preWarmDictionaryChecker();
  });

  it('ensureDictionaryCheckersLoaded is idempotent', async () => {
    const mod = await freshModule();
    await mod.ensureDictionaryCheckersLoaded();
    await mod.ensureDictionaryCheckersLoaded();
    // No error, initialization ran only needed times
  });

  it('handles Harper init failure gracefully', async () => {
    vi.resetModules();
    vi.doMock('harper.js', () => { throw new Error('Harper WASM failed'); });
    vi.doMock('nspell', () => ({
      default: vi.fn().mockImplementation(() => ({
        correct: (w: string) => mockCorrect(w),
        suggest: (w: string) => mockSuggest(w),
        add: (w: string) => mockAdd(w),
      })),
    }));
    vi.doMock('dictionary-en', () => ({
      default: vi.fn((cb: (err: Error | null, result: any) => void) =>
        cb(null, { aff: Buffer.from(''), dic: Buffer.from('') }),
      ),
    }));
    vi.doMock('./data/tech-dictionary.txt?raw', () => ({
      default: 'webhook\nmicroservice\nkubernetes\n',
    }));

    const mod = await import('./dictionary-checker');
    // Should not throw
    await mod.ensureDictionaryCheckersLoaded();
    // Should still work with nspell only
    mockCorrect.mockReturnValue(true);
    const result = await mod.dictionaryPrePass('Hello', []);
    expect(result.text).toBe('Hello');
  });

  it('handles nspell init failure gracefully', async () => {
    vi.resetModules();
    vi.doMock('harper.js', () => ({
      LocalLinter: vi.fn().mockImplementation(function (this: any) {
        this.lint = mockLint;
        this.setup = mockSetup;
      }),
      binary: 'mock-binary',
      Dialect: { American: 0 },
    }));
    vi.doMock('nspell', () => { throw new Error('nspell failed'); });
    vi.doMock('dictionary-en', () => ({
      default: vi.fn((cb: (err: Error | null, result: any) => void) =>
        cb(new Error('dict failed'), null),
      ),
    }));
    vi.doMock('./data/tech-dictionary.txt?raw', () => ({
      default: 'webhook\nmicroservice\nkubernetes\n',
    }));

    const mod = await import('./dictionary-checker');
    // Should not throw
    await mod.ensureDictionaryCheckersLoaded();
    // Should still work with Harper only
    mockLint.mockResolvedValue([]);
    const result = await mod.dictionaryPrePass('Hello', []);
    expect(result.text).toBe('Hello');
  });
});

// ═══════════════════════════════════════
// isCamelCase
// ═══════════════════════════════════════

describe('isCamelCase', () => {
  it('detects camelCase words', async () => {
    const { isCamelCase } = await freshModule();
    expect(isCamelCase('backgroundColor')).toBe(true);
    expect(isCamelCase('userId')).toBe(true);
    expect(isCamelCase('onClick')).toBe(true);
  });

  it('rejects non-camelCase words', async () => {
    const { isCamelCase } = await freshModule();
    expect(isCamelCase('webhook')).toBe(false);
    expect(isCamelCase('ALLCAPS')).toBe(false);
    expect(isCamelCase('PascalCase')).toBe(false);
    expect(isCamelCase('hello')).toBe(false);
  });
});

// ═══════════════════════════════════════
// hasEmbeddedDigits
// ═══════════════════════════════════════

describe('hasEmbeddedDigits', () => {
  it('detects words with embedded digits', async () => {
    const { hasEmbeddedDigits } = await freshModule();
    expect(hasEmbeddedDigits('utf8')).toBe(true);
    expect(hasEmbeddedDigits('base64')).toBe(true);
    expect(hasEmbeddedDigits('h264')).toBe(true);
    expect(hasEmbeddedDigits('3d')).toBe(true);
  });

  it('rejects pure letter words', async () => {
    const { hasEmbeddedDigits } = await freshModule();
    expect(hasEmbeddedDigits('hello')).toBe(false);
    expect(hasEmbeddedDigits('webhook')).toBe(false);
  });
});

// ═══════════════════════════════════════
// isTechCompound
// ═══════════════════════════════════════

describe('isTechCompound', () => {
  it('detects tech compound words', async () => {
    const { isTechCompound } = await freshModule();
    // "hook" and "service" pass checker.correct() since mock returns true by default
    mockCorrect.mockReturnValue(true);
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    expect(isTechCompound('webhook', checker)).toBe(true);
    expect(isTechCompound('microservice', checker)).toBe(true);
    expect(isTechCompound('preload', checker)).toBe(true);
  });

  it('rejects when suffix is not a real word', async () => {
    const { isTechCompound } = await freshModule();
    mockCorrect.mockReturnValue(false);
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    expect(isTechCompound('webxyz', checker)).toBe(false);
  });

  it('rejects when suffix is less than 3 chars', async () => {
    const { isTechCompound } = await freshModule();
    mockCorrect.mockReturnValue(true);
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    // "webit" has suffix "it" which is only 2 chars
    expect(isTechCompound('webit', checker)).toBe(false);
  });

  it('rejects words that do not start with a compound prefix', async () => {
    const { isTechCompound } = await freshModule();
    mockCorrect.mockReturnValue(true);
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    expect(isTechCompound('something', checker)).toBe(false);
  });

  it('detects compound words with common English prefixes', async () => {
    const { isTechCompound } = await freshModule();
    mockCorrect.mockReturnValue(true);
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    expect(isTechCompound('pushback', checker)).toBe(true);
    expect(isTechCompound('fallback', checker)).toBe(true);
    expect(isTechCompound('callback', checker)).toBe(true);
    expect(isTechCompound('kickback', checker)).toBe(true);
    expect(isTechCompound('setback', checker)).toBe(true);
  });
});

// ═══════════════════════════════════════
// levenshteinDistance
// ═══════════════════════════════════════

describe('levenshteinDistance', () => {
  it('returns 0 for identical strings', async () => {
    const { levenshteinDistance } = await freshModule();
    expect(levenshteinDistance('hello', 'hello')).toBe(0);
  });

  it('computes distance for single substitution', async () => {
    const { levenshteinDistance } = await freshModule();
    expect(levenshteinDistance('teh', 'the')).toBe(2);
  });

  it('computes distance for pushback vs cashback', async () => {
    const { levenshteinDistance } = await freshModule();
    expect(levenshteinDistance('pushback', 'cashback')).toBe(2);
  });

  it('computes distance for insertion/deletion', async () => {
    const { levenshteinDistance } = await freshModule();
    expect(levenshteinDistance('dont', "don't")).toBe(1);
  });

  it('handles empty strings', async () => {
    const { levenshteinDistance } = await freshModule();
    expect(levenshteinDistance('', 'abc')).toBe(3);
    expect(levenshteinDistance('abc', '')).toBe(3);
    expect(levenshteinDistance('', '')).toBe(0);
  });
});

// ═══════════════════════════════════════
// isSafeNspellSuggestion
// ═══════════════════════════════════════

describe('isSafeNspellSuggestion', () => {
  it('rejects pushback -> cashback (first 2 chars differ)', async () => {
    const { isSafeNspellSuggestion } = await freshModule();
    expect(isSafeNspellSuggestion('pushback', 'cashback')).toBe(false);
  });

  it('allows teh -> the (first char matches)', async () => {
    const { isSafeNspellSuggestion } = await freshModule();
    expect(isSafeNspellSuggestion('teh', 'the')).toBe(true);
  });

  it('allows recieve -> receive (first char matches)', async () => {
    const { isSafeNspellSuggestion } = await freshModule();
    expect(isSafeNspellSuggestion('recieve', 'receive')).toBe(true);
  });

  it('allows thier -> their (first char matches)', async () => {
    const { isSafeNspellSuggestion } = await freshModule();
    expect(isSafeNspellSuggestion('thier', 'their')).toBe(true);
  });

  it('allows dont -> don\'t (first char matches)', async () => {
    const { isSafeNspellSuggestion } = await freshModule();
    expect(isSafeNspellSuggestion('dont', "don't")).toBe(true);
  });

  it('allows colour -> color (first char matches)', async () => {
    const { isSafeNspellSuggestion } = await freshModule();
    expect(isSafeNspellSuggestion('colour', 'color')).toBe(true);
  });

  it('rejects suggestions with excessive edit distance', async () => {
    const { isSafeNspellSuggestion } = await freshModule();
    expect(isSafeNspellSuggestion('cat', 'elephant')).toBe(false);
  });

  it('rejects suggestions with excessive length difference', async () => {
    const { isSafeNspellSuggestion } = await freshModule();
    expect(isSafeNspellSuggestion('run', 'running')).toBe(false);
  });
});

// ═══════════════════════════════════════
// applyFixes — nspell guard
// ═══════════════════════════════════════

describe('applyFixes nspell guard', () => {
  it('blocks unsafe nspell suggestion (pushback -> cashback)', async () => {
    const { applyFixes } = await freshModule();
    const issue: SpellCheckIssue = {
      word: 'pushback',
      range: { start: 15, end: 23 },
      kind: 'spelling',
      suggestions: ['cashback'],
      source: 'nspell',
    };
    const result = applyFixes('there was some pushback on this', [issue]);
    expect(result.text).toContain('pushback');
    expect(result.text).not.toContain('cashback');
    expect(result.fixCount).toBe(0);
  });

  it('allows safe nspell suggestion (teh -> the)', async () => {
    const { applyFixes } = await freshModule();
    const issue: SpellCheckIssue = {
      word: 'teh',
      range: { start: 0, end: 3 },
      kind: 'spelling',
      suggestions: ['the'],
      source: 'nspell',
    };
    const result = applyFixes('teh world', [issue]);
    expect(result.text).toBe('the world');
    expect(result.fixCount).toBe(1);
  });

  it('does not guard harper suggestions', async () => {
    const { applyFixes } = await freshModule();
    const issue: SpellCheckIssue = {
      word: 'pushback',
      range: { start: 15, end: 23 },
      kind: 'spelling',
      suggestions: ['cashback'],
      source: 'harper',
    };
    // Harper is context-aware, so its suggestions are trusted
    const result = applyFixes('there was some pushback on this', [issue]);
    expect(result.text).toContain('cashback');
    expect(result.fixCount).toBe(1);
  });
});

// ═══════════════════════════════════════
// getNspellIssues — heuristic skips
// ═══════════════════════════════════════

describe('getNspellIssues heuristic skips', () => {
  it('skips camelCase words', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockImplementation((w) => w !== 'backgroundColor');
    mockSuggest.mockImplementation((w) => (w === 'backgroundColor' ? ['background'] : []));
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'set backgroundColor here');
    expect(issues.find((i) => i.word === 'backgroundColor')).toBeUndefined();
  });

  it('skips words with embedded digits', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockImplementation((w) => !['base64', 'utf8'].includes(w));
    mockSuggest.mockImplementation((w) => {
      if (w === 'base64') return ['based'];
      if (w === 'utf8') return ['utf'];
      return [];
    });
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'encode as base64 using utf8');
    expect(issues.find((i) => i.word === 'base64')).toBeUndefined();
    expect(issues.find((i) => i.word === 'utf8')).toBeUndefined();
  });

  it('skips tech compound words', async () => {
    const { getNspellIssues } = await freshModule();
    // "webhook" is not correct, but suffix "hook" is correct
    mockCorrect.mockImplementation((w) => {
      if (w === 'webhook') return false;
      if (w === 'hook') return true;
      return true;
    });
    mockSuggest.mockImplementation((w) => (w === 'webhook' ? ['webfoot'] : []));
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'configure the webhook');
    expect(issues.find((i) => i.word === 'webhook')).toBeUndefined();
  });

  it('still catches real misspellings', async () => {
    const { getNspellIssues } = await freshModule();
    // "recieved" is not correct; "cieved" is also not a real word so isTechCompound won't match
    mockCorrect.mockImplementation((w) => !['recieved', 'cieved'].includes(w));
    mockSuggest.mockImplementation((w) => (w === 'recieved' ? ['received'] : []));
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'I recieved the email');
    expect(issues.find((i) => i.word === 'recieved')).toBeDefined();
  });

  it('skips words inside kebab-case identifiers', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockImplementation((w) => !['nxt'].includes(w));
    mockSuggest.mockImplementation((w) => (w === 'nxt' ? ['next'] : []));
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'check nxt-backend for updates');
    expect(issues.find((i) => i.word === 'nxt')).toBeUndefined();
  });

  it('skips words inside snake_case identifiers', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockImplementation((w) => !['nxt'].includes(w));
    mockSuggest.mockImplementation((w) => (w === 'nxt' ? ['next'] : []));
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'set nxt_backend as target');
    expect(issues.find((i) => i.word === 'nxt')).toBeUndefined();
  });

  it('skips PascalCase words', async () => {
    const { getNspellIssues } = await freshModule();
    mockCorrect.mockImplementation((w) => !['StringBuilder'].includes(w));
    mockSuggest.mockImplementation((w) => (w === 'StringBuilder' ? ['string'] : []));
    const checker = { correct: mockCorrect, suggest: mockSuggest };
    const issues = getNspellIssues(checker, 'StringBuilder is useful');
    expect(issues.find((i) => i.word === 'StringBuilder')).toBeUndefined();
  });
});

// ═══════════════════════════════════════
// isPascalCase
// ═══════════════════════════════════════

describe('isPascalCase', () => {
  it('detects PascalCase words', async () => {
    const { isPascalCase } = await freshModule();
    expect(isPascalCase('StringBuilder')).toBe(true);
    expect(isPascalCase('HttpClient')).toBe(true);
    expect(isPascalCase('MyComponent')).toBe(true);
  });

  it('rejects non-PascalCase words', async () => {
    const { isPascalCase } = await freshModule();
    expect(isPascalCase('hello')).toBe(false);
    expect(isPascalCase('ALLCAPS')).toBe(false);
    expect(isPascalCase('camelCase')).toBe(false);
    expect(isPascalCase('Proper')).toBe(false);
  });
});

// ═══════════════════════════════════════
// getCompoundIdentifierRanges
// ═══════════════════════════════════════

describe('getCompoundIdentifierRanges', () => {
  it('detects kebab-case identifiers', async () => {
    const { getCompoundIdentifierRanges } = await freshModule();
    const ranges = getCompoundIdentifierRanges('use my-component here');
    expect(ranges).toHaveLength(1);
    expect(ranges[0]).toEqual({ start: 4, end: 16 });
  });

  it('detects snake_case identifiers', async () => {
    const { getCompoundIdentifierRanges } = await freshModule();
    const ranges = getCompoundIdentifierRanges('set max_retries to 5');
    expect(ranges).toHaveLength(1);
    expect(ranges[0]).toEqual({ start: 4, end: 15 });
  });

  it('detects multiple compound identifiers', async () => {
    const { getCompoundIdentifierRanges } = await freshModule();
    const ranges = getCompoundIdentifierRanges('use my-component and user_name');
    expect(ranges).toHaveLength(2);
  });

  it('returns empty for plain text', async () => {
    const { getCompoundIdentifierRanges } = await freshModule();
    const ranges = getCompoundIdentifierRanges('hello world');
    expect(ranges).toHaveLength(0);
  });
});
