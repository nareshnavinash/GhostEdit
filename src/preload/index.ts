import { contextBridge, ipcRenderer } from 'electron';
import { IPC } from '../shared/types';
import type {
  AppConfig,
  CorrectionHistoryEntry,
  LocalModelInfo,
  LocalModelVariant,
  WindowType,
} from '../shared/types';

/**
 * Expose a safe API to the renderer via contextBridge.
 */
const api = {
  // ── Config ──
  getConfig: (): Promise<AppConfig> => ipcRenderer.invoke(IPC.GET_CONFIG),
  saveConfig: (config: AppConfig): Promise<{ success: boolean }> =>
    ipcRenderer.invoke(IPC.SAVE_CONFIG, config),

  // ── CLI Status ──
  getCLIStatus: (): Promise<Record<string, { found: boolean; path: string | null }>> =>
    ipcRenderer.invoke(IPC.GET_CLI_STATUS),

  // ── Correction ──
  correctText: (
    systemPrompt: string,
    text: string,
  ): Promise<{ success: boolean; text?: string; durationMs?: number; error?: any }> =>
    ipcRenderer.invoke(IPC.CORRECT_TEXT, systemPrompt, text),

  correctTextStreaming: (
    systemPrompt: string,
    text: string,
  ): Promise<{ success: boolean; text?: string; durationMs?: number; error?: any }> =>
    ipcRenderer.invoke(IPC.CORRECT_TEXT_STREAMING, systemPrompt, text),

  // ── Streaming events ──
  onStreamingChunk: (callback: (chunk: string) => void) => {
    const listener = (_event: any, chunk: string) => callback(chunk);
    ipcRenderer.on(IPC.STREAMING_CHUNK, listener);
    return () => ipcRenderer.removeListener(IPC.STREAMING_CHUNK, listener);
  },
  onStreamingDone: (callback: (fullText: string) => void) => {
    const listener = (_event: any, text: string) => callback(text);
    ipcRenderer.on(IPC.STREAMING_DONE, listener);
    return () => ipcRenderer.removeListener(IPC.STREAMING_DONE, listener);
  },
  onStreamingError: (callback: (error: any) => void) => {
    const listener = (_event: any, error: any) => callback(error);
    ipcRenderer.on(IPC.STREAMING_ERROR, listener);
    return () => ipcRenderer.removeListener(IPC.STREAMING_ERROR, listener);
  },

  // ── HUD events (from main → renderer) ──
  onHudShow: (callback: (message: string) => void) => {
    const listener = (_event: any, msg: string) => callback(msg);
    ipcRenderer.on(IPC.HUD_SHOW, listener);
    return () => ipcRenderer.removeListener(IPC.HUD_SHOW, listener);
  },
  onHudHide: (callback: () => void) => {
    const listener = () => callback();
    ipcRenderer.on(IPC.HUD_HIDE, listener);
    return () => ipcRenderer.removeListener(IPC.HUD_HIDE, listener);
  },

  // ── History ──
  getHistory: (): Promise<CorrectionHistoryEntry[]> =>
    ipcRenderer.invoke(IPC.GET_HISTORY),
  clearHistory: (): Promise<{ success: boolean }> =>
    ipcRenderer.invoke(IPC.CLEAR_HISTORY),

  // ── Windows ──
  openWindow: (type: WindowType): Promise<{ success: boolean }> =>
    ipcRenderer.invoke(IPC.OPEN_WINDOW, type),

  // ── Accept / Reject from preview ──
  acceptCorrection: (text: string) =>
    ipcRenderer.invoke(IPC.ACCEPT_CORRECTION, text),
  rejectCorrection: () =>
    ipcRenderer.invoke(IPC.REJECT_CORRECTION),
  regenerateCorrection: () =>
    ipcRenderer.invoke(IPC.REGENERATE_CORRECTION),

  // ── Local Model ──
  getLocalModelStatus: (): Promise<LocalModelInfo> =>
    ipcRenderer.invoke(IPC.GET_LOCAL_MODEL_STATUS),
  getInferenceDevice: (): Promise<{ device: string; runtime: string; label: string } | null> =>
    ipcRenderer.invoke(IPC.GET_INFERENCE_DEVICE),
  downloadModelVariant: (variant: LocalModelVariant): Promise<{ success: boolean; error?: string }> =>
    ipcRenderer.invoke(IPC.DOWNLOAD_MODEL_VARIANT, variant),
  onDownloadVariantProgress: (callback: (data: { variant: LocalModelVariant; progress: number }) => void) => {
    const listener = (_event: any, data: { variant: LocalModelVariant; progress: number }) => callback(data);
    ipcRenderer.on(IPC.DOWNLOAD_VARIANT_PROGRESS, listener);
    return () => ipcRenderer.removeListener(IPC.DOWNLOAD_VARIANT_PROGRESS, listener);
  },

  // ── Preview original text (from main → renderer) ──
  onSetPreviewOriginal: (callback: (text: string) => void) => {
    const listener = (_event: any, text: string) => callback(text);
    ipcRenderer.on(IPC.SET_PREVIEW_ORIGINAL, listener);
    return () => ipcRenderer.removeListener(IPC.SET_PREVIEW_ORIGINAL, listener);
  },

  // ── Inference IPC (for hidden inference window) ──
  onInferenceCommand: (callback: (data: any) => void) => {
    const listener = (_event: any, data: any) => callback(data);
    ipcRenderer.on(IPC.INFERENCE_COMMAND, listener);
    return () => ipcRenderer.removeListener(IPC.INFERENCE_COMMAND, listener);
  },
  sendInferenceResult: (data: any) => {
    ipcRenderer.send(IPC.INFERENCE_RESULT, data);
  },

  // ── Window info (passed as query param) ──
  getWindowType: (): WindowType => {
    const params = new URLSearchParams(window.location.search);
    return (params.get('windowType') as WindowType) || 'settings';
  },
};

export type GhostEditAPI = typeof api;

contextBridge.exposeInMainWorld('ghostedit', api);
