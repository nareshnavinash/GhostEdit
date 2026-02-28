import React from "react";
import { lightColors } from "../theme/lightColors";
import { fontStyles } from "../theme/fonts";

interface LightFeatureCardProps {
  icon: string;
  title: string;
  description: string;
  accentColor?: string;
  width?: number;
}

export const LightFeatureCard: React.FC<LightFeatureCardProps> = ({
  icon,
  title,
  description,
  accentColor = lightColors.spectralBlue,
  width = 380,
}) => {
  return (
    <div
      style={{
        width,
        padding: 32,
        borderRadius: 16,
        backgroundColor: lightColors.canvas,
        border: `1px solid ${lightColors.border}`,
        boxShadow: "0 4px 24px rgba(0,0,0,0.06)",
        display: "flex",
        flexDirection: "row",
        gap: 16,
      }}
    >
      {/* Colored accent bar */}
      <div
        style={{
          width: 4,
          borderRadius: 2,
          backgroundColor: accentColor,
          flexShrink: 0,
        }}
      />

      <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
        <div style={{ fontSize: 38 }}>{icon}</div>
        <div
          style={{
            ...fontStyles.title,
            fontSize: 26,
            color: lightColors.textPrimary,
          }}
        >
          {title}
        </div>
        <div
          style={{
            ...fontStyles.body,
            fontSize: 18,
            color: lightColors.textSecondary,
            lineHeight: 1.5,
          }}
        >
          {description}
        </div>
      </div>
    </div>
  );
};
