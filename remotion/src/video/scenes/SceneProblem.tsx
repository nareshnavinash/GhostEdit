import React from "react";
import { AbsoluteFill, useCurrentFrame, interpolate } from "remotion";
import { colors } from "../../theme/colors";
import { fontStyles } from "../../theme/fonts";
import { MacWindow } from "../../components/MacWindow";
import { TextCursor } from "../../components/TextCursor";
import { SceneBackground } from "../../components/SceneBackground";

const TYPO_TEXT = "Their going to effect the entire teams moral...";
const CHARS_PER_FRAME = 0.9;

// Words with errors and their positions (character index ranges)
const ERROR_WORDS = [
  { start: 0, end: 5, word: "Their" },
  { start: 20, end: 26, word: "effect" },
  { start: 39, end: 44, word: "teams" },
  { start: 45, end: 50, word: "moral" },
];

export const SceneProblem: React.FC = () => {
  const frame = useCurrentFrame();

  // Typing animation (frames 0-100)
  const charsShown = Math.min(
    Math.floor(frame * CHARS_PER_FRAME),
    TYPO_TEXT.length,
  );
  const typedText = TYPO_TEXT.slice(0, charsShown);
  const typingDone = charsShown >= TYPO_TEXT.length;

  // Red underlines appear after typing (frame ~70+)
  const underlineOpacity = interpolate(frame, [70, 85], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Overlay text (frame 110+)
  const overlayOpacity = interpolate(frame, [110, 130], [0, 1], {
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
        <MacWindow width={900} height={400} title="Notes.txt">
          <div
            style={{
              ...fontStyles.regular,
              fontSize: 28,
              color: colors.spiritWhite,
              lineHeight: 2,
              position: "relative",
            }}
          >
            {/* Render text with underlines */}
            {typedText.split("").map((char, i) => {
              const isError = ERROR_WORDS.some(
                (e) => i >= e.start && i < e.end,
              );
              return (
                <span
                  key={i}
                  style={{
                    textDecoration:
                      isError && typingDone ? "underline" : "none",
                    textDecorationColor: `rgba(244, 114, 182, ${underlineOpacity})`,
                    textDecorationStyle: "wavy",
                    textUnderlineOffset: 6,
                  }}
                >
                  {char}
                </span>
              );
            })}
            {!typingDone && <TextCursor height={28} />}
          </div>
        </MacWindow>

        {/* Overlay message */}
        <div
          style={{
            position: "absolute",
            bottom: 120,
            ...fontStyles.body,
            fontSize: 32,
            color: colors.etherGray,
            textAlign: "center",
            opacity: overlayOpacity,
          }}
        >
          Writing mistakes happen.
          <br />
          <span style={{ color: colors.spiritWhite }}>
            Fixing them shouldn&apos;t be work.
          </span>
        </div>
      </AbsoluteFill>
    </SceneBackground>
  );
};
