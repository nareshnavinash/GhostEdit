// ── Provider ──

export type ProviderName = 'claude' | 'codex' | 'gemini' | 'local';
export type CLIProviderName = Exclude<ProviderName, 'local'>;

export interface CLIProvider {
  name: CLIProviderName;
  displayName: string;
  executableName: string;
  authCommand: string;
  configPathKey: keyof Pick<AppConfig, 'claudePath' | 'codexPath' | 'geminiPath'>;
  availableModels: string[];
  defaultModel: string;
}

// ── App Configuration ──

export interface AppConfig {
  claudePath: string;
  codexPath: string;
  geminiPath: string;
  provider: ProviderName;
  model: string;
  cliProvider: CLIProviderName;  // CLI provider for the Shift hotkey (e.g. 'claude')
  cliModel: string;              // Model for the CLI provider (e.g. 'sonnet')
  timeoutSeconds: number;
  localHotkeyAccelerator: string; // Electron accelerator for local model correction e.g. "CommandOrControl+E"
  cliHotkeyAccelerator: string; // Electron accelerator for CLI provider correction e.g. "CommandOrControl+Shift+E"
  undoHotkeyAccelerator: string; // Electron accelerator for undo last correction e.g. "CommandOrControl+Shift+Z"
  launchAtLogin: boolean;
  historyLimit: number;
  developerMode: boolean;
  language: string;
  soundFeedbackEnabled: boolean;
  notifyOnSuccess: boolean;
  clipboardOnlyMode: boolean;
  tonePreset: TonePreset;
  diffPreviewMode: DiffPreviewMode;
  passivePreviewSeconds: number;
  autoPasteDelaySeconds: number;
  localModelEngine: LocalModelEngine;
  bonsaiModelSize: BonsaiModelSize;
  localModelVariant: LocalModelVariant;
  localModelSpeed: 'fast' | 'quality';
  firstRunComplete: boolean;
  monitoringEnabled: boolean;
  trafficLightPosition: IconPosition;
  trafficLightInactivityMs: number;
  lineHotkeyAccelerator: string;
  backgroundModelRefinement: boolean;
  streakDates: string[]; // ISO date strings (YYYY-MM-DD) of days with corrections
  dailyDigestEnabled: boolean;
  settingsMode: 'simple' | 'advanced';
  monitoringAppFilter: 'all' | 'whitelist';
  monitoringAppWhitelist: string[];
  appToneOverrides: Record<string, TonePreset>;
  meetingModeEnabled: boolean;
  meetingApps: string[];
  suppressedSuggestions: Record<string, number>;
}

export type TonePreset = 'default' | 'casual' | 'professional' | 'academic' | 'slack';

export type DiffPreviewMode = 'none' | 'passive' | 'interactive';

// ── Correction History ──

export interface CorrectionHistoryEntry {
  id: string;
  timestamp: string; // ISO 8601
  originalText: string;
  generatedText: string;
  provider: ProviderName;
  model: string;
  durationMilliseconds: number;
  succeeded: boolean;
  rejected?: boolean; // true if user rejected interactive diff preview
}

// ── Error Log ──

export interface ErrorLogEntry {
  id: string;
  timestamp: string; // ISO 8601
  message: string;
  provider?: ProviderName;
}

// ── Usage Statistics ──

export interface UsageStats {
  totalCorrections: number;
  successfulCorrections: number;
  failedCorrections: number;
  successRate: number;
  totalDurationMs: number;
  avgDurationMs: number;
  totalWordsProcessed: number;
  correctionsByProvider: Record<string, number>;
  correctionsByDate: Record<string, number>;
}

// ── Diff ──

export type DiffSegmentKind = 'equal' | 'insertion' | 'deletion';

export interface DiffSegment {
  kind: DiffSegmentKind;
  text: string;
}

// ── Token Preservation ──

export interface ProtectedToken {
  placeholder: string;
  originalToken: string;
}

export interface TokenProtectionResult {
  protectedText: string;
  tokens: ProtectedToken[];
  hasProtectedTokens: boolean;
}

// ── Correction Result ──

export interface CorrectionResult {
  text: string;
  durationMs: number;
}

// ── Shell Runner ──

export type ShellRunnerErrorType =
  | 'cli-not-found'
  | 'authentication-required'
  | 'launch-failed'
  | 'process-failed'
  | 'timed-out'
  | 'empty-response'
  | 'protected-tokens-modified';

export interface ShellRunnerError {
  type: ShellRunnerErrorType;
  message: string;
  provider?: ProviderName;
  exitCode?: number;
  stderr?: string;
}

// ── Local Model ──

export type LocalModelEngine = 'bonsai' | 't5';
export type BonsaiModelSize = '1.7b' | '4b' | '8b';

export type LocalModelVariant = 'q4f16' | 'int8' | 'fp16' | 'fp32';

export interface LocalModelVariantInfo {
  variant: LocalModelVariant;
  displayName: string;
  sizeMB: number;
  available: boolean;
  bundled: boolean;
}

export interface LocalModelInfo {
  ready: boolean;
  activeVariant: LocalModelVariant;
  variants: LocalModelVariantInfo[];
}

// ── Bonsai Model ──

export interface BonsaiModelInfo {
  size: BonsaiModelSize;
  displayName: string;
  sizeMB: number;
  available: boolean;
  bundled: boolean;
}

export interface BonsaiServerStatus {
  running: boolean;
  port: number | null;
  healthy: boolean;
  modelSize: BonsaiModelSize | null;
}

// ── IPC Channel Names ──

export const IPC = {
  CORRECT_TEXT: 'correct-text',
  CORRECT_TEXT_STREAMING: 'correct-text-streaming',
  STREAMING_CHUNK: 'streaming-chunk',
  STREAMING_DONE: 'streaming-done',
  STREAMING_ERROR: 'streaming-error',
  GET_CONFIG: 'get-config',
  SAVE_CONFIG: 'save-config',
  GET_HISTORY: 'get-history',
  CLEAR_HISTORY: 'clear-history',
  EXPORT_HISTORY: 'export-history',
  OPEN_WINDOW: 'open-window',
  HUD_SHOW: 'hud-show',
  HUD_HIDE: 'hud-hide',
  GET_CLI_STATUS: 'get-cli-status',
  ACCEPT_CORRECTION: 'accept-correction',
  REJECT_CORRECTION: 'reject-correction',
  REGENERATE_CORRECTION: 'regenerate-correction',
  GET_LOCAL_MODEL_STATUS: 'get-local-model-status',
  DOWNLOAD_MODEL_VARIANT: 'download-model-variant',
  DOWNLOAD_VARIANT_PROGRESS: 'download-variant-progress',
  DOWNLOAD_VARIANT_ERROR: 'download-variant-error',
  SET_PREVIEW_ORIGINAL: 'set-preview-original',
  SET_PREVIEW_CONFIG: 'set-preview-config',
  INFERENCE_COMMAND: 'inference:command',
  INFERENCE_RESULT: 'inference:result',
  GET_INFERENCE_DEVICE: 'get-inference-device',
  GET_ERROR_LOG: 'get-error-log',
  GET_SYSTEM_PROMPT: 'get-system-prompt',
  SAVE_SYSTEM_PROMPT: 'save-system-prompt',
  GET_PERSONAL_DICTIONARY: 'get-personal-dictionary',
  SAVE_PERSONAL_DICTIONARY: 'save-personal-dictionary',
  GET_USAGE_STATS: 'get-usage-stats',
  SUGGESTIONS_UPDATE: 'suggestions-update',
  APPLY_FIX: 'apply-fix',
  APPLY_ALL_FIXES: 'apply-all-fixes',
  CHECK_ACCESSIBILITY: 'check-accessibility',
  CORRECT_INLINE: 'correct-inline',
  EXPLAIN_DIFF: 'explain-diff',
  RE_CORRECT: 're-correct',
  DISMISS_SUGGESTION: 'dismiss-suggestion',
  GET_BONSAI_STATUS: 'get-bonsai-status',
  DOWNLOAD_BONSAI_MODEL: 'download-bonsai-model',
  DOWNLOAD_BONSAI_PROGRESS: 'download-bonsai-progress',
  DOWNLOAD_BONSAI_ERROR: 'download-bonsai-error',
} as const;

// ── Dictionary Checker ──

export type SpellCheckIssueKind = 'spelling' | 'grammar' | 'style';

export interface SpellCheckIssue {
  word: string;
  range: { start: number; end: number };
  kind: SpellCheckIssueKind;
  suggestions: string[];
  source: 'harper' | 'nspell';
}

export interface DictionaryPrePassResult {
  text: string;
  issuesFixed: number;
  passes: number;
}

// ── Window Types ──

export type WindowType = 'settings' | 'history' | 'hud' | 'streaming-preview' | 'suggestions';

// ── Traffic Light ──

export type TrafficLightColor = 'green' | 'yellow' | 'red';
export type IconPosition = 'top-right' | 'top-left' | 'bottom-right' | 'bottom-left';
