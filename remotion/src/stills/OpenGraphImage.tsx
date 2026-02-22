import React from "react";
import { AbsoluteFill } from "remotion";
import { colors, gradients } from "../theme/colors";
import { fontStyles } from "../theme/fonts";
import { GhostLogo } from "../components/GhostLogo";

export const OpenGraphImage: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: gradients.darkRadial }}>
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          width: "100%",
          height: "100%",
          gap: 24,
        }}
      >
        <GhostLogo size={200} glowOpacity={0.3} />

        <div
          style={{
            ...fontStyles.title,
            fontSize: 72,
            color: colors.spiritWhite,
          }}
        >
          GhostEdit
        </div>

        <div
          style={{
            ...fontStyles.body,
            fontSize: 28,
            color: colors.etherGray,
          }}
        >
          Fix your writing. Sharpen your habits.
        </div>

        {/* Before/After example */}
        <div
          style={{
            marginTop: 24,
            display: "flex",
            flexDirection: "column",
            gap: 8,
            padding: "20px 32px",
            borderRadius: 12,
            backgroundColor: colors.phantomSlate,
          }}
        >
          <div
            style={{
              ...fontStyles.regular,
              fontSize: 22,
              color: colors.whisperRose,
              textDecoration: "line-through",
            }}
          >
            Their going to effect the teams moral
          </div>
          <div
            style={{
              ...fontStyles.regular,
              fontSize: 22,
              color: colors.phantomGreen,
            }}
          >
            They&apos;re going to affect the team&apos;s morale
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
