import React from "react";
import { AbsoluteFill } from "remotion";
import { colors, gradients } from "../theme/colors";
import { fontStyles } from "../theme/fonts";
import { GhostLogo } from "../components/GhostLogo";

export const InstagramPost: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: gradients.darkRadial }}>
      {/* Gradient border effect */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 0,
          border: "3px solid transparent",
          backgroundImage: `${gradients.brand}`,
          backgroundOrigin: "border-box",
          backgroundClip: "padding-box",
          opacity: 0.3,
        }}
      />

      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          width: "100%",
          height: "100%",
          padding: 50,
          gap: 24,
        }}
      >
        {/* Icon */}
        <GhostLogo size={280} glowOpacity={0.3} showParticles />

        {/* Title */}
        <div
          style={{
            ...fontStyles.title,
            fontSize: 120,
            color: colors.spiritWhite,
            textAlign: "center",
            lineHeight: 1,
          }}
        >
          GhostEdit
        </div>

        <div
          style={{
            ...fontStyles.body,
            fontSize: 42,
            color: colors.etherGray,
            textAlign: "center",
            lineHeight: 1.2,
          }}
        >
          Fix your writing. Sharpen your habits.
        </div>

        {/* Feature list */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 16,
            marginTop: 12,
            width: "100%",
          }}
        >
          {[
            { icon: "⌨️", text: "Select text, press ⌘E, done" },
            { icon: "🤖", text: "Claude, Codex, or Gemini" },
            { icon: "📊", text: "Writing coach analyzes habits" },
          ].map((item, i) => (
            <div
              key={i}
              style={{
                display: "flex",
                alignItems: "center",
                gap: 18,
                padding: "18px 28px",
                borderRadius: 14,
                backgroundColor: `${colors.phantomSlate}CC`,
                ...fontStyles.regular,
                fontSize: 38,
                color: colors.spiritWhite,
              }}
            >
              <span style={{ fontSize: 44 }}>{item.icon}</span>
              {item.text}
            </div>
          ))}
        </div>

        {/* Footer */}
        <div
          style={{
            ...fontStyles.body,
            fontSize: 30,
            color: colors.etherGray,
            marginTop: 8,
          }}
        >
          Available for macOS
        </div>
      </div>
    </AbsoluteFill>
  );
};
