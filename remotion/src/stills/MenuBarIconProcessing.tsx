import React from "react";
import { AbsoluteFill } from "remotion";

// Same paths as GhostLogo at 1024x1024 — viewBox padded so ghost height ≈ 15pt
const GHOST_BODY_PATH =
  "M 512 175 C 654 175 742 280 742 430 L 742 660 C 742 720 720 760 684 760 C 648 760 630 700 598 700 C 566 700 548 760 512 760 C 476 760 458 700 426 700 C 394 700 376 760 340 760 C 304 760 282 720 282 660 L 282 430 C 282 280 370 175 512 175 Z";
const MOUTH_PATH = "M 478 500 L 546 500 C 546 555 478 555 478 500 Z";
const DARK_FILL = "#1A1D27";
const LIGHT_FILL = "#FFFFFF";

export const MenuBarIconProcessing: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: "transparent",
      }}
    >
      <svg width={44} height={44} viewBox="82 38 860 860">
        {/* Ghost body — dark */}
        <path d={GHOST_BODY_PATH} fill={DARK_FILL} />
        {/* Eyes — white */}
        <ellipse
          cx={420}
          cy={390}
          rx={48}
          ry={60}
          fill={LIGHT_FILL}
          transform="rotate(-8, 420, 390)"
        />
        <ellipse
          cx={604}
          cy={390}
          rx={48}
          ry={60}
          fill={LIGHT_FILL}
          transform="rotate(8, 604, 390)"
        />
        {/* Eye highlights — dark (inverted) */}
        <circle cx={436} cy={370} r={13} fill={DARK_FILL} />
        <circle cx={620} cy={370} r={13} fill={DARK_FILL} />
        {/* Mouth — white */}
        <path d={MOUTH_PATH} fill={LIGHT_FILL} />

        {/* Spectacles — white */}
        {/* Left lens */}
        <circle
          cx={420}
          cy={390}
          r={78}
          fill="none"
          stroke={LIGHT_FILL}
          strokeWidth={14}
        />
        {/* Right lens */}
        <circle
          cx={604}
          cy={390}
          r={78}
          fill="none"
          stroke={LIGHT_FILL}
          strokeWidth={14}
        />
        {/* Bridge */}
        <path
          d="M 498 385 Q 512 365 526 385"
          fill="none"
          stroke={LIGHT_FILL}
          strokeWidth={14}
          strokeLinecap="round"
        />
        {/* Left arm */}
        <path
          d="M 342 390 L 295 410"
          fill="none"
          stroke={LIGHT_FILL}
          strokeWidth={14}
          strokeLinecap="round"
        />
        {/* Right arm */}
        <path
          d="M 682 390 L 729 410"
          fill="none"
          stroke={LIGHT_FILL}
          strokeWidth={14}
          strokeLinecap="round"
        />
      </svg>
    </AbsoluteFill>
  );
};
