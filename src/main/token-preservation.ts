import type { ProtectedToken, TokenProtectionResult } from '../shared/types';

/**
 * Token preservation system.
 * Port of TokenPreservationSupport.swift.
 *
 * Replaces special tokens (@mentions, URLs, code spans, emoji, etc.) with
 * stable placeholders before sending to AI, then restores them afterwards.
 */

const PLACEHOLDER_PREFIX = '[K';
const PLACEHOLDER_SUFFIX = ']';

/** Ordered list of regex patterns for tokens that should be preserved. */
const TOKEN_PATTERNS: RegExp[] = [
  // 1. Inline code
  /`[^`\n]+`/g,
  // 2. URLs
  /https?:\/\/[^\s<>()]+[^\s<>()\.,;:!?]/g,
  // 3. Email addresses
  /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/g,
  // 4. Absolute/relative file paths
  /(?:~|\/|\.{1,2}\/)(?:[A-Za-z0-9._\-]+\/)*[A-Za-z0-9._\-]+(?:\.[A-Za-z0-9._\-]+)?/g,
  // 5. Folder/file style paths
  /(?:[A-Za-z0-9._\-]+\/){1,}[A-Za-z0-9._\-]+(?:\.[A-Za-z0-9._\-]+)?/g,
  // 6. Slack-style emoji :emoji_name:
  /:[A-Za-z0-9_+\-]+:/g,
  // 7. Slack special mentions (before @mentions to avoid partial matches)
  /<!(?:here|channel|everyone)>/g,
  // 8. Slack user group mentions
  /<!subteam\^[^|>]+(?:\|[^>]+)?>/g,
  // 9. @<id> mentions
  /(?<![\w@])@<[^>\s]+>/g,
  // 10. <@id> mentions
  /(?<![\w@])<@[A-Za-z0-9][A-Za-z0-9._\-]*>/g,
  // 11. @name mentions
  /(?<![\w@])@[A-Za-z0-9](?:[A-Za-z0-9._\-]*[A-Za-z0-9_\-])?/g,
  // 12. #hashtag / #channel names
  /(?<![#\w])#[A-Za-z][A-Za-z0-9_\-]*/g,
  // 13. Jira-style issue keys (PROJ-123)
  /\b[A-Z][A-Z0-9]+-\d+\b/g,
];

/**
 * Replace tokens with numbered placeholders.
 */
export function protectTokens(text: string): TokenProtectionResult {
  const tokens: ProtectedToken[] = [];
  // Track already-replaced ranges to avoid double-matching
  const replacedRanges: Array<{ start: number; end: number }> = [];
  let workingText = text;

  for (const pattern of TOKEN_PATTERNS) {
    // Reset lastIndex for global patterns
    pattern.lastIndex = 0;

    // Collect matches first, then replace to avoid index shifting issues
    const matches: Array<{ match: string; index: number }> = [];
    let m: RegExpExecArray | null;
    while ((m = pattern.exec(workingText)) !== null) {
      const start = m.index;
      const end = start + m[0].length;
      // Skip if overlapping with already-replaced placeholder
      const overlaps = replacedRanges.some(
        (r) => start < r.end && end > r.start,
      );
      if (!overlaps) {
        matches.push({ match: m[0], index: start });
      }
    }

    // Build result from segments instead of repeated string slicing
    if (matches.length > 0) {
      // Sort matches by index (ascending) for forward iteration
      matches.sort((a, b) => a.index - b.index);
      const segments: string[] = [];
      let cursor = 0;
      for (const { match, index } of matches) {
        const placeholder = `${PLACEHOLDER_PREFIX}${tokens.length}${PLACEHOLDER_SUFFIX}`;
        tokens.push({ placeholder, originalToken: match });
        segments.push(workingText.slice(cursor, index));
        segments.push(placeholder);
        replacedRanges.push({
          start: index,
          end: index + placeholder.length,
        });
        cursor = index + match.length;
      }
      segments.push(workingText.slice(cursor));
      workingText = segments.join('');
    }
  }

  return {
    protectedText: workingText,
    tokens,
    hasProtectedTokens: tokens.length > 0,
  };
}

/**
 * Restore placeholders back to original tokens.
 */
export function restoreTokens(
  text: string,
  tokens: ProtectedToken[],
): string {
  let result = text;
  // Restore in reverse order so indices don't shift
  for (let i = tokens.length - 1; i >= 0; i--) {
    const { placeholder, originalToken } = tokens[i];
    result = result.replaceAll(placeholder, originalToken);
  }
  return result;
}

/**
 * Check if all placeholders are still present in the text.
 */
export function placeholdersAreIntact(
  text: string,
  tokens: ProtectedToken[],
): boolean {
  return tokens.every((t) => text.includes(t.placeholder));
}

/**
 * Get the character ranges of all placeholders in the protected text.
 * Used by the dictionary pre-pass to avoid correcting inside placeholders.
 */
export function getPlaceholderRanges(
  protectedText: string,
  tokens: ProtectedToken[],
): Array<{ start: number; end: number }> {
  return tokens.map((t) => {
    const idx = protectedText.indexOf(t.placeholder);
    return { start: idx, end: idx + t.placeholder.length };
  }).filter((r) => r.start >= 0);
}

/**
 * Best-effort restore: restore whichever placeholders survived.
 */
export function bestEffortRestore(
  text: string,
  tokens: ProtectedToken[],
): string {
  let result = text;
  for (const { placeholder, originalToken } of tokens) {
    if (result.includes(placeholder)) {
      result = result.replaceAll(placeholder, originalToken);
    }
  }
  return result;
}

/**
 * Get the character ranges of all original tokens in the restored text.
 * Used by dictionary polish to avoid correcting inside restored tokens.
 */
export function getOriginalTokenRanges(
  text: string,
  tokens: ProtectedToken[],
): Array<{ start: number; end: number }> {
  const ranges: Array<{ start: number; end: number }> = [];
  for (const { originalToken } of tokens) {
    let searchFrom = 0;
    let idx: number;
    while ((idx = text.indexOf(originalToken, searchFrom)) !== -1) {
      ranges.push({ start: idx, end: idx + originalToken.length });
      searchFrom = idx + originalToken.length;
    }
  }
  return ranges;
}

/**
 * Strip any leaked [KN] placeholders from text.
 * Safety net for when the model duplicates placeholders that restoreTokens
 * can't fully resolve.
 */
export function stripLeakedPlaceholders(text: string): string {
  return text.replace(/\[K\d+\]/g, '');
}
