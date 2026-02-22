import "./index.css";
import { Composition, Still } from "remotion";

// Stills
import { AppIcon1024 } from "./stills/AppIcon1024";
import { MenuBarIconIdle } from "./stills/MenuBarIconIdle";
import { MenuBarIconProcessing } from "./stills/MenuBarIconProcessing";
import { TwitterBanner } from "./stills/TwitterBanner";
import { OpenGraphImage } from "./stills/OpenGraphImage";
import { GitHubSocialPreview } from "./stills/GitHubSocialPreview";
import { InstagramPost } from "./stills/InstagramPost";
import { ProductHuntThumbnail } from "./stills/ProductHuntThumbnail";

// Video
import { LaunchTrailer } from "./video/LaunchTrailer";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      {/* === App Icons === */}
      <Still id="AppIcon1024" component={AppIcon1024} width={1024} height={1024} />
      <Still id="MenuBarIconIdle" component={MenuBarIconIdle} width={44} height={44} />
      <Still id="MenuBarIconProcessing" component={MenuBarIconProcessing} width={44} height={44} />

      {/* === Social Media === */}
      <Still id="TwitterBanner" component={TwitterBanner} width={1500} height={500} />
      <Still id="OpenGraphImage" component={OpenGraphImage} width={1200} height={630} />
      <Still id="GitHubSocialPreview" component={GitHubSocialPreview} width={1280} height={640} />
      <Still id="InstagramPost" component={InstagramPost} width={1080} height={1080} />
      <Still id="ProductHuntThumbnail" component={ProductHuntThumbnail} width={240} height={240} />

      {/* === Launch Trailer === */}
      <Composition
        id="LaunchTrailer"
        component={LaunchTrailer}
        durationInFrames={905}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
