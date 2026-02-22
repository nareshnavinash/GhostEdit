import React from "react";
import { AbsoluteFill } from "remotion";
import { GhostLogo } from "../components/GhostLogo";

export const ProductHuntThumbnail: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: "transparent",
      }}
    >
      <GhostLogo size={240} glowOpacity={0.25} />
    </AbsoluteFill>
  );
};
