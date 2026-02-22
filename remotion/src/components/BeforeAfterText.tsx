import React from "react";
import { useCurrentFrame, interpolate } from "remotion";
import { colors } from "../theme/colors";
import { fontStyles } from "../theme/fonts";

interface BeforeAfterTextProps {
  before: string;
  after: string;
  startFrame?: number;
  framesPerWord?: number;
  fontSize?: number;
}

export const BeforeAfterText: React.FC<BeforeAfterTextProps> = ({
  before,
  after,
  startFrame = 0,
  framesPerWord = 8,
  fontSize = 32,
}) => {
  const frame = useCurrentFrame();
  const beforeWords = before.split(" ");
  const afterWords = after.split(" ");

  return (
    <div
      style={{
        ...fontStyles.regular,
        fontSize,
        color: colors.spiritWhite,
        lineHeight: 1.6,
      }}
    >
      {afterWords.map((word, i) => {
        const wordFrame = startFrame + i * framesPerWord;
        const isChanged = beforeWords[i] !== afterWords[i];
        const progress = interpolate(
          frame,
          [wordFrame, wordFrame + framesPerWord],
          [0, 1],
          { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
        );

        const showCorrected = frame >= wordFrame && isChanged;
        const displayWord =
          showCorrected || !isChanged ? word : (beforeWords[i] ?? word);

        const flashOpacity =
          isChanged && progress > 0 && progress < 1
            ? interpolate(progress, [0, 0.5, 1], [0, 0.6, 0])
            : 0;

        return (
          <span key={i}>
            <span
              style={{
                position: "relative",
                display: "inline",
              }}
            >
              {/* Green flash background */}
              {flashOpacity > 0 && (
                <span
                  style={{
                    position: "absolute",
                    inset: "-2px -4px",
                    backgroundColor: colors.phantomGreen,
                    opacity: flashOpacity,
                    borderRadius: 4,
                  }}
                />
              )}
              <span
                style={{
                  position: "relative",
                  color:
                    showCorrected && isChanged
                      ? colors.phantomGreen
                      : colors.spiritWhite,
                  transition: "color 0.2s",
                }}
              >
                {displayWord}
              </span>
            </span>
            {i < afterWords.length - 1 ? " " : ""}
          </span>
        );
      })}
    </div>
  );
};
