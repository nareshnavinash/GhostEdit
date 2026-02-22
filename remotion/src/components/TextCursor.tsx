import React from "react";
import { useCurrentFrame, interpolate } from "remotion";
import { colors } from "../theme/colors";

interface TextCursorProps {
  color?: string;
  height?: number;
  width?: number;
  blinkRate?: number; // frames per blink cycle
}

export const TextCursor: React.FC<TextCursorProps> = ({
  color = colors.spiritWhite,
  height = 24,
  width = 2,
  blinkRate = 30,
}) => {
  const frame = useCurrentFrame();
  const cyclePos = (frame % blinkRate) / blinkRate;
  const opacity = interpolate(
    cyclePos,
    [0, 0.45, 0.5, 0.95, 1],
    [1, 1, 0, 0, 1],
  );

  return (
    <span
      style={{
        display: "inline-block",
        width,
        height,
        backgroundColor: color,
        opacity,
        verticalAlign: "text-bottom",
        marginLeft: 1,
      }}
    />
  );
};
