import * as path from 'node:path';
import * as fs from 'node:fs';
import * as os from 'node:os';
import { app } from 'electron';
import { LOCAL_PROVIDER, VARIANT_ONNX_FILES, MODEL_VARIANTS, DEFAULT_BUNDLED_VARIANT } from '../shared/constants';
import { configManager } from './config-manager';
import { detectBestDevice, getCachedDevice, type DeviceSelection } from './device-selector';
import type { AppConfig, CorrectionResult, LocalModelInfo, LocalModelVariant, LocalModelVariantInfo } from '../shared/types';

let pipelinePromise: Promise<any> | null = null;
let loadedVariant: LocalModelVariant | null = null;
let loadedDevice: string | null = null;

// ── Idle unload timer ──
const MODEL_IDLE_TIMEOUT = 5 * 60 * 1000; // 5 minutes
let idleTimer: ReturnType<typeof setTimeout> | null = null;

function resetIdleTimer(): void {
  if (idleTimer) clearTimeout(idleTimer);
  idleTimer = setTimeout(() => {
    if (pipelinePromise) {
      console.log('[GhostEdit] Unloading idle model to free memory');
      pipelinePromise = null;
      loadedVariant = null;
      loadedDevice = null;
    }
    idleTimer = null;
  }, MODEL_IDLE_TIMEOUT);
}

const MODEL_SUBPATH = 'Xenova/t5-base-grammar-correction';
const ONNX_SUBDIR = 'onnx';
const SHARED_FILES = ['config.json', 'tokenizer.json', 'tokenizer_config.json', 'generation_config.json'];

/**
 * Returns the path to the bundled model directory inside app resources.
 * In production: process.resourcesPath/models
 * In development: <project>/resources/models
 */
export function getBundledModelDir(): string {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'models');
  }
  return path.join(app.getAppPath(), 'resources', 'models');
}

/**
 * Returns the writable user model directory (~/.ghostedit/models/).
 */
export function getUserModelDir(): string {
  return path.join(os.homedir(), '.ghostedit', 'models');
}

/**
 * Returns the best cache_dir for a given variant.
 * User dir is preferred if it has the ONNX files for the variant;
 * falls back to bundled dir.
 */
export function getModelDirForVariant(variant: LocalModelVariant): string {
  const userDir = getUserModelDir();
  const userModelDir = path.join(userDir, MODEL_SUBPATH, ONNX_SUBDIR);
  const files = VARIANT_ONNX_FILES[variant];

  if (
    fs.existsSync(path.join(userModelDir, files.encoder)) &&
    fs.existsSync(path.join(userModelDir, files.decoder))
  ) {
    return userDir;
  }

  return getBundledModelDir();
}

/**
 * Check whether a variant's ONNX files exist in either bundled or user dirs.
 */
function isVariantAvailable(variant: LocalModelVariant): boolean {
  const files = VARIANT_ONNX_FILES[variant];

  // Check bundled dir
  const bundledOnnxDir = path.join(getBundledModelDir(), MODEL_SUBPATH, ONNX_SUBDIR);
  if (
    fs.existsSync(path.join(bundledOnnxDir, files.encoder)) &&
    fs.existsSync(path.join(bundledOnnxDir, files.decoder))
  ) {
    return true;
  }

  // Check user dir
  const userOnnxDir = path.join(getUserModelDir(), MODEL_SUBPATH, ONNX_SUBDIR);
  if (
    fs.existsSync(path.join(userOnnxDir, files.encoder)) &&
    fs.existsSync(path.join(userOnnxDir, files.decoder))
  ) {
    return true;
  }

  return false;
}

/**
 * Check whether a variant is bundled with the app.
 */
function isVariantBundled(variant: LocalModelVariant): boolean {
  const files = VARIANT_ONNX_FILES[variant];
  const bundledOnnxDir = path.join(getBundledModelDir(), MODEL_SUBPATH, ONNX_SUBDIR);
  return (
    fs.existsSync(path.join(bundledOnnxDir, files.encoder)) &&
    fs.existsSync(path.join(bundledOnnxDir, files.decoder))
  );
}

/**
 * Scans both bundled and user dirs to determine availability of all variants.
 * Results are cached with a 30s TTL to avoid repeated fs.existsSync calls.
 */
let variantCache: LocalModelVariantInfo[] | null = null;
let variantCacheTime = 0;
const VARIANT_CACHE_TTL = 30_000;

export function scanAvailableVariants(): LocalModelVariantInfo[] {
  const now = Date.now();
  if (variantCache && now - variantCacheTime < VARIANT_CACHE_TTL) {
    return variantCache;
  }
  variantCache = MODEL_VARIANTS.map((meta) => ({
    variant: meta.variant,
    displayName: meta.displayName,
    sizeMB: meta.sizeMB,
    available: isVariantAvailable(meta.variant),
    bundled: isVariantBundled(meta.variant),
  }));
  variantCacheTime = now;
  return variantCache;
}

/** Invalidate the variant scan cache (e.g. after downloading a new variant). */
export function invalidateVariantCache(): void {
  variantCache = null;
  variantCacheTime = 0;
}

export function getLocalModelStatus(): LocalModelInfo {
  const config = configManager.load();
  const activeVariant = config.localModelVariant ?? DEFAULT_BUNDLED_VARIANT;
  const variants = scanAvailableVariants();
  const activeInfo = variants.find((v) => v.variant === activeVariant);

  return {
    ready: activeInfo?.available ?? false,
    activeVariant,
    variants,
  };
}

async function loadPipeline(variant: LocalModelVariant, device?: string): Promise<any> {
  const { pipeline: createPipeline } = await import('@huggingface/transformers');
  const cacheDir = getModelDirForVariant(variant);

  const opts: Record<string, any> = {
    cache_dir: cacheDir,
    local_files_only: true,
  };

  // fp32 is the default dtype — omit to avoid forcing it
  if (variant !== 'fp32') {
    opts.dtype = variant;
  }

  if (device) {
    opts.device = device;
  }

  return createPipeline('text2text-generation', LOCAL_PROVIDER.modelRepoId, opts);
}

async function ensureModelLoaded(): Promise<any> {
  const config = configManager.load();
  const desiredVariant = config.localModelVariant ?? DEFAULT_BUNDLED_VARIANT;

  // Lazy device detection on first use
  let deviceSel = getCachedDevice();
  if (!deviceSel) {
    const cacheDir = getModelDirForVariant(desiredVariant);
    const pipelineOpts: Record<string, any> = { cache_dir: cacheDir, local_files_only: true };
    if (desiredVariant !== 'fp32') pipelineOpts.dtype = desiredVariant;
    try {
      const { selection, pipeline: probePipeline } = await detectBestDevice(
        LOCAL_PROVIDER.modelRepoId, cacheDir, pipelineOpts,
      );
      deviceSel = selection;
      if (probePipeline && selection.runtime === 'node') {
        setPreloadedPipeline(probePipeline, desiredVariant, selection.device);
        return probePipeline;
      }
    } catch {
      // Fall through to normal pipeline load on CPU
    }
  }

  const desiredDevice = (deviceSel?.runtime === 'node' && deviceSel.device !== 'cpu')
    ? deviceSel.device
    : undefined;

  // If a different variant or device is requested, invalidate the current pipeline
  if (pipelinePromise && (loadedVariant !== desiredVariant || loadedDevice !== (desiredDevice ?? null))) {
    pipelinePromise = null;
    loadedVariant = null;
    loadedDevice = null;
  }

  if (pipelinePromise) return pipelinePromise;

  loadedVariant = desiredVariant;
  loadedDevice = desiredDevice ?? null;
  pipelinePromise = loadPipeline(desiredVariant, desiredDevice);
  try {
    return await pipelinePromise;
  } catch (e) {
    pipelinePromise = null;
    loadedVariant = null;
    loadedDevice = null;
    throw e;
  }
}

/**
 * Force-invalidate the loaded pipeline so the next correction
 * picks up a newly selected variant.
 */
export function invalidatePipeline(): void {
  pipelinePromise = null;
  loadedVariant = null;
  loadedDevice = null;
}

/**
 * Set an already-loaded pipeline from the device probe (avoids double-loading).
 */
export function setPreloadedPipeline(pipe: any, variant: LocalModelVariant, device: string): void {
  pipelinePromise = Promise.resolve(pipe);
  loadedVariant = variant;
  loadedDevice = device;
}

/**
 * Download a model variant to the user model directory.
 * Copies shared config/tokenizer files from bundled dir if needed.
 */
export async function downloadVariant(
  variant: LocalModelVariant,
  onProgress?: (progress: number) => void,
): Promise<void> {
  const { pipeline: createPipeline } = await import('@huggingface/transformers');
  const userDir = getUserModelDir();
  const userModelDir = path.join(userDir, MODEL_SUBPATH);

  // Ensure user model directory exists
  fs.mkdirSync(path.join(userModelDir, ONNX_SUBDIR), { recursive: true });

  // Copy shared config/tokenizer files from bundled dir if they don't exist
  const bundledModelDir = path.join(getBundledModelDir(), MODEL_SUBPATH);
  for (const file of SHARED_FILES) {
    const dest = path.join(userModelDir, file);
    const src = path.join(bundledModelDir, file);
    if (!fs.existsSync(dest) && fs.existsSync(src)) {
      fs.copyFileSync(src, dest);
    }
  }

  const opts: Record<string, any> = {
    cache_dir: userDir,
    local_files_only: false,
    progress_callback: (info: any) => {
      if (info?.progress != null && onProgress) {
        onProgress(Math.round(info.progress));
      }
    },
  };

  if (variant !== 'fp32') {
    opts.dtype = variant;
  }

  await createPipeline('text2text-generation', LOCAL_PROVIDER.modelRepoId, opts);
  invalidateVariantCache();
}

/**
 * Pre-warm the local model at app startup (fire-and-forget).
 * Only loads if the provider is set to 'local'.
 */
export function preWarmModel(): void {
  const config = configManager.load();
  if (config.provider === 'local') {
    ensureModelLoaded().catch((err) => {
      console.warn('[GhostEdit] Model pre-warm failed:', err.message);
    });
  }
}

export async function correctTextLocal(
  _systemPrompt: string,
  text: string,
): Promise<CorrectionResult> {
  const startTime = Date.now();
  const config = configManager.load();

  // Node-side inference (GPU or CPU)
  const pipe = await ensureModelLoaded();

  const input = `grammar: ${text}`;
  const maxNewTokens = Math.min(text.length * 2, 512);

  const beamOpts = config.localModelSpeed === 'quality'
    ? { num_beams: 4, early_stopping: true }
    : { num_beams: 1 };

  const result = await pipe(input, {
    max_new_tokens: maxNewTokens,
    no_repeat_ngram_size: 3,
    repetition_penalty: 1.2,
    ...beamOpts,
  });

  const output = Array.isArray(result) ? result[0]?.generated_text ?? '' : String(result);

  resetIdleTimer();
  return {
    text: output.trim(),
    durationMs: Date.now() - startTime,
  };
}

export async function correctTextLocalStreaming(
  _systemPrompt: string,
  text: string,
  onChunk: (chunk: string) => void,
): Promise<CorrectionResult> {
  const config = configManager.load();

  // Node-side streaming with TextStreamer (works with dml/cuda/cpu)
  const startTime = Date.now();
  const pipe = await ensureModelLoaded();

  const input = `grammar: ${text}`;
  const maxNewTokens = Math.min(text.length * 2, 512);

  const beamOpts = config.localModelSpeed === 'quality'
    ? { num_beams: 4, early_stopping: true }
    : { num_beams: 1 };

  try {
    const { TextStreamer } = await import('@huggingface/transformers');
    let fullText = '';
    const streamer = new TextStreamer(pipe.tokenizer, {
      skip_prompt: true,
      callback_function: (token: string) => {
        fullText += token;
        onChunk(token);
      },
    });

    await pipe(input, {
      max_new_tokens: maxNewTokens,
      no_repeat_ngram_size: 3,
      repetition_penalty: 1.2,
      ...beamOpts,
      streamer,
    });

    resetIdleTimer();
    return { text: fullText.trim(), durationMs: Date.now() - startTime };
  } catch {
    // Fallback: non-streaming if TextStreamer is unavailable
    const result = await correctTextLocal(_systemPrompt, text);
    onChunk(result.text);
    return result;
  }
}
