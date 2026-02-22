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
import { MacWindow } from "../../components/MacWindow";
import { MenuBarMockup } from "../../components/MenuBarMockup";
import { KeyboardShortcut } from "../../components/KeyboardShortcut";
import { SceneBackground } from "../../components/SceneBackground";

// Real emojis — shows emoji preservation
const BEFORE_TEXT =
  "Hey @sarah and @mike 👋 I think their going to need the report from https://docs.company.com before the meeting tommorow 🙏";
const AFTER_TEXT =
  "Hey @sarah and @mike 👋 I think they're going to need the report from https://docs.company.com before the meeting tomorrow 🙏";

interface Token {
  text: string;
  type: "mention" | "emoji" | "url";
}

const TOKENS: Token[] = [
  { text: "@sarah", type: "mention" },
  { text: "@mike", type: "mention" },
  { text: "👋", type: "emoji" },
  { text: "https://docs.company.com", type: "url" },
  { text: "🙏", type: "emoji" },
];

const TOKEN_COLORS: Record<Token["type"], string> = {
  mention: colors.spectralBlue,
  emoji: colors.ghostGlow,
  url: colors.phantomGreen,
};

const CORRECTIONS = [
  { before: "their", after: "they're" },
  { before: "tommorow", after: "tomorrow" },
];

const renderHighlightedText = (
  text: string,
  tokenGlowOpacity: number,
  correctionProgress: number,
) => {
  const segments: { text: string; type: "text" | Token["type"] }[] = [];
  let remaining = text;

  while (remaining.length > 0) {
    let earliest = -1;
    let earliestToken: Token | null = null;

    for (const token of TOKENS) {
      const idx = remaining.indexOf(token.text);
      if (idx !== -1 && (earliest === -1 || idx < earliest)) {
        earliest = idx;
        earliestToken = token;
      }
    }

    if (earliestToken && earliest !== -1) {
      if (earliest > 0) {
        segments.push({ text: remaining.slice(0, earliest), type: "text" });
      }
      segments.push({ text: earliestToken.text, type: earliestToken.type });
      remaining = remaining.slice(earliest + earliestToken.text.length);
    } else {
      segments.push({ text: remaining, type: "text" });
      remaining = "";
    }
  }

  return segments.map((seg, i) => {
    if (seg.type === "text") {
      return renderTextWithCorrections(seg.text, correctionProgress, i);
    }

    // Mentions always blue
    if (seg.type === "mention") {
      const bgHex = Math.round(tokenGlowOpacity * 0.25 * 255)
        .toString(16)
        .padStart(2, "0");
      const borderHex = Math.round(tokenGlowOpacity * 0.5 * 255)
        .toString(16)
        .padStart(2, "0");
      return (
        <span
          key={i}
          style={{
            color: colors.spectralBlue,
            fontWeight: 600,
            backgroundColor:
              tokenGlowOpacity > 0
                ? `${TOKEN_COLORS.mention}${bgHex}`
                : "transparent",
            border:
              tokenGlowOpacity > 0
                ? `1px solid ${TOKEN_COLORS.mention}${borderHex}`
                : "1px solid transparent",
            borderRadius: 4,
            padding: "1px 3px",
          }}
        >
          {seg.text}
        </span>
      );
    }

    const bgColor = TOKEN_COLORS[seg.type];
    const bgHex = Math.round(tokenGlowOpacity * 0.25 * 255)
      .toString(16)
      .padStart(2, "0");
    const borderHex = Math.round(tokenGlowOpacity * 0.5 * 255)
      .toString(16)
      .padStart(2, "0");
    return (
      <span
        key={i}
        style={{
          backgroundColor:
            tokenGlowOpacity > 0 ? `${bgColor}${bgHex}` : "transparent",
          border:
            tokenGlowOpacity > 0
              ? `1px solid ${bgColor}${borderHex}`
              : "1px solid transparent",
          borderRadius: 4,
          padding: "1px 3px",
        }}
      >
        {seg.text}
      </span>
    );
  });
};

const renderTextWithCorrections = (
  text: string,
  correctionProgress: number,
  keyBase: number,
) => {
  const parts: React.ReactNode[] = [];
  let remaining = text;
  let partIdx = 0;

  while (remaining.length > 0) {
    let found = false;
    for (const corr of CORRECTIONS) {
      const idx = remaining.indexOf(corr.after);
      if (idx !== -1) {
        if (idx > 0) {
          parts.push(
            <span key={`${keyBase}-${partIdx++}`}>
              {remaining.slice(0, idx)}
            </span>,
          );
        }
        const isGreen = correctionProgress > 0;
        parts.push(
          <span
            key={`${keyBase}-${partIdx++}`}
            style={{
              color: isGreen ? colors.phantomGreen : colors.spiritWhite,
              backgroundColor: isGreen
                ? `${colors.phantomGreen}18`
                : "transparent",
              borderRadius: 3,
              padding: "0 2px",
            }}
          >
            {corr.after}
          </span>,
        );
        remaining = remaining.slice(idx + corr.after.length);
        found = true;
        break;
      }
    }
    if (!found) {
      parts.push(
        <span key={`${keyBase}-${partIdx++}`}>{remaining}</span>,
      );
      remaining = "";
    }
  }

  return parts;
};

// 200 frames total (~6.7s at 30fps)
export const SceneSlackDemo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Menu bar slides in (0-10)
  const menuBarY = interpolate(frame, [0, 10], [-32, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Window fades in (0-10)
  const windowOpacity = interpolate(frame, [0, 10], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Selection sweep (10-25)
  const selectionWidth = interpolate(frame, [10, 25], [0, 100], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Cmd+A overlay (10-28)
  const cmdAOpacity = interpolate(frame, [10, 14, 24, 28], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Cmd+E overlay (30-50)
  const cmdEOpacity = interpolate(frame, [30, 34, 44, 50], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Selection fades as correction starts
  const selectionOpacity = interpolate(frame, [40, 48], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Processing icon (38-140)
  const iconVariant: "idle" | "processing" =
    frame >= 38 && frame < 140 ? "processing" : "idle";

  // Correction (48-100)
  const correctionProgress = interpolate(frame, [48, 90], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const showAfter = frame >= 48;

  // Token glow (110-140)
  const tokenGlowOpacity = interpolate(frame, [110, 135], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Notification toast (145+)
  const notifSpring = spring({
    frame: frame - 145,
    fps,
    config: { damping: 15, stiffness: 120 },
  });
  const notifTranslate = frame > 145 ? interpolate(notifSpring, [0, 1], [-40, 0]) : -40;
  const notifOpacity = frame > 145 ? notifSpring : 0;

  const displayText = showAfter ? AFTER_TEXT : BEFORE_TEXT;

  return (
    <SceneBackground>
      {/* Menu bar */}
      <div style={{ transform: `translateY(${menuBarY}px)` }}>
        <MenuBarMockup iconVariant={iconVariant} />
      </div>

      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          paddingTop: 16,
        }}
      >
        {/* Slack window */}
        <div style={{ opacity: windowOpacity }}>
          <MacWindow
            width={1200}
            height={320}
            title="Slack — #team-updates"
          >
            <div style={{ position: "relative" }}>
              {selectionWidth > 0 && selectionOpacity > 0 && (
                <div
                  style={{
                    position: "absolute",
                    top: 0,
                    left: 0,
                    width: `${selectionWidth}%`,
                    height: "100%",
                    backgroundColor: `${colors.spectralBlue}33`,
                    borderRadius: 2,
                    opacity: selectionOpacity,
                    pointerEvents: "none",
                  }}
                />
              )}
              <div
                style={{
                  ...fontStyles.regular,
                  fontSize: 26,
                  color: colors.spiritWhite,
                  lineHeight: 1.8,
                }}
              >
                {showAfter
                  ? renderHighlightedText(
                      displayText,
                      tokenGlowOpacity,
                      correctionProgress,
                    )
                  : renderHighlightedText(displayText, 0, 0)}
              </div>
            </div>
          </MacWindow>
        </div>

        {/* Cmd+A overlay */}
        <div
          style={{
            position: "absolute",
            bottom: 180,
            left: "50%",
            transform: "translateX(-50%)",
            opacity: cmdAOpacity,
            pointerEvents: "none",
          }}
        >
          <div
            style={{
              padding: "14px 24px",
              borderRadius: 14,
              backgroundColor: `${colors.ghostInk}EE`,
              border: `1px solid ${colors.spectralBlue}44`,
              backdropFilter: "blur(10px)",
            }}
          >
            <KeyboardShortcut keys={["⌘", "A"]} fontSize={24} />
          </div>
        </div>

        {/* Cmd+E overlay */}
        <div
          style={{
            position: "absolute",
            bottom: 180,
            left: "50%",
            transform: "translateX(-50%)",
            opacity: cmdEOpacity,
            pointerEvents: "none",
          }}
        >
          <div
            style={{
              padding: "14px 24px",
              borderRadius: 14,
              backgroundColor: `${colors.ghostInk}EE`,
              border: `1px solid ${colors.spectralBlue}44`,
              backdropFilter: "blur(10px)",
            }}
          >
            <KeyboardShortcut keys={["⌘", "E"]} fontSize={24} />
          </div>
        </div>

        {/* Notification toast */}
        <div
          style={{
            position: "absolute",
            top: 46,
            right: 40,
            transform: `translateY(${notifTranslate}px)`,
            opacity: notifOpacity,
            padding: "10px 18px",
            borderRadius: 10,
            backgroundColor: colors.phantomSlate,
            border: `1px solid ${colors.phantomGreen}44`,
            display: "flex",
            alignItems: "center",
            gap: 8,
            ...fontStyles.regular,
            fontSize: 15,
            color: colors.phantomGreen,
          }}
        >
          <span>✓</span> Correction complete
        </div>

        {/* Tagline — visible from the start */}
        <div
          style={{
            position: "absolute",
            bottom: 60,
            ...fontStyles.title,
            fontSize: 30,
            color: colors.etherGray,
            textAlign: "center",
          }}
        >
          Preserves links, names, and emojis.
        </div>
      </AbsoluteFill>
    </SceneBackground>
  );
};
