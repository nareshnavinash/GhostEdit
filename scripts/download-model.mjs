/**
 * Downloads the T5 grammar correction model (int8 variant) into resources/models/
 * so it can be bundled with the app via extraResource.
 *
 * Usage: node scripts/download-model.mjs
 */
import { pipeline } from '@huggingface/transformers';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const cacheDir = path.join(__dirname, '..', 'resources', 'models');

console.log(`Downloading int8 model to: ${cacheDir}`);

const pipe = await pipeline('text2text-generation', 'Xenova/t5-base-grammar-correction', {
  cache_dir: cacheDir,
  dtype: 'int8',
  progress_callback: (info) => {
    if (info?.progress != null) {
      process.stdout.write(`\r  ${info.file ?? 'unknown'}: ${Math.round(info.progress)}%`);
      if (Math.round(info.progress) === 100) process.stdout.write('\n');
    }
  },
});

// Quick sanity check
const result = await pipe('grammar: She go to school yesterday', {
  max_new_tokens: 64,
  num_beams: 4,
  early_stopping: true,
});
console.log(`\nSanity check: "${result[0].generated_text}"`);

// Clean up any fp32 ONNX files that may remain from previous downloads
const onnxDir = path.join(cacheDir, 'Xenova', 't5-base-grammar-correction', 'onnx');
const fp32Files = ['encoder_model.onnx', 'decoder_model_merged.onnx'];
for (const file of fp32Files) {
  const filePath = path.join(onnxDir, file);
  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
    console.log(`Removed old fp32 file: ${file}`);
  }
}

console.log('Model downloaded successfully (int8 variant)!');
