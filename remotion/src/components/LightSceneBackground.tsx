import React from "react";
import { AbsoluteFill } from "remotion";
import { lightGradients } from "../theme/lightColors";

interface LightSceneBackgroundProps {
  variant?: "default" | "warm" | "cool";
  children?: React.ReactNode;
}

export const LightSceneBackground: React.FC<LightSceneBackgroundProps> = ({
  variant = "default",
  children,
}) => {
  const bg =
    variant === "cool"
      ? lightGradients.canvasRadialCool
      : variant === "warm"
        ? lightGradients.canvasRadialWarm
        : lightGradients.canvasRadial;

  return <AbsoluteFill style={{ background: bg }}>{children}</AbsoluteFill>;
};
