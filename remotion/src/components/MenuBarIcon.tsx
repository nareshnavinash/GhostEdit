import React from "react";
import { AbsoluteFill } from "remotion";
import { GhostIcon } from "./GhostIcon";

type MenuBarIconProps = {
  state: "idle" | "processing";
  size: number;
};

export const MenuBarIcon: React.FC<MenuBarIconProps> = ({ state, size }) => {
  const iconSize = size * 0.85;

  return (
    <AbsoluteFill
      style={{
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        backgroundColor: "transparent",
      }}
    >
      <GhostIcon state={state} size={iconSize} monochrome />
    </AbsoluteFill>
  );
};
