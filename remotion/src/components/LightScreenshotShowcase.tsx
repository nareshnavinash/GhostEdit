import React from "react";
import { Img, useCurrentFrame, interpolate, staticFile } from "remotion";
import { LightWindow } from "./LightWindow";
import { lightColors } from "../theme/lightColors";
import { fontStyles } from "../theme/fonts";

interface HighlightRect {
  x: number; // percentage 0-100
  y: number;
  width: number;
  height: number;
}

interface LightScreenshotShowcaseProps {
  src: string;
  highlightRect?: HighlightRect;
  label?: string;
  windowWidth?: number;
  windowHeight?: number;
}

export const LightScreenshotShowcase: React.FC<
  LightScreenshotShowcaseProps
> = ({
  src,
  highlightRect,
  label,
  windowWidth = 900,
  windowHeight = 560,
}) => {
  const frame = useCurrentFrame();

  const highlightOpacity = interpolate(frame, [10, 20], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <div style={{ position: "relative" }}>
      <LightWindow
        width={windowWidth}
        height={windowHeight}
        title={label || "Preview"}
      >
        <div
          style={{
            width: "100%",
            height: "100%",
            overflow: "hidden",
            position: "relative",
            borderRadius: 4,
          }}
        >
          <Img
            src={staticFile(src)}
            style={{
              width: "100%",
              height: "100%",
              objectFit: "contain",
            }}
          />

          {/* Highlight rectangle — solid blue border */}
          {highlightRect && (
            <div
              style={{
                position: "absolute",
                left: `${highlightRect.x}%`,
                top: `${highlightRect.y}%`,
                width: `${highlightRect.width}%`,
                height: `${highlightRect.height}%`,
                border: `2px solid ${lightColors.spectralBlue}`,
                borderRadius: 6,
                opacity: highlightOpacity,
                boxShadow: `0 0 12px ${lightColors.spectralBlue}44`,
              }}
            />
          )}
        </div>
      </LightWindow>

      {/* Label below */}
      {label && (
        <div
          style={{
            ...fontStyles.body,
            color: lightColors.textSecondary,
            fontSize: 16,
            textAlign: "center",
            marginTop: 12,
            opacity: interpolate(frame, [5, 15], [0, 1], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            }),
          }}
        >
          {label}
        </div>
      )}
    </div>
  );
};
