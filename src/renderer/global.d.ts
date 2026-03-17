import type { GhostEditAPI } from '../preload/index';

declare global {
  interface Window {
    ghostedit: GhostEditAPI;
  }
}
