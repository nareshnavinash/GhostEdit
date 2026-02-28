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
import { GhostLogo } from "../../components/GhostLogo";
import { LightSceneBackground } from "../../components/LightSceneBackground";

export const InstantSceneOutro: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Logo spring in (15-45)
  const logoSpring = spring({
    frame: frame - 15,
    fps,
    config: { damping: 12, stiffness: 60 },
  });
  const logoScale =
    frame >= 15 ? interpolate(logoSpring, [0, 1], [0.3, 1]) : 0;

  // Shimmer (25-45)
  const shimmerX = interpolate(frame, [25, 45], [-200, 450], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Title fade in (45-62)
  const titleOpacity = interpolate(frame, [45, 56], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Subtitle (55-70)
  const subtitleOpacity = interpolate(frame, [55, 66], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Three items staggered (70-100)
  const items = [
    { type: "code" as const, text: "brew tap nareshnavinash/ghostedit && brew install --cask ghostedit" },
    { type: "link" as const, text: "github.com/nareshnavinash/GhostEdit" },
    { type: "meta" as const, text: "v7.5.2 | macOS 13.0+" },
  ];
  const itemStates = items.map((_, i) => {
    const s = spring({
      frame: frame - (70 + i * 10),
      fps,
      config: { damping: 14, stiffness: 80 },
    });
    return { spring: frame >= 70 + i * 10 ? s : 0 };
  });

  // Download button (100-130)
  const buttonSpring = spring({
    frame: frame - 100,
    fps,
    config: { damping: 12, stiffness: 60 },
  });
  const buttonScale = frame >= 100 ? buttonSpring : 0;

  // Fade to white (145-160)
  const fadeOut = interpolate(frame, [145, 160], [0, 1], {
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
            gap: 20,
          }}
        >
          {/* Logo with shimmer */}
          <div
            style={{
              position: "relative",
              transform: `scale(${logoScale})`,
              opacity: logoSpring,
              overflow: "hidden",
              borderRadius: "22%",
            }}
          >
            <GhostLogo size={200} glowOpacity={0.2} variant="full" />
            {frame >= 25 && frame <= 45 && (
              <div
                style={{
                  position: "absolute",
                  top: 0,
                  left: shimmerX,
                  width: 80,
                  height: "100%",
                  background:
                    "linear-gradient(90deg, transparent, rgba(255,255,255,0.35), transparent)",
                  transform: "skewX(-20deg)",
                }}
              />
            )}
          </div>

          {/* Title */}
          <div
            style={{
              ...fontStyles.title,
              fontSize: 60,
              color: lightColors.textPrimary,
              opacity: titleOpacity,
            }}
          >
            GhostEdit
          </div>

          {/* Subtitle */}
          <div
            style={{
              ...fontStyles.body,
              fontSize: 30,
              color: lightColors.textSecondary,
              opacity: subtitleOpacity,
            }}
          >
            Grammar correction for everyone
          </div>

          {/* Three items */}
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 14,
              marginTop: 8,
            }}
          >
            {items.map((item, i) => (
              <div
                key={i}
                style={{
                  opacity: itemStates[i].spring,
                  transform: `translateY(${interpolate(itemStates[i].spring, [0, 1], [10, 0])}px)`,
                }}
              >
                {item.type === "code" ? (
                  <div
                    style={{
                      ...fontStyles.body,
                      fontSize: 24,
                      color: lightColors.spectralBlue,
                      backgroundColor: lightColors.panel,
                      border: `1px solid ${lightColors.border}`,
                      padding: "8px 20px",
                      borderRadius: 8,
                      fontFamily: "monospace",
                    }}
                  >
                    {item.text}
                  </div>
                ) : item.type === "link" ? (
                  <div
                    style={{
                      ...fontStyles.regular,
                      fontSize: 22,
                      color: lightColors.spectralBlue,
                    }}
                  >
                    {item.text}
                  </div>
                ) : (
                  <div
                    style={{
                      ...fontStyles.body,
                      fontSize: 18,
                      color: lightColors.textTertiary,
                    }}
                  >
                    {item.text}
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* Download Free button */}
          <div
            style={{
              transform: `scale(${buttonScale})`,
              marginTop: 12,
            }}
          >
            <div
              style={{
                ...fontStyles.title,
                fontSize: 26,
                color: "#FFFFFF",
                background: lightGradients.brand,
                padding: "14px 48px",
                borderRadius: 12,
                boxShadow: "0 4px 20px rgba(108,142,239,0.4)",
              }}
            >
              Download Free
            </div>
          </div>
        </div>
      </AbsoluteFill>

      {/* Fade to white */}
      {frame >= 145 && (
        <AbsoluteFill
          style={{
            backgroundColor: "#FFFFFF",
            opacity: fadeOut,
          }}
        />
      )}
    </LightSceneBackground>
  );
};
