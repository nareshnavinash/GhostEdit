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
import { lightColors } from "../theme/lightColors";
import { fontStyles } from "../theme/fonts";
import { InstantSceneIntro } from "./scenes/InstantSceneIntro";
import { InstantSceneComparison } from "./scenes/InstantSceneComparison";
import { InstantSceneLocalDemo } from "./scenes/InstantSceneLocalDemo";
import { InstantSceneCloudDemo } from "./scenes/InstantSceneCloudDemo";
import { InstantSceneScreenshots } from "./scenes/InstantSceneScreenshots";
import { InstantScenePrivacy } from "./scenes/InstantScenePrivacy";
import { InstantSceneOutro } from "./scenes/InstantSceneOutro";

// 30fps — blue glow-wipe transitions overlap by 15 frames
//
// Scene layout:
//   Intro:        0      dur=120  (4.0s)
//   Comparison:   105    dur=105  (3.5s)
//   LocalDemo:    195    dur=165  (5.5s)
//   CloudDemo:    345    dur=165  (5.5s)
//   Screenshots:  495    dur=140  (4.7s)
//   Privacy:      620    dur=135  (4.5s)
//   Outro:        740    dur=160  (5.3s)
//
//   Total: 740 + 160 = 900 frames = 30s
//
// Watermark: visible from Comparison start (105) to Outro start (740)

const OVERLAP = 15;

const scenes = [
  { Component: InstantSceneIntro, duration: 120, name: "Intro" },
  { Component: InstantSceneComparison, duration: 105, name: "Comparison" },
  { Component: InstantSceneLocalDemo, duration: 165, name: "LocalDemo" },
  { Component: InstantSceneCloudDemo, duration: 165, name: "CloudDemo" },
  { Component: InstantSceneScreenshots, duration: 140, name: "Screenshots" },
  { Component: InstantScenePrivacy, duration: 135, name: "Privacy" },
  { Component: InstantSceneOutro, duration: 160, name: "Outro" },
];

const WATERMARK_START = 105; // Comparison begins
const WATERMARK_END = 740; // Outro begins
const WATERMARK_DURATION = WATERMARK_END - WATERMARK_START;

const Watermark: React.FC = () => {
  const frame = useCurrentFrame();

  const fadeIn = interpolate(frame, [0, 15], [0, 0.5], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const fadeOut = interpolate(
    frame,
    [WATERMARK_DURATION - 15, WATERMARK_DURATION],
    [0.5, 0],
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
        <GhostLogo
          size={52}
          glowOpacity={0}
          showSquircle={false}
          variant="monoBlack"
        />
        <span
          style={{
            ...fontStyles.title,
            fontSize: 26,
            color: lightColors.textPrimary,
          }}
        >
          GhostEdit
        </span>
      </div>
    </AbsoluteFill>
  );
};

export const LaunchTrailerInstant: React.FC = () => {
  const frame = useCurrentFrame();
  let offset = 0;

  // Audio: winning-elevation.mp3 from 1:05 (1950 frames at 30fps)
  const audioVolume = interpolate(
    frame,
    [0, 30, 870, 900],
    [0, 0.7, 0.7, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <>
      <Audio
        src={staticFile("winning-elevation.mp3")}
        volume={audioVolume}
        startFrom={1950}
      />

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
