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
          gap: 20,
        }}
      >
        <GhostLogo size={240} glowOpacity={0.3} />

        <div
          style={{
            ...fontStyles.title,
            fontSize: 120,
            color: colors.spiritWhite,
            lineHeight: 1,
          }}
        >
          GhostEdit
        </div>

        <div
          style={{
            ...fontStyles.body,
            fontSize: 44,
            color: colors.etherGray,
            lineHeight: 1.2,
          }}
        >
          Fix your writing. Sharpen your habits.
        </div>

        {/* Before/After example */}
        <div
          style={{
            marginTop: 16,
            display: "flex",
            flexDirection: "column",
            gap: 10,
            padding: "24px 40px",
            borderRadius: 14,
            backgroundColor: colors.phantomSlate,
          }}
        >
          <div
            style={{
              ...fontStyles.regular,
              fontSize: 34,
              color: colors.whisperRose,
              textDecoration: "line-through",
            }}
          >
            Their going to effect the teams moral
          </div>
          <div
            style={{
              ...fontStyles.regular,
              fontSize: 34,
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
