import React from "react";
import { fontStyles } from "../theme/fonts";

type Provider = "Claude" | "Codex" | "Gemini";

const providerColors: Record<Provider, string> = {
  Claude: "#D97757",
  Codex: "#10A37F",
  Gemini: "#4285F4",
};

interface ProviderBadgeProps {
  provider: Provider;
  size?: "sm" | "md" | "lg";
}

export const ProviderBadge: React.FC<ProviderBadgeProps> = ({
  provider,
  size = "md",
}) => {
  const fontSize = size === "sm" ? 12 : size === "md" ? 16 : 22;
  const paddingH = size === "sm" ? 10 : size === "md" ? 16 : 24;
  const paddingV = size === "sm" ? 4 : size === "md" ? 8 : 12;

  return (
    <div
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: 8,
        padding: `${paddingV}px ${paddingH}px`,
        borderRadius: 999,
        backgroundColor: `${providerColors[provider]}18`,
        border: `1px solid ${providerColors[provider]}44`,
        ...fontStyles.regular,
        fontSize,
        color: providerColors[provider],
      }}
    >
      <div
        style={{
          width: fontSize * 0.6,
          height: fontSize * 0.6,
          borderRadius: "50%",
          backgroundColor: providerColors[provider],
        }}
      />
      {provider}
    </div>
  );
};
