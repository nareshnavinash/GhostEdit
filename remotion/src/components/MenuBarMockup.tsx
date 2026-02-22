import React from "react";
import { colors } from "../theme/colors";
import { fontStyles } from "../theme/fonts";

const GHOST_BODY_PATH =
  "M 512 175 C 654 175 742 280 742 430 L 742 660 C 742 720 720 760 684 760 C 648 760 630 700 598 700 C 566 700 548 760 512 760 C 476 760 458 700 426 700 C 394 700 376 760 340 760 C 304 760 282 720 282 660 L 282 430 C 282 280 370 175 512 175 Z";
const MOUTH_PATH = "M 478 500 L 546 500 C 546 555 478 555 478 500 Z";
const EYE_FILL = "#1A1D27";

const GhostIconIdle: React.FC = () => (
  <svg width={20} height={20} viewBox="197 152 630 630">
    <path d={GHOST_BODY_PATH} fill="#FFFFFF" />
    <ellipse cx={420} cy={390} rx={48} ry={60} fill={EYE_FILL} transform="rotate(-8, 420, 390)" />
    <ellipse cx={604} cy={390} rx={48} ry={60} fill={EYE_FILL} transform="rotate(8, 604, 390)" />
    <circle cx={436} cy={370} r={13} fill="#FFFFFF" />
    <circle cx={620} cy={370} r={13} fill="#FFFFFF" />
    <path d={MOUTH_PATH} fill={EYE_FILL} />
  </svg>
);

const GhostIconProcessing: React.FC = () => (
  <svg width={20} height={20} viewBox="197 152 630 630">
    <path d={GHOST_BODY_PATH} fill="#FFFFFF" />
    <ellipse cx={420} cy={390} rx={48} ry={60} fill={EYE_FILL} transform="rotate(-8, 420, 390)" />
    <ellipse cx={604} cy={390} rx={48} ry={60} fill={EYE_FILL} transform="rotate(8, 604, 390)" />
    <circle cx={436} cy={370} r={13} fill="#FFFFFF" />
    <circle cx={620} cy={370} r={13} fill="#FFFFFF" />
    <path d={MOUTH_PATH} fill={EYE_FILL} />
    {/* Spectacles */}
    <circle cx={420} cy={390} r={78} fill="none" stroke={EYE_FILL} strokeWidth={14} />
    <circle cx={604} cy={390} r={78} fill="none" stroke={EYE_FILL} strokeWidth={14} />
    <path d="M 498 385 Q 512 365 526 385" fill="none" stroke={EYE_FILL} strokeWidth={14} strokeLinecap="round" />
    <path d="M 342 390 L 295 410" fill="none" stroke={EYE_FILL} strokeWidth={14} strokeLinecap="round" />
    <path d="M 682 390 L 729 410" fill="none" stroke={EYE_FILL} strokeWidth={14} strokeLinecap="round" />
  </svg>
);

interface MenuBarMockupProps {
  iconVariant?: "idle" | "processing";
  width?: number;
}

export const MenuBarMockup: React.FC<MenuBarMockupProps> = ({
  iconVariant = "idle",
  width = 1920,
}) => {
  return (
    <div
      style={{
        width,
        height: 32,
        backgroundColor: "rgba(30, 30, 30, 0.85)",
        backdropFilter: "blur(20px)",
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        paddingLeft: 16,
        paddingRight: 16,
        ...fontStyles.regular,
        fontSize: 13,
        color: colors.spiritWhite,
      }}
    >
      {/* Left side - Apple logo + app name */}
      <div style={{ display: "flex", alignItems: "center", gap: 20 }}>
        <span style={{ fontSize: 16 }}></span>
        <span style={{ fontWeight: 600 }}>TextEdit</span>
        <span>File</span>
        <span>Edit</span>
        <span>Format</span>
        <span>View</span>
      </div>

      {/* Right side - system tray */}
      <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
        <div
          style={{
            width: 24,
            height: 24,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          {iconVariant === "processing" ? <GhostIconProcessing /> : <GhostIconIdle />}
        </div>
        <span style={{ fontSize: 15 }}>⚙</span>
        <span style={{ fontSize: 14 }}>Wi-Fi</span>
        <span>3:42 PM</span>
      </div>
    </div>
  );
};
