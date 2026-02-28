// GhostEdit Light Theme Palette

export const lightColors = {
  // Backgrounds
  canvas: "#FFFFFF",
  surface: "#F8F9FC",
  panel: "#F1F3F8",
  border: "#E5E7EB",

  // Text
  textPrimary: "#1A1D27",
  textSecondary: "#4B5563",
  textTertiary: "#9CA3AF",

  // Accents (same brand colors)
  spectralBlue: "#6C8EEF",
  ghostGlow: "#A78BFA",
  phantomGreen: "#34D399",
  whisperRose: "#F472B6",

  // Semantic
  success: "#22C55E",
  error: "#EF4444",
  warning: "#F59E0B",

  // Provider
  claude: "#D97757",
  codex: "#10A37F",
  gemini: "#4285F4",
} as const;

export const lightGradients = {
  canvasRadial:
    "radial-gradient(ellipse at 50% 40%, #EEF0FF 0%, #FFFFFF 70%)",
  canvasRadialCool:
    "radial-gradient(ellipse at 50% 40%, #E0E7FF 0%, #FFFFFF 70%)",
  canvasRadialWarm:
    "radial-gradient(ellipse at 50% 40%, #FFF0F5 0%, #FFFFFF 70%)",
  brand: "linear-gradient(135deg, #6C8EEF, #A78BFA)",
  brandText: "linear-gradient(135deg, #6C8EEF, #A78BFA)",
} as const;
