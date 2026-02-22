import React from "react";
import { colors } from "../theme/colors";
import { fontStyles } from "../theme/fonts";

interface FeatureCardProps {
  icon: string;
  title: string;
  description: string;
  width?: number;
}

export const FeatureCard: React.FC<FeatureCardProps> = ({
  icon,
  title,
  description,
  width = 320,
}) => {
  return (
    <div
      style={{
        width,
        padding: 28,
        borderRadius: 16,
        backgroundColor: colors.phantomSlate,
        border: `1px solid ${colors.etherGray}22`,
        display: "flex",
        flexDirection: "column",
        gap: 12,
      }}
    >
      <div style={{ fontSize: 36 }}>{icon}</div>
      <div
        style={{
          ...fontStyles.title,
          fontSize: 22,
          color: colors.spiritWhite,
        }}
      >
        {title}
      </div>
      <div
        style={{
          ...fontStyles.body,
          fontSize: 16,
          color: colors.etherGray,
          lineHeight: 1.5,
        }}
      >
        {description}
      </div>
    </div>
  );
};
