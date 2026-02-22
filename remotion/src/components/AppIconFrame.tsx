import React from "react";
import { AbsoluteFill } from "remotion";
import { colors } from "../design/tokens";
import { GhostIcon } from "./GhostIcon";

type AppIconFrameProps = {
  state: "idle" | "processing";
  size: number;
};

export const AppIconFrame: React.FC<AppIconFrameProps> = ({ state, size }) => {
  const padding = size * 0.1;
  const iconSize = size - padding * 2;
  const borderRadius = size * 0.22; // macOS icon radius

  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(circle at 50% 40%, ${colors.darkBg}, ${colors.darkBgDeep})`,
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        borderRadius,
        overflow: "hidden",
      }}
    >
      <div style={{ padding }}>
        <GhostIcon state={state} size={iconSize} />
      </div>

      {/* Glossy highlight overlay */}
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          borderRadius,
          background:
            "linear-gradient(170deg, rgba(255,255,255,0.25) 0%, rgba(255,255,255,0.08) 35%, rgba(255,255,255,0) 50%)",
          pointerEvents: "none",
        }}
      />

      {/* Subtle inner border glow */}
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          borderRadius,
          boxShadow: `inset 0 1px 0 rgba(255,255,255,0.15), inset 0 0 ${size * 0.03}px rgba(255,255,255,0.05)`,
          pointerEvents: "none",
        }}
      />
    </AbsoluteFill>
  );
};
