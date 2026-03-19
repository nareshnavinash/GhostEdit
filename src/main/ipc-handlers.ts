import { ipcMain, dialog, type BrowserWindow } from 'electron';
import * as fs from 'node:fs';
import { IPC, type AppConfig, type CorrectionHistoryEntry, type LocalModelVariant, type WindowType } from '../shared/types';
import { configManager } from './config-manager';
import { correctText, correctTextStreaming } from './correction-dispatcher';
import { getLocalModelStatus, invalidatePipeline, downloadVariant } from './local-model-runner';
import { loadHistory, clearHistory, computeUsageStats } from './history-store';
import { resolveCLIPath } from './cli-arguments';
import { CLI_PROVIDERS, DEFAULT_SYSTEM_PROMPT } from '../shared/constants';
import { getCachedDevice } from './device-selector';
import { getErrors } from './error-log';
import { reloadPersonalDictionary } from './dictionary-checker';

type WindowOpener = (type: WindowType) => void;

/**
 * Register all IPC handlers for renderer ↔ main communication.
 */
export function registerIPCHandlers(openWindow: WindowOpener): void {
  // ── Config ──
  ipcMain.handle(IPC.GET_CONFIG, () => {
    return configManager.load();
  });

  ipcMain.handle(IPC.SAVE_CONFIG, (_event, config: AppConfig) => {
    const previous = configManager.load();
    configManager.save(config);
    if (previous.localModelVariant !== config.localModelVariant) {
      invalidatePipeline();
    }
    ipcMain.emit('config-changed');
    return { success: true };
  });

  // ── CLI Status ──
  ipcMain.handle(IPC.GET_CLI_STATUS, () => {
    const config = configManager.load();
    const statuses: Record<string, { found: boolean; path: string | null }> = {};
    for (const [name, provider] of Object.entries(CLI_PROVIDERS)) {
      const customPath = config[provider.configPathKey] || undefined;
      const resolved = resolveCLIPath(provider.name, customPath);
      statuses[name] = { found: !!resolved, path: resolved };
    }
    return statuses;
  });

  // ── Correction (non-streaming) ──
  ipcMain.handle(
    IPC.CORRECT_TEXT,
    async (_event, systemPrompt: string, text: string) => {
      try {
        const config = configManager.load();
        const result = await correctText(systemPrompt, text, config);
        return { success: true, ...result };
      } catch (err) {
        return { success: false, error: err };
      }
    },
  );

  // ── Correction (streaming) ──
  ipcMain.handle(
    IPC.CORRECT_TEXT_STREAMING,
    async (event, systemPrompt: string, text: string) => {
      try {
        const config = configManager.load();
        const result = await correctTextStreaming(
          systemPrompt,
          text,
          (chunk) => {
            if (!event.sender.isDestroyed()) {
              event.sender.send(IPC.STREAMING_CHUNK, chunk);
            }
          },
          config,
        );
        if (!event.sender.isDestroyed()) {
          event.sender.send(IPC.STREAMING_DONE, result.text);
        }
        return { success: true, ...result };
      } catch (err) {
        if (!event.sender.isDestroyed()) {
          event.sender.send(IPC.STREAMING_ERROR, err);
        }
        return { success: false, error: err };
      }
    },
  );

  // ── History ──
  ipcMain.handle(IPC.GET_HISTORY, () => {
    return loadHistory();
  });

  ipcMain.handle(IPC.CLEAR_HISTORY, () => {
    clearHistory();
    return { success: true };
  });

  // ── Window management ──
  ipcMain.handle(IPC.OPEN_WINDOW, (_event, type: WindowType) => {
    openWindow(type);
    return { success: true };
  });

  // ── Local Model ──
  ipcMain.handle(IPC.GET_LOCAL_MODEL_STATUS, () => {
    return getLocalModelStatus();
  });

  // ── Inference Device ──
  ipcMain.handle(IPC.GET_INFERENCE_DEVICE, () => {
    return getCachedDevice();
  });

  // ── Download Model Variant ──
  ipcMain.handle(IPC.DOWNLOAD_MODEL_VARIANT, async (event, variant: LocalModelVariant) => {
    try {
      await downloadVariant(variant, (progress) => {
        if (!event.sender.isDestroyed()) {
          event.sender.send(IPC.DOWNLOAD_VARIANT_PROGRESS, { variant, progress });
        }
      });
      return { success: true };
    } catch (err) {
      if (!event.sender.isDestroyed()) {
        event.sender.send(IPC.DOWNLOAD_VARIANT_ERROR, { variant, error: String(err) });
      }
      return { success: false, error: String(err) };
    }
  });

  // ── Export History ──
  ipcMain.handle(IPC.EXPORT_HISTORY, async (_event, format: 'json' | 'csv') => {
    const entries = loadHistory();
    const ext = format === 'json' ? 'json' : 'csv';
    const result = await dialog.showSaveDialog({
      title: 'Export Correction History',
      defaultPath: `ghostedit-history.${ext}`,
      filters: [
        format === 'json'
          ? { name: 'JSON', extensions: ['json'] }
          : { name: 'CSV', extensions: ['csv'] },
      ],
    });

    if (result.canceled || !result.filePath) return { success: false };

    let content: string;
    if (format === 'json') {
      content = JSON.stringify(entries, null, 2);
    } else {
      const header = 'id,timestamp,originalText,generatedText,provider,model,durationMs,succeeded\n';
      const rows = entries.map((e) =>
        [e.id, e.timestamp, csvEscape(e.originalText), csvEscape(e.generatedText), e.provider, e.model, e.durationMilliseconds, e.succeeded].join(','),
      );
      content = header + rows.join('\n');
    }

    await fs.promises.writeFile(result.filePath, content, 'utf-8');
    return { success: true, path: result.filePath };
  });

  // ── Error Log ──
  ipcMain.handle(IPC.GET_ERROR_LOG, () => {
    return getErrors();
  });

  // ── System Prompt ──
  ipcMain.handle(IPC.GET_SYSTEM_PROMPT, () => {
    return {
      prompt: configManager.loadSystemPrompt(),
      defaultPrompt: DEFAULT_SYSTEM_PROMPT,
    };
  });

  ipcMain.handle(IPC.SAVE_SYSTEM_PROMPT, (_event, prompt: string) => {
    configManager.saveSystemPrompt(prompt);
    return { success: true };
  });

  // ── Personal Dictionary ──
  ipcMain.handle(IPC.GET_PERSONAL_DICTIONARY, () => {
    return configManager.loadPersonalDictionary();
  });

  ipcMain.handle(IPC.SAVE_PERSONAL_DICTIONARY, (_event, words: string[]) => {
    configManager.savePersonalDictionary(words);
    reloadPersonalDictionary();
    return { success: true };
  });

  // ── Usage Stats ──
  ipcMain.handle(IPC.GET_USAGE_STATS, () => {
    return computeUsageStats();
  });

  // ── Re-Correct (run correction again on original text) ──
  ipcMain.handle(IPC.RE_CORRECT, async (_event, text: string) => {
    try {
      const config = configManager.load();
      const result = await correctText(
        configManager.loadSystemPrompt(),
        text,
        config,
      );
      return { success: true, text: result.text, durationMs: result.durationMs };
    } catch (err: any) {
      return { success: false, error: err?.message || String(err) };
    }
  });

  // ── Explain Diff (for interactive preview "Why?" tooltip) ──
  ipcMain.handle(IPC.EXPLAIN_DIFF, async (_event, original: string, corrected: string) => {
    try {
      const config = configManager.load();
      const prompt = `Explain in 10 words or fewer why "${original}" was changed to "${corrected}". Be specific about the grammar or spelling rule.`;
      const result = await correctText(prompt, '', {
        ...config,
        provider: config.provider === 'local' ? 'local' : config.cliProvider,
        model: config.provider === 'local' ? 't5-grammar' : config.cliModel,
      });
      return { success: true, explanation: result.text };
    } catch {
      // For local model, return a generic category-based explanation
      const lower = original.toLowerCase();
      const lowerCorrected = corrected.toLowerCase();
      if (lower === lowerCorrected) {
        return { success: true, explanation: 'Capitalization fix' };
      }
      return { success: true, explanation: 'Spelling or grammar correction' };
    }
  });

  // ── Inline Correction (for onboarding, no clipboard) ──
  ipcMain.handle(IPC.CORRECT_INLINE, async (_event, text: string) => {
    try {
      const config = configManager.load();
      const result = await correctText(
        'You are a grammar correction assistant. Fix grammar, spelling, and punctuation in the provided text. Return ONLY the corrected text, nothing else.',
        text,
        { ...config, provider: 'local', model: 't5-grammar' },
      );
      return { success: true, text: result.text };
    } catch (err: any) {
      return { success: false, error: err?.message || String(err) };
    }
  });
}

function csvEscape(value: string): string {
  if (value.includes(',') || value.includes('"') || value.includes('\n')) {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return value;
}
