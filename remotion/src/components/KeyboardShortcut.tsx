import React from "react";
import { colors } from "../theme/colors";
import { fontStyles } from "../theme/fonts";

interface KeyboardShortcutProps {
  keys: string[];
  fontSize?: number;
}

export const KeyboardShortcut: React.FC<KeyboardShortcutProps> = ({
  keys,
  fontSize = 20,
}) => {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
      {keys.map((key, i) => (
        <React.Fragment key={i}>
          <div
            style={{
              display: "inline-flex",
              alignItems: "center",
              justifyContent: "center",
              minWidth: 36,
              height: 36,
              padding: "0 10px",
              borderRadius: 8,
              backgroundColor: colors.phantomSlate,
              border: `1px solid ${colors.etherGray}44`,
              boxShadow: `0 2px 0 ${colors.ghostInk}, 0 3px 4px rgba(0,0,0,0.3)`,
              color: colors.spiritWhite,
              ...fontStyles.regular,
              fontSize,
              lineHeight: 1,
            }}
          >
            {key}
          </div>
          {i < keys.length - 1 && (
            <span
              style={{
                color: colors.etherGray,
                fontSize: fontSize * 0.8,
              }}
            >
              +
            </span>
          )}
        </React.Fragment>
      ))}
    </div>
  );
};
