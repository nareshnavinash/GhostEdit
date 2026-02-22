import React from "react";
import { AbsoluteFill, useCurrentFrame, interpolate } from "remotion";
import { colors } from "../theme/colors";

interface SceneTransitionProps {
  children: React.ReactNode;
  durationInFrames: number;
  fadeIn?: number;
  fadeOut?: number;
}

/**
 * Wipe-with-glow transition.
 * - fadeIn: incoming scene reveals left→right with a glowing line at the edge
 * - fadeOut: outgoing scene clips away left→right with a glowing line at the edge
 */
export const SceneTransition: React.FC<SceneTransitionProps> = ({
  children,
  durationInFrames,
  fadeIn = 15,
  fadeOut = 15,
}) => {
  const frame = useCurrentFrame();

  // Incoming wipe: reveal from left to right
  const isWipingIn = fadeIn > 0 && frame < fadeIn;
  const inProgress =
    fadeIn > 0
      ? interpolate(frame, [0, fadeIn], [0, 100], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        })
      : 100;

  // Outgoing wipe: clip away from left to right
  const isWipingOut = fadeOut > 0 && frame > durationInFrames - fadeOut;
  const outProgress =
    fadeOut > 0
      ? interpolate(
          frame,
          [durationInFrames - fadeOut, durationInFrames],
          [0, 100],
          { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
        )
      : 0;

  // Compute clip-path
  let clipPath = "none";
  let glowLineX = -100; // off-screen
  let showGlow = false;

  if (isWipingIn) {
    // Incoming: visible area is 0 to inProgress%
    clipPath = `inset(0 ${100 - inProgress}% 0 0)`;
    glowLineX = inProgress;
    showGlow = true;
  } else if (isWipingOut) {
    // Outgoing: visible area is outProgress% to 100%
    clipPath = `inset(0 0 0 ${outProgress}%)`;
    glowLineX = outProgress;
    showGlow = true;
  }

  return (
    <AbsoluteFill
      style={{
        clipPath: clipPath !== "none" ? clipPath : undefined,
      }}
    >
      {children}

      {/* Glowing wipe line */}
      {showGlow && (
        <div
          style={{
            position: "absolute",
            top: 0,
            left: `${glowLineX}%`,
            width: 3,
            height: "100%",
            transform: "translateX(-50%)",
            background: colors.spectralBlue,
            boxShadow: `0 0 20px 8px ${colors.spectralBlue}, 0 0 60px 20px ${colors.spectralBlue}66, 0 0 100px 40px ${colors.ghostGlow}33`,
          }}
        />
      )}
    </AbsoluteFill>
  );
};
