import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  interpolate,
  spring,
  useVideoConfig,
} from "remotion";
import { colors } from "../../theme/colors";
import { fontStyles } from "../../theme/fonts";
import { GhostLogo } from "../../components/GhostLogo";

export const SceneIntro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Phase 1: Radial glow expands from center (frames 0-30)
  const glowRadius = interpolate(frame, [0, 30], [0, 600], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const glowIntensity = interpolate(frame, [0, 15, 30], [0, 0.5, 0.25], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Phase 2: App icon scales in with spring (frames 10-50)
  const logoSpring = spring({
    frame: frame - 10,
    fps,
    config: { damping: 12, stiffness: 60 },
  });
  const logoScale = frame >= 10 ? interpolate(logoSpring, [0, 1], [0.3, 1]) : 0;
  const logoOpacity = frame >= 10 ? logoSpring : 0;

  // Phase 3: Shimmer sweep across logo (frames 40-70)
  const shimmerX = interpolate(frame, [40, 70], [-250, 550], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Phase 4: "GhostEdit" text fades in letter by letter (frame 55-90)
  const titleText = "GhostEdit";
  const titleOpacity = interpolate(frame, [55, 65], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Background glow settles
  const bgGlowOpacity = interpolate(frame, [10, 60], [0, 0.4], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ background: colors.ghostInk }}>
      {/* Expanding radial glow burst */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at 50% 45%, ${colors.spectralBlue}${Math.round(glowIntensity * 60)
            .toString(16)
            .padStart(2, "0")} 0%, transparent ${glowRadius}px)`,
        }}
      />

      {/* Persistent background glow */}
      <AbsoluteFill
        style={{
          background: `radial-gradient(circle at 50% 45%, ${colors.spectralBlue}${Math.round(bgGlowOpacity * 40)
            .toString(16)
            .padStart(2, "0")} 0%, transparent 50%)`,
        }}
      />

      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {/* App icon with shimmer */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 30,
          }}
        >
          <div
            style={{
              position: "relative",
              transform: `scale(${logoScale})`,
              opacity: logoOpacity,
              overflow: "hidden",
              borderRadius: "22%",
            }}
          >
            <GhostLogo
              size={300}
              glowOpacity={0.25}
              showParticles={frame > 50}
            />
            {/* Shimmer overlay */}
            {frame >= 40 && frame <= 70 && (
              <div
                style={{
                  position: "absolute",
                  top: 0,
                  left: shimmerX,
                  width: 100,
                  height: "100%",
                  background:
                    "linear-gradient(90deg, transparent, rgba(255,255,255,0.2), transparent)",
                  transform: "skewX(-20deg)",
                }}
              />
            )}
          </div>

          {/* Title appearing letter by letter */}
          <div
            style={{
              ...fontStyles.title,
              fontSize: 72,
              color: colors.spiritWhite,
              opacity: titleOpacity,
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
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
