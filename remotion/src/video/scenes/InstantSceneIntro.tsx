import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  interpolate,
  spring,
  useVideoConfig,
} from "remotion";
import { lightColors } from "../../theme/lightColors";
import { fontStyles } from "../../theme/fonts";
import { GhostLogo } from "../../components/GhostLogo";
import { GhostParticles } from "../../components/GhostParticles";
import { LightSceneBackground } from "../../components/LightSceneBackground";

export const InstantSceneIntro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Background fade in (0-15)
  const bgOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Radial blue glow expands (0-15)
  const glowRadius = interpolate(frame, [0, 15], [0, 500], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const glowIntensity = interpolate(frame, [0, 8, 15], [0, 0.3, 0.15], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Logo spring in (10-50)
  const logoSpring = spring({
    frame: frame - 10,
    fps,
    config: { damping: 12, stiffness: 60 },
  });
  const logoScale =
    frame >= 10 ? interpolate(logoSpring, [0, 1], [0.3, 1]) : 0;
  const logoOpacity = frame >= 10 ? logoSpring : 0;

  // Shimmer sweep (40-70)
  const shimmerX = interpolate(frame, [40, 70], [-280, 580], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Letter-by-letter title (55-90)
  const titleText = "GhostEdit";

  // Subtitle fade in (90-120)
  const subtitleOpacity = interpolate(frame, [85, 105], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const subtitleY = interpolate(frame, [85, 105], [12, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <LightSceneBackground variant="cool">
      <AbsoluteFill style={{ opacity: bgOpacity }}>
        {/* Expanding radial glow burst */}
        <AbsoluteFill
          style={{
            background: `radial-gradient(circle at 50% 42%, ${lightColors.spectralBlue}${Math.round(glowIntensity * 40)
              .toString(16)
              .padStart(2, "0")} 0%, transparent ${glowRadius}px)`,
          }}
        />

        {/* Particles behind logo */}
        {frame > 50 && (
          <GhostParticles
            count={15}
            color={lightColors.spectralBlue}
            seed={42}
          />
        )}

        <AbsoluteFill
          style={{ alignItems: "center", justifyContent: "center" }}
        >
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 28,
            }}
          >
            {/* App icon with shimmer */}
            <div
              style={{
                position: "relative",
                transform: `scale(${logoScale})`,
                opacity: logoOpacity,
                overflow: "hidden",
                borderRadius: "22%",
              }}
            >
              <GhostLogo size={280} glowOpacity={0.2} variant="full" />
              {/* Shimmer overlay */}
              {frame >= 40 && frame <= 70 && (
                <div
                  style={{
                    position: "absolute",
                    top: 0,
                    left: shimmerX,
                    width: 120,
                    height: "100%",
                    background:
                      "linear-gradient(90deg, transparent, rgba(255,255,255,0.35), transparent)",
                    transform: "skewX(-20deg)",
                  }}
                />
              )}
            </div>

            {/* Letter-by-letter title */}
            <div
              style={{
                ...fontStyles.title,
                fontSize: 72,
                color: lightColors.textPrimary,
                display: "flex",
              }}
            >
              {titleText.split("").map((char, i) => {
                const charDelay = 55 + i * 3;
                const charOpacity = interpolate(
                  frame,
                  [charDelay, charDelay + 8],
                  [0, 1],
                  {
                    extrapolateLeft: "clamp",
                    extrapolateRight: "clamp",
                  },
                );
                return (
                  <span key={i} style={{ opacity: charOpacity }}>
                    {char}
                  </span>
                );
              })}
            </div>

            {/* Subtitle */}
            <div
              style={{
                ...fontStyles.body,
                fontSize: 32,
                color: lightColors.textSecondary,
                opacity: subtitleOpacity,
                transform: `translateY(${subtitleY}px)`,
              }}
            >
              Instant grammar correction for macOS
            </div>
          </div>
        </AbsoluteFill>
      </AbsoluteFill>
    </LightSceneBackground>
  );
};
