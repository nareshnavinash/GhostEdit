import { ipcMain, type BrowserWindow } from 'electron';
import { IPC, type AppConfig, type CorrectionHistoryEntry, type LocalModelVariant, type WindowType } from '../shared/types';
import { configManager } from './config-manager';
import { correctText, correctTextStreaming } from './correction-dispatcher';
import { getLocalModelStatus, invalidatePipeline, downloadVariant } from './local-model-runner';
import { loadHistory, clearHistory } from './history-store';
import { resolveCLIPath } from './cli-arguments';
import { CLI_PROVIDERS } from '../shared/constants';
import { getCachedDevice } from './device-selector';

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
      return { success: false, error: String(err) };
    }
  });
}
