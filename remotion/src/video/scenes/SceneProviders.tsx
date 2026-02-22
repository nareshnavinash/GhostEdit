import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  spring,
  useVideoConfig,
  interpolate,
} from "remotion";
import { colors } from "../../theme/colors";
import { fontStyles } from "../../theme/fonts";
import { GhostLogo } from "../../components/GhostLogo";
import { ProviderBadge } from "../../components/ProviderBadge";
import { SceneBackground } from "../../components/SceneBackground";

type Provider = "Claude" | "Codex" | "Gemini";
const PROVIDERS: Provider[] = ["Claude", "Codex", "Gemini"];

// Positions around the center logo
const POSITIONS = [
  { x: -280, y: -60 },
  { x: 280, y: -60 },
  { x: 0, y: 140 },
];

export const SceneProviders: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Title fades in
  const titleOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Center logo appears
  const logoScale = spring({
    frame,
    fps,
    config: { damping: 12, stiffness: 80 },
  });

  return (
    <SceneBackground>
      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {/* Title */}
        <div
          style={{
            position: "absolute",
            top: 80,
            ...fontStyles.title,
            fontSize: 42,
            color: colors.spiritWhite,
            opacity: titleOpacity,
            textAlign: "center",
          }}
        >
          Use any AI provider you like
        </div>

        {/* Center logo */}
        <div style={{ transform: `scale(${logoScale})` }}>
          <GhostLogo size={160} glowOpacity={0.3} />
        </div>

        {/* Provider badges orbiting */}
        {PROVIDERS.map((provider, i) => {
          const delay = 10 + i * 12;
          const badgeSpring = spring({
            frame: frame - delay,
            fps,
            config: { damping: 14, stiffness: 70 },
          });
          const pos = POSITIONS[i];
          const x = interpolate(badgeSpring, [0, 1], [0, pos.x]);
          const y = interpolate(badgeSpring, [0, 1], [0, pos.y]);

          // Connection line opacity
          const lineOpacity = interpolate(
            frame,
            [delay + 15, delay + 25],
            [0, 0.3],
            { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
          );

          return (
            <React.Fragment key={provider}>
              {/* Connection line */}
              <svg
                style={{
                  position: "absolute",
                  top: 0,
                  left: 0,
                  width: "100%",
                  height: "100%",
                  pointerEvents: "none",
                }}
              >
                <line
                  x1="50%"
                  y1="50%"
                  x2={`calc(50% + ${x}px)`}
                  y2={`calc(50% + ${y}px)`}
                  stroke={colors.spectralBlue}
                  strokeWidth={1}
                  opacity={lineOpacity}
                  strokeDasharray="4 4"
                />
              </svg>

              {/* Badge */}
              <div
                style={{
                  position: "absolute",
                  top: "50%",
                  left: "50%",
                  transform: `translate(calc(-50% + ${x}px), calc(-50% + ${y}px))`,
                  opacity: badgeSpring,
                }}
              >
                <ProviderBadge provider={provider} size="lg" />
              </div>
            </React.Fragment>
          );
        })}
      </AbsoluteFill>
    </SceneBackground>
  );
};
