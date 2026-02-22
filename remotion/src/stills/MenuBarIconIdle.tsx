import React from "react";
import { AbsoluteFill } from "remotion";

// Same paths as GhostLogo at 1024x1024 — SVG scales to 44px
const GHOST_BODY_PATH =
  "M 512 175 C 654 175 742 280 742 430 L 742 660 C 742 720 720 760 684 760 C 648 760 630 700 598 700 C 566 700 548 760 512 760 C 476 760 458 700 426 700 C 394 700 376 760 340 760 C 304 760 282 720 282 660 L 282 430 C 282 280 370 175 512 175 Z";
const MOUTH_PATH = "M 478 500 L 546 500 C 546 555 478 555 478 500 Z";
const EYE_FILL = "#1A1D27";

export const MenuBarIconIdle: React.FC = () => {
  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "center",
        backgroundColor: "transparent",
      }}
    >
      <svg width={44} height={44} viewBox="197 152 630 630">
        {/* Ghost body */}
        <path d={GHOST_BODY_PATH} fill="#FFFFFF" />
        {/* Eyes */}
        <ellipse
          cx={420}
          cy={390}
          rx={48}
          ry={60}
          fill={EYE_FILL}
          transform="rotate(-8, 420, 390)"
        />
        <ellipse
          cx={604}
          cy={390}
          rx={48}
          ry={60}
          fill={EYE_FILL}
          transform="rotate(8, 604, 390)"
        />
        {/* Eye highlights */}
        <circle cx={436} cy={370} r={13} fill="#FFFFFF" />
        <circle cx={620} cy={370} r={13} fill="#FFFFFF" />
        {/* Mouth */}
        <path d={MOUTH_PATH} fill={EYE_FILL} />
      </svg>
    </AbsoluteFill>
  );
};
