import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { app } from 'electron';

export interface DeviceSelection {
  device: string;              // 'dml' | 'cuda' | 'webgpu' | 'wasm' | 'cpu'
  runtime: 'node' | 'renderer'; // main-process pipeline vs inference window
  label: string;               // for developer mode display
}

const CACHE_FILE = path.join(os.homedir(), '.ghostedit', 'device-cache.json');

let cachedSelection: DeviceSelection | null = null;

interface DiskCache {
  appVersion: string;
  device: string;
  runtime: 'node' | 'renderer';
  label: string;
}

/**
 * Read cached device from disk. Returns null if missing or version mismatch.
 */
function readDiskCache(): DeviceSelection | null {
  try {
    if (!fs.existsSync(CACHE_FILE)) return null;
    const raw: DiskCache = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf-8'));
    if (raw.appVersion !== app.getVersion()) return null;
    return { device: raw.device, runtime: raw.runtime as 'node' | 'renderer', label: raw.label };
  } catch {
    return null;
  }
}

/**
 * Persist device selection to disk.
 */
function writeDiskCache(sel: DeviceSelection): void {
  try {
    const dir = path.dirname(CACHE_FILE);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const data: DiskCache = { appVersion: app.getVersion(), ...sel };
    fs.writeFileSync(CACHE_FILE, JSON.stringify(data, null, 2));
  } catch {
    // Non-critical — probe will re-run next time
  }
}

/**
 * Clear the disk cache (e.g. on config-changed when model variant changes).
 */
export function clearDeviceCache(): void {
  cachedSelection = null;
  try {
    if (fs.existsSync(CACHE_FILE)) fs.unlinkSync(CACHE_FILE);
  } catch {
    // Ignore
  }
}

/**
 * Get the candidates to probe in order, based on platform.
 * All inference runs in the node (main) process — no renderer candidates.
 *
 * macOS:        CPU (node)
 * Windows:      DirectML (node) → CPU (node)
 * Linux x64:    CUDA (node) → CPU (node)
 * Linux arm64:  CPU (node)
 */
function getCandidates(): DeviceSelection[] {
  const platform = process.platform;
  const arch = process.arch;

  const nodeCPU: DeviceSelection = { device: 'cpu', runtime: 'node', label: 'CPU (Node)' };

  if (platform === 'win32') {
    return [
      { device: 'dml', runtime: 'node', label: 'DirectML (GPU)' },
      nodeCPU,
    ];
  }

  if (platform === 'linux' && arch === 'x64') {
    return [
      { device: 'cuda', runtime: 'node', label: 'CUDA (GPU)' },
      nodeCPU,
    ];
  }

  // macOS and Linux arm64: CPU only
  return [nodeCPU];
}

/**
 * Probe whether a node-side device (dml/cuda) actually works by loading a
 * tiny test pipeline. The loaded pipeline becomes the warm cache for
 * local-model-runner.
 *
 * Returns the pipeline if successful, or null on failure.
 */
async function probeNodeDevice(
  device: string,
  modelRepoId: string,
  cacheDir: string,
  pipelineOpts: Record<string, any>,
): Promise<any | null> {
  try {
    const { pipeline: createPipeline } = await import('@huggingface/transformers');
    const opts = { ...pipelineOpts, device: device as any };
    const pipe = await createPipeline('text2text-generation', modelRepoId, opts);
    return pipe;
  } catch (err) {
    console.warn(`[GhostEdit] Device probe failed for "${device}":`, (err as Error).message);
    return null;
  }
}

/**
 * Detect the best inference device. Checks disk cache first, then probes
 * node-side GPU devices if needed. Renderer-side devices (webgpu/wasm) are
 * not probed — the inference window handles fallback internally.
 *
 * @param modelRepoId  e.g. 'Xenova/t5-base-grammar-correction'
 * @param cacheDir     model cache directory
 * @param pipelineOpts base pipeline options (dtype, local_files_only, etc.)
 * @returns { selection, pipeline? } — pipeline is non-null when a node probe succeeded
 */
export async function detectBestDevice(
  modelRepoId: string,
  cacheDir: string,
  pipelineOpts: Record<string, any>,
): Promise<{ selection: DeviceSelection; pipeline: any | null }> {
  // 1. Check in-memory cache
  if (cachedSelection) {
    return { selection: cachedSelection, pipeline: null };
  }

  // 2. Check disk cache
  const diskCached = readDiskCache();
  if (diskCached) {
    cachedSelection = diskCached;
    console.log(`[GhostEdit] Using cached device: ${diskCached.label}`);
    return { selection: diskCached, pipeline: null };
  }

  // 3. Probe candidates
  const candidates = getCandidates();

  for (const candidate of candidates) {
    if (candidate.runtime === 'node' && (candidate.device === 'dml' || candidate.device === 'cuda')) {
      // Probe this GPU device
      console.log(`[GhostEdit] Probing device: ${candidate.label}...`);
      const pipe = await probeNodeDevice(candidate.device, modelRepoId, cacheDir, pipelineOpts);
      if (pipe) {
        cachedSelection = candidate;
        writeDiskCache(candidate);
        console.log(`[GhostEdit] Selected device: ${candidate.label}`);
        return { selection: candidate, pipeline: pipe };
      }
      // Probe failed — try next candidate
      continue;
    }

    // For renderer-side or CPU node devices, just accept the first one without probing
    cachedSelection = candidate;
    writeDiskCache(candidate);
    console.log(`[GhostEdit] Selected device: ${candidate.label}`);
    return { selection: candidate, pipeline: null };
  }

  // Should never reach here, but fallback to CPU
  const fallback: DeviceSelection = { device: 'cpu', runtime: 'node', label: 'CPU (Node)' };
  cachedSelection = fallback;
  writeDiskCache(fallback);
  return { selection: fallback, pipeline: null };
}

/**
 * Sync read of the in-memory cached device selection.
 */
export function getCachedDevice(): DeviceSelection | null {
  return cachedSelection;
}
