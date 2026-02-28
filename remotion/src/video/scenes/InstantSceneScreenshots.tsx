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

const FEATURES = [
  {
    icon: "Live Feedback",
    emoji: "\u{1F4DD}",
    description: "Real-time spell & grammar checking",
  },
  {
    icon: "Writing Coach",
    emoji: "\u{1F3AF}",
    description: "Improve your writing style",
  },
  {
    icon: "Streaming Preview",
    emoji: "\u{26A1}",
    description: "Watch fixes appear live",
  },
  {
    icon: "Diff View",
    emoji: "\u{1F50D}",
    description: "See exactly what changed",
  },
  {
    icon: "Correction History",
    emoji: "\u{1F4CB}",
    description: "Browse past corrections",
  },
  {
    icon: "Custom Hotkeys",
    emoji: "\u{2328}\u{FE0F}",
    description: "Any key combo you want",
  },
];

const CARD_WIDTH = 420;
const CARD_HEIGHT = 140;
const GRID_GAP = 24;

export const InstantSceneScreenshots: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Cards spring in staggered: first at frame 10, each 8 frames apart
  const cardSprings = FEATURES.map((_, i) =>
    spring({
      frame: frame - (10 + i * 8),
      fps,
      config: { damping: 14, stiffness: 70 },
    }),
  );

  // Tagline (105-130)
  const taglineOpacity = interpolate(frame, [105, 118], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const taglineY = interpolate(frame, [105, 118], [15, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <LightSceneBackground variant="cool">
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
          {/* 2x3 Feature Grid */}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: `${CARD_WIDTH}px ${CARD_WIDTH}px`,
              gridTemplateRows: `${CARD_HEIGHT}px ${CARD_HEIGHT}px ${CARD_HEIGHT}px`,
              gap: GRID_GAP,
            }}
          >
            {FEATURES.map((feature, i) => {
              const s = cardSprings[i];
              const scale = interpolate(s, [0, 1], [0.7, 1]);
              return (
                <div
                  key={i}
                  style={{
                    width: CARD_WIDTH,
                    height: CARD_HEIGHT,
                    borderRadius: 16,
                    backgroundColor: lightColors.canvas,
                    border: `1px solid ${lightColors.border}`,
                    boxShadow: "0 4px 24px rgba(0,0,0,0.06)",
                    display: "flex",
                    flexDirection: "row",
                    alignItems: "center",
                    gap: 16,
                    padding: "0 28px",
                    transform: `scale(${scale})`,
                    opacity: s,
                  }}
                >
                  {/* Emoji icon */}
                  <div style={{ fontSize: 36, flexShrink: 0 }}>
                    {feature.emoji}
                  </div>
                  {/* Text */}
                  <div
                    style={{
                      display: "flex",
                      flexDirection: "column",
                      gap: 4,
                    }}
                  >
                    <div
                      style={{
                        ...fontStyles.title,
                        fontSize: 22,
                        color: lightColors.textPrimary,
                      }}
                    >
                      {feature.icon}
                    </div>
                    <div
                      style={{
                        ...fontStyles.body,
                        fontSize: 16,
                        color: lightColors.textSecondary,
                        lineHeight: 1.4,
                      }}
                    >
                      {feature.description}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>

          {/* Tagline */}
          {frame >= 105 && (
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
              Fully configurable. Every detail.
            </div>
          )}
        </div>
      </AbsoluteFill>
    </LightSceneBackground>
  );
};
