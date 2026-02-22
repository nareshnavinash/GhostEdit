import React from "react";
import {
  AbsoluteFill,
  Audio,
  Sequence,
  staticFile,
  useCurrentFrame,
  interpolate,
} from "remotion";
import { SceneTransition } from "../components/SceneTransition";
import { GhostLogo } from "../components/GhostLogo";
import { colors } from "../theme/colors";
import { fontStyles } from "../theme/fonts";
import { SceneIntro } from "./scenes/SceneIntro";
import { SceneSlackDemo } from "./scenes/SceneSlackDemo";
import { SceneFeatures } from "./scenes/SceneFeatures";
import { SceneWritingCoach } from "./scenes/SceneWritingCoach";
import { SceneProviders } from "./scenes/SceneProviders";
import { SceneOutro } from "./scenes/SceneOutro";

// 30fps — glow-wipe transitions overlap by 15 frames
//
// Scene layout:
//   Intro:        0      dur=120  (4s)
//   SlackDemo:    105    dur=200  (6.7s)
//   Features:     290    dur=270  (9s — 6 cards + grid)
//   WritingCoach: 545    dur=180  (6s)
//   Providers:    710    dur=90   (3s)
//   Outro:        785    dur=120  (4s)
//
//   Total: 785 + 120 = 905 frames ≈ 30.2s
//
// Watermark: visible from SlackDemo start (105) to Outro start (785)

const OVERLAP = 15;

const scenes = [
  { Component: SceneIntro, duration: 120, name: "Intro" },
  { Component: SceneSlackDemo, duration: 200, name: "SlackDemo" },
  { Component: SceneFeatures, duration: 270, name: "Features" },
  { Component: SceneWritingCoach, duration: 180, name: "WritingCoach" },
  { Component: SceneProviders, duration: 90, name: "Providers" },
  { Component: SceneOutro, duration: 120, name: "Outro" },
];

const WATERMARK_START = 105; // SlackDemo begins
const WATERMARK_END = 785; // Outro begins
const WATERMARK_DURATION = WATERMARK_END - WATERMARK_START;

const Watermark: React.FC = () => {
  const frame = useCurrentFrame();

  const fadeIn = interpolate(frame, [0, 15], [0, 0.6], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fadeOut = interpolate(
    frame,
    [WATERMARK_DURATION - 15, WATERMARK_DURATION],
    [0.6, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  const opacity = Math.min(fadeIn, fadeOut);

  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      <div
        style={{
          position: "absolute",
          top: 20,
          left: 24,
          display: "flex",
          alignItems: "center",
          gap: 10,
          opacity,
        }}
      >
        <GhostLogo size={52} glowOpacity={0} showSquircle={false} variant="monoWhite" />
        <span
          style={{
            ...fontStyles.title,
            fontSize: 26,
            color: colors.spiritWhite,
          }}
        >
          GhostEdit
        </span>
      </div>
    </AbsoluteFill>
  );
};

export const LaunchTrailer: React.FC = () => {
  let offset = 0;

  return (
    <>
      <Audio src={staticFile("winning-elevation.mp3")} volume={0.7} />

      {scenes.map(({ Component, duration, name }, i) => {
        const from = offset;
        offset += duration - (i < scenes.length - 1 ? OVERLAP : 0);

        return (
          <Sequence
            key={name}
            from={from}
            durationInFrames={duration}
            name={name}
          >
            <SceneTransition
              durationInFrames={duration}
              fadeIn={i === 0 ? 0 : OVERLAP}
              fadeOut={i === scenes.length - 1 ? 0 : OVERLAP}
            >
              <Component />
            </SceneTransition>
          </Sequence>
        );
      })}

      {/* Watermark: appears after Intro, removed before Outro */}
      <Sequence
        from={WATERMARK_START}
        durationInFrames={WATERMARK_DURATION}
        name="Watermark"
      >
        <Watermark />
      </Sequence>
    </>
  );
};
