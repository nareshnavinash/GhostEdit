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
import { SceneBackground } from "../../components/SceneBackground";
import { GhostParticles } from "../../components/GhostParticles";

const FEATURES = [
  {
    icon: "⌨️",
    title: "Global Hotkey",
    description: "Select text in any app, press ⌘E, and it's fixed.",
    accent: colors.spectralBlue,
  },
  {
    icon: "🔒",
    title: "Token Preservation",
    description: "Mentions, emojis, URLs, and code blocks stay untouched.",
    accent: colors.ghostGlow,
  },
  {
    icon: "🔀",
    title: "Your AI, Your Choice",
    description: "Claude, Codex, or Gemini — bring your own API key.",
    accent: colors.phantomGreen,
  },
  {
    icon: "📊",
    title: "Correction History",
    description: "Track every fix with diffs, timestamps, and per-app stats.",
    accent: colors.whisperRose,
  },
  {
    icon: "⚙️",
    title: "Fully Configurable",
    description: "Custom prompts, token rules, hotkeys, and notifications.",
    accent: colors.spectralBlue,
  },
  {
    icon: "🧠",
    title: "Writing Coach",
    description: "Learn from your mistakes with pattern analysis.",
    accent: colors.ghostGlow,
  },
];

const FRAMES_PER_CARD = 35;

export const SceneFeatures: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Which card is currently featured
  const activeIndex = Math.min(
    Math.floor(frame / FRAMES_PER_CARD),
    FEATURES.length - 1,
  );
  const cardLocalFrame = frame - activeIndex * FRAMES_PER_CARD;

  // After all cards have had their turn, show the final grid
  const allRevealed = frame >= FEATURES.length * FRAMES_PER_CARD;
  const gridTransition = allRevealed
    ? spring({
        frame: frame - FEATURES.length * FRAMES_PER_CARD,
        fps,
        config: { damping: 14, stiffness: 60 },
      })
    : 0;

  return (
    <SceneBackground>
      <GhostParticles count={12} seed={99} />
      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {!allRevealed ? (
          // === Individual card showcase ===
          <SingleCardShowcase
            feature={FEATURES[activeIndex]}
            localFrame={cardLocalFrame}
            index={activeIndex}
            fps={fps}
          />
        ) : (
          // === Final grid: all 6 cards ===
          <div
            style={{
              display: "flex",
              flexWrap: "wrap",
              gap: 28,
              maxWidth: 1100,
              justifyContent: "center",
              transform: `scale(${interpolate(gridTransition, [0, 1], [0.85, 1])})`,
              opacity: gridTransition,
            }}
          >
            {FEATURES.map((feature, i) => {
              const stagger = spring({
                frame: frame - FEATURES.length * FRAMES_PER_CARD - i * 3,
                fps,
                config: { damping: 12, stiffness: 100 },
              });
              return (
                <div
                  key={i}
                  style={{
                    width: 320,
                    padding: 22,
                    borderRadius: 14,
                    backgroundColor: colors.phantomSlate,
                    border: `1px solid ${feature.accent}33`,
                    opacity: stagger,
                    transform: `translateY(${interpolate(stagger, [0, 1], [20, 0])}px)`,
                  }}
                >
                  <div style={{ fontSize: 28, marginBottom: 8 }}>
                    {feature.icon}
                  </div>
                  <div
                    style={{
                      ...fontStyles.title,
                      fontSize: 18,
                      color: colors.spiritWhite,
                      marginBottom: 6,
                    }}
                  >
                    {feature.title}
                  </div>
                  <div
                    style={{
                      ...fontStyles.body,
                      fontSize: 14,
                      color: colors.etherGray,
                      lineHeight: 1.4,
                    }}
                  >
                    {feature.description}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </AbsoluteFill>
    </SceneBackground>
  );
};

// Individual card showcase — big centered card with glow + animation
const SingleCardShowcase: React.FC<{
  feature: (typeof FEATURES)[number];
  localFrame: number;
  index: number;
  fps: number;
}> = ({ feature, localFrame, index, fps }) => {
  // Icon scales in
  const iconSpring = spring({
    frame: localFrame,
    fps,
    config: { damping: 10, stiffness: 120 },
  });
  const iconScale = interpolate(iconSpring, [0, 1], [0.2, 1]);

  // Title slides up
  const titleSpring = spring({
    frame: localFrame - 4,
    fps,
    config: { damping: 14, stiffness: 80 },
  });
  const titleY = interpolate(titleSpring, [0, 1], [30, 0]);

  // Description fades in
  const descOpacity = interpolate(localFrame, [8, 16], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Glow burst behind the icon
  const glowIntensity = interpolate(localFrame, [0, 8, 20], [0, 0.6, 0.15], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Card entrance
  const cardSpring = spring({
    frame: localFrame,
    fps,
    config: { damping: 12, stiffness: 90 },
  });
  const cardScale = interpolate(cardSpring, [0, 1], [0.8, 1]);

  // Progress counter
  const counter = `${index + 1}/6`;

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 20,
        transform: `scale(${cardScale})`,
        opacity: cardSpring,
      }}
    >
      {/* Glow burst */}
      <div
        style={{
          position: "absolute",
          width: 300,
          height: 300,
          borderRadius: "50%",
          background: `radial-gradient(circle, ${feature.accent}${Math.round(glowIntensity * 80)
            .toString(16)
            .padStart(2, "0")} 0%, transparent 70%)`,
          pointerEvents: "none",
        }}
      />

      {/* Icon */}
      <div
        style={{
          fontSize: 80,
          transform: `scale(${iconScale})`,
          position: "relative",
        }}
      >
        {feature.icon}
      </div>

      {/* Title */}
      <div
        style={{
          ...fontStyles.title,
          fontSize: 44,
          color: colors.spiritWhite,
          transform: `translateY(${titleY}px)`,
          opacity: titleSpring,
        }}
      >
        {feature.title}
      </div>

      {/* Description */}
      <div
        style={{
          ...fontStyles.body,
          fontSize: 24,
          color: colors.etherGray,
          maxWidth: 600,
          textAlign: "center",
          lineHeight: 1.5,
          opacity: descOpacity,
        }}
      >
        {feature.description}
      </div>

      {/* Accent line */}
      <div
        style={{
          width: interpolate(cardSpring, [0, 1], [0, 80]),
          height: 3,
          borderRadius: 2,
          backgroundColor: feature.accent,
          marginTop: 8,
          boxShadow: `0 0 12px ${feature.accent}88`,
        }}
      />

      {/* Counter */}
      <div
        style={{
          position: "absolute",
          bottom: 60,
          ...fontStyles.regular,
          fontSize: 16,
          color: colors.etherGray,
          opacity: 0.5,
        }}
      >
        {counter}
      </div>
    </div>
  );
};
