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
import { LightSceneBackground } from "../../components/LightSceneBackground";
import { LightWindow } from "../../components/LightWindow";
import { KeyboardShortcut } from "../../components/KeyboardShortcut";
import { TextCursor } from "../../components/TextCursor";

const ORIGINAL_TEXT = "Their going to effect the entire teams moral";

const PROCESSING_STEPS = [
  { icon: "🧠", text: "T5 Grammar Model — vennify/t5-base-grammar-correction", tag: "HuggingFace" },
  { icon: "📖", text: "Harper spell checker — scanning...", tag: "Harper" },
  { icon: "🍎", text: "Apple NSSpellChecker — verifying...", tag: "macOS" },
];

export const InstantSceneLocalDemo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Window spring in from right (15-30)
  const windowSpring = spring({
    frame: frame - 15,
    fps,
    config: { damping: 14, stiffness: 70 },
  });
  const windowX = interpolate(windowSpring, [0, 1], [300, 0]);
  const windowOpacity = windowSpring;

  // Text typing char by char (30-60)
  const typedChars = Math.min(
    ORIGINAL_TEXT.length,
    Math.max(0, Math.floor(((frame - 30) / 30) * ORIGINAL_TEXT.length)),
  );
  const showCursor = frame >= 30 && frame < 65;

  // Selection highlight sweep (65-82)
  const selectionWidth = interpolate(frame, [65, 82], [0, 100], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Keyboard shortcut overlay (85-100)
  const shortcutOpacity = interpolate(frame, [85, 90, 97, 100], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Processing steps (100-120)
  const stepStates = PROCESSING_STEPS.map((_, i) => {
    const stepStart = 100 + i * 7;
    const typing = interpolate(frame, [stepStart, stepStart + 5], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    const done = frame >= stepStart + 10;
    return { typing, done };
  });

  // Before→After transition (120-130)
  const showAfter = frame >= 120;
  const afterOpacity = interpolate(frame, [120, 130], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Success message (132-140)
  const successOpacity = interpolate(frame, [132, 140], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Technology badges (143-161, staggered 6-frame delay)
  const TECH_BADGES = [
    { label: "🤗 vennify/t5-base-grammar-correction", color: lightColors.spectralBlue },
    { label: "Harper", color: lightColors.success },
    { label: "NSSpellChecker", color: lightColors.textTertiary },
  ];
  const badgeSprings = TECH_BADGES.map((_, i) =>
    spring({
      frame: frame - (143 + i * 6),
      fps,
      config: { damping: 12, stiffness: 80 },
    }),
  );

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
            gap: 20,
          }}
        >
          {/* Window */}
          <div
            style={{
              transform: `translateX(${windowX}px)`,
              opacity: windowOpacity,
              position: "relative",
            }}
          >
            <LightWindow width={1600} height={660} title="Text Editor">
              <div
                style={{
                  position: "relative",
                  height: "100%",
                  display: "flex",
                  flexDirection: "column",
                  gap: 16,
                }}
              >
                {/* OFFLINE pill badge */}
                <div
                  style={{
                    position: "absolute",
                    top: 0,
                    right: 0,
                    padding: "4px 12px",
                    borderRadius: 999,
                    backgroundColor: `${lightColors.warning}18`,
                    border: `1px solid ${lightColors.warning}44`,
                    ...fontStyles.regular,
                    fontSize: 12,
                    color: lightColors.warning,
                  }}
                >
                  OFFLINE
                </div>

                {/* Text area */}
                <div
                  style={{
                    ...fontStyles.body,
                    fontSize: 26,
                    color: lightColors.textPrimary,
                    lineHeight: 1.8,
                    marginTop: 32,
                    position: "relative",
                  }}
                >
                  {!showAfter ? (
                    <div style={{ position: "relative", display: "inline" }}>
                      {/* Selection highlight */}
                      {frame >= 65 && (
                        <div
                          style={{
                            position: "absolute",
                            top: 0,
                            left: 0,
                            width: `${selectionWidth}%`,
                            height: "100%",
                            backgroundColor: `${lightColors.spectralBlue}20`,
                            borderRadius: 3,
                          }}
                        />
                      )}
                      <span>
                        {ORIGINAL_TEXT.slice(0, typedChars)}
                        {showCursor && (
                          <TextCursor
                            color={lightColors.textPrimary}
                            height={22}
                          />
                        )}
                      </span>
                    </div>
                  ) : (
                    <div style={{ opacity: afterOpacity }}>
                      {/* Corrected text with blue highlights on changed words */}
                      <span>They&apos;re going to </span>
                      <span
                        style={{
                          color: lightColors.spectralBlue,
                          backgroundColor: `${lightColors.spectralBlue}10`,
                          borderRadius: 3,
                          padding: "0 4px",
                        }}
                      >
                        affect
                      </span>
                      <span> the entire </span>
                      <span
                        style={{
                          color: lightColors.spectralBlue,
                          backgroundColor: `${lightColors.spectralBlue}10`,
                          borderRadius: 3,
                          padding: "0 4px",
                        }}
                      >
                        team&apos;s
                      </span>
                      <span> </span>
                      <span
                        style={{
                          color: lightColors.spectralBlue,
                          backgroundColor: `${lightColors.spectralBlue}10`,
                          borderRadius: 3,
                          padding: "0 4px",
                        }}
                      >
                        morale
                      </span>
                    </div>
                  )}
                </div>

                {/* Processing steps */}
                {frame >= 100 && frame < 125 && (
                  <div
                    style={{
                      display: "flex",
                      flexDirection: "column",
                      gap: 8,
                      marginTop: 16,
                    }}
                  >
                    {PROCESSING_STEPS.map((step, i) => (
                      <div
                        key={i}
                        style={{
                          display: "flex",
                          alignItems: "center",
                          gap: 10,
                          opacity: stepStates[i].typing,
                          ...fontStyles.body,
                          fontSize: 18,
                          color: lightColors.textSecondary,
                        }}
                      >
                        <span
                          style={{
                            color: stepStates[i].done
                              ? lightColors.success
                              : lightColors.spectralBlue,
                            fontSize: 16,
                          }}
                        >
                          {stepStates[i].done ? "✓" : step.icon}
                        </span>
                        <span style={{ flex: 1 }}>{step.text}</span>
                        <span
                          style={{
                            padding: "2px 8px",
                            borderRadius: 6,
                            backgroundColor:
                              step.tag === "HuggingFace"
                                ? `${lightColors.spectralBlue}15`
                                : step.tag === "Harper"
                                  ? `${lightColors.success}15`
                                  : `${lightColors.textTertiary}15`,
                            color:
                              step.tag === "HuggingFace"
                                ? lightColors.spectralBlue
                                : step.tag === "Harper"
                                  ? lightColors.success
                                  : lightColors.textTertiary,
                            fontSize: 14,
                            ...fontStyles.regular,
                          }}
                        >
                          {step.tag}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </LightWindow>

            {/* Keyboard shortcut overlay */}
            {frame >= 85 && frame <= 100 && (
              <div
                style={{
                  position: "absolute",
                  top: "50%",
                  left: "50%",
                  transform: "translate(-50%, -50%)",
                  opacity: shortcutOpacity,
                  padding: "16px 28px",
                  borderRadius: 16,
                  backgroundColor: "rgba(255,255,255,0.85)",
                  backdropFilter: "blur(12px)",
                  boxShadow: "0 8px 32px rgba(0,0,0,0.1)",
                  border: `1px solid ${lightColors.border}`,
                }}
              >
                <KeyboardShortcut keys={["⌘", "E"]} fontSize={24} />
              </div>
            )}
          </div>

          {/* Success message */}
          {frame >= 132 && (
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 6,
                opacity: successOpacity,
              }}
            >
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 8,
                  ...fontStyles.regular,
                  fontSize: 22,
                  color: lightColors.success,
                }}
              >
                <span>✓</span>
                <span>4 corrections applied</span>
                <span
                  style={{
                    padding: "2px 8px",
                    borderRadius: 6,
                    backgroundColor: `${lightColors.textTertiary}15`,
                    fontSize: 16,
                    color: lightColors.textTertiary,
                  }}
                >
                  local
                </span>
                <span
                  style={{
                    padding: "2px 8px",
                    borderRadius: 6,
                    backgroundColor: `${lightColors.textTertiary}15`,
                    fontSize: 16,
                    color: lightColors.textTertiary,
                  }}
                >
                  0.8s
                </span>
              </div>
              <div
                style={{
                  ...fontStyles.body,
                  fontSize: 18,
                  color: lightColors.textTertiary,
                  fontStyle: "italic",
                }}
              >
                No network requests made
              </div>
            </div>
          )}

          {/* Technology badges */}
          {frame >= 143 && (
            <div
              style={{
                display: "flex",
                gap: 12,
                justifyContent: "center",
                flexWrap: "wrap",
              }}
            >
              {TECH_BADGES.map((badge, i) => (
                <div
                  key={i}
                  style={{
                    transform: `scale(${badgeSprings[i]})`,
                    opacity: badgeSprings[i],
                    padding: "6px 14px",
                    borderRadius: 999,
                    backgroundColor: `${badge.color}12`,
                    border: `1px solid ${badge.color}33`,
                    ...fontStyles.regular,
                    fontSize: 16,
                    color: badge.color,
                  }}
                >
                  {badge.label}
                </div>
              ))}
            </div>
          )}
        </div>
      </AbsoluteFill>
    </LightSceneBackground>
  );
};
