import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  interpolate,
  spring,
  useVideoConfig,
} from "remotion";
import { colors, gradients } from "../../theme/colors";
import { fontStyles } from "../../theme/fonts";
import { SceneBackground } from "../../components/SceneBackground";

interface CoachItem {
  text: string;
  color: string;
}

const strengths: CoachItem[] = [
  { text: "Clear sentence structure", color: colors.phantomGreen },
  { text: "Good use of active voice", color: colors.phantomGreen },
  { text: "Consistent tone throughout", color: colors.phantomGreen },
];

const improvements: CoachItem[] = [
  { text: "Frequent their/they're confusion", color: colors.whisperRose },
  { text: "Affect vs. effect mix-ups", color: colors.whisperRose },
  { text: "Missing possessive apostrophes", color: colors.whisperRose },
];

export const SceneWritingCoach: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Phase 1: Title + button appear (0-20)
  const titleOpacity = interpolate(frame, [0, 15], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  const btnSpring = spring({
    frame: frame - 5,
    fps,
    config: { damping: 14, stiffness: 80 },
  });

  // Phase 2: Cursor moves from bottom-right to button center (20-40)
  const cursorLeft = interpolate(frame, [20, 38], [320, 160], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const cursorTop = interpolate(frame, [20, 38], [140, 22], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const cursorOpacity = interpolate(frame, [20, 24, 38, 50], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Phase 3: Button press (40-50)
  const isPressed = frame >= 40 && frame < 48;
  const btnScale = isPressed ? 0.95 : 1;
  const btnGlow = interpolate(frame, [40, 45, 55], [0, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Phase 4: Button fades out, panels slide in (50+)
  const btnFadeOut = interpolate(frame, [50, 60], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Panels slide in from sides
  const leftPanelSpring = spring({
    frame: frame - 60,
    fps,
    config: { damping: 14, stiffness: 60 },
  });
  const rightPanelSpring = spring({
    frame: frame - 70,
    fps,
    config: { damping: 14, stiffness: 60 },
  });
  const leftX = frame >= 60 ? interpolate(leftPanelSpring, [0, 1], [-400, 0]) : -400;
  const rightX = frame >= 70 ? interpolate(rightPanelSpring, [0, 1], [400, 0]) : 400;

  // Tagline
  const tagOpacity = interpolate(frame, [140, 155], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
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
            fontSize: 48,
            color: colors.spiritWhite,
            opacity: titleOpacity,
          }}
        >
          Writing Coach
        </div>

        {/* Button — visible until panels come in */}
        <div
          style={{
            position: "relative",
            opacity: Math.min(btnSpring, btnFadeOut),
            transform: `scale(${btnScale * interpolate(btnSpring, [0, 1], [0.8, 1])})`,
          }}
        >
          <div
            style={{
              padding: "18px 40px",
              borderRadius: 14,
              background: gradients.brand,
              boxShadow: btnGlow > 0
                ? `0 0 ${30 * btnGlow}px ${colors.spectralBlue}88, 0 0 ${60 * btnGlow}px ${colors.ghostGlow}44`
                : "0 4px 20px rgba(0,0,0,0.3)",
              cursor: "pointer",
              ...fontStyles.regular,
              fontSize: 22,
              color: colors.spiritWhite,
              textAlign: "center" as const,
            }}
          >
            Sharpen My Writing Style
          </div>

          {/* Cursor — moves from bottom-right to button center */}
          {cursorOpacity > 0 && (
            <div
              style={{
                position: "absolute",
                left: cursorLeft,
                top: cursorTop,
                opacity: cursorOpacity,
                pointerEvents: "none",
              }}
            >
              <svg width={24} height={28} viewBox="0 0 24 28" fill="none">
                <path
                  d="M5 2L5 22L9.5 17.5L13.5 25L17 23L13 15.5L19 15.5L5 2Z"
                  fill="white"
                  stroke={colors.ghostInk}
                  strokeWidth={1.5}
                />
              </svg>
            </div>
          )}
        </div>

        {/* Panels — appear after button click */}
        <div
          style={{
            display: "flex",
            gap: 36,
            position: "absolute",
            top: "50%",
            transform: "translateY(-50%)",
          }}
        >
          {/* Strengths panel */}
          <div
            style={{
              width: 380,
              padding: 26,
              borderRadius: 16,
              backgroundColor: colors.phantomSlate,
              border: `1px solid ${colors.phantomGreen}33`,
              transform: `translateX(${leftX}px)`,
              opacity: leftPanelSpring,
            }}
          >
            <div
              style={{
                ...fontStyles.title,
                fontSize: 20,
                color: colors.phantomGreen,
                marginBottom: 18,
              }}
            >
              Strengths
            </div>
            {strengths.map((item, i) => {
              const itemDelay = 75 + i * 10;
              const itemOpacity = interpolate(
                frame,
                [itemDelay, itemDelay + 12],
                [0, 1],
                { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
              );
              const itemX = interpolate(
                frame,
                [itemDelay, itemDelay + 12],
                [-20, 0],
                { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
              );
              return (
                <div
                  key={i}
                  style={{
                    ...fontStyles.regular,
                    fontSize: 17,
                    color: item.color,
                    opacity: itemOpacity,
                    transform: `translateX(${itemX}px)`,
                    padding: "7px 0",
                    display: "flex",
                    alignItems: "center",
                    gap: 10,
                  }}
                >
                  <span>✓</span> {item.text}
                </div>
              );
            })}
          </div>

          {/* Improvements panel */}
          <div
            style={{
              width: 380,
              padding: 26,
              borderRadius: 16,
              backgroundColor: colors.phantomSlate,
              border: `1px solid ${colors.whisperRose}33`,
              transform: `translateX(${rightX}px)`,
              opacity: rightPanelSpring,
            }}
          >
            <div
              style={{
                ...fontStyles.title,
                fontSize: 20,
                color: colors.whisperRose,
                marginBottom: 18,
              }}
            >
              Areas to Improve
            </div>
            {improvements.map((item, i) => {
              const itemDelay = 85 + i * 10;
              const itemOpacity = interpolate(
                frame,
                [itemDelay, itemDelay + 12],
                [0, 1],
                { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
              );
              const itemX = interpolate(
                frame,
                [itemDelay, itemDelay + 12],
                [20, 0],
                { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
              );
              return (
                <div
                  key={i}
                  style={{
                    ...fontStyles.regular,
                    fontSize: 17,
                    color: item.color,
                    opacity: itemOpacity,
                    transform: `translateX(${itemX}px)`,
                    padding: "7px 0",
                    display: "flex",
                    alignItems: "center",
                    gap: 10,
                  }}
                >
                  <span>→</span> {item.text}
                </div>
              );
            })}
          </div>
        </div>

        {/* Tagline */}
        <div
          style={{
            position: "absolute",
            bottom: 80,
            ...fontStyles.title,
            fontSize: 30,
            color: colors.spiritWhite,
            opacity: tagOpacity,
            textAlign: "center",
          }}
        >
          Fix your writing.{" "}
          <span style={{ color: colors.ghostGlow }}>
            Then fix your habits.
          </span>
        </div>
      </AbsoluteFill>
    </SceneBackground>
  );
};
