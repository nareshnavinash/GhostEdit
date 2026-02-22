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

  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(circle at 50% 40%, ${colors.darkBg}, ${colors.darkBgDeep})`,
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
      }}
    >
      <div style={{ padding }}>
        <GhostIcon state={state} size={iconSize} />
      </div>
    </AbsoluteFill>
  );
};
