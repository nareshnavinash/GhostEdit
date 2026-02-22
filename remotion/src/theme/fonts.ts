import { loadFont } from "@remotion/google-fonts/Inter";

const { fontFamily } = loadFont("normal", {
  weights: ["400", "600", "700"],
  subsets: ["latin"],
});

export const interFamily = fontFamily;

export const fontStyles = {
  title: {
    fontFamily,
    fontWeight: 700 as const,
  },
  body: {
    fontFamily,
    fontWeight: 400 as const,
  },
  regular: {
    fontFamily,
    fontWeight: 600 as const,
  },
};
