import React from "react";
import { AbsoluteFill, useCurrentFrame, interpolate } from "remotion";
import { colors } from "../theme/colors";

interface Particle {
  x: number;
  startY: number;
  size: number;
  opacity: number;
  speed: number;
  delay: number;
}

const generateParticles = (count: number, seed: number): Particle[] => {
  const particles: Particle[] = [];
  for (let i = 0; i < count; i++) {
    const hash = Math.sin(seed + i * 127.1) * 43758.5453;
    const r = hash - Math.floor(hash);
    const hash2 = Math.sin(seed + i * 269.5) * 43758.5453;
    const r2 = hash2 - Math.floor(hash2);
    particles.push({
      x: r * 100,
      startY: 80 + r2 * 30,
      size: 2 + r * 4,
      opacity: 0.15 + r2 * 0.35,
      speed: 0.3 + r * 0.5,
      delay: r2 * 60,
    });
  }
  return particles;
};

interface GhostParticlesProps {
  count?: number;
  color?: string;
  seed?: number;
}

export const GhostParticles: React.FC<GhostParticlesProps> = ({
  count = 20,
  color = colors.spectralBlue,
  seed = 42,
}) => {
  const frame = useCurrentFrame();
  const particles = React.useMemo(
    () => generateParticles(count, seed),
    [count, seed],
  );

  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      {particles.map((p, i) => {
        const activeFrame = Math.max(0, frame - p.delay);
        const yOffset = activeFrame * p.speed;
        const y = p.startY - (yOffset % (p.startY + 20));
        const fadeOut = interpolate(
          y,
          [0, p.startY * 0.3, p.startY],
          [0, 1, 0.3],
          { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
        );

        return (
          <div
            key={i}
            style={{
              position: "absolute",
              left: `${p.x}%`,
              top: `${y}%`,
              width: p.size,
              height: p.size,
              borderRadius: "50%",
              backgroundColor: color,
              opacity: p.opacity * fadeOut,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};
