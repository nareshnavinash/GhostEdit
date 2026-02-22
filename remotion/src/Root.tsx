import "./index.css";
import { Composition, Still } from "remotion";
import { AppIconIdle } from "./compositions/AppIconIdle";
import { AppIconProcessing } from "./compositions/AppIconProcessing";
import { MenuBarIconIdle } from "./compositions/MenuBarIconIdle";
import { MenuBarIconProcessing } from "./compositions/MenuBarIconProcessing";
import { ProcessingAnimation } from "./compositions/ProcessingAnimation";
import { TwitterHeader } from "./compositions/TwitterHeader";
import { GitHubSocial } from "./compositions/GitHubSocial";
import { OpenGraph } from "./compositions/OpenGraph";
import { Generic16x9 } from "./compositions/Generic16x9";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      {/* App icons */}
      <Still
        id="AppIconIdle"
        component={AppIconIdle}
        width={1024}
        height={1024}
      />
      <Still
        id="AppIconProcessing"
        component={AppIconProcessing}
        width={1024}
        height={1024}
      />

      {/* Menu bar icons (@2x retina) */}
      <Still
        id="MenuBarIconIdle"
        component={MenuBarIconIdle}
        width={44}
        height={44}
      />
      <Still
        id="MenuBarIconProcessing"
        component={MenuBarIconProcessing}
        width={44}
        height={44}
      />

      {/* Processing animation — 2s loop at 30fps */}
      <Composition
        id="ProcessingAnimation"
        component={ProcessingAnimation}
        durationInFrames={60}
        fps={30}
        width={256}
        height={256}
      />

      {/* Social banners */}
      <Still
        id="TwitterHeader"
        component={TwitterHeader}
        width={1500}
        height={500}
      />
      <Still
        id="GitHubSocial"
        component={GitHubSocial}
        width={1280}
        height={640}
      />
      <Still
        id="OpenGraph"
        component={OpenGraph}
        width={1200}
        height={630}
      />
      <Still
        id="Generic16x9"
        component={Generic16x9}
        width={1920}
        height={1080}
      />
    </>
  );
};
