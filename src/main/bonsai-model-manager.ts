import * as fs from 'fs';
import * as path from 'path';
import * as https from 'https';
import { app } from 'electron';
import type { BonsaiModelSize, BonsaiModelInfo } from '../shared/types';
import { BONSAI_MODELS, BONSAI_GGUF_FILES, BONSAI_HF_REPOS } from '../shared/constants';

// ── Paths ──

export function getBundledBonsaiModelDir(): string {
  if (app.isPackaged) {
    return path.join(process.resourcesPath, 'models', 'bonsai');
  }
  return path.join(app.getAppPath(), 'resources', 'models', 'bonsai');
}

export function getUserBonsaiModelDir(): string {
  return path.join(app.getPath('home'), '.ghostedit', 'models', 'bonsai');
}

export function getBonsaiModelPath(size: BonsaiModelSize): string | null {
  const filename = BONSAI_GGUF_FILES[size];

  // Check user dir first (downloaded models)
  const userPath = path.join(getUserBonsaiModelDir(), filename);
  if (fs.existsSync(userPath)) return userPath;

  // Check bundled dir
  const bundledPath = path.join(getBundledBonsaiModelDir(), filename);
  if (fs.existsSync(bundledPath)) return bundledPath;

  return null;
}

// ── Scanning ──

let cachedModels: BonsaiModelInfo[] | null = null;
let cacheTimestamp = 0;
const CACHE_TTL = 30_000;

export function scanBonsaiModels(): BonsaiModelInfo[] {
  const now = Date.now();
  if (cachedModels && now - cacheTimestamp < CACHE_TTL) {
    return cachedModels;
  }

  const bundledDir = getBundledBonsaiModelDir();
  const userDir = getUserBonsaiModelDir();

  const result: BonsaiModelInfo[] = BONSAI_MODELS.map((m) => {
    const filename = BONSAI_GGUF_FILES[m.size];
    const bundledPath = path.join(bundledDir, filename);
    const userPath = path.join(userDir, filename);
    const bundled = fs.existsSync(bundledPath);
    const downloaded = fs.existsSync(userPath);

    return {
      size: m.size,
      displayName: m.displayName,
      sizeMB: m.sizeMB,
      available: bundled || downloaded,
      bundled,
    };
  });

  cachedModels = result;
  cacheTimestamp = now;
  return result;
}

export function invalidateBonsaiModelCache(): void {
  cachedModels = null;
  cacheTimestamp = 0;
}

// ── Download ──

function getDownloadUrl(size: BonsaiModelSize): string {
  const repo = BONSAI_HF_REPOS[size];
  const file = BONSAI_GGUF_FILES[size];
  return `https://huggingface.co/${repo}/resolve/main/${file}`;
}

export async function downloadBonsaiModel(
  size: BonsaiModelSize,
  onProgress?: (progress: number) => void,
): Promise<void> {
  const url = getDownloadUrl(size);
  const destDir = getUserBonsaiModelDir();
  const filename = BONSAI_GGUF_FILES[size];
  const destPath = path.join(destDir, filename);
  const partialPath = destPath + '.partial';

  fs.mkdirSync(destDir, { recursive: true });

  await new Promise<void>((resolve, reject) => {
    const download = (downloadUrl: string, redirectCount: number) => {
      if (redirectCount > 5) {
        reject(new Error('Too many redirects'));
        return;
      }

      const protocol = downloadUrl.startsWith('https') ? https : require('http');
      protocol.get(downloadUrl, (resp: any) => {
        // Handle redirects
        if (resp.statusCode >= 300 && resp.statusCode < 400 && resp.headers.location) {
          download(resp.headers.location, redirectCount + 1);
          return;
        }

        if (resp.statusCode !== 200) {
          reject(new Error(`Download failed: HTTP ${resp.statusCode}`));
          return;
        }

        const totalBytes = parseInt(resp.headers['content-length'] || '0', 10);
        let downloadedBytes = 0;
        const fileStream = fs.createWriteStream(partialPath);

        resp.on('data', (chunk: Buffer) => {
          downloadedBytes += chunk.length;
          if (totalBytes > 0 && onProgress) {
            onProgress(Math.round((downloadedBytes / totalBytes) * 100));
          }
        });

        resp.pipe(fileStream);

        fileStream.on('finish', () => {
          fileStream.close();
          // Atomic rename
          fs.renameSync(partialPath, destPath);
          invalidateBonsaiModelCache();
          resolve();
        });

        fileStream.on('error', (err: Error) => {
          // Clean up partial file
          try { fs.unlinkSync(partialPath); } catch { /* ignore */ }
          reject(err);
        });

        resp.on('error', (err: Error) => {
          try { fs.unlinkSync(partialPath); } catch { /* ignore */ }
          reject(err);
        });
      }).on('error', reject);
    };

    download(url, 0);
  });
}
