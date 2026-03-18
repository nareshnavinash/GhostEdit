import React from 'react';
import Settings from './windows/Settings';
import History from './windows/History';
import HudOverlay from './windows/HudOverlay';
import StreamingPreview from './windows/StreamingPreview';
import TrafficLight from './windows/TrafficLight';
import SuggestionsDropdown from './windows/SuggestionsDropdown';
import type { WindowType } from '../shared/types';

/**
 * Root component — renders the correct window based on the query parameter.
 */
export default function App() {
  const windowType = window.ghostedit.getWindowType() as WindowType;

  switch (windowType) {
    case 'settings':
      return <Settings />;
    case 'history':
      return <History />;
    case 'hud':
      return <HudOverlay />;
    case 'streaming-preview':
      return <StreamingPreview />;
    case 'traffic-light':
      return <TrafficLight />;
    case 'suggestions':
      return <SuggestionsDropdown />;
    default:
      return <Settings />;
  }
}
