#!/usr/bin/env node
/**
 * Tests multiple placeholder formats through the full protect → T5 → restore → strip pipeline.
 *
 * Usage:
 *   node scripts/test-sentinel-placeholders.mjs
 *   node scripts/test-sentinel-placeholders.mjs --packaged
 */
import { pipeline } from '@huggingface/transformers';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const usePackaged = process.argv.includes('--packaged');

const modelDir = usePackaged
  ? path.join(__dirname, '../out/GhostEdit-darwin-arm64/GhostEdit.app/Contents/Resources/models')
  : path.join(__dirname, '../resources/models');

const MODEL_ID = 'Xenova/t5-base-grammar-correction';

// ── Token patterns (same as production) ──

const TOKEN_PATTERNS = [
  /`[^`\n]+`/g,
  /https?:\/\/[^\s<>()]+[^\s<>()\.,;:!?]/g,
  /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/g,
  /(?:~|\/|\.{1,2}\/)(?:[A-Za-z0-9._\-]+\/)*[A-Za-z0-9._\-]+(?:\.[A-Za-z0-9._\-]+)?/g,
  /(?:[A-Za-z0-9._\-]+\/){1,}[A-Za-z0-9._\-]+(?:\.[A-Za-z0-9._\-]+)?/g,
  /:[A-Za-z0-9_+\-]+:/g,
  /(?<![\w@])@<[^>\s]+>/g,
  /(?<![\w@])<@[A-Za-z0-9][A-Za-z0-9._\-]*>/g,
  /(?<![\w@])@[A-Za-z0-9](?:[A-Za-z0-9._\-]*[A-Za-z0-9_\-])?/g,
  /(?<![#\w])#[A-Za-z][A-Za-z0-9_\-]*/g,
];

// ── Placeholder formats to test ──

const FORMATS = [
  {
    name: '<extra_id_N> (T5 sentinel)',
    prefix: '<extra_id_',
    suffix: '>',
    stripRegex: /<extra_id_\d+>/g,
  },
  {
    name: '[K0] (bracket-wrapped)',
    prefix: '[K',
    suffix: ']',
    stripRegex: /\[K\d+\]/g,
  },
];

function protectTokens(text, prefix, suffix) {
  const tokens = [];
  const replacedRanges = [];
  let workingText = text;

  for (const pattern of TOKEN_PATTERNS) {
    pattern.lastIndex = 0;
    const matches = [];
    let m;
    while ((m = pattern.exec(workingText)) !== null) {
      const start = m.index;
      const end = start + m[0].length;
      const overlaps = replacedRanges.some((r) => start < r.end && end > r.start);
      if (!overlaps) {
        matches.push({ match: m[0], index: start });
      }
    }

    if (matches.length > 0) {
      matches.sort((a, b) => a.index - b.index);
      const segments = [];
      let cursor = 0;
      for (const { match, index } of matches) {
        const placeholder = `${prefix}${tokens.length}${suffix}`;
        tokens.push({ placeholder, originalToken: match });
        segments.push(workingText.slice(cursor, index));
        segments.push(placeholder);
        replacedRanges.push({ start: index, end: index + placeholder.length });
        cursor = index + match.length;
      }
      segments.push(workingText.slice(cursor));
      workingText = segments.join('');
    }
  }

  return { protectedText: workingText, tokens };
}

function bestEffortRestore(text, tokens) {
  let result = text;
  for (const { placeholder, originalToken } of tokens) {
    if (result.includes(placeholder)) {
      result = result.replaceAll(placeholder, originalToken);
    }
  }
  return result;
}

// ── Test cases ──

const TEST_CASES = [
  {
    input: '@Manoj are you sure no issue? :think:',
    description: 'Mentions + emoji (original failing case)',
    expectTokens: ['@Manoj', ':think:'],
  },
  {
    input: 'check #general for updates @Alice',
    description: 'Hashtag + mention',
    expectTokens: ['#general', '@Alice'],
  },
  {
    input: 'She go to school yesterday',
    description: 'Plain text (no tokens to protect)',
    expectTokens: [],
  },
];

async function main() {
  console.log(`Loading model from: ${modelDir}`);
  console.log(`Model ID: ${MODEL_ID}\n`);

  const startLoad = Date.now();
  const pipe = await pipeline('text2text-generation', MODEL_ID, {
    cache_dir: modelDir,
    local_files_only: true,
    dtype: 'int8',
  });
  console.log(`Model loaded in ${((Date.now() - startLoad) / 1000).toFixed(1)}s\n`);

  for (const fmt of FORMATS) {
    console.log(`\n${'='.repeat(60)}`);
    console.log(`FORMAT: ${fmt.name}`);
    console.log(`${'='.repeat(60)}\n`);

    let allPassed = true;

    for (const tc of TEST_CASES) {
      const protection = protectTokens(tc.input, fmt.prefix, fmt.suffix);

      const modelInput = `grammar: ${protection.protectedText}`;
      const startInfer = Date.now();
      const result = await pipe(modelInput, {
        max_new_tokens: 128,
        no_repeat_ngram_size: 3,
        repetition_penalty: 1.2,
        num_beams: 4,
      });
      const rawOutput = Array.isArray(result) ? result[0]?.generated_text ?? '' : String(result);
      const elapsed = Date.now() - startInfer;

      const restored = bestEffortRestore(rawOutput, protection.tokens);
      const final = restored.replace(fmt.stripRegex, '').trim();

      const hasLeaked = fmt.stripRegex.test(restored);
      // Reset regex lastIndex after test()
      fmt.stripRegex.lastIndex = 0;
      const tokensPresent = tc.expectTokens.every((tok) => final.includes(tok));
      const isClean = !hasLeaked;
      const passed = isClean && (tc.expectTokens.length === 0 || tokensPresent);

      console.log(`[${passed ? 'PASS' : 'FAIL'}] ${tc.description} (${elapsed}ms)`);
      console.log(`  Input:     "${tc.input}"`);
      console.log(`  Protected: "${protection.protectedText}"`);
      console.log(`  T5 raw:    "${rawOutput}"`);
      console.log(`  Restored:  "${restored}"`);
      console.log(`  Final:     "${final}"`);
      if (hasLeaked) console.log(`  ! Leaked placeholders in output`);
      if (!tokensPresent && tc.expectTokens.length > 0) {
        const missing = tc.expectTokens.filter((tok) => !final.includes(tok));
        console.log(`  ! Missing tokens: ${missing.join(', ')}`);
      }
      console.log();

      if (!passed) allPassed = false;
    }

    console.log(allPassed ? `>>> ${fmt.name}: ALL PASSED` : `>>> ${fmt.name}: SOME FAILED`);
  }
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
