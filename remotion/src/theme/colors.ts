// GhostEdit Brand Color Palette

export const colors = {
  ghostInk: "#0D0F14",
  phantomSlate: "#1A1D27",
  etherGray: "#6B7280",
  spiritWhite: "#F1F3F8",
  spectralBlue: "#6C8EEF",
  ghostGlow: "#A78BFA",
  phantomGreen: "#34D399",
  whisperRose: "#F472B6",
} as const;

export const gradients = {
  brand: "linear-gradient(135deg, #6C8EEF, #A78BFA)",
  brandReverse: "linear-gradient(135deg, #A78BFA, #6C8EEF)",
  darkRadial: `radial-gradient(ellipse at 50% 40%, ${colors.phantomSlate} 0%, ${colors.ghostInk} 70%)`,
  glowBlue: `radial-gradient(circle, ${colors.spectralBlue}33 0%, transparent 70%)`,
  glowViolet: `radial-gradient(circle, ${colors.ghostGlow}33 0%, transparent 70%)`,
} as const;
