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
import { ProviderBadge } from "../../components/ProviderBadge";

const STREAMING_WORDS =
  "The quarterly results demonstrate a significant improvement in our team's performance metrics, reflecting the strategic changes implemented across all departments.".split(
    " ",
  );

export const InstantSceneCloudDemo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Window spring from left (15-35)
  const windowSpring = spring({
    frame: frame - 15,
    fps,
    config: { damping: 14, stiffness: 70 },
  });
  const windowX = interpolate(windowSpring, [0, 1], [-300, 0]);

  // Pre-filled text with selection (35-55)
  const selectionOpacity = interpolate(frame, [35, 42], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Keyboard shortcut (55-70)
  const shortcutOpacity = interpolate(
    frame,
    [55, 60, 67, 70],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  // Provider badges spring in staggered (70-85)
  const providers = ["Claude", "Codex", "Gemini"] as const;
  const badgeStates = providers.map((_, i) => {
    const s = spring({
      frame: frame - (70 + i * 5),
      fps,
      config: { damping: 12, stiffness: 80 },
    });
    return { scale: frame >= 70 + i * 5 ? s : 0 };
  });

  // Claude glow at frame 82
  const claudeGlow = interpolate(frame, [80, 85], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // "Sending to Claude..." phase (70-85)
  const sendingOpacity = interpolate(frame, [70, 74, 82, 85], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const dotCount = frame >= 70 && frame < 85 ? (Math.floor((frame - 70) / 4) % 3) + 1 : 0;

  // Data flow line (70-88)
  const flowLineOpacity = interpolate(frame, [70, 74, 85, 88], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  // Glowing dot travels down the line
  const flowDotProgress = interpolate(frame, [70, 85], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Streaming words (85-125)
  const visibleWords = Math.min(
    STREAMING_WORDS.length,
    Math.max(0, Math.floor(((frame - 85) / 40) * STREAMING_WORDS.length)),
  );

  // Diff summary (128-136)
  const summaryOpacity = interpolate(frame, [128, 136], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // API key note (140-148)
  const noteOpacity = interpolate(frame, [140, 148], [0, 1], {
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
            gap: 20,
          }}
        >
          {/* Window */}
          <div
            style={{
              transform: `translateX(${windowX}px)`,
              opacity: windowSpring,
              position: "relative",
            }}
          >
            <LightWindow width={1600} height={660} title="Document Editor">
              <div
                style={{
                  position: "relative",
                  height: "100%",
                  display: "flex",
                  flexDirection: "column",
                  gap: 16,
                }}
              >
                {/* STREAMING pill */}
                <div
                  style={{
                    position: "absolute",
                    top: 0,
                    right: 0,
                    padding: "4px 12px",
                    borderRadius: 999,
                    backgroundColor: `${lightColors.spectralBlue}18`,
                    border: `1px solid ${lightColors.spectralBlue}44`,
                    ...fontStyles.regular,
                    fontSize: 14,
                    color: lightColors.spectralBlue,
                  }}
                >
                  STREAMING
                </div>

                {/* Text area with selection or streaming content */}
                <div
                  style={{
                    ...fontStyles.body,
                    fontSize: 24,
                    color: lightColors.textPrimary,
                    lineHeight: 1.8,
                    marginTop: 32,
                    position: "relative",
                  }}
                >
                  {frame < 85 ? (
                    // Pre-filled text with selection
                    <div style={{ position: "relative" }}>
                      <div
                        style={{
                          position: "absolute",
                          top: 0,
                          left: 0,
                          width: "100%",
                          height: "100%",
                          backgroundColor: `${lightColors.spectralBlue}18`,
                          borderRadius: 3,
                          opacity: selectionOpacity,
                        }}
                      />
                      <span>
                        The quartly results demonstrats a signficant
                        improvment in our teams perfomance metrics,
                        reflectin the strategc changes implimented across
                        all departmants.
                      </span>
                    </div>
                  ) : (
                    // Streaming words
                    <div>
                      {STREAMING_WORDS.slice(0, visibleWords).map(
                        (word, i) => (
                          <span key={i}>
                            {word}{" "}
                            {i === visibleWords - 1 && (
                              <span
                                style={{
                                  display: "inline-block",
                                  width: 8,
                                  height: 20,
                                  backgroundColor:
                                    lightColors.spectralBlue,
                                  verticalAlign: "text-bottom",
                                  marginLeft: 2,
                                  opacity:
                                    0.6 +
                                    0.4 *
                                      Math.sin(
                                        ((frame - 85) / 8) * Math.PI * 2,
                                      ),
                                }}
                              />
                            )}
                          </span>
                        ),
                      )}
                    </div>
                  )}
                </div>

                {/* Sending to Claude status — always in DOM to avoid layout jump */}
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    gap: 14,
                    opacity: sendingOpacity,
                    marginTop: 12,
                  }}
                >
                  {/* Upload arrow */}
                  <svg
                    width="28"
                    height="28"
                    viewBox="0 0 20 20"
                    fill="none"
                    style={{
                      transform: `translateY(${-2 + 2 * Math.sin(((frame - 70) / 4) * Math.PI * 2)}px)`,
                    }}
                  >
                    <path
                      d="M10 16V4M10 4L5 9M10 4L15 9"
                      stroke={lightColors.claude}
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                  <span
                    style={{
                      ...fontStyles.regular,
                      fontSize: 28,
                      color: lightColors.claude,
                    }}
                  >
                    Sending to Claude{".".repeat(dotCount)}
                  </span>
                  {/* Pulsing dot */}
                  <div
                    style={{
                      width: 10,
                      height: 10,
                      borderRadius: "50%",
                      backgroundColor: lightColors.claude,
                      opacity: 0.5 + 0.5 * Math.sin(((frame - 70) / 6) * Math.PI * 2),
                    }}
                  />
                </div>
              </div>
            </LightWindow>

            {/* Keyboard shortcut overlay */}
            {frame >= 55 && frame <= 70 && (
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
                <KeyboardShortcut keys={["⌘", "⇧", "E"]} fontSize={24} />
              </div>
            )}
          </div>

          {/* Data flow connection line — always in DOM to avoid layout jump */}
          <div
            style={{
              position: "relative",
              width: 2,
              height: 32,
              opacity: flowLineOpacity,
            }}
          >
            {/* Dashed line */}
            <div
              style={{
                position: "absolute",
                top: 0,
                left: 0,
                width: 2,
                height: "100%",
                backgroundImage: `repeating-linear-gradient(to bottom, ${lightColors.claude} 0px, ${lightColors.claude} 4px, transparent 4px, transparent 8px)`,
              }}
            />
            {/* Traveling glow dot */}
            <div
              style={{
                position: "absolute",
                left: -4,
                top: `${flowDotProgress * 100}%`,
                width: 10,
                height: 10,
                borderRadius: "50%",
                backgroundColor: lightColors.claude,
                boxShadow: `0 0 8px ${lightColors.claude}`,
                transform: "translateY(-50%)",
              }}
            />
          </div>

          {/* Provider badges */}
          <div
            style={{
              display: "flex",
              gap: 16,
              alignItems: "center",
            }}
          >
              {providers.map((provider, i) => (
                <div
                  key={provider}
                  style={{
                    transform: `scale(${badgeStates[i].scale})`,
                    boxShadow:
                      provider === "Claude" && claudeGlow > 0
                        ? `0 0 20px ${lightColors.claude}${Math.round(claudeGlow * 40)
                            .toString(16)
                            .padStart(2, "0")}`
                        : provider === "Claude" && sendingOpacity > 0
                          ? `0 0 ${12 + 8 * Math.sin(((frame - 70) / 5) * Math.PI * 2)}px ${lightColors.claude}${Math.round(sendingOpacity * 30)
                              .toString(16)
                              .padStart(2, "0")}`
                          : "none",
                    borderRadius: 999,
                  }}
                >
                  <ProviderBadge provider={provider} size="sm" />
                </div>
              ))}
          </div>

          {/* Diff summary */}
          <div
            style={{
              ...fontStyles.regular,
              fontSize: 22,
              color: lightColors.textSecondary,
              opacity: summaryOpacity,
              display: "flex",
              gap: 16,
              alignItems: "center",
            }}
          >
            <span style={{ color: lightColors.spectralBlue }}>
              7 corrections
            </span>
            <span style={{ color: lightColors.border }}>|</span>
            <span>Claude sonnet</span>
            <span style={{ color: lightColors.border }}>|</span>
            <span>2.1s</span>
          </div>

          {/* API key note */}
          <div
            style={{
              ...fontStyles.body,
              fontSize: 20,
              color: lightColors.textTertiary,
              opacity: noteOpacity,
            }}
          >
            Bring your own API key
          </div>
        </div>
      </AbsoluteFill>
    </LightSceneBackground>
  );
};
