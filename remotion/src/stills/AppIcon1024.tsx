import React from "react";
import { AbsoluteFill } from "remotion";
import { GhostLogo } from "../components/GhostLogo";

export const AppIcon1024: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: "transparent",
      }}
    >
      <GhostLogo size={1024} glowOpacity={0.25} showParticles />
    </AbsoluteFill>
  );
};
