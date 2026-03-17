import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock electron
vi.mock('electron', () => ({
  app: {
    isPackaged: false,
    getAppPath: vi.fn(() => '/mock/app'),
  },
}));

// Mock fs
vi.mock('node:fs', () => {
  return {
    default: {
      existsSync: vi.fn(() => false),
      readdirSync: vi.fn(() => []),
      statSync: vi.fn(() => ({ size: 0 })),
      mkdirSync: vi.fn(),
      copyFileSync: vi.fn(),
    },
    existsSync: vi.fn(() => false),
    readdirSync: vi.fn(() => []),
    statSync: vi.fn(() => ({ size: 0 })),
    mkdirSync: vi.fn(),
    copyFileSync: vi.fn(),
  };
});

// Mock config-manager
const mockConfigLoad = vi.fn((): Record<string, any> => ({ localModelVariant: 'q4f16', localModelSpeed: 'fast', provider: 'local' }));
vi.mock('./config-manager', () => ({
  configManager: {
    load: () => mockConfigLoad(),
  },
}));

// Mock device-selector (return node/cpu)
vi.mock('./device-selector', () => ({
  getCachedDevice: vi.fn(() => ({ device: 'cpu', runtime: 'node', label: 'CPU (Node)' })),
}));

// Mock @huggingface/transformers
const mockPipeline = vi.fn();
const mockTextStreamer = vi.fn();

vi.mock('@huggingface/transformers', () => ({
  pipeline: mockPipeline,
  TextStreamer: mockTextStreamer,
}));

import * as fs from 'node:fs';

// Helper: get a fresh module instance to reset pipelinePromise state
async function freshModule() {
  vi.resetModules();
  // Re-apply mocks after reset
  vi.doMock('electron', () => ({
    app: { isPackaged: false, getAppPath: vi.fn(() => '/mock/app') },
  }));
  vi.doMock('node:fs', () => ({
    default: fs,
    ...fs,
  }));
  vi.doMock('./config-manager', () => ({
    configManager: {
      load: () => mockConfigLoad(),
    },
  }));
  vi.doMock('./device-selector', () => ({
    getCachedDevice: vi.fn(() => ({ device: 'cpu', runtime: 'node', label: 'CPU (Node)' })),
  }));
  vi.doMock('@huggingface/transformers', () => ({
    pipeline: mockPipeline,
    TextStreamer: mockTextStreamer,
  }));
  return import('./local-model-runner');
}

beforeEach(() => {
  vi.clearAllMocks();
  mockPipeline.mockReset();
  mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16', localModelSpeed: 'fast', provider: 'local' });
});

describe('getBundledModelDir', () => {
  it('returns resources/models path in development', async () => {
    const { getBundledModelDir } = await freshModule();
    const dir = getBundledModelDir();
    expect(dir).toContain('resources');
    expect(dir).toContain('models');
  });
});

describe('getUserModelDir', () => {
  it('returns ~/.ghostedit/models/ path', async () => {
    const { getUserModelDir } = await freshModule();
    const dir = getUserModelDir();
    expect(dir).toContain('.ghostedit');
    expect(dir).toContain('models');
  });
});

describe('getModelDirForVariant', () => {
  it('prefers user dir when variant files exist there', async () => {
    const { getModelDirForVariant, getUserModelDir } = await freshModule();
    vi.mocked(fs.existsSync).mockImplementation((p) => {
      const ps = String(p);
      // User dir has the q4f16 files
      if (ps.includes('.ghostedit') && ps.endsWith('.onnx')) return true;
      return false;
    });

    const dir = getModelDirForVariant('q4f16');
    expect(dir).toBe(getUserModelDir());
  });

  it('falls back to bundled dir when user dir lacks files', async () => {
    const { getModelDirForVariant, getBundledModelDir } = await freshModule();
    vi.mocked(fs.existsSync).mockReturnValue(false);

    const dir = getModelDirForVariant('q4f16');
    expect(dir).toBe(getBundledModelDir());
  });
});

describe('scanAvailableVariants', () => {
  it('returns all 4 variants with correct availability', async () => {
    const { scanAvailableVariants } = await freshModule();
    vi.mocked(fs.existsSync).mockImplementation((p) => {
      const ps = String(p);
      // Only q4f16 files exist in bundled dir
      if (ps.includes('q4f16') && ps.includes('resources')) return true;
      return false;
    });

    const variants = scanAvailableVariants();
    expect(variants).toHaveLength(4);

    const q4 = variants.find((v) => v.variant === 'q4f16');
    expect(q4?.available).toBe(true);
    expect(q4?.bundled).toBe(true);

    const fp32 = variants.find((v) => v.variant === 'fp32');
    expect(fp32?.available).toBe(false);
    expect(fp32?.bundled).toBe(false);
  });
});

describe('getLocalModelStatus', () => {
  it('returns ready: false when active variant is not available', async () => {
    const { getLocalModelStatus } = await freshModule();
    vi.mocked(fs.existsSync).mockReturnValue(false);
    const status = getLocalModelStatus();
    expect(status.ready).toBe(false);
    expect(status.activeVariant).toBe('q4f16');
    expect(status.variants).toHaveLength(4);
  });

  it('returns ready: true when active variant files exist', async () => {
    const { getLocalModelStatus } = await freshModule();
    vi.mocked(fs.existsSync).mockImplementation((p) => {
      const ps = String(p);
      if (ps.includes('q4f16') && ps.includes('resources')) return true;
      return false;
    });

    const status = getLocalModelStatus();
    expect(status.ready).toBe(true);
    expect(status.activeVariant).toBe('q4f16');
  });

  it('reads variant from config', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'fp16', localModelSpeed: 'fast', provider: 'local' });
    const { getLocalModelStatus } = await freshModule();
    vi.mocked(fs.existsSync).mockReturnValue(false);

    const status = getLocalModelStatus();
    expect(status.activeVariant).toBe('fp16');
  });
});

describe('ensureModelLoaded (via correctTextLocal)', () => {
  it('passes dtype for non-fp32 variants', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16', localModelSpeed: 'fast', provider: 'local' });
    const { correctTextLocal } = await freshModule();
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'ok' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    await correctTextLocal('', 'test');

    expect(mockPipeline).toHaveBeenCalledWith(
      'text2text-generation',
      'Xenova/t5-base-grammar-correction',
      expect.objectContaining({
        local_files_only: true,
        cache_dir: expect.stringContaining('models'),
        dtype: 'q4f16',
      }),
    );
  });

  it('omits dtype for fp32 variant', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'fp32', localModelSpeed: 'fast', provider: 'local' });
    const { correctTextLocal } = await freshModule();
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'ok' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    await correctTextLocal('', 'test');

    const callArgs = mockPipeline.mock.calls[0][2];
    expect(callArgs).not.toHaveProperty('dtype');
  });

  it('returns same pipeline on concurrent calls (no duplicate creation)', async () => {
    const { correctTextLocal } = await freshModule();
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'ok' }]);
    mockPipeline.mockImplementation(
      () => new Promise((r) => setTimeout(() => r(mockPipe), 50)),
    );

    const [r1, r2] = await Promise.all([
      correctTextLocal('', 'text1'),
      correctTextLocal('', 'text2'),
    ]);

    expect(r1.text).toBe('ok');
    expect(r2.text).toBe('ok');
    expect(mockPipeline).toHaveBeenCalledTimes(1);
  });

  it('resets state on failure so retry works', async () => {
    const { correctTextLocal } = await freshModule();
    mockPipeline.mockRejectedValueOnce(new Error('load failed'));

    await expect(correctTextLocal('', 'text')).rejects.toThrow('load failed');

    // Retry should work
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'ok' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    const result = await correctTextLocal('', 'retry');
    expect(result.text).toBe('ok');
    expect(mockPipeline).toHaveBeenCalledTimes(2);
  });
});

describe('invalidatePipeline', () => {
  it('forces pipeline reload on next call', async () => {
    const { correctTextLocal, invalidatePipeline } = await freshModule();
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'ok' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    await correctTextLocal('', 'test1');
    expect(mockPipeline).toHaveBeenCalledTimes(1);

    invalidatePipeline();
    await correctTextLocal('', 'test2');
    expect(mockPipeline).toHaveBeenCalledTimes(2);
  });
});

describe('correctTextLocal', () => {
  it('prepends "grammar: " prefix to input', async () => {
    const { correctTextLocal } = await freshModule();
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'corrected' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    await correctTextLocal('', 'hello world');

    expect(mockPipe).toHaveBeenCalledWith(
      'grammar: hello world',
      expect.any(Object),
    );
  });

  it('uses greedy decode (num_beams: 1) in fast mode', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16', localModelSpeed: 'fast', provider: 'local' });
    const { correctTextLocal } = await freshModule();
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'fixed' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    await correctTextLocal('', 'test');

    expect(mockPipe).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        num_beams: 1,
        max_new_tokens: expect.any(Number),
      }),
    );
    // Should NOT have early_stopping in fast mode
    const callArgs = mockPipe.mock.calls[0][1];
    expect(callArgs).not.toHaveProperty('early_stopping');
  });

  it('uses beam search (num_beams: 4) in quality mode', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16', localModelSpeed: 'quality', provider: 'local' });
    const { correctTextLocal } = await freshModule();
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'fixed' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    await correctTextLocal('', 'test');

    expect(mockPipe).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        num_beams: 4,
        early_stopping: true,
        max_new_tokens: expect.any(Number),
      }),
    );
  });

  it('passes anti-repetition params (no_repeat_ngram_size, repetition_penalty)', async () => {
    const { correctTextLocal } = await freshModule();
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'fixed' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    await correctTextLocal('', 'test input');

    expect(mockPipe).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        no_repeat_ngram_size: 3,
        repetition_penalty: 1.2,
      }),
    );
  });

  it('caps max_new_tokens at 512', async () => {
    const { correctTextLocal } = await freshModule();
    const longText = 'x'.repeat(1000);
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'fixed' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    await correctTextLocal('', longText);

    const callArgs = mockPipe.mock.calls[0][1];
    expect(callArgs.max_new_tokens).toBe(512);
  });

  it('returns trimmed generated_text and durationMs', async () => {
    const { correctTextLocal } = await freshModule();
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: '  corrected text  ' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    const result = await correctTextLocal('', 'test');

    expect(result.text).toBe('corrected text');
    expect(result.durationMs).toBeGreaterThanOrEqual(0);
  });
});

describe('preWarmModel', () => {
  it('calls ensureModelLoaded when provider is local', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16', localModelSpeed: 'fast', provider: 'local' });
    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'ok' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    const { preWarmModel } = await freshModule();
    preWarmModel();

    // Give the async operation a tick to start
    await new Promise((r) => setTimeout(r, 10));
    expect(mockPipeline).toHaveBeenCalledTimes(1);
  });

  it('does not load model when provider is not local', async () => {
    mockConfigLoad.mockReturnValue({ localModelVariant: 'q4f16', localModelSpeed: 'fast', provider: 'claude' });

    const { preWarmModel } = await freshModule();
    preWarmModel();

    await new Promise((r) => setTimeout(r, 10));
    expect(mockPipeline).not.toHaveBeenCalled();
  });
});

describe('correctTextLocalStreaming', () => {
  it('uses TextStreamer for real streaming in node runtime', async () => {
    const { correctTextLocalStreaming } = await freshModule();

    // Mock TextStreamer as a class so `new TextStreamer(...)` works
    let capturedCallback: ((text: string) => void) | null = null;
    mockTextStreamer.mockImplementation(function (this: any, _tokenizer: any, opts: any) {
      capturedCallback = opts.callback_function;
    });

    const mockPipeFn = vi.fn(async () => {
      // Simulate token emission during generation
      capturedCallback?.('Hello');
      capturedCallback?.(' world');
      return [{ generated_text: 'Hello world' }];
    });
    (mockPipeFn as any).tokenizer = {};
    mockPipeline.mockResolvedValue(mockPipeFn);

    const onChunk = vi.fn();
    const result = await correctTextLocalStreaming('', 'test', onChunk);

    expect(onChunk).toHaveBeenCalledWith('Hello');
    expect(onChunk).toHaveBeenCalledWith(' world');
    expect(result.text).toBe('Hello world');
  });

  it('passes anti-repetition params in streaming mode', async () => {
    const { correctTextLocalStreaming } = await freshModule();

    let capturedCallback: ((text: string) => void) | null = null;
    mockTextStreamer.mockImplementation(function (this: any, _tokenizer: any, opts: any) {
      capturedCallback = opts.callback_function;
    });

    const mockPipeFn = vi.fn(async (_input: string, opts: any) => {
      capturedCallback?.('ok');
      // Verify the params were passed
      expect(opts.no_repeat_ngram_size).toBe(3);
      expect(opts.repetition_penalty).toBe(1.2);
      return [{ generated_text: 'ok' }];
    });
    (mockPipeFn as any).tokenizer = {};
    mockPipeline.mockResolvedValue(mockPipeFn);

    const onChunk = vi.fn();
    await correctTextLocalStreaming('', 'test', onChunk);

    expect(mockPipeFn).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        no_repeat_ngram_size: 3,
        repetition_penalty: 1.2,
      }),
    );
  });

  it('falls back to non-streaming when TextStreamer throws', async () => {
    const { correctTextLocalStreaming } = await freshModule();

    mockTextStreamer.mockImplementation(() => { throw new Error('TextStreamer not available'); });

    const mockPipe = vi.fn().mockResolvedValue([{ generated_text: 'fallback' }]);
    mockPipeline.mockResolvedValue(mockPipe);

    const onChunk = vi.fn();
    const result = await correctTextLocalStreaming('', 'test', onChunk);

    expect(result.text).toBe('fallback');
    expect(onChunk).toHaveBeenCalledWith('fallback');
  });
});
