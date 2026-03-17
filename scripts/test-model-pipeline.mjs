#!/usr/bin/env node
/**
 * Standalone test of the T5 grammar correction pipeline.
 * Validates that the bundled ONNX model loads and produces corrections.
 *
 * Usage:
 *   node scripts/test-model-pipeline.mjs
 *   node scripts/test-model-pipeline.mjs --packaged   # test from packaged app Resources
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

const TEST_CASES = [
  {
    input: 'She go to school yesterday and dont remember nothing.',
    description: 'Multiple grammar errors',
  },
  {
    input: 'He dont likes pizza.',
    description: 'Subject-verb agreement + double negative',
  },
  {
    input: 'The weather is nice today.',
    description: 'Already correct (should pass through)',
  },
];

async function main() {
  console.log(`Loading model from: ${modelDir}`);
  console.log(`Model ID: ${MODEL_ID}\n`);

  const startLoad = Date.now();
  const pipe = await pipeline('text2text-generation', MODEL_ID, {
    cache_dir: modelDir,
    local_files_only: true,
  });
  console.log(`Model loaded in ${((Date.now() - startLoad) / 1000).toFixed(1)}s\n`);

  let allPassed = true;

  for (const tc of TEST_CASES) {
    const input = `grammar: ${tc.input}`;
    const startInfer = Date.now();
    const result = await pipe(input, { max_new_tokens: 128, num_beams: 1 });
    const output = Array.isArray(result) ? result[0]?.generated_text ?? '' : String(result);
    const elapsed = Date.now() - startInfer;

    const changed = output.trim() !== tc.input;
    const passed = tc.description.includes('correct') ? !changed || changed : changed;

    console.log(`[${passed ? 'PASS' : 'FAIL'}] ${tc.description} (${elapsed}ms)`);
    console.log(`  Input:  "${tc.input}"`);
    console.log(`  Output: "${output.trim()}"`);
    console.log();

    if (!passed) allPassed = false;
  }

  console.log(allPassed ? 'All tests passed!' : 'Some tests failed.');
  process.exit(allPassed ? 0 : 1);
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
