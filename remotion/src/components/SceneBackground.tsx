import React from "react";
import { AbsoluteFill } from "remotion";
import { colors, gradients } from "../theme/colors";

interface SceneBackgroundProps {
  showRadialGradient?: boolean;
  children?: React.ReactNode;
}

export const SceneBackground: React.FC<SceneBackgroundProps> = ({
  showRadialGradient = true,
  children,
}) => {
  return (
    <AbsoluteFill
      style={{
        background: showRadialGradient
          ? gradients.darkRadial
          : colors.ghostInk,
      }}
    >
      {children}
    </AbsoluteFill>
  );
};
