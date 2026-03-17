import { describe, it, expect, vi, beforeEach } from 'vitest';
import { EventEmitter } from 'node:events';

// Mock config-manager
vi.mock('./config-manager', () => ({
  configManager: {
    load: vi.fn(),
  },
}));

// Mock cli-arguments
vi.mock('./cli-arguments', () => ({
  resolveCLIPath: vi.fn(() => '/usr/bin/mock-cli'),
  buildCLIArguments: vi.fn(() => ['--arg']),
  buildRuntimePath: vi.fn(() => '/usr/bin'),
  isAuthenticationError: vi.fn(() => false),
}));

// Mock child_process spawn
const mockSpawn = vi.fn();
vi.mock('node:child_process', () => ({
  spawn: (...args: any[]) => mockSpawn(...args),
}));

import { correctText, correctTextStreaming } from './cli-runner';
import type { AppConfig } from '../shared/types';

const localConfig = {
  provider: 'local',
  timeoutSeconds: 60,
} as AppConfig;

const claudeConfig = {
  provider: 'claude',
  model: 'sonnet',
  timeoutSeconds: 60,
} as AppConfig;

beforeEach(() => {
  vi.clearAllMocks();
  vi.useFakeTimers();
});

function createMockProcess() {
  const proc = new EventEmitter() as any;
  proc.stdout = new EventEmitter();
  proc.stderr = new EventEmitter();
  proc.exitCode = null;
  proc.kill = vi.fn();
  proc.removeAllListeners = vi.fn();
  return proc;
}

describe('correctText', () => {
  it('throws launch-failed when provider is local', async () => {
    await expect(correctText('prompt', 'text', localConfig)).rejects.toMatchObject({
      type: 'launch-failed',
      message: 'Local provider should use local-model-runner',
    });
  });
});

describe('correctTextStreaming', () => {
  it('throws launch-failed when provider is local', async () => {
    await expect(correctTextStreaming('prompt', 'text', vi.fn(), localConfig)).rejects.toMatchObject({
      type: 'launch-failed',
      message: 'Local provider should use local-model-runner',
    });
  });

  it('rejects with timed-out on code === null', async () => {
    const proc = createMockProcess();
    mockSpawn.mockReturnValue(proc);

    const promise = correctTextStreaming('prompt', 'text', vi.fn(), claudeConfig);

    // Simulate timeout (code is null)
    proc.emit('close', null);

    await expect(promise).rejects.toMatchObject({
      type: 'timed-out',
    });
  });

  it('rejects on non-zero exit code', async () => {
    const proc = createMockProcess();
    mockSpawn.mockReturnValue(proc);

    const promise = correctTextStreaming('prompt', 'text', vi.fn(), claudeConfig);

    proc.emit('close', 1);

    await expect(promise).rejects.toMatchObject({
      type: 'process-failed',
    });
  });

  it('rejects with empty-response on empty output', async () => {
    const proc = createMockProcess();
    mockSpawn.mockReturnValue(proc);

    const promise = correctTextStreaming('prompt', 'text', vi.fn(), claudeConfig);

    proc.emit('close', 0);

    await expect(promise).rejects.toMatchObject({
      type: 'empty-response',
    });
  });
});
