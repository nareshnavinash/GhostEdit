import React, { useId } from "react";
import { colors } from "../theme/colors";
// macOS continuous-curvature superellipse (squircle) path at 1024x1024
const SQUIRCLE_PATH =
  "M512 0C192.9 0 112.5 0 56.3 56.3S0 192.9 0 512s0 399.5 56.3 455.7S192.9 1024 512 1024s399.5 0 455.7-56.3S1024 831.1 1024 512s0-399.5-56.3-455.7S831.1 0 512 0z";

// Ghost body: dome top, straight sides, 3-scallop wavy bottom
const GHOST_BODY_PATH =
  "M 512 175 C 654 175 742 280 742 430 L 742 660 C 742 720 720 760 684 760 C 648 760 630 700 598 700 C 566 700 548 760 512 760 C 476 760 458 700 426 700 C 394 700 376 760 340 760 C 304 760 282 720 282 660 L 282 430 C 282 280 370 175 512 175 Z";

// Happy open D-shaped mouth: flat top, curved bottom
const MOUTH_PATH = "M 478 500 L 546 500 C 546 555 478 555 478 500 Z";

interface GhostLogoProps {
  size?: number;
  glowOpacity?: number;
  showParticles?: boolean;
  variant?: "full" | "monoWhite" | "monoBlack" | "fullLight";
  showSquircle?: boolean;
}

export const GhostLogo: React.FC<GhostLogoProps> = ({
  size = 512,
  glowOpacity = 0.2,
  showParticles = false,
  variant = "full",
  showSquircle = true,
}) => {
  const uid = useId().replace(/:/g, "");
  const isMono = variant === "monoWhite" || variant === "monoBlack";
  const monoColor = variant === "monoWhite" ? "#FFFFFF" : "#000000";

  const ghostFill = isMono
    ? monoColor
    : variant === "fullLight"
      ? colors.spiritWhite
      : "#FFFFFF";

  const eyeFill = colors.phantomSlate;
  const mouthFill = colors.phantomSlate;

  const gradId = `bg-gradient-${uid}`;
  const glowGradId = `glow-${uid}`;
  const maskId = `ghost-mask-${uid}`;

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 1024 1024"
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        {variant === "full" && (
          <>
            <linearGradient
              id={gradId}
              x1="0%"
              y1="0%"
              x2="100%"
              y2="100%"
            >
              <stop offset="0%" stopColor={colors.phantomSlate} />
              <stop offset="100%" stopColor={colors.ghostInk} />
            </linearGradient>
            <radialGradient id={glowGradId} cx="50%" cy="45%" r="40%">
              <stop
                offset="0%"
                stopColor={colors.spectralBlue}
                stopOpacity={glowOpacity}
              />
              <stop
                offset="70%"
                stopColor={colors.ghostGlow}
                stopOpacity={glowOpacity * 0.3}
              />
              <stop offset="100%" stopColor="transparent" stopOpacity={0} />
            </radialGradient>
          </>
        )}
        {isMono && (
          <mask id={maskId}>
            <path d={GHOST_BODY_PATH} fill="white" />
            {/* Cut out eyes */}
            <ellipse
              cx={420}
              cy={390}
              rx={48}
              ry={60}
              fill="black"
              transform="rotate(-8, 420, 390)"
            />
            <ellipse
              cx={604}
              cy={390}
              rx={48}
              ry={60}
              fill="black"
              transform="rotate(8, 604, 390)"
            />
            {/* Cut out mouth */}
            <path d={MOUTH_PATH} fill="black" />
          </mask>
        )}
      </defs>

      {/* Squircle background */}
      {showSquircle && (
        <path
          d={SQUIRCLE_PATH}
          fill={
            variant === "full"
              ? `url(#${gradId})`
              : variant === "fullLight"
                ? "#FFFFFF"
                : "none"
          }
          stroke={isMono ? monoColor : "none"}
          strokeWidth={isMono ? 24 : 0}
        />
      )}

      {/* Spectral glow behind the ghost */}
      {variant === "full" && showSquircle && (
        <circle cx="512" cy="460" r="320" fill={`url(#${glowGradId})`} />
      )}

      {/* Ghost character */}
      {isMono ? (
        <path
          d={GHOST_BODY_PATH}
          fill={monoColor}
          mask={`url(#${maskId})`}
        />
      ) : (
        <g>
          {/* Ghost body */}
          <path d={GHOST_BODY_PATH} fill={ghostFill} />
          {/* Eyes */}
          <ellipse
            cx={420}
            cy={390}
            rx={48}
            ry={60}
            fill={eyeFill}
            transform="rotate(-8, 420, 390)"
          />
          <ellipse
            cx={604}
            cy={390}
            rx={48}
            ry={60}
            fill={eyeFill}
            transform="rotate(8, 604, 390)"
          />
          {/* Eye highlights (catchlights) */}
          <circle cx={436} cy={370} r={13} fill="#FFFFFF" />
          <circle cx={620} cy={370} r={13} fill="#FFFFFF" />
          {/* Mouth */}
          <path d={MOUTH_PATH} fill={mouthFill} />
        </g>
      )}

      {/* Ghost particles */}
      {showParticles &&
        !isMono &&
        PARTICLE_POSITIONS.map((p, i) => (
          <circle
            key={i}
            cx={p.x}
            cy={p.y}
            r={p.r}
            fill={colors.spectralBlue}
            opacity={p.opacity}
          />
        ))}
    </svg>
  );
};

const PARTICLE_POSITIONS = [
  { x: 280, y: 200, r: 4, opacity: 0.5 },
  { x: 350, y: 120, r: 3, opacity: 0.3 },
  { x: 700, y: 180, r: 5, opacity: 0.4 },
  { x: 750, y: 100, r: 3, opacity: 0.25 },
  { x: 200, y: 350, r: 3, opacity: 0.35 },
  { x: 820, y: 300, r: 4, opacity: 0.3 },
  { x: 460, y: 80, r: 3, opacity: 0.4 },
  { x: 580, y: 60, r: 2, opacity: 0.3 },
];
