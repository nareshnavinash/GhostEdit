import React from "react";
import { lightColors } from "../theme/lightColors";
import { fontStyles } from "../theme/fonts";

interface LightWindowProps {
  width?: number;
  height?: number;
  title?: string;
  children?: React.ReactNode;
}

export const LightWindow: React.FC<LightWindowProps> = ({
  width = 800,
  height = 500,
  title = "Untitled",
  children,
}) => {
  return (
    <div
      style={{
        width,
        height,
        borderRadius: 12,
        overflow: "hidden",
        backgroundColor: lightColors.canvas,
        border: `1px solid ${lightColors.border}`,
        boxShadow: "0 25px 60px rgba(0,0,0,0.12)",
        display: "flex",
        flexDirection: "column",
      }}
    >
      {/* Title bar */}
      <div
        style={{
          height: 40,
          backgroundColor: lightColors.surface,
          borderBottom: `1px solid ${lightColors.border}`,
          display: "flex",
          alignItems: "center",
          paddingLeft: 16,
          paddingRight: 16,
          flexShrink: 0,
        }}
      >
        {/* Traffic lights */}
        <div style={{ display: "flex", gap: 8 }}>
          <div
            style={{
              width: 12,
              height: 12,
              borderRadius: "50%",
              backgroundColor: "#FF5F57",
            }}
          />
          <div
            style={{
              width: 12,
              height: 12,
              borderRadius: "50%",
              backgroundColor: "#FEBC2E",
            }}
          />
          <div
            style={{
              width: 12,
              height: 12,
              borderRadius: "50%",
              backgroundColor: "#28C840",
            }}
          />
        </div>
        <div
          style={{
            flex: 1,
            textAlign: "center",
            ...fontStyles.body,
            color: lightColors.textSecondary,
            fontSize: 15,
          }}
        >
          {title}
        </div>
        <div style={{ width: 52 }} />
      </div>

      {/* Content area */}
      <div
        style={{
          flex: 1,
          padding: 24,
          overflow: "hidden",
        }}
      >
        {children}
      </div>
    </div>
  );
};
