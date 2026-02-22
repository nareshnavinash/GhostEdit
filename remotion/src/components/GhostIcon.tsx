import React from "react";
import { interpolate, useCurrentFrame } from "remotion";
import { colors } from "../design/tokens";

type GhostIconProps = {
  state: "idle" | "processing";
  size: number;
  monochrome?: boolean;
  animate?: boolean;
};

export const GhostIcon: React.FC<GhostIconProps> = ({
  state,
  size,
  monochrome = false,
  animate = false,
}) => {
  const frame = useCurrentFrame();

  const ghostFill = monochrome ? colors.black : colors.ghostWhite;
  const eyeFill = monochrome ? colors.white : colors.eyes;
  const glassesFill = monochrome ? colors.white : colors.processingAccent;

  // Animation: gentle float
  const floatY = animate
    ? interpolate(frame, [0, 30, 60], [-4, 4, -4], {
        extrapolateRight: "extend",
      })
    : 0;

  // Animation: glasses glow pulse
  const glowOpacity = animate
    ? interpolate(frame, [0, 30, 60], [0.3, 0.7, 0.3], {
        extrapolateRight: "extend",
      })
    : 0.4;

  // The ghost is designed in a 100x100 viewBox
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g transform={`translate(0, ${floatY})`}>
        {/* Ghost body: semicircle top + rect + wavy bottom */}
        <path
          d={[
            // Start at bottom-left
            "M 20 85",
            // Wavy bottom: 3 tails
            "Q 27 75, 33 85",
            "Q 40 95, 50 85",
            "Q 57 75, 67 85",
            "Q 73 95, 80 85",
            // Right side up
            "L 80 45",
            // Semicircle top (arc from right to left)
            "A 30 30 0 0 0 20 45",
            // Close
            "Z",
          ].join(" ")}
          fill={ghostFill}
        />

        {/* Left eye */}
        <ellipse cx="38" cy="48" rx="5" ry="6" fill={eyeFill} />

        {/* Right eye */}
        <ellipse cx="62" cy="48" rx="5" ry="6" fill={eyeFill} />

        {/* Processing state: nerd glasses */}
        {state === "processing" && (
          <>
            {/* Glasses glow (animated) */}
            {animate && (
              <>
                <circle
                  cx="38"
                  cy="48"
                  r="12"
                  fill="none"
                  stroke={colors.processingAccent}
                  strokeWidth="2"
                  opacity={glowOpacity}
                />
                <circle
                  cx="62"
                  cy="48"
                  r="12"
                  fill="none"
                  stroke={colors.processingAccent}
                  strokeWidth="2"
                  opacity={glowOpacity}
                />
              </>
            )}

            {/* Left lens frame */}
            <circle
              cx="38"
              cy="48"
              r="10"
              fill="none"
              stroke={glassesFill}
              strokeWidth="2.5"
            />

            {/* Right lens frame */}
            <circle
              cx="62"
              cy="48"
              r="10"
              fill="none"
              stroke={glassesFill}
              strokeWidth="2.5"
            />

            {/* Bridge */}
            <line
              x1="48"
              y1="46"
              x2="52"
              y2="46"
              stroke={glassesFill}
              strokeWidth="2.5"
              strokeLinecap="round"
            />

            {/* Left arm */}
            <line
              x1="28"
              y1="46"
              x2="22"
              y2="44"
              stroke={glassesFill}
              strokeWidth="2"
              strokeLinecap="round"
            />

            {/* Right arm */}
            <line
              x1="72"
              y1="46"
              x2="78"
              y2="44"
              stroke={glassesFill}
              strokeWidth="2"
              strokeLinecap="round"
            />
          </>
        )}
      </g>
    </svg>
  );
};
