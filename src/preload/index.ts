import { contextBridge, ipcRenderer } from 'electron';
import { IPC } from '../shared/types';
import type {
  AppConfig,
  CorrectionHistoryEntry,
  DiffPreviewMode,
  ErrorLogEntry,
  UsageStats,
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
  exportHistory: (format: 'json' | 'csv'): Promise<{ success: boolean; path?: string }> =>
    ipcRenderer.invoke(IPC.EXPORT_HISTORY, format),

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
  onDownloadVariantError: (callback: (data: { variant: LocalModelVariant; error: string }) => void) => {
    const listener = (_event: any, data: { variant: LocalModelVariant; error: string }) => callback(data);
    ipcRenderer.on(IPC.DOWNLOAD_VARIANT_ERROR, listener);
    return () => ipcRenderer.removeListener(IPC.DOWNLOAD_VARIANT_ERROR, listener);
  },

  // ── Preview original text (from main → renderer) ──
  onSetPreviewOriginal: (callback: (text: string) => void) => {
    const listener = (_event: any, text: string) => callback(text);
    ipcRenderer.on(IPC.SET_PREVIEW_ORIGINAL, listener);
    return () => ipcRenderer.removeListener(IPC.SET_PREVIEW_ORIGINAL, listener);
  },
  onSetPreviewConfig: (callback: (config: { autoPasteDelaySeconds: number; diffPreviewMode: DiffPreviewMode; passivePreviewSeconds: number }) => void) => {
    const listener = (_event: any, config: { autoPasteDelaySeconds: number; diffPreviewMode: DiffPreviewMode; passivePreviewSeconds: number }) => callback(config);
    ipcRenderer.on(IPC.SET_PREVIEW_CONFIG, listener);
    return () => ipcRenderer.removeListener(IPC.SET_PREVIEW_CONFIG, listener);
  },

  // ── Error Log ──
  getErrorLog: (): Promise<ErrorLogEntry[]> =>
    ipcRenderer.invoke(IPC.GET_ERROR_LOG),

  // ── System Prompt ──
  getSystemPrompt: (): Promise<{ prompt: string; defaultPrompt: string }> =>
    ipcRenderer.invoke(IPC.GET_SYSTEM_PROMPT),
  saveSystemPrompt: (prompt: string): Promise<{ success: boolean }> =>
    ipcRenderer.invoke(IPC.SAVE_SYSTEM_PROMPT, prompt),

  // ── Personal Dictionary ──
  getPersonalDictionary: (): Promise<string[]> =>
    ipcRenderer.invoke(IPC.GET_PERSONAL_DICTIONARY),
  savePersonalDictionary: (words: string[]): Promise<{ success: boolean }> =>
    ipcRenderer.invoke(IPC.SAVE_PERSONAL_DICTIONARY, words),

  // ── Usage Stats ──
  getUsageStats: (): Promise<UsageStats> =>
    ipcRenderer.invoke(IPC.GET_USAGE_STATS),

  // ── Traffic Light & Suggestions (from main → renderer) ──
  onTrafficLightUpdate: (callback: (data: { color: string; visible: boolean }) => void) => {
    const listener = (_event: any, data: { color: string; visible: boolean }) => callback(data);
    ipcRenderer.on(IPC.TRAFFIC_LIGHT_UPDATE, listener);
    return () => ipcRenderer.removeListener(IPC.TRAFFIC_LIGHT_UPDATE, listener);
  },
  onTrafficLightHide: (callback: () => void) => {
    const listener = () => callback();
    ipcRenderer.on(IPC.TRAFFIC_LIGHT_HIDE, listener);
    return () => ipcRenderer.removeListener(IPC.TRAFFIC_LIGHT_HIDE, listener);
  },
  trafficLightClicked: () => {
    ipcRenderer.send(IPC.TRAFFIC_LIGHT_CLICKED);
  },
  onSuggestionsUpdate: (callback: (issues: any[]) => void) => {
    const listener = (_event: any, issues: any[]) => callback(issues);
    ipcRenderer.on(IPC.SUGGESTIONS_UPDATE, listener);
    return () => ipcRenderer.removeListener(IPC.SUGGESTIONS_UPDATE, listener);
  },
  applyFix: (index: number) => {
    ipcRenderer.invoke(IPC.APPLY_FIX, index);
  },
  applyAllFixes: () => {
    ipcRenderer.invoke(IPC.APPLY_ALL_FIXES);
  },
  checkAccessibility: (): Promise<{ trusted: boolean }> =>
    ipcRenderer.invoke(IPC.CHECK_ACCESSIBILITY),

  // ── Inference IPC (for hidden inference window) ──
  onInferenceCommand: (callback: (data: any) => void) => {
    const listener = (_event: any, data: any) => callback(data);
    ipcRenderer.on(IPC.INFERENCE_COMMAND, listener);
    return () => ipcRenderer.removeListener(IPC.INFERENCE_COMMAND, listener);
  },
  sendInferenceResult: (data: any) => {
    ipcRenderer.send(IPC.INFERENCE_RESULT, data);
  },

  // ── Platform & Window Controls ──
  platform: process.platform,
  windowControls: {
    close: () => ipcRenderer.send('window-close'),
    minimize: () => ipcRenderer.send('window-minimize'),
  },

  // ── Window info (passed as query param) ──
  getWindowType: (): WindowType => {
    const params = new URLSearchParams(window.location.search);
    return (params.get('windowType') as WindowType) || 'settings';
  },
};

export type GhostEditAPI = typeof api;

contextBridge.exposeInMainWorld('ghostedit', api);
