import React from "react";
import { AbsoluteFill } from "remotion";
import { loadFont } from "@remotion/google-fonts/Creepster";
import { colors, fonts, brand } from "../design/tokens";
import { GhostIcon } from "./GhostIcon";

const { fontFamily: ghostFont } = loadFont();

type BannerLayoutProps = {
  width: number;
  height: number;
};

export const BannerLayout: React.FC<BannerLayoutProps> = ({
  width,
  height,
}) => {
  const isWide = width / height > 2;
  const iconSize = Math.min(height * 0.6, width * 0.2);
  const headingSize = Math.max(height * 0.14, 28);
  const taglineSize = Math.max(height * 0.055, 14);

  return (
    <AbsoluteFill
      style={{
        background: `linear-gradient(135deg, ${colors.darkBgDeep} 0%, ${colors.darkBg} 50%, #1E1E3A 100%)`,
        display: "flex",
        flexDirection: "row",
        justifyContent: "center",
        alignItems: "center",
        gap: isWide ? width * 0.04 : width * 0.06,
        padding: `${height * 0.1}px ${width * 0.08}px`,
      }}
    >
      <GhostIcon state="idle" size={iconSize} />
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: height * 0.04,
        }}
      >
        <div
          style={{
            fontFamily: ghostFont,
            fontSize: headingSize,
            fontWeight: 400,
            color: colors.ghostWhite,
            letterSpacing: "0.04em",
          }}
        >
          {brand.name}
        </div>
        <div
          style={{
            fontFamily: fonts.heading,
            fontSize: taglineSize,
            fontWeight: 400,
            color: colors.ghostWhiteSubtle,
            letterSpacing: "0.02em",
          }}
        >
          {brand.tagline}
        </div>
      </div>
    </AbsoluteFill>
  );
};
