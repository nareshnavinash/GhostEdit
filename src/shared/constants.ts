import type { AppConfig, CLIProvider, TonePreset, ProviderName, LocalModelVariant, DiffPreviewMode, IconPosition } from './types';

// ── CLI Provider Definitions ──

export const CLI_PROVIDERS: Record<string, CLIProvider> = {
  claude: {
    name: 'claude',
    displayName: 'Claude',
    executableName: 'claude',
    authCommand: 'claude auth login',
    configPathKey: 'claudePath',
    availableModels: ['sonnet', 'haiku', 'opus'],
    defaultModel: 'sonnet',
  },
  codex: {
    name: 'codex',
    displayName: 'Codex',
    executableName: 'codex',
    authCommand: 'codex auth',
    configPathKey: 'codexPath',
    availableModels: ['o4-mini', 'o3', 'gpt-4.1', 'gpt-4.1-mini', 'gpt-4.1-nano'],
    defaultModel: 'o4-mini',
  },
  gemini: {
    name: 'gemini',
    displayName: 'Gemini',
    executableName: 'gemini',
    authCommand: 'gemini auth',
    configPathKey: 'geminiPath',
    availableModels: ['gemini-2.5-flash', 'gemini-2.5-pro', 'gemini-2.0-flash'],
    defaultModel: 'gemini-2.5-flash',
  },
};

// ── Local Provider Definition ──

export const LOCAL_PROVIDER = {
  name: 'local' as const,
  displayName: 'Built-in (Offline)',
  availableModels: ['t5-grammar'],
  defaultModel: 't5-grammar',
  modelRepoId: 'Xenova/t5-base-grammar-correction',
};

// ── All Providers (CLI + local) ──

export const ALL_PROVIDERS: Record<string, { name: ProviderName; displayName: string; availableModels: string[]; defaultModel: string }> = {
  ...Object.fromEntries(
    Object.entries(CLI_PROVIDERS).map(([key, p]) => [key, { name: p.name, displayName: p.displayName, availableModels: p.availableModels, defaultModel: p.defaultModel }]),
  ),
  local: LOCAL_PROVIDER,
};

// ── Model Variant Definitions ──

export const DEFAULT_BUNDLED_VARIANT: LocalModelVariant = 'int8';

export const MODEL_VARIANTS: readonly { variant: LocalModelVariant; displayName: string; sizeMB: number }[] = [
  { variant: 'q4f16', displayName: 'Q4 F16 (Smallest)', sizeMB: 210 },
  { variant: 'int8', displayName: 'INT8 (Default)', sizeMB: 250 },
  { variant: 'fp16', displayName: 'FP16', sizeMB: 496 },
  { variant: 'fp32', displayName: 'FP32 (Largest)', sizeMB: 963 },
] as const;

export const VARIANT_ONNX_FILES: Record<LocalModelVariant, { encoder: string; decoder: string }> = {
  q4f16: { encoder: 'encoder_model_q4f16.onnx', decoder: 'decoder_model_merged_q4f16.onnx' },
  int8: { encoder: 'encoder_model_int8.onnx', decoder: 'decoder_model_merged_int8.onnx' },
  fp16: { encoder: 'encoder_model_fp16.onnx', decoder: 'decoder_model_merged_fp16.onnx' },
  fp32: { encoder: 'encoder_model.onnx', decoder: 'decoder_model_merged.onnx' },
};

// ── Default Configuration ──

export const DEFAULT_CONFIG: AppConfig = {
  claudePath: '',
  codexPath: '',
  geminiPath: '',
  provider: 'local',
  model: 't5-grammar',
  cliProvider: 'claude',
  cliModel: 'sonnet',
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
  diffPreviewMode: 'interactive',
  passivePreviewSeconds: 5,
  autoPasteDelaySeconds: 5,
  localModelVariant: 'int8',
  localModelSpeed: 'fast',
  firstRunComplete: false,
  monitoringEnabled: true,
  trafficLightPosition: 'top-right',
  trafficLightInactivityMs: 3000,
  lineHotkeyAccelerator: 'CommandOrControl+L',
  backgroundModelRefinement: false,
  streakDates: [],
  dailyDigestEnabled: true,
  settingsMode: 'simple',
  monitoringAppFilter: 'all',
  monitoringAppWhitelist: [],
  appToneOverrides: {},
  meetingModeEnabled: true,
  meetingApps: ['Zoom', 'Microsoft Teams', 'Google Meet', 'Webex', 'FaceTime'],
  suppressedSuggestions: {},
};

// ── Tone Preset Prompts ──

export const TONE_PROMPTS: Record<TonePreset, string> = {
  default: '',
  casual:
    'Revise the following text for grammar and spelling. Use a casual, friendly, and conversational tone. Keep contractions, informal phrasing, and a relaxed style.',
  professional:
    'Revise for grammar, spelling, and punctuation. Use a polished, professional tone suitable for business communication.',
  academic:
    'Revise for grammar, spelling, and punctuation. Use a formal academic tone with precise vocabulary and clear structure.',
  slack:
    'Revise for grammar and spelling. Keep a concise, upbeat Slack-message tone. Preserve any emoji and informal abbreviations.',
};

// ── Default System Prompt ──

export const DEFAULT_SYSTEM_PROMPT = `You are a grammar correction assistant. Fix grammar, spelling, and punctuation in the provided text. Return ONLY the corrected text, nothing else. Do not add explanations, notes, or markdown. Preserve the original meaning, tone, and formatting. If the text is already correct, return it as-is.`;

// ── Config Directory ──

export const CONFIG_DIR_NAME = '.ghostedit';
export const CONFIG_FILE_NAME = 'config.json';
export const HISTORY_FILE_NAME = 'history.json';
export const PROMPT_FILE_NAME = 'prompt.txt';
export const PERSONAL_DICTIONARY_FILE_NAME = 'personal-dictionary.txt';
export const ERROR_LOG_MAX_ENTRIES = 10;

// ── Languages ──

export const LANGUAGES: Record<string, string> = {
  auto: 'Auto-detect',
  en: 'English',
  es: 'Spanish',
  fr: 'French',
  de: 'German',
  it: 'Italian',
  pt: 'Portuguese',
  ja: 'Japanese',
  ko: 'Korean',
  zh: 'Chinese',
  ru: 'Russian',
  ar: 'Arabic',
  hi: 'Hindi',
};
