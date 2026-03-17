import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// Mock electron
vi.mock('electron', () => ({
  app: {
    getVersion: vi.fn(() => '1.0.0'),
  },
}));

// Mock fs
const mockExistsSync = vi.fn((_path?: string) => false);
const mockReadFileSync = vi.fn((_path?: string, _enc?: string) => '{}');
const mockWriteFileSync = vi.fn((_path?: string, _data?: string) => {});
const mockMkdirSync = vi.fn((_path?: string, _opts?: any) => {});
const mockUnlinkSync = vi.fn((_path?: string) => {});

vi.mock('node:fs', () => ({
  default: {
    existsSync: (p: string) => mockExistsSync(p),
    readFileSync: (p: string, e: string) => mockReadFileSync(p, e),
    writeFileSync: (p: string, d: string) => mockWriteFileSync(p, d),
    mkdirSync: (p: string, o: any) => mockMkdirSync(p, o),
    unlinkSync: (p: string) => mockUnlinkSync(p),
  },
  existsSync: (p: string) => mockExistsSync(p),
  readFileSync: (p: string, e: string) => mockReadFileSync(p, e),
  writeFileSync: (p: string, d: string) => mockWriteFileSync(p, d),
  mkdirSync: (p: string, o: any) => mockMkdirSync(p, o),
  unlinkSync: (p: string) => mockUnlinkSync(p),
}));

// Mock @huggingface/transformers
const mockPipeline = vi.fn();
vi.mock('@huggingface/transformers', () => ({
  pipeline: mockPipeline,
}));

// Helper: get a fresh module to reset in-memory state
async function freshModule() {
  vi.resetModules();
  vi.doMock('electron', () => ({
    app: { getVersion: vi.fn(() => '1.0.0') },
  }));
  vi.doMock('node:fs', () => ({
    default: {
      existsSync: (p: string) => mockExistsSync(p),
      readFileSync: (p: string, e: string) => mockReadFileSync(p, e),
      writeFileSync: (p: string, d: string) => mockWriteFileSync(p, d),
      mkdirSync: (p: string, o: any) => mockMkdirSync(p, o),
      unlinkSync: (p: string) => mockUnlinkSync(p),
    },
    existsSync: (p: string) => mockExistsSync(p),
    readFileSync: (p: string, e: string) => mockReadFileSync(p, e),
    writeFileSync: (p: string, d: string) => mockWriteFileSync(p, d),
    mkdirSync: (p: string, o: any) => mockMkdirSync(p, o),
    unlinkSync: (p: string) => mockUnlinkSync(p),
  }));
  vi.doMock('@huggingface/transformers', () => ({
    pipeline: mockPipeline,
  }));
  return import('./device-selector');
}

beforeEach(() => {
  vi.clearAllMocks();
  mockPipeline.mockReset();
  mockExistsSync.mockReturnValue(false);
});

describe('getCachedDevice', () => {
  it('returns null when no detection has been performed', async () => {
    const { getCachedDevice } = await freshModule();
    expect(getCachedDevice()).toBeNull();
  });
});

describe('clearDeviceCache', () => {
  it('clears in-memory and disk cache', async () => {
    const { clearDeviceCache, getCachedDevice } = await freshModule();
    clearDeviceCache();
    expect(getCachedDevice()).toBeNull();
  });

  it('calls unlinkSync when cache file exists', async () => {
    mockExistsSync.mockReturnValue(true);
    const { clearDeviceCache } = await freshModule();
    clearDeviceCache();
    expect(mockUnlinkSync).toHaveBeenCalled();
  });
});

describe('detectBestDevice', () => {
  it('returns disk-cached device when available and version matches', async () => {
    const cachedData = JSON.stringify({
      appVersion: '1.0.0',
      device: 'dml',
      runtime: 'node',
      label: 'DirectML (GPU)',
    });
    mockExistsSync.mockImplementation((p?: string) => {
      if (String(p).includes('device-cache.json')) return true;
      return false;
    });
    mockReadFileSync.mockReturnValue(cachedData);

    const { detectBestDevice } = await freshModule();
    const { selection, pipeline } = await detectBestDevice('model', '/cache', {});

    expect(selection.device).toBe('dml');
    expect(selection.runtime).toBe('node');
    expect(pipeline).toBeNull();
    // Should NOT have called the pipeline probe
    expect(mockPipeline).not.toHaveBeenCalled();
  });

  it('ignores disk cache when version mismatches', async () => {
    const cachedData = JSON.stringify({
      appVersion: '0.9.0', // different version
      device: 'dml',
      runtime: 'node',
      label: 'DirectML (GPU)',
    });
    mockExistsSync.mockImplementation((p?: string) => {
      if (String(p).includes('device-cache.json')) return true;
      return false;
    });
    mockReadFileSync.mockReturnValue(cachedData);

    const { detectBestDevice } = await freshModule();

    // On macOS (test runner), first candidate is cpu (node) — no probe needed
    const { selection } = await detectBestDevice('model', '/cache', {});
    expect(selection.device).toBe('cpu');
    expect(selection.runtime).toBe('node');
  });

  it('writes disk cache after detection', async () => {
    mockExistsSync.mockReturnValue(false);

    const { detectBestDevice } = await freshModule();
    await detectBestDevice('model', '/cache', {});

    expect(mockWriteFileSync).toHaveBeenCalled();
    const written = JSON.parse(mockWriteFileSync.mock.calls[0][1] as string);
    expect(written.appVersion).toBe('1.0.0');
    expect(written.device).toBeDefined();
  });

  it('returns cached selection on second call without re-probing', async () => {
    mockExistsSync.mockReturnValue(false);

    const { detectBestDevice } = await freshModule();
    const first = await detectBestDevice('model', '/cache', {});
    const second = await detectBestDevice('model', '/cache', {});

    expect(first.selection).toEqual(second.selection);
    // writeFileSync called only once (first detection)
    expect(mockWriteFileSync).toHaveBeenCalledTimes(1);
  });
});

describe('detectBestDevice on win32', () => {
  const originalPlatform = process.platform;

  beforeEach(() => {
    Object.defineProperty(process, 'platform', { value: 'win32' });
  });

  afterEach(() => {
    Object.defineProperty(process, 'platform', { value: originalPlatform });
  });

  it('probes DirectML first on Windows and uses it when probe succeeds', async () => {
    mockExistsSync.mockReturnValue(false);
    const mockPipe = vi.fn();
    mockPipeline.mockResolvedValue(mockPipe);

    const { detectBestDevice } = await freshModule();
    const { selection, pipeline } = await detectBestDevice('model', '/cache', {});

    expect(selection.device).toBe('dml');
    expect(selection.runtime).toBe('node');
    expect(selection.label).toBe('DirectML (GPU)');
    expect(pipeline).toBe(mockPipe);
    expect(mockPipeline).toHaveBeenCalledWith(
      'text2text-generation',
      'model',
      expect.objectContaining({ device: 'dml' }),
    );
  });

  it('falls back to CPU when DirectML probe fails', async () => {
    mockExistsSync.mockReturnValue(false);
    mockPipeline.mockRejectedValue(new Error('No DirectML device'));

    const { detectBestDevice } = await freshModule();
    const { selection, pipeline } = await detectBestDevice('model', '/cache', {});

    expect(selection.device).toBe('cpu');
    expect(selection.runtime).toBe('node');
    expect(pipeline).toBeNull();
  });
});

describe('detectBestDevice on linux x64', () => {
  const originalPlatform = process.platform;
  const originalArch = process.arch;

  beforeEach(() => {
    Object.defineProperty(process, 'platform', { value: 'linux' });
    Object.defineProperty(process, 'arch', { value: 'x64' });
  });

  afterEach(() => {
    Object.defineProperty(process, 'platform', { value: originalPlatform });
    Object.defineProperty(process, 'arch', { value: originalArch });
  });

  it('probes CUDA first on Linux x64 and uses it when probe succeeds', async () => {
    mockExistsSync.mockReturnValue(false);
    const mockPipe = vi.fn();
    mockPipeline.mockResolvedValue(mockPipe);

    const { detectBestDevice } = await freshModule();
    const { selection, pipeline } = await detectBestDevice('model', '/cache', {});

    expect(selection.device).toBe('cuda');
    expect(selection.runtime).toBe('node');
    expect(selection.label).toBe('CUDA (GPU)');
    expect(pipeline).toBe(mockPipe);
  });

  it('falls back to CPU when CUDA probe fails', async () => {
    mockExistsSync.mockReturnValue(false);
    mockPipeline.mockRejectedValue(new Error('No CUDA'));

    const { detectBestDevice } = await freshModule();
    const { selection } = await detectBestDevice('model', '/cache', {});

    expect(selection.device).toBe('cpu');
    expect(selection.runtime).toBe('node');
  });
});
