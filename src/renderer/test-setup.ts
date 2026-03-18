// This file is imported by jsdom test files directly via
// @vitest-environment jsdom setup.
// It provides jest-dom matchers and mocks window.ghostedit.

import { vi } from 'vitest';
import '@testing-library/jest-dom/vitest';

const noopRemover = () => {};
const ghosteditMock = {
  getConfig: vi.fn().mockResolvedValue({
    claudePath: '',
    codexPath: '',
    geminiPath: '',
    provider: 'local',
    model: 't5-grammar',
    timeoutSeconds: 60,
    localHotkeyAccelerator: 'CommandOrControl+E',
    cliHotkeyAccelerator: 'CommandOrControl+Shift+E',
    undoHotkeyAccelerator: 'CommandOrControl+Shift+Z',
    launchAtLogin: false,
    historyLimit: 50,
    developerMode: false,
    language: 'auto',
    soundFeedbackEnabled: true,
    notifyOnSuccess: false,
    clipboardOnlyMode: false,
    tonePreset: 'default',
    diffPreviewMode: 'passive',
    passivePreviewSeconds: 5,
    autoPasteDelaySeconds: 5,
    localModelVariant: 'fp32',
    localModelSpeed: 'fast',
    firstRunComplete: false,
  }),
  saveConfig: vi.fn().mockResolvedValue({ success: true }),
  getCLIStatus: vi.fn().mockResolvedValue({}),
  correctText: vi.fn().mockResolvedValue({ success: true, text: 'corrected' }),
  correctTextStreaming: vi.fn().mockResolvedValue({ success: true, text: 'corrected' }),
  onStreamingChunk: vi.fn().mockReturnValue(noopRemover),
  onStreamingDone: vi.fn().mockReturnValue(noopRemover),
  onStreamingError: vi.fn().mockReturnValue(noopRemover),
  onHudShow: vi.fn().mockReturnValue(noopRemover),
  onHudHide: vi.fn().mockReturnValue(noopRemover),
  getHistory: vi.fn().mockResolvedValue([]),
  clearHistory: vi.fn().mockResolvedValue({ success: true }),
  openWindow: vi.fn().mockResolvedValue({ success: true }),
  acceptCorrection: vi.fn().mockResolvedValue(undefined),
  rejectCorrection: vi.fn().mockResolvedValue(undefined),
  regenerateCorrection: vi.fn().mockResolvedValue(undefined),
  getLocalModelStatus: vi.fn().mockResolvedValue({ ready: false, activeVariant: 'fp32', variants: [] }),
  getInferenceDevice: vi.fn().mockResolvedValue(null),
  downloadModelVariant: vi.fn().mockResolvedValue({ success: true }),
  onDownloadVariantProgress: vi.fn().mockReturnValue(noopRemover),
  onDownloadVariantError: vi.fn().mockReturnValue(noopRemover),
  exportHistory: vi.fn().mockResolvedValue({ success: true }),
  getErrorLog: vi.fn().mockResolvedValue([]),
  getSystemPrompt: vi.fn().mockResolvedValue({ prompt: '', defaultPrompt: '' }),
  saveSystemPrompt: vi.fn().mockResolvedValue({ success: true }),
  getPersonalDictionary: vi.fn().mockResolvedValue([]),
  savePersonalDictionary: vi.fn().mockResolvedValue({ success: true }),
  getUsageStats: vi.fn().mockResolvedValue({ totalCorrections: 0, successfulCorrections: 0, failedCorrections: 0, successRate: 0, totalDurationMs: 0, avgDurationMs: 0, totalWordsProcessed: 0, correctionsByProvider: {}, correctionsByDate: {} }),
  onSetPreviewOriginal: vi.fn().mockReturnValue(noopRemover),
  onSetPreviewConfig: vi.fn().mockReturnValue(noopRemover),
  onInferenceCommand: vi.fn().mockReturnValue(noopRemover),
  sendInferenceResult: vi.fn(),
  getWindowType: vi.fn().mockReturnValue('settings'),
  platform: 'darwin',
  windowControls: {
    close: vi.fn(),
    minimize: vi.fn(),
  },
};

Object.defineProperty(window, 'ghostedit', {
  value: ghosteditMock,
  writable: true,
  configurable: true,
});
