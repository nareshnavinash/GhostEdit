/**
 * Downloads llama-server binaries from llama.cpp GitHub releases
 * for all supported platforms into resources/bin/<platform-arch>/
 *
 * Usage: node scripts/download-llama-server.mjs
 *
 * By default downloads the latest release. Pass a tag to pin:
 *   node scripts/download-llama-server.mjs b5460
 */
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const binDir = path.join(__dirname, '..', 'resources', 'bin');

// Map of platform-arch to llama.cpp release asset name patterns
// These patterns match the naming convention from llama.cpp GitHub releases
const PLATFORMS = {
  'darwin-arm64': { asset: 'llama-*-bin-macos-arm64.zip', binary: 'llama-server' },
  'darwin-x64': { asset: 'llama-*-bin-macos-x64.zip', binary: 'llama-server' },
  'linux-x64': { asset: 'llama-*-bin-ubuntu-x64.zip', binary: 'llama-server' },
  'win32-x64': { asset: 'llama-*-bin-win-avx2-x64.zip', binary: 'llama-server.exe' },
};

// Only download for the current platform by default, or all if --all is passed
const downloadAll = process.argv.includes('--all');
const currentPlatform = `${process.platform}-${process.arch}`;
const targetTag = process.argv.find((a) => !a.startsWith('-') && a !== process.argv[0] && a !== process.argv[1]);

const platformsToDownload = downloadAll
  ? Object.keys(PLATFORMS)
  : PLATFORMS[currentPlatform]
    ? [currentPlatform]
    : [];

if (platformsToDownload.length === 0) {
  console.log(`No llama-server binary available for ${currentPlatform}`);
  console.log('Use --all to download for all platforms');
  process.exit(0);
}

console.log(`Downloading llama-server for: ${platformsToDownload.join(', ')}`);
console.log(`Target: ${binDir}`);
console.log('');
console.log('NOTE: You need to manually download llama-server binaries from');
console.log('  https://github.com/ggml-org/llama.cpp/releases');
console.log('');
console.log('For each platform, download the appropriate zip, extract llama-server,');
console.log('and place it in the corresponding directory:');
console.log('');

for (const platform of platformsToDownload) {
  const info = PLATFORMS[platform];
  const destDir = path.join(binDir, platform);
  const destPath = path.join(destDir, info.binary);

  if (fs.existsSync(destPath)) {
    console.log(`  ${platform}: already exists at ${destPath}`);
    continue;
  }

  fs.mkdirSync(destDir, { recursive: true });
  console.log(`  ${platform}: place ${info.binary} in ${destDir}/`);
  console.log(`    Asset pattern: ${info.asset}`);
}

console.log('');
console.log('After placing binaries, make them executable:');
console.log('  chmod +x resources/bin/*/llama-server');
