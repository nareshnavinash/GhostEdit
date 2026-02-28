import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  interpolate,
} from "remotion";
import { lightColors } from "../../theme/lightColors";
import { fontStyles } from "../../theme/fonts";
import { LightSceneBackground } from "../../components/LightSceneBackground";

const SHIELD_BARS = [
  { label: "Telemetry", value: "NONE" },
  { label: "Analytics", value: "NONE" },
  { label: "Cloud Uploads", value: "NONE" },
  { label: "Account Required", value: "NONE" },
];

const CHECKBOXES = [
  "Zero telemetry",
  "Zero cloud dependency",
  "100% open source",
];

export const InstantScenePrivacy: React.FC = () => {
  const frame = useCurrentFrame();

  // Shield bars animate in (15-35)
  const barStates = SHIELD_BARS.map((_, i) => {
    const barStart = 15 + i * 5;
    const width = interpolate(frame, [barStart, barStart + 12], [0, 100], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    const opacity = interpolate(frame, [barStart, barStart + 6], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    return { width, opacity };
  });

  // Padlock + headline (40-60)
  const headlineOpacity = interpolate(frame, [40, 52], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const headlineY = interpolate(frame, [40, 52], [15, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Animated checkboxes (70-100)
  const checkStates = CHECKBOXES.map((_, i) => {
    const checkStart = 70 + i * 10;
    const opacity = interpolate(frame, [checkStart, checkStart + 8], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    const scale = interpolate(frame, [checkStart, checkStart + 8], [0.8, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
    return { opacity, scale };
  });

  // GitHub section (100-130)
  const githubOpacity = interpolate(frame, [100, 112], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <LightSceneBackground variant="warm">
      <AbsoluteFill
        style={{ alignItems: "center", justifyContent: "center" }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
            gap: 36,
            maxWidth: 1000,
          }}
        >
          {/* Shield bars */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 10,
              width: "100%",
            }}
          >
            {SHIELD_BARS.map((bar, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 16,
                  opacity: barStates[i].opacity,
                }}
              >
                <div
                  style={{
                    ...fontStyles.body,
                    fontSize: 20,
                    color: lightColors.textSecondary,
                    width: 180,
                    textAlign: "right",
                  }}
                >
                  {bar.label}
                </div>
                <div
                  style={{
                    flex: 1,
                    height: 32,
                    backgroundColor: lightColors.panel,
                    borderRadius: 6,
                    overflow: "hidden",
                    position: "relative",
                  }}
                >
                  <div
                    style={{
                      width: `${barStates[i].width}%`,
                      height: "100%",
                      backgroundColor: `${lightColors.success}20`,
                      borderRadius: 6,
                    }}
                  />
                </div>
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 6,
                    width: 80,
                  }}
                >
                  <span style={{ color: lightColors.success, fontSize: 16 }}>
                    ✓
                  </span>
                  <span
                    style={{
                      ...fontStyles.regular,
                      fontSize: 16,
                      color: lightColors.success,
                    }}
                  >
                    {bar.value}
                  </span>
                </div>
              </div>
            ))}
          </div>

          {/* Padlock + headline */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 12,
              opacity: headlineOpacity,
              transform: `translateY(${headlineY}px)`,
            }}
          >
            {/* Padlock icon */}
            <svg
              width={48}
              height={48}
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <rect
                x="5"
                y="11"
                width="14"
                height="10"
                rx="2"
                fill={lightColors.spectralBlue}
              />
              <path
                d="M8 11V7a4 4 0 018 0v4"
                stroke={lightColors.spectralBlue}
                strokeWidth="2"
                strokeLinecap="round"
                fill="none"
              />
              <circle cx="12" cy="16" r="1.5" fill="#FFFFFF" />
            </svg>
            <div
              style={{
                ...fontStyles.title,
                fontSize: 48,
                color: lightColors.textPrimary,
                textAlign: "center",
              }}
            >
              Your text never leaves your Mac
            </div>
          </div>

          {/* Animated checkboxes */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 14,
              alignItems: "flex-start",
            }}
          >
            {CHECKBOXES.map((text, i) => (
              <div
                key={i}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 12,
                  opacity: checkStates[i].opacity,
                  transform: `scale(${checkStates[i].scale})`,
                }}
              >
                <div
                  style={{
                    width: 24,
                    height: 24,
                    borderRadius: 6,
                    backgroundColor: lightColors.spectralBlue,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    color: "#FFFFFF",
                    fontSize: 14,
                  }}
                >
                  ✓
                </div>
                <span
                  style={{
                    ...fontStyles.regular,
                    fontSize: 26,
                    color: lightColors.textPrimary,
                  }}
                >
                  {text}
                </span>
              </div>
            ))}
          </div>

          {/* GitHub section */}
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 12,
              opacity: githubOpacity,
            }}
          >
            {/* GitHub icon */}
            <svg
              width={28}
              height={28}
              viewBox="0 0 24 24"
              fill={lightColors.textPrimary}
              xmlns="http://www.w3.org/2000/svg"
            >
              <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
            </svg>
            <span
              style={{
                ...fontStyles.regular,
                fontSize: 22,
                color: lightColors.textSecondary,
              }}
            >
              MIT License | github.com/nareshnavinash/GhostEdit
            </span>
          </div>
        </div>
      </AbsoluteFill>
    </LightSceneBackground>
  );
};
