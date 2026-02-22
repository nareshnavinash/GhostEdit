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

  const gFill = monochrome ? colors.black : colors.gLetter;
  const ghostFill = monochrome ? "none" : colors.ghostWhite;
  const eyeFill = monochrome ? colors.black : colors.eyes;
  const glassesFill = monochrome ? colors.black : colors.processingAccent;

  // Animation: gentle float
  const floatY = animate
    ? interpolate(frame, [0, 30, 60], [-3, 3, -3], {
        extrapolateRight: "extend",
      })
    : 0;

  // Animation: glasses glow pulse
  const glowOpacity = animate
    ? interpolate(frame, [0, 30, 60], [0.3, 0.7, 0.3], {
        extrapolateRight: "extend",
      })
    : 0.4;

  // Design: Bold G letter with ghost as negative space inside.
  // Layers (bottom to top):
  //   1. Dark G circle (the ring body)
  //   2. White ghost shape (carved out of the ring interior)
  //   3. Dark G arm (top-right terminal, overlaps gap area)
  //   4. Dark eyes on the ghost
  //   5. Processing glasses (optional)
  //
  // Center of G ring: (50, 54), outer radius: 40
  // Ghost wisp extends above the ring (to ~y=6)

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 100 100"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g transform={`translate(0, ${floatY})`}>
        {/* 1. Dark G circle — full ring body */}
        <circle cx="50" cy="54" r="40" fill={gFill} />

        {/* 2. Ghost — white shape inside the ring + wisp above */}
        <path
          d={[
            // Start at right inner wall, mid-height
            "M 70 56",
            // Wavy ghost bottom (right to left, 3 waves)
            "Q 62 46, 54 56",
            "Q 46 66, 38 56",
            "Q 30 46, 22 56",
            // Up the left inner wall
            "C 18 38, 22 22, 34 14",
            // Ghost dome curves up toward wisp
            "C 42 8, 52 4, 58 6",
            // Wisp — pointed tip extending above the G circle
            "C 66 8, 72 14, 72 22",
            // Down the right inner wall back to start
            "C 72 34, 72 46, 70 56",
            "Z",
          ].join(" ")}
          fill={ghostFill}
        />

        {/* 3. Dark G arm — top-right terminal */}
        <path
          d={[
            "M 70 20",
            "C 76 8, 92 10, 90 22",
            "C 88 30, 80 28, 76 22",
            "Z",
          ].join(" ")}
          fill={gFill}
        />

        {/* 4. Eyes */}
        <ellipse cx="40" cy="36" rx="5" ry="7" fill={eyeFill} />
        <ellipse cx="58" cy="36" rx="5" ry="7" fill={eyeFill} />

        {/* 5. Processing state: nerd glasses */}
        {state === "processing" && (
          <>
            {/* Glow pulse (animated only) */}
            {animate && (
              <>
                <circle
                  cx="40"
                  cy="36"
                  r="12"
                  fill="none"
                  stroke={colors.processingAccent}
                  strokeWidth="2"
                  opacity={glowOpacity}
                />
                <circle
                  cx="58"
                  cy="36"
                  r="12"
                  fill="none"
                  stroke={colors.processingAccent}
                  strokeWidth="2"
                  opacity={glowOpacity}
                />
              </>
            )}

            {/* Left lens */}
            <circle
              cx="40"
              cy="36"
              r="10"
              fill="none"
              stroke={glassesFill}
              strokeWidth="2.5"
            />

            {/* Right lens */}
            <circle
              cx="58"
              cy="36"
              r="10"
              fill="none"
              stroke={glassesFill}
              strokeWidth="2.5"
            />

            {/* Bridge */}
            <line
              x1="50"
              y1="34"
              x2="48"
              y2="34"
              stroke={glassesFill}
              strokeWidth="2.5"
              strokeLinecap="round"
            />

            {/* Left arm */}
            <line
              x1="30"
              y1="34"
              x2="24"
              y2="32"
              stroke={glassesFill}
              strokeWidth="2"
              strokeLinecap="round"
            />

            {/* Right arm */}
            <line
              x1="68"
              y1="34"
              x2="74"
              y2="32"
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
