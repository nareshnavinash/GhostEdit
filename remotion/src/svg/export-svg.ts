/**
 * SVG Export Script
 *
 * Generates standalone SVG logo variants from the GhostLogo component.
 * Run with: npx tsx src/svg/export-svg.ts
 */

import fs from "fs";
import path from "path";
const INTER_FAMILY = "'Inter', sans-serif";

const SQUIRCLE_PATH =
  "M512 0C192.9 0 112.5 0 56.3 56.3S0 192.9 0 512s0 399.5 56.3 455.7S192.9 1024 512 1024s399.5 0 455.7-56.3S1024 831.1 1024 512s0-399.5-56.3-455.7S831.1 0 512 0z";

const GHOST_BODY_PATH =
  "M 512 175 C 654 175 742 280 742 430 L 742 660 C 742 720 720 760 684 760 C 648 760 630 700 598 700 C 566 700 548 760 512 760 C 476 760 458 700 426 700 C 394 700 376 760 340 760 C 304 760 282 720 282 660 L 282 430 C 282 280 370 175 512 175 Z";

const MOUTH_PATH = "M 478 500 L 546 500 C 546 555 478 555 478 500 Z";

const colors = {
  ghostInk: "#0D0F14",
  phantomSlate: "#1A1D27",
  spiritWhite: "#F1F3F8",
  spectralBlue: "#6C8EEF",
  ghostGlow: "#A78BFA",
};

function makeSvg(content: string, size = 1024): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg width="${size}" height="${size}" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
${content}
</svg>`;
}

function ghostElements(bodyFill: string, eyeFill: string): string {
  return `
  <!-- Ghost body -->
  <path d="${GHOST_BODY_PATH}" fill="${bodyFill}" />
  <!-- Eyes -->
  <ellipse cx="420" cy="390" rx="48" ry="60" fill="${eyeFill}" transform="rotate(-8, 420, 390)" />
  <ellipse cx="604" cy="390" rx="48" ry="60" fill="${eyeFill}" transform="rotate(8, 604, 390)" />
  <!-- Eye highlights -->
  <circle cx="436" cy="370" r="13" fill="#FFFFFF" />
  <circle cx="620" cy="370" r="13" fill="#FFFFFF" />
  <!-- Mouth -->
  <path d="${MOUTH_PATH}" fill="${eyeFill}" />`;
}

function fullColorSvg(bgColor: string): string {
  const isLight = bgColor === "#FFFFFF";
  const bodyFill = isLight ? colors.spiritWhite : "#FFFFFF";

  return makeSvg(`
  <defs>
    <linearGradient id="bg-grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${colors.phantomSlate}" />
      <stop offset="100%" stop-color="${colors.ghostInk}" />
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="45%" r="40%">
      <stop offset="0%" stop-color="${colors.spectralBlue}" stop-opacity="0.25" />
      <stop offset="70%" stop-color="${colors.ghostGlow}" stop-opacity="0.08" />
      <stop offset="100%" stop-color="transparent" stop-opacity="0" />
    </radialGradient>
  </defs>
  ${bgColor !== "none" ? `<rect width="1024" height="1024" fill="${bgColor}" />` : ""}
  <path d="${SQUIRCLE_PATH}" fill="${isLight ? "#FFFFFF" : "url(#bg-grad)"}" />
  ${isLight ? "" : `<circle cx="512" cy="460" r="320" fill="url(#glow)" />`}
  ${ghostElements(bodyFill, colors.phantomSlate)}`);
}

function monoSvg(color: string): string {
  return makeSvg(`
  <defs>
    <mask id="ghost-mask">
      <path d="${GHOST_BODY_PATH}" fill="white" />
      <ellipse cx="420" cy="390" rx="48" ry="60" fill="black" transform="rotate(-8, 420, 390)" />
      <ellipse cx="604" cy="390" rx="48" ry="60" fill="black" transform="rotate(8, 604, 390)" />
      <path d="${MOUTH_PATH}" fill="black" />
    </mask>
  </defs>
  <path d="${SQUIRCLE_PATH}" fill="none" stroke="${color}" stroke-width="24" />
  <path d="${GHOST_BODY_PATH}" fill="${color}" mask="url(#ghost-mask)" />`);
}

function wordmarkSvg(): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg width="600" height="120" viewBox="0 0 600 120" xmlns="http://www.w3.org/2000/svg">
  <text x="300" y="75" text-anchor="middle" dominant-baseline="central"
    font-family="${INTER_FAMILY}" font-weight="200" font-size="80"
    fill="${colors.spiritWhite}">GhostEdit</text>
</svg>`;
}

function logoWithWordmarkSvg(): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg width="800" height="200" viewBox="0 0 800 200" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg-grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="${colors.phantomSlate}" />
      <stop offset="100%" stop-color="${colors.ghostInk}" />
    </linearGradient>
    <radialGradient id="glow" cx="50%" cy="45%" r="40%">
      <stop offset="0%" stop-color="${colors.spectralBlue}" stop-opacity="0.2" />
      <stop offset="100%" stop-color="transparent" stop-opacity="0" />
    </radialGradient>
  </defs>
  <g transform="translate(20, 10) scale(0.176)">
    <path d="${SQUIRCLE_PATH}" fill="url(#bg-grad)" />
    <circle cx="512" cy="460" r="320" fill="url(#glow)" />
    ${ghostElements("#FFFFFF", colors.phantomSlate)}
  </g>
  <text x="250" y="115" text-anchor="start" dominant-baseline="central"
    font-family="${INTER_FAMILY}" font-weight="200" font-size="80"
    fill="${colors.spiritWhite}">GhostEdit</text>
</svg>`;
}

const outDir = path.resolve(__dirname);

const variants: [string, string][] = [
  ["LogoFullColor.svg", fullColorSvg("none")],
  ["LogoFullColorLight.svg", fullColorSvg("#FFFFFF")],
  ["LogoMonoWhite.svg", monoSvg("#FFFFFF")],
  ["LogoMonoBlack.svg", monoSvg("#000000")],
  ["Wordmark.svg", wordmarkSvg()],
  ["LogoWithWordmark.svg", logoWithWordmarkSvg()],
];

for (const [filename, content] of variants) {
  const filePath = path.join(outDir, filename);
  fs.writeFileSync(filePath, content, "utf-8");
  console.log(`✓ ${filename}`);
}

console.log(`\nDone! ${variants.length} SVG files written to ${outDir}`);
