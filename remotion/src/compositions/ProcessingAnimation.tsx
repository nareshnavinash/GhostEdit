import React from "react";
import { AbsoluteFill } from "remotion";
import { colors } from "../design/tokens";
import { GhostIcon } from "../components/GhostIcon";

export const ProcessingAnimation: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(circle at 50% 40%, ${colors.darkBg}, ${colors.darkBgDeep})`,
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
      }}
    >
      <GhostIcon state="processing" size={200} animate />
    </AbsoluteFill>
  );
};
