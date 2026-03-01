import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  interpolate,
  spring,
  useVideoConfig,
} from "remotion";
import { lightColors, lightGradients } from "../../theme/lightColors";
import { fontStyles } from "../../theme/fonts";
import { LightSceneBackground } from "../../components/LightSceneBackground";
import { LightFeatureCard } from "../../components/LightFeatureCard";

export const InstantSceneComparison: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Left card spring from left (10-25)
  const leftSpring = spring({
    frame: frame - 10,
    fps,
    config: { damping: 14, stiffness: 80 },
  });
  const leftX = interpolate(leftSpring, [0, 1], [-400, 0]);

  // Right card spring from right (18-33)
  const rightSpring = spring({
    frame: frame - 18,
    fps,
    config: { damping: 14, stiffness: 80 },
  });
  const rightX = interpolate(rightSpring, [0, 1], [400, 0]);

  // Right card glow + checkmark (40-48)
  const glowOpacity = interpolate(frame, [40, 48], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Bullet points stagger (50-75)
  const bullets = [
    "Free forever - no subscriptions",
    "No account needed",
    "100% local - nothing sent to the cloud",
  ];

  // Gradient tagline (75-120)
  const taglineOpacity = interpolate(frame, [65, 78], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const taglineY = interpolate(frame, [65, 78], [20, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <LightSceneBackground>
      <AbsoluteFill
        style={{ alignItems: "center", justifyContent: "center" }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 40,
          }}
        >
          {/* Two cards side by side */}
          <div style={{ display: "flex", gap: 40 }}>
            {/* Left card — Others (mild red tint) */}
            <div
              style={{
                transform: `translateX(${leftX}px)`,
                borderRadius: 20,
                backgroundColor: `${lightColors.error}0C`,
                border: `1.5px solid ${lightColors.error}22`,
                padding: 4,
              }}
            >
              <LightFeatureCard
                icon="💸"
                title="Other Tools"
                description="$20–30/mo, data sent to their servers"
                accentColor={lightColors.error}
                width={480}
              />
            </div>

            {/* Right card — GhostEdit (mild green tint) */}
            <div
              style={{
                transform: `translateX(${rightX}px)`,
                position: "relative",
                borderRadius: 20,
                backgroundColor: `${lightColors.success}0C`,
                border: `1.5px solid ${lightColors.success}22`,
                padding: 4,
              }}
            >
              <div
                style={{
                  boxShadow:
                    glowOpacity > 0
                      ? `0 0 30px ${lightColors.success}${Math.round(glowOpacity * 40)
                          .toString(16)
                          .padStart(2, "0")}`
                      : "none",
                  borderRadius: 16,
                }}
              >
                <LightFeatureCard
                  icon="👻"
                  title="GhostEdit"
                  description="100% free — data never leaves your Mac"
                  accentColor={lightColors.success}
                  width={480}
                />
              </div>
              {/* Green checkmark */}
              {frame >= 40 && (
                <div
                  style={{
                    position: "absolute",
                    top: -8,
                    right: -8,
                    width: 36,
                    height: 36,
                    borderRadius: "50%",
                    backgroundColor: lightColors.success,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    opacity: glowOpacity,
                    fontSize: 18,
                    color: "#FFFFFF",
                    boxShadow: "0 2px 8px rgba(34,197,94,0.4)",
                  }}
                >
                  ✓
                </div>
              )}
            </div>
          </div>

          {/* Bullet points */}
          <div style={{ display: "flex", gap: 32 }}>
            {bullets.map((text, i) => {
              const bulletDelay = 50 + i * 8;
              const bulletOpacity = interpolate(
                frame,
                [bulletDelay, bulletDelay + 10],
                [0, 1],
                { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
              );
              const bulletY = interpolate(
                frame,
                [bulletDelay, bulletDelay + 10],
                [10, 0],
                { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
              );
              return (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 8,
                    opacity: bulletOpacity,
                    transform: `translateY(${bulletY}px)`,
                  }}
                >
                  <div
                    style={{
                      width: 28,
                      height: 28,
                      borderRadius: "50%",
                      backgroundColor: `${lightColors.success}18`,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      fontSize: 16,
                      color: lightColors.success,
                    }}
                  >
                    ✓
                  </div>
                  <span
                    style={{
                      ...fontStyles.regular,
                      fontSize: 24,
                      color: lightColors.textPrimary,
                    }}
                  >
                    {text}
                  </span>
                </div>
              );
            })}
          </div>

          {/* Gradient tagline */}
          <div
            style={{
              ...fontStyles.title,
              fontSize: 42,
              background: lightGradients.brandText,
              WebkitBackgroundClip: "text",
              WebkitTextFillColor: "transparent",
              opacity: taglineOpacity,
              transform: `translateY(${taglineY}px)`,
            }}
          >
            Your text. Your machine. Your rules.
          </div>
        </div>
      </AbsoluteFill>
    </LightSceneBackground>
  );
};
