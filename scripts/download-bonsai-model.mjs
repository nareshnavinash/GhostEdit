/**
 * Downloads the Bonsai 1.7B GGUF model into resources/models/bonsai/
 * so it can be bundled with the app via extraResource.
 *
 * Usage: node scripts/download-bonsai-model.mjs
 */
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const destDir = path.join(__dirname, '..', 'resources', 'models', 'bonsai');
const filename = 'Bonsai-1.7B.gguf';
const destPath = path.join(destDir, filename);
const url = 'https://huggingface.co/prism-ml/Bonsai-1.7B-gguf/resolve/main/Bonsai-1.7B.gguf';

if (fs.existsSync(destPath)) {
  const stats = fs.statSync(destPath);
  console.log(`Model already exists (${(stats.size / 1024 / 1024).toFixed(1)} MB): ${destPath}`);
  process.exit(0);
}

fs.mkdirSync(destDir, { recursive: true });

console.log(`Downloading Bonsai 1.7B to: ${destPath}`);

function download(downloadUrl, redirectCount = 0) {
  if (redirectCount > 5) {
    console.error('Too many redirects');
    process.exit(1);
  }

  https.get(downloadUrl, (resp) => {
    if (resp.statusCode >= 300 && resp.statusCode < 400 && resp.headers.location) {
      download(resp.headers.location, redirectCount + 1);
      return;
    }

    if (resp.statusCode !== 200) {
      console.error(`Download failed: HTTP ${resp.statusCode}`);
      process.exit(1);
    }

    const totalBytes = parseInt(resp.headers['content-length'] || '0', 10);
    let downloadedBytes = 0;
    const partialPath = destPath + '.partial';
    const fileStream = fs.createWriteStream(partialPath);

    resp.on('data', (chunk) => {
      downloadedBytes += chunk.length;
      if (totalBytes > 0) {
        const pct = Math.round((downloadedBytes / totalBytes) * 100);
        const mb = (downloadedBytes / 1024 / 1024).toFixed(1);
        const totalMb = (totalBytes / 1024 / 1024).toFixed(1);
        process.stdout.write(`\r  ${mb} MB / ${totalMb} MB (${pct}%)`);
      }
    });

    resp.pipe(fileStream);

    fileStream.on('finish', () => {
      fileStream.close();
      fs.renameSync(partialPath, destPath);
      const finalSize = (fs.statSync(destPath).size / 1024 / 1024).toFixed(1);
      console.log(`\nDownloaded successfully: ${filename} (${finalSize} MB)`);
    });

    fileStream.on('error', (err) => {
      try { fs.unlinkSync(partialPath); } catch { /* ignore */ }
      console.error('Write error:', err.message);
      process.exit(1);
    });
  }).on('error', (err) => {
    console.error('Download error:', err.message);
    process.exit(1);
  });
}

download(url);
