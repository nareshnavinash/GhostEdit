import { describe, it, expect, vi, beforeEach } from 'vitest';

// Collect registered handlers
const handlers: Record<string, Function> = {};
const mockEmit = vi.fn();

// Mock electron
vi.mock('electron', () => ({
  ipcMain: {
    handle: vi.fn((channel: string, handler: Function) => {
      handlers[channel] = handler;
    }),
    emit: (...args: any[]) => mockEmit(...args),
  },
}));

// Mock dependencies
const mockConfigLoad = vi.fn(() => ({ localModelVariant: 'q4f16' }));
const mockConfigSave = vi.fn();

vi.mock('./config-manager', () => ({
  configManager: {
    load: () => mockConfigLoad(),
    save: (config: any) => mockConfigSave(config),
  },
}));

vi.mock('./correction-dispatcher', () => ({
  correctText: vi.fn(),
  correctTextStreaming: vi.fn(),
}));

const mockGetLocalModelStatus = vi.fn();
const mockInvalidatePipeline = vi.fn();
const mockDownloadVariant = vi.fn();

vi.mock('./local-model-runner', () => ({
  getLocalModelStatus: () => mockGetLocalModelStatus(),
  invalidatePipeline: () => mockInvalidatePipeline(),
  downloadVariant: (variant: any, onProgress: any) => mockDownloadVariant(variant, onProgress),
}));

vi.mock('./history-store', () => ({
  loadHistory: vi.fn(() => []),
  clearHistory: vi.fn(),
}));

vi.mock('./cli-arguments', () => ({
  resolveCLIPath: vi.fn(),
}));

vi.mock('../shared/constants', () => ({
  CLI_PROVIDERS: {},
}));

import { registerIPCHandlers } from './ipc-handlers';
import { IPC } from '../shared/types';

beforeEach(() => {
  vi.clearAllMocks();
  Object.keys(handlers).forEach((k) => delete handlers[k]);
  mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16' });
  registerIPCHandlers(vi.fn());
});

function createMockEvent(destroyed = false) {
  return {
    sender: {
      send: vi.fn(),
      isDestroyed: vi.fn(() => destroyed),
    },
  };
}

describe('GET_LOCAL_MODEL_STATUS handler', () => {
  it('returns model info when ready', async () => {
    mockGetLocalModelStatus.mockReturnValue({ ready: true, activeVariant: 'q4f16', variants: [] });

    const result = await handlers[IPC.GET_LOCAL_MODEL_STATUS]();

    expect(result).toEqual({ ready: true, activeVariant: 'q4f16', variants: [] });
  });

  it('returns not ready when model is missing', async () => {
    mockGetLocalModelStatus.mockReturnValue({ ready: false, activeVariant: 'q4f16', variants: [] });

    const result = await handlers[IPC.GET_LOCAL_MODEL_STATUS]();

    expect(result).toEqual({ ready: false, activeVariant: 'q4f16', variants: [] });
  });
});

describe('SAVE_CONFIG handler', () => {
  it('invalidates pipeline when localModelVariant changes', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16' });

    await handlers[IPC.SAVE_CONFIG]({}, { localModelVariant: 'fp16' });

    expect(mockInvalidatePipeline).toHaveBeenCalledTimes(1);
    expect(mockConfigSave).toHaveBeenCalledWith({ localModelVariant: 'fp16' });
  });

  it('does not invalidate pipeline when localModelVariant stays the same', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16' });

    await handlers[IPC.SAVE_CONFIG]({}, { localModelVariant: 'q4f16' });

    expect(mockInvalidatePipeline).not.toHaveBeenCalled();
  });

  it('emits config-changed event after saving', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16' });

    await handlers[IPC.SAVE_CONFIG]({}, { localModelVariant: 'q4f16' });

    expect(mockEmit).toHaveBeenCalledWith('config-changed');
  });
});

describe('DOWNLOAD_MODEL_VARIANT handler', () => {
  it('calls downloadVariant and returns success', async () => {
    mockDownloadVariant.mockResolvedValue(undefined);
    const event = createMockEvent(false);

    const result = await handlers[IPC.DOWNLOAD_MODEL_VARIANT](event, 'int8');

    expect(mockDownloadVariant).toHaveBeenCalledWith('int8', expect.any(Function));
    expect(result).toEqual({ success: true });
  });

  it('sends progress events to renderer', async () => {
    mockDownloadVariant.mockImplementation(async (_variant: string, onProgress: Function) => {
      onProgress(50);
      onProgress(100);
    });
    const event = createMockEvent(false);

    await handlers[IPC.DOWNLOAD_MODEL_VARIANT](event, 'fp16');

    expect(event.sender.send).toHaveBeenCalledWith(IPC.DOWNLOAD_VARIANT_PROGRESS, { variant: 'fp16', progress: 50 });
    expect(event.sender.send).toHaveBeenCalledWith(IPC.DOWNLOAD_VARIANT_PROGRESS, { variant: 'fp16', progress: 100 });
  });

  it('does not send progress when sender is destroyed', async () => {
    mockDownloadVariant.mockImplementation(async (_variant: string, onProgress: Function) => {
      onProgress(50);
    });
    const event = createMockEvent(true);

    await handlers[IPC.DOWNLOAD_MODEL_VARIANT](event, 'fp16');

    expect(event.sender.send).not.toHaveBeenCalled();
  });

  it('returns error on failure', async () => {
    mockDownloadVariant.mockRejectedValue(new Error('download failed'));
    const event = createMockEvent(false);

    const result = await handlers[IPC.DOWNLOAD_MODEL_VARIANT](event, 'fp32');

    expect(result).toEqual({ success: false, error: 'Error: download failed' });
  });
});

describe('CORRECT_TEXT_STREAMING handler', () => {
  it('skips sending chunks when sender is destroyed', async () => {
    const { correctTextStreaming } = await import('./correction-dispatcher');
    vi.mocked(correctTextStreaming).mockImplementation(async (_sp, _t, onChunk) => {
      onChunk('chunk');
      return { text: 'chunk', durationMs: 10 };
    });

    const event = createMockEvent(true);
    const result = await handlers[IPC.CORRECT_TEXT_STREAMING](event, 'prompt', 'text');

    expect(result.success).toBe(true);
    expect(event.sender.send).not.toHaveBeenCalledWith(IPC.STREAMING_CHUNK, expect.anything());
  });

  it('sends chunks when sender is alive', async () => {
    const { correctTextStreaming } = await import('./correction-dispatcher');
    vi.mocked(correctTextStreaming).mockImplementation(async (_sp, _t, onChunk) => {
      onChunk('hello');
      return { text: 'hello', durationMs: 5 };
    });

    const event = createMockEvent(false);
    const result = await handlers[IPC.CORRECT_TEXT_STREAMING](event, 'prompt', 'text');

    expect(result.success).toBe(true);
    expect(event.sender.send).toHaveBeenCalledWith(IPC.STREAMING_CHUNK, 'hello');
  });
});
