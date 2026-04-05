import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import type { AppConfig } from '../shared/types';
import {
  CONFIG_DIR_NAME,
  CONFIG_FILE_NAME,
  HISTORY_FILE_NAME,
  PROMPT_FILE_NAME,
  PERSONAL_DICTIONARY_FILE_NAME,
  DEFAULT_CONFIG,
  DEFAULT_SYSTEM_PROMPT,
  BONSAI_DEFAULT_SYSTEM_PROMPT,
  CLI_PROVIDERS,
} from '../shared/constants';

class ConfigManager {
  private configDir: string;
  private configPath: string;
  private promptPath: string;
  private cachedConfig: AppConfig | null = null;

  constructor() {
    // Use os.homedir() instead of app.getPath('home') to avoid calling before app is ready
    const home = os.homedir();
    this.configDir = path.join(home, CONFIG_DIR_NAME);
    this.configPath = path.join(this.configDir, CONFIG_FILE_NAME);
    this.promptPath = path.join(this.configDir, PROMPT_FILE_NAME);
  }

  /** Ensure ~/.ghostedit/ directory and default files exist */
  ensureDefaults(): void {
    if (!fs.existsSync(this.configDir)) {
      fs.mkdirSync(this.configDir, { recursive: true });
    }
    if (!fs.existsSync(this.configPath)) {
      this.writeConfigFile(DEFAULT_CONFIG);
    }
    if (!fs.existsSync(this.promptPath)) {
      const defaultPrompt = DEFAULT_CONFIG.localModelEngine === 'bonsai'
        ? BONSAI_DEFAULT_SYSTEM_PROMPT
        : DEFAULT_SYSTEM_PROMPT;
      fs.writeFileSync(this.promptPath, defaultPrompt, 'utf-8');
    }
  }

  /** Load config from disk, falling back to defaults for missing keys */
  load(): AppConfig {
    if (this.cachedConfig) return { ...this.cachedConfig };

    try {
      const raw = fs.readFileSync(this.configPath, 'utf-8');
      const parsed = JSON.parse(raw);
      // Migrate old single-hotkey config to dual hotkeys
      if (parsed.hotkeyAccelerator && !parsed.localHotkeyAccelerator) {
        parsed.cliHotkeyAccelerator = parsed.hotkeyAccelerator;
        parsed.localHotkeyAccelerator = DEFAULT_CONFIG.localHotkeyAccelerator;
        delete parsed.hotkeyAccelerator;
      }
      // Migrate: add cliProvider/cliModel for configs that predate the dual-provider system
      if (!parsed.cliProvider) {
        if (parsed.provider && parsed.provider !== 'local') {
          parsed.cliProvider = parsed.provider;
          parsed.cliModel = parsed.model || CLI_PROVIDERS[parsed.provider]?.defaultModel || 'sonnet';
        }
        // else: DEFAULT_CONFIG spread below provides 'claude'/'sonnet'
      }
      // Migrate: showDiffPreview boolean → diffPreviewMode enum
      if ('showDiffPreview' in parsed && !('diffPreviewMode' in parsed)) {
        parsed.diffPreviewMode = parsed.showDiffPreview ? 'interactive' : 'none';
        delete parsed.showDiffPreview;
      }
      // Migrate: fp32 is no longer bundled — switch to int8 default
      if (parsed.localModelVariant === 'fp32') {
        parsed.localModelVariant = 'int8';
      }
      // Migrate: add bonsai engine fields
      if (!('localModelEngine' in parsed)) {
        parsed.localModelEngine = 'bonsai';
      }
      if (!('bonsaiModelSize' in parsed)) {
        parsed.bonsaiModelSize = '1.7b';
      }
      if (parsed.model === 't5-grammar' && parsed.provider === 'local') {
        parsed.model = 'bonsai-1.7b';
      }
      // Merge with defaults so new keys are always present
      const config: AppConfig = { ...DEFAULT_CONFIG, ...parsed };
      this.cachedConfig = config;
      return { ...config };
    } catch {
      this.cachedConfig = { ...DEFAULT_CONFIG };
      return { ...DEFAULT_CONFIG };
    }
  }

  /** Write config JSON to disk (no recursion guard needed) */
  private writeConfigFile(config: AppConfig): void {
    if (!fs.existsSync(this.configDir)) {
      fs.mkdirSync(this.configDir, { recursive: true });
    }
    fs.writeFileSync(this.configPath, JSON.stringify(config, null, 2), 'utf-8');
  }

  /** Save config to disk */
  save(config: AppConfig): void {
    this.writeConfigFile(config);
    this.cachedConfig = { ...config };
  }

  /** Update specific fields */
  update(partial: Partial<AppConfig>): AppConfig {
    const current = this.load();
    const updated = { ...current, ...partial };
    this.save(updated);
    return updated;
  }

  /** Invalidate cache (e.g. after external file change) */
  invalidateCache(): void {
    this.cachedConfig = null;
  }

  /** Load custom system prompt from prompt.txt, fall back to default */
  loadSystemPrompt(): string {
    try {
      const custom = fs.readFileSync(this.promptPath, 'utf-8').trim();
      return custom || DEFAULT_SYSTEM_PROMPT;
    } catch {
      return DEFAULT_SYSTEM_PROMPT;
    }
  }

  /** Save custom system prompt to prompt.txt */
  saveSystemPrompt(prompt: string): void {
    if (!fs.existsSync(this.configDir)) {
      fs.mkdirSync(this.configDir, { recursive: true });
    }
    fs.writeFileSync(this.promptPath, prompt, 'utf-8');
  }

  /** Load personal dictionary words */
  loadPersonalDictionary(): string[] {
    try {
      const raw = fs.readFileSync(this.personalDictionaryPath, 'utf-8');
      return raw.split('\n').map((w) => w.trim()).filter(Boolean);
    } catch {
      return [];
    }
  }

  /** Save personal dictionary words */
  savePersonalDictionary(words: string[]): void {
    if (!fs.existsSync(this.configDir)) {
      fs.mkdirSync(this.configDir, { recursive: true });
    }
    fs.writeFileSync(this.personalDictionaryPath, words.join('\n'), 'utf-8');
  }

  /** Get path to history file */
  get historyPath(): string {
    return path.join(this.configDir, HISTORY_FILE_NAME);
  }

  /** Get path to personal dictionary file */
  get personalDictionaryPath(): string {
    return path.join(this.configDir, PERSONAL_DICTIONARY_FILE_NAME);
  }

  /** Get the config directory path */
  get configDirPath(): string {
    return this.configDir;
  }
}

export const configManager = new ConfigManager();
