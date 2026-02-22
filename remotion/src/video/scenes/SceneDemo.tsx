import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  interpolate,
  spring,
  useVideoConfig,
} from "remotion";
import { colors } from "../../theme/colors";
import { fontStyles } from "../../theme/fonts";
import { MacWindow } from "../../components/MacWindow";
import { MenuBarMockup } from "../../components/MenuBarMockup";
import { KeyboardShortcut } from "../../components/KeyboardShortcut";
import { BeforeAfterText } from "../../components/BeforeAfterText";
import { SceneBackground } from "../../components/SceneBackground";

const BEFORE = "Their going to effect the entire teams moral and therefor reduce productivity";
const AFTER = "They're going to affect the entire team's morale and therefore reduce productivity";

export const SceneDemo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Phase 1: Menu bar slides in (0-20)
  const menuBarY = interpolate(frame, [0, 20], [-32, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Phase 2: Text already visible from frame 10+ (no typing — Problem scene already typed it)
  // Blue selection highlight sweeps left→right (frames 20-40) simulating Cmd+A
  const selectionWidth = interpolate(frame, [20, 40], [0, 100], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Cmd+A shortcut overlay (frames 20-40)
  const cmdAOpacity = interpolate(frame, [20, 25, 35, 40], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Cmd+E shortcut overlay (frames 45-75)
  const cmdEOpacity = interpolate(frame, [45, 50, 65, 75], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Icon switches to processing (frames 55-190)
  const iconVariant: "idle" | "processing" = frame >= 55 && frame < 190 ? "processing" : "idle";

  // Correction animation starts at frame 80
  const correctionStart = 80;

  // Selection fades out as correction begins
  const selectionOpacity = interpolate(frame, [75, 85], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Notification toast (frame 220+)
  const notifY = spring({
    frame: frame - 220,
    fps,
    config: { damping: 15, stiffness: 100 },
  });
  const notifTranslate = frame > 220 ? interpolate(notifY, [0, 1], [-50, 0]) : -50;
  const notifOpacity = frame > 220 ? notifY : 0;

  // Tagline (frame 260+)
  const taglineOpacity = interpolate(frame, [260, 280], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <SceneBackground>
      {/* Menu bar */}
      <div style={{ transform: `translateY(${menuBarY}px)` }}>
        <MenuBarMockup iconVariant={iconVariant} />
      </div>

      <AbsoluteFill
        style={{
          alignItems: "center",
          justifyContent: "center",
          paddingTop: 32,
        }}
      >
        {/* Editor window */}
        <MacWindow width={1000} height={400} title="Email Draft">
          <div style={{ position: "relative" }}>
            {/* Blue selection highlight overlay */}
            {selectionWidth > 0 && selectionOpacity > 0 && (
              <div
                style={{
                  position: "absolute",
                  top: 0,
                  left: 0,
                  width: `${selectionWidth}%`,
                  height: "100%",
                  backgroundColor: `${colors.spectralBlue}33`,
                  borderRadius: 2,
                  opacity: selectionOpacity,
                  pointerEvents: "none",
                }}
              />
            )}
            <BeforeAfterText
              before={BEFORE}
              after={AFTER}
              startFrame={correctionStart}
              framesPerWord={10}
              fontSize={30}
            />
          </div>
        </MacWindow>

        {/* Cmd+A overlay */}
        <div
          style={{
            position: "absolute",
            top: "50%",
            left: "50%",
            transform: "translate(-50%, -80%)",
            opacity: cmdAOpacity,
            pointerEvents: "none",
          }}
        >
          <div
            style={{
              padding: "20px 32px",
              borderRadius: 16,
              backgroundColor: `${colors.ghostInk}EE`,
              border: `1px solid ${colors.spectralBlue}44`,
              backdropFilter: "blur(10px)",
            }}
          >
            <KeyboardShortcut keys={["⌘", "A"]} fontSize={28} />
          </div>
        </div>

        {/* Cmd+E overlay */}
        <div
          style={{
            position: "absolute",
            top: "50%",
            left: "50%",
            transform: "translate(-50%, -80%)",
            opacity: cmdEOpacity,
            pointerEvents: "none",
          }}
        >
          <div
            style={{
              padding: "20px 32px",
              borderRadius: 16,
              backgroundColor: `${colors.ghostInk}EE`,
              border: `1px solid ${colors.spectralBlue}44`,
              backdropFilter: "blur(10px)",
            }}
          >
            <KeyboardShortcut keys={["⌘", "E"]} fontSize={28} />
          </div>
        </div>

        {/* Notification toast */}
        <div
          style={{
            position: "absolute",
            top: 60,
            right: 40,
            transform: `translateY(${notifTranslate}px)`,
            opacity: notifOpacity,
            padding: "12px 20px",
            borderRadius: 10,
            backgroundColor: colors.phantomSlate,
            border: `1px solid ${colors.phantomGreen}44`,
            display: "flex",
            alignItems: "center",
            gap: 10,
            ...fontStyles.regular,
            fontSize: 16,
            color: colors.phantomGreen,
          }}
        >
          <span>✓</span> Correction complete
        </div>

        {/* Tagline */}
        <div
          style={{
            position: "absolute",
            bottom: 80,
            ...fontStyles.title,
            fontSize: 36,
            color: colors.spiritWhite,
            opacity: taglineOpacity,
          }}
        >
          Select. Hotkey. Done.
        </div>
      </AbsoluteFill>
    </SceneBackground>
  );
};
