import React from "react";
import { AbsoluteFill } from "remotion";
import { lightColors, lightGradients } from "../theme/lightColors";
import { fontStyles } from "../theme/fonts";
import { GhostLogo } from "../components/GhostLogo";

const FEATURE_PILLS: { emoji: string; label: string }[] = [
  { emoji: "\u{1F9E0}", label: "Local Models" },
  { emoji: "\u{26A1}", label: "Instant Fix" },
  { emoji: "\u{1F512}", label: "Privacy First" },
];

const PROVIDERS: { name: string; color: string }[] = [
  { name: "Claude", color: lightColors.claude },
  { name: "Codex", color: lightColors.codex },
  { name: "Gemini", color: lightColors.gemini },
];

export const TwitterBanner: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: lightGradients.canvasRadialCool }}>
      {/* Subtle radial accent top-right */}
      <div
        style={{
          position: "absolute",
          top: -120,
          right: -80,
          width: 500,
          height: 400,
          borderRadius: "50%",
          background: `radial-gradient(circle, ${lightColors.spectralBlue}12 0%, transparent 70%)`,
        }}
      />
      {/* Subtle radial accent bottom-left */}
      <div
        style={{
          position: "absolute",
          bottom: -120,
          left: -80,
          width: 500,
          height: 400,
          borderRadius: "50%",
          background: `radial-gradient(circle, ${lightColors.ghostGlow}10 0%, transparent 70%)`,
        }}
      />

      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          width: "100%",
          height: "100%",
          padding: "0 80px 0 160px",
          gap: 56,
        }}
      >
        {/* Left — Logo with dark squircle */}
        <GhostLogo size={300} glowOpacity={0.15} variant="full" />

        {/* Right — Text + feature pills */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 14,
          }}
        >
          {/* Title */}
          <div
            style={{
              ...fontStyles.title,
              fontSize: 96,
              color: lightColors.textPrimary,
              lineHeight: 1,
              textAlign: "center",
            }}
          >
            GhostEdit
          </div>

          {/* Subtitle */}
          <div
            style={{
              ...fontStyles.body,
              fontSize: 36,
              color: lightColors.textSecondary,
              lineHeight: 1.3,
              textAlign: "center",
            }}
          >
            Grammar correction for everyone
          </div>

          {/* Feature pills row */}
          <div style={{ display: "flex", gap: 12, marginTop: 12, flexWrap: "wrap", justifyContent: "center" }}>
            {/* Feature pills */}
            {FEATURE_PILLS.map((pill, i) => (
              <div
                key={i}
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: 8,
                  padding: "8px 20px",
                  borderRadius: 999,
                  backgroundColor: lightColors.surface,
                  border: `1px solid ${lightColors.border}`,
                  ...fontStyles.regular,
                  fontSize: 22,
                  color: lightColors.textPrimary,
                }}
              >
                <span>{pill.emoji}</span>
                <span>{pill.label}</span>
              </div>
            ))}

            {/* Cloud providers pill */}
            <div
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 10,
                padding: "8px 20px",
                borderRadius: 999,
                backgroundColor: lightColors.surface,
                border: `1px solid ${lightColors.border}`,
                ...fontStyles.regular,
                fontSize: 22,
                color: lightColors.textSecondary,
              }}
            >
              <span>{"\u2601\uFE0F"}</span>
              {PROVIDERS.map((p, i) => (
                <React.Fragment key={p.name}>
                  <span style={{ display: "inline-flex", alignItems: "center", gap: 5 }}>
                    <span
                      style={{
                        display: "inline-block",
                        width: 10,
                        height: 10,
                        borderRadius: "50%",
                        backgroundColor: p.color,
                      }}
                    />
                    <span style={{ color: lightColors.textPrimary }}>{p.name}</span>
                  </span>
                  {i < PROVIDERS.length - 1 && (
                    <span style={{ color: lightColors.border }}>{"\u00B7"}</span>
                  )}
                </React.Fragment>
              ))}
            </div>
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
