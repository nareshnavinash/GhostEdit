import React from "react";
import { AbsoluteFill } from "remotion";
import { colors, gradients } from "../theme/colors";
import { fontStyles } from "../theme/fonts";
import { GhostLogo } from "../components/GhostLogo";
import { ProviderBadge } from "../components/ProviderBadge";

export const GitHubSocialPreview: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: gradients.darkRadial }}>
      <div
        style={{
          display: "flex",
          width: "100%",
          height: "100%",
          padding: "40px 60px",
          gap: 50,
          alignItems: "center",
        }}
      >
        {/* Left column */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 20,
            flex: 1,
          }}
        >
          <GhostLogo size={160} glowOpacity={0.3} />
          <div
            style={{
              ...fontStyles.title,
              fontSize: 56,
              color: colors.spiritWhite,
            }}
          >
            GhostEdit
          </div>
          <div
            style={{
              ...fontStyles.body,
              fontSize: 22,
              color: colors.etherGray,
              lineHeight: 1.4,
            }}
          >
            Native macOS menu bar app that fixes your writing with local AI.
          </div>
          <div style={{ display: "flex", gap: 10, marginTop: 8 }}>
            <ProviderBadge provider="Claude" size="sm" />
            <ProviderBadge provider="Codex" size="sm" />
            <ProviderBadge provider="Gemini" size="sm" />
          </div>
        </div>

        {/* Right column - feature pills */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 14,
          }}
        >
          {[
            "⌘E — Fix in any app",
            "🔒 Local AI providers",
            "📝 Writing coach mode",
            "⚡ Works everywhere",
          ].map((feature, i) => (
            <div
              key={i}
              style={{
                padding: "12px 24px",
                borderRadius: 10,
                backgroundColor: colors.phantomSlate,
                border: `1px solid ${colors.etherGray}22`,
                ...fontStyles.regular,
                fontSize: 20,
                color: colors.spiritWhite,
              }}
            >
              {feature}
            </div>
          ))}
        </div>
      </div>
    </AbsoluteFill>
  );
};
