import { loadFont } from "@remotion/google-fonts/Inter";

const { fontFamily } = loadFont("normal", {
  weights: ["100", "200", "400"],
  subsets: ["latin"],
});

export const interFamily = fontFamily;

export const fontStyles = {
  title: {
    fontFamily,
    fontWeight: 200 as const,
  },
  body: {
    fontFamily,
    fontWeight: 100 as const,
  },
  regular: {
    fontFamily,
    fontWeight: 400 as const,
  },
};
