import { describe, it, expect } from 'vitest';
import {
  protectTokens,
  restoreTokens,
  bestEffortRestore,
  placeholdersAreIntact,
  getPlaceholderRanges,
  getOriginalTokenRanges,
  stripLeakedPlaceholders,
} from './token-preservation';

// ── protectTokens ──

describe('protectTokens', () => {
  it('returns text unchanged when no special tokens exist', () => {
    const result = protectTokens('hello world');
    expect(result.protectedText).toBe('hello world');
    expect(result.tokens).toHaveLength(0);
    expect(result.hasProtectedTokens).toBe(false);
  });

  it('protects @mentions', () => {
    const result = protectTokens('hey @Manoj check this');
    expect(result.protectedText).toContain('[K');
    expect(result.protectedText).not.toContain('@Manoj');
    expect(result.tokens).toHaveLength(1);
    expect(result.tokens[0].originalToken).toBe('@Manoj');
  });

  it('protects Slack-style emoji :name:', () => {
    const result = protectTokens('great job :think:');
    expect(result.protectedText).not.toContain(':think:');
    expect(result.tokens.some((t) => t.originalToken === ':think:')).toBe(true);
  });

  it('protects URLs', () => {
    const result = protectTokens('see https://example.com/path for details');
    expect(result.tokens.some((t) => t.originalToken.startsWith('https://'))).toBe(true);
  });

  it('protects email addresses', () => {
    const result = protectTokens('email me at user@example.com please');
    expect(result.tokens.some((t) => t.originalToken === 'user@example.com')).toBe(true);
  });

  it('protects inline code', () => {
    const result = protectTokens('run `npm install` first');
    expect(result.tokens.some((t) => t.originalToken === '`npm install`')).toBe(true);
  });

  it('protects file paths', () => {
    const result = protectTokens('edit /usr/local/bin/node');
    expect(result.tokens.some((t) => t.originalToken === '/usr/local/bin/node')).toBe(true);
  });

  it('assigns sequential placeholder numbers for multiple tokens', () => {
    const result = protectTokens('@Alice and @Bob said :thumbsup:');
    expect(result.tokens.length).toBeGreaterThanOrEqual(3);
    for (let i = 0; i < result.tokens.length; i++) {
      expect(result.tokens[i].placeholder).toBe(`[K${i}]`);
    }
  });

  it('does not double-match overlapping patterns', () => {
    const result = protectTokens('check user@example.com now');
    // Email should be matched once, not also as @example mention
    const emailTokens = result.tokens.filter((t) => t.originalToken.includes('@example'));
    expect(emailTokens).toHaveLength(1);
  });
});

// ── restoreTokens ──

describe('restoreTokens', () => {
  it('restores a single placeholder', () => {
    const protection = protectTokens('hello @World');
    const restored = restoreTokens(protection.protectedText, protection.tokens);
    expect(restored).toBe('hello @World');
  });

  it('restores multiple placeholders', () => {
    const protection = protectTokens('@Alice and :wave: at https://example.com');
    const restored = restoreTokens(protection.protectedText, protection.tokens);
    expect(restored).toBe('@Alice and :wave: at https://example.com');
  });

  it('restores duplicated placeholders (replaceAll regression)', () => {
    const protection = protectTokens('hello @Manoj');
    // Simulate model duplicating the placeholder
    const duplicated = `${protection.protectedText} ${protection.tokens[0].placeholder}`;
    const restored = restoreTokens(duplicated, protection.tokens);
    expect(restored).not.toContain('[K');
    expect(restored).toContain('@Manoj');
  });

  it('returns text unchanged when no placeholders present', () => {
    const restored = restoreTokens('hello world', []);
    expect(restored).toBe('hello world');
  });
});

// ── bestEffortRestore ──

describe('bestEffortRestore', () => {
  it('restores surviving placeholders', () => {
    const protection = protectTokens('@Alice said :wave:');
    // Keep only first placeholder, drop the second
    const mangled = protection.protectedText.replace(protection.tokens[1].placeholder, 'GONE');
    const restored = bestEffortRestore(mangled, protection.tokens);
    expect(restored).toContain(protection.tokens[0].originalToken);
    expect(restored).not.toContain(protection.tokens[0].placeholder);
  });

  it('restores duplicated placeholders (replaceAll regression)', () => {
    const protection = protectTokens(':fire:');
    const duplicated = `${protection.protectedText} extra ${protection.tokens[0].placeholder}`;
    const restored = bestEffortRestore(duplicated, protection.tokens);
    expect(restored).not.toContain('[K');
  });

  it('returns text unchanged when no placeholders match', () => {
    const result = bestEffortRestore('no placeholders here', [
      { placeholder: '[K99]', originalToken: '@nobody' },
    ]);
    expect(result).toBe('no placeholders here');
  });

  it('restores partial set of surviving placeholders', () => {
    const protection = protectTokens('@A and @B and @C');
    // Remove placeholder for @B
    const partial = protection.protectedText.replace(protection.tokens[1].placeholder, 'missing');
    const restored = bestEffortRestore(partial, protection.tokens);
    expect(restored).toContain('@A');
    expect(restored).toContain('@C');
    expect(restored).toContain('missing');
  });
});

// ── placeholdersAreIntact ──

describe('placeholdersAreIntact', () => {
  it('returns true when all placeholders are present', () => {
    const protection = protectTokens('@Alice :wave:');
    expect(placeholdersAreIntact(protection.protectedText, protection.tokens)).toBe(true);
  });

  it('returns false when one placeholder is missing', () => {
    const protection = protectTokens('@Alice :wave:');
    const mangled = protection.protectedText.replace(protection.tokens[0].placeholder, '');
    expect(placeholdersAreIntact(mangled, protection.tokens)).toBe(false);
  });

  it('returns true for empty token list', () => {
    expect(placeholdersAreIntact('hello', [])).toBe(true);
  });
});

// ── getPlaceholderRanges ──

describe('getPlaceholderRanges', () => {
  it('returns correct ranges', () => {
    const protection = protectTokens('hello @World');
    const ranges = getPlaceholderRanges(protection.protectedText, protection.tokens);
    expect(ranges).toHaveLength(1);
    expect(ranges[0].start).toBeGreaterThanOrEqual(0);
    expect(ranges[0].end).toBeGreaterThan(ranges[0].start);
    expect(protection.protectedText.slice(ranges[0].start, ranges[0].end)).toBe(
      protection.tokens[0].placeholder,
    );
  });

  it('returns empty array for empty token list', () => {
    expect(getPlaceholderRanges('hello', [])).toEqual([]);
  });

  it('filters out missing tokens', () => {
    const ranges = getPlaceholderRanges('no match', [
      { placeholder: '[K0]', originalToken: '@gone' },
    ]);
    expect(ranges).toHaveLength(0);
  });
});

// ── stripLeakedPlaceholders ──

describe('stripLeakedPlaceholders', () => {
  it('strips a single leaked placeholder', () => {
    expect(stripLeakedPlaceholders('hello [K0] world')).toBe('hello  world');
  });

  it('strips multiple different leaked placeholders', () => {
    const input = 'text [K0] more [K1] end';
    expect(stripLeakedPlaceholders(input)).toBe('text  more  end');
  });

  it('strips repeated same placeholder', () => {
    const input = '[K0] and [K0] again';
    expect(stripLeakedPlaceholders(input)).toBe(' and  again');
  });

  it('returns text unchanged when no placeholders present', () => {
    expect(stripLeakedPlaceholders('clean text')).toBe('clean text');
  });
});

// ── End-to-end bug reproduction ──

describe('end-to-end: T5 repetition bug', () => {
  it('produces clean output from garbled T5 repetition', () => {
    const input = '@Manoj are you Sure, no issues :think:';
    const protection = protectTokens(input);

    // Simulate T5 repetition: model repeats text with placeholders
    const garbledOutput = [
      protection.protectedText,
      'are you Sure, no issues',
      protection.tokens.find((t) => t.originalToken === ':think:')!.placeholder,
      'are you Sure, no issues',
      protection.tokens.find((t) => t.originalToken === ':think:')!.placeholder,
    ].join(' ');

    // Restore tokens (replaceAll fixes duplicate placeholders)
    let result: string;
    if (placeholdersAreIntact(garbledOutput, protection.tokens)) {
      result = restoreTokens(garbledOutput, protection.tokens);
    } else {
      result = bestEffortRestore(garbledOutput, protection.tokens);
    }

    // Strip any remaining leaked placeholders
    result = stripLeakedPlaceholders(result);

    // No leaked placeholders in output
    expect(result).not.toMatch(/\[K\d+\]/);
    // Original tokens are restored
    expect(result).toContain('@Manoj');
    expect(result).toContain(':think:');
  });
});

// ── #hashtag protection ──

describe('protectTokens: #hashtag / #channel', () => {
  it('protects #hashtag / #channel names', () => {
    const result = protectTokens('check #general for updates');
    expect(result.tokens.some((t) => t.originalToken === '#general')).toBe(true);
    expect(result.protectedText).not.toContain('#general');
  });

  it('does not protect bare numbers after #', () => {
    const result = protectTokens('see issue #123 for details');
    expect(result.tokens.some((t) => t.originalToken === '#123')).toBe(false);
    expect(result.protectedText).toContain('#123');
  });

  it('round-trips #hashtag tokens through protect/restore', () => {
    const input = 'post in #team-standup and #project_v2';
    const protection = protectTokens(input);
    expect(protection.tokens.some((t) => t.originalToken === '#team-standup')).toBe(true);
    expect(protection.tokens.some((t) => t.originalToken === '#project_v2')).toBe(true);
    const restored = restoreTokens(protection.protectedText, protection.tokens);
    expect(restored).toBe(input);
  });

  it('does not match ## markdown headers', () => {
    const result = protectTokens('## Heading');
    expect(result.tokens.some((t) => t.originalToken.startsWith('#'))).toBe(false);
  });
});

// ── getOriginalTokenRanges ──

describe('getOriginalTokenRanges', () => {
  it('finds original token positions in restored text', () => {
    const text = '@Manoj said #general is good';
    const tokens = [
      { placeholder: '[K0]', originalToken: '@Manoj' },
      { placeholder: '[K1]', originalToken: '#general' },
    ];
    const ranges = getOriginalTokenRanges(text, tokens);
    expect(ranges).toHaveLength(2);
    expect(text.slice(ranges[0].start, ranges[0].end)).toBe('@Manoj');
    expect(text.slice(ranges[1].start, ranges[1].end)).toBe('#general');
  });

  it('returns empty array when no tokens', () => {
    expect(getOriginalTokenRanges('hello', [])).toEqual([]);
  });

  it('finds duplicate occurrences', () => {
    const text = ':wave: hello :wave:';
    const tokens = [{ placeholder: '[K0]', originalToken: ':wave:' }];
    const ranges = getOriginalTokenRanges(text, tokens);
    expect(ranges).toHaveLength(2);
  });
});

// ── T5-friendly [KN] placeholder format ──

describe('T5-friendly [KN] placeholder format', () => {
  it('uses [KN] bracket-wrapped placeholders', () => {
    const result = protectTokens('@Alice');
    expect(result.tokens[0].placeholder).toBe('[K0]');
  });

  it('bracket placeholders survive simulated T5 round-trip', () => {
    const input = '@Manoj are you sure no issue? :think:';
    const protection = protectTokens(input);

    // With bracket-wrapped format, T5 preserves them faithfully
    const t5Output = protection.protectedText;

    expect(placeholdersAreIntact(t5Output, protection.tokens)).toBe(true);
    const restored = restoreTokens(t5Output, protection.tokens);
    expect(restored).toBe(input);
  });

  it('bracket placeholders are not matched by token patterns', () => {
    const text = 'hello [K0] world [K5] end';
    const result = protectTokens(text);
    expect(result.tokens).toHaveLength(0);
    expect(result.protectedText).toBe(text);
  });
});

// ── Jira-style issue keys ──

describe('protectTokens: Jira-style issue keys', () => {
  it('protects PROJ-123 style keys', () => {
    const result = protectTokens('see ENG-456 for details');
    expect(result.tokens.some((t) => t.originalToken === 'ENG-456')).toBe(true);
    expect(result.protectedText).not.toContain('ENG-456');
  });

  it('protects multi-letter project keys', () => {
    const result = protectTokens('fix BUG-99 and PROJ-1234');
    expect(result.tokens.some((t) => t.originalToken === 'BUG-99')).toBe(true);
    expect(result.tokens.some((t) => t.originalToken === 'PROJ-1234')).toBe(true);
  });

  it('does not protect lowercase keys', () => {
    const result = protectTokens('not eng-456');
    expect(result.tokens.some((t) => t.originalToken === 'eng-456')).toBe(false);
  });

  it('round-trips Jira keys', () => {
    const input = 'working on ENG-123 and BUG-42';
    const protection = protectTokens(input);
    const restored = restoreTokens(protection.protectedText, protection.tokens);
    expect(restored).toBe(input);
  });
});

// ── Slack special mentions ──

describe('protectTokens: Slack special mentions', () => {
  it('protects <!here>', () => {
    const result = protectTokens('hey <!here> check this');
    expect(result.tokens.some((t) => t.originalToken === '<!here>')).toBe(true);
  });

  it('protects <!channel> and <!everyone>', () => {
    const result = protectTokens('<!channel> and <!everyone> please');
    expect(result.tokens.some((t) => t.originalToken === '<!channel>')).toBe(true);
    expect(result.tokens.some((t) => t.originalToken === '<!everyone>')).toBe(true);
  });

  it('round-trips Slack special mentions', () => {
    const input = 'attention <!here> important';
    const protection = protectTokens(input);
    const restored = restoreTokens(protection.protectedText, protection.tokens);
    expect(restored).toBe(input);
  });
});

// ── Slack user group mentions ──

describe('protectTokens: Slack user group mentions', () => {
  it('protects <!subteam^ID|@group> format', () => {
    const result = protectTokens('cc <!subteam^S1234|@backend-team>');
    expect(result.tokens.some((t) => t.originalToken === '<!subteam^S1234|@backend-team>')).toBe(true);
  });

  it('protects <!subteam^ID> without display name', () => {
    const result = protectTokens('notify <!subteam^S5678>');
    expect(result.tokens.some((t) => t.originalToken === '<!subteam^S5678>')).toBe(true);
  });

  it('round-trips subteam mentions', () => {
    const input = 'hey <!subteam^S1234|@ops> check this';
    const protection = protectTokens(input);
    const restored = restoreTokens(protection.protectedText, protection.tokens);
    expect(restored).toBe(input);
  });
});

// ── Kebab-case identifiers ──

describe('protectTokens: kebab-case identifiers', () => {
  it('protects repo-style kebab-case names', () => {
    const result = protectTokens('check my-component for the fix');
    expect(result.tokens.some((t) => t.originalToken === 'my-component')).toBe(true);
    expect(result.protectedText).not.toContain('my-component');
  });

  it('protects multi-segment kebab-case', () => {
    const result = protectTokens('install react-router-dom please');
    expect(result.tokens.some((t) => t.originalToken === 'react-router-dom')).toBe(true);
  });

  it('round-trips kebab-case identifiers', () => {
    const input = 'use docker-compose and ts-node';
    const protection = protectTokens(input);
    const restored = restoreTokens(protection.protectedText, protection.tokens);
    expect(restored).toBe(input);
  });
});

// ── Snake_case identifiers ──

describe('protectTokens: snake_case identifiers', () => {
  it('protects snake_case names', () => {
    const result = protectTokens('set user_name as the target');
    expect(result.tokens.some((t) => t.originalToken === 'user_name')).toBe(true);
  });

  it('protects SCREAMING_SNAKE_CASE', () => {
    const result = protectTokens('set MAX_RETRIES to 5');
    expect(result.tokens.some((t) => t.originalToken === 'MAX_RETRIES')).toBe(true);
  });

  it('round-trips snake_case identifiers', () => {
    const input = 'check user_name and BASE_URL';
    const protection = protectTokens(input);
    const restored = restoreTokens(protection.protectedText, protection.tokens);
    expect(restored).toBe(input);
  });
});

// ── Environment variables ──

describe('protectTokens: environment variables', () => {
  it('protects $VAR style', () => {
    const result = protectTokens('set $NODE_ENV to production');
    expect(result.tokens.some((t) => t.originalToken === '$NODE_ENV')).toBe(true);
  });

  it('protects ${VAR} style', () => {
    const result = protectTokens('use ${DATABASE_URL} for connection');
    expect(result.tokens.some((t) => t.originalToken === '${DATABASE_URL}')).toBe(true);
  });
});

// ── CLI flags ──

describe('protectTokens: CLI flags', () => {
  it('protects double-dash flags', () => {
    const result = protectTokens('run with --verbose flag');
    expect(result.tokens.some((t) => t.originalToken === '--verbose')).toBe(true);
  });

  it('protects flags with hyphens', () => {
    const result = protectTokens('add --no-cache option');
    expect(result.tokens.some((t) => t.originalToken === '--no-cache')).toBe(true);
  });
});

// ── Version strings ──

describe('protectTokens: version strings', () => {
  it('protects semver strings', () => {
    const result = protectTokens('upgrade to v1.2.3 please');
    expect(result.tokens.some((t) => t.originalToken === 'v1.2.3')).toBe(true);
  });

  it('protects version with prerelease', () => {
    const result = protectTokens('using 1.0.0-beta.1 now');
    expect(result.tokens.some((t) => t.originalToken === '1.0.0-beta.1')).toBe(true);
  });
});
