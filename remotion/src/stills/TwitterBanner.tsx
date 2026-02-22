import React from "react";
import { AbsoluteFill } from "remotion";
import { colors, gradients } from "../theme/colors";
import { fontStyles } from "../theme/fonts";
import { GhostLogo } from "../components/GhostLogo";
import { ProviderBadge } from "../components/ProviderBadge";

// Static ambient particles to fill corners
const PARTICLES: { x: number; y: number; size: number; opacity: number; color: string }[] = [
  // Top-left quadrant
  { x: 60, y: 40, size: 4, opacity: 0.35, color: colors.spectralBlue },
  { x: 150, y: 100, size: 3, opacity: 0.25, color: colors.ghostGlow },
  { x: 90, y: 180, size: 5, opacity: 0.3, color: colors.spectralBlue },
  // Top-right quadrant
  { x: 1380, y: 50, size: 4, opacity: 0.3, color: colors.ghostGlow },
  { x: 1440, y: 140, size: 3, opacity: 0.25, color: colors.spectralBlue },
  { x: 1300, y: 90, size: 5, opacity: 0.35, color: colors.ghostGlow },
  // Bottom-left quadrant
  { x: 80, y: 380, size: 4, opacity: 0.3, color: colors.spectralBlue },
  { x: 170, y: 440, size: 3, opacity: 0.25, color: colors.ghostGlow },
  { x: 50, y: 320, size: 5, opacity: 0.35, color: colors.spectralBlue },
  // Bottom-right quadrant
  { x: 1400, y: 370, size: 4, opacity: 0.25, color: colors.ghostGlow },
  { x: 1320, y: 430, size: 3, opacity: 0.3, color: colors.spectralBlue },
  { x: 1450, y: 290, size: 5, opacity: 0.35, color: colors.ghostGlow },
  // Extra center-edge particles
  { x: 200, y: 250, size: 3, opacity: 0.2, color: colors.spectralBlue },
  { x: 1250, y: 250, size: 3, opacity: 0.2, color: colors.ghostGlow },
];

export const TwitterBanner: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: gradients.darkRadial }}>
      {/* Corner radial glows */}
      <div
        style={{
          position: "absolute",
          top: -100,
          right: -100,
          width: 500,
          height: 400,
          borderRadius: "50%",
          background: `radial-gradient(circle, ${colors.spectralBlue}10 0%, transparent 70%)`,
          opacity: 0.06,
        }}
      />
      <div
        style={{
          position: "absolute",
          bottom: -100,
          left: -100,
          width: 500,
          height: 400,
          borderRadius: "50%",
          background: `radial-gradient(circle, ${colors.ghostGlow}10 0%, transparent 70%)`,
          opacity: 0.06,
        }}
      />

      {/* Ambient particles */}
      {PARTICLES.map((p, i) => (
        <div
          key={i}
          style={{
            position: "absolute",
            left: p.x,
            top: p.y,
            width: p.size,
            height: p.size,
            borderRadius: "50%",
            backgroundColor: p.color,
            opacity: p.opacity,
            boxShadow: `0 0 ${p.size * 3}px ${p.color}`,
          }}
        />
      ))}

      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          width: "100%",
          height: "100%",
          padding: "0 50px",
          gap: 60,
        }}
      >
        {/* Left - Logo */}
        <GhostLogo size={340} glowOpacity={0.3} showParticles />

        {/* Right - Text + badges */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 16,
          }}
        >
          <div
            style={{
              ...fontStyles.title,
              fontSize: 64,
              color: colors.spiritWhite,
            }}
          >
            GhostEdit
          </div>
          <div
            style={{
              ...fontStyles.body,
              fontSize: 24,
              color: colors.etherGray,
              maxWidth: 500,
            }}
          >
            Fix your writing. Sharpen your habits.
          </div>
          <div style={{ display: "flex", gap: 12, marginTop: 12 }}>
            <ProviderBadge provider="Claude" size="md" />
            <ProviderBadge provider="Codex" size="md" />
            <ProviderBadge provider="Gemini" size="md" />
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
