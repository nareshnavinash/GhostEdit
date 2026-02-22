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
import { SceneBackground } from "../../components/SceneBackground";

export const SceneOutro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Fade in from dark
  const fadeIn = interpolate(frame, [0, 20], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Logo pop
  const logoSpring = spring({
    frame: frame - 10,
    fps,
    config: { damping: 12, stiffness: 60 },
  });

  // Title
  const titleOpacity = interpolate(frame, [30, 45], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Subtitle
  const subtitleOpacity = interpolate(frame, [50, 65], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Shimmer effect across logo
  const shimmerX = interpolate(frame, [70, 100], [-200, 500], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <SceneBackground>
      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          opacity: fadeIn,
        }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 24,
          }}
        >
          {/* Logo with shimmer */}
          <div
            style={{
              position: "relative",
              transform: `scale(${logoSpring})`,
              overflow: "hidden",
              borderRadius: "22%",
            }}
          >
            <GhostLogo size={240} glowOpacity={0.3} showParticles />
            {/* Shimmer overlay */}
            {frame > 70 && (
              <div
                style={{
                  position: "absolute",
                  top: 0,
                  left: shimmerX,
                  width: 80,
                  height: "100%",
                  background:
                    "linear-gradient(90deg, transparent, rgba(255,255,255,0.15), transparent)",
                  transform: "skewX(-20deg)",
                }}
              />
            )}
          </div>

          {/* Title */}
          <div
            style={{
              ...fontStyles.title,
              fontSize: 72,
              color: colors.spiritWhite,
              opacity: titleOpacity,
            }}
          >
            GhostEdit
          </div>

          {/* Subtitle */}
          <div
            style={{
              ...fontStyles.body,
              fontSize: 28,
              color: colors.etherGray,
              opacity: subtitleOpacity,
            }}
          >
            Available for macOS
          </div>
        </div>
      </AbsoluteFill>
    </SceneBackground>
  );
};
