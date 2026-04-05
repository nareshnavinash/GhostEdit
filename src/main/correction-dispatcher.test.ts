import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock cli-runner
vi.mock('./cli-runner', () => ({
  correctText: vi.fn(),
  correctTextStreaming: vi.fn(),
}));

// Mock local-model-runner
vi.mock('./local-model-runner', () => ({
  correctTextLocal: vi.fn(),
  correctTextLocalStreaming: vi.fn(),
}));

// Mock bonsai-inference
vi.mock('./bonsai-inference', () => ({
  correctTextBonsai: vi.fn(),
  correctTextBonsaiStreaming: vi.fn(),
}));

import { correctText as correctTextCLI, correctTextStreaming as correctTextStreamingCLI } from './cli-runner';
import { correctTextLocal, correctTextLocalStreaming } from './local-model-runner';
import { correctTextBonsai, correctTextBonsaiStreaming } from './bonsai-inference';
import { correctText, correctTextStreaming } from './correction-dispatcher';
import type { AppConfig } from '../shared/types';

beforeEach(() => {
  vi.clearAllMocks();
});

const bonsaiConfig = { provider: 'local', localModelEngine: 'bonsai' } as AppConfig;
const t5Config = { provider: 'local', localModelEngine: 't5' } as AppConfig;
const claudeConfig = { provider: 'claude' } as AppConfig;
const geminiConfig = { provider: 'gemini' } as AppConfig;
const codexConfig = { provider: 'codex' } as AppConfig;

describe('correctText', () => {
  it('routes to correctTextBonsai when provider is local and engine is bonsai', async () => {
    vi.mocked(correctTextBonsai).mockResolvedValue({ text: 'bonsai result', durationMs: 10 });

    const result = await correctText('prompt', 'input text', bonsaiConfig);

    expect(correctTextBonsai).toHaveBeenCalledWith('prompt', 'input text');
    expect(correctTextLocal).not.toHaveBeenCalled();
    expect(correctTextCLI).not.toHaveBeenCalled();
    expect(result).toEqual({ text: 'bonsai result', durationMs: 10 });
  });

  it('routes to correctTextLocal when provider is local and engine is t5', async () => {
    vi.mocked(correctTextLocal).mockResolvedValue({ text: 't5 result', durationMs: 15 });

    const result = await correctText('prompt', 'input text', t5Config);

    expect(correctTextLocal).toHaveBeenCalledWith('prompt', 'input text');
    expect(correctTextBonsai).not.toHaveBeenCalled();
    expect(correctTextCLI).not.toHaveBeenCalled();
    expect(result).toEqual({ text: 't5 result', durationMs: 15 });
  });

  it('routes to correctTextCLI when provider is claude', async () => {
    vi.mocked(correctTextCLI).mockResolvedValue({ text: 'claude result', durationMs: 20 });

    const result = await correctText('prompt', 'input text', claudeConfig);

    expect(correctTextCLI).toHaveBeenCalledWith('prompt', 'input text', claudeConfig);
    expect(correctTextLocal).not.toHaveBeenCalled();
    expect(correctTextBonsai).not.toHaveBeenCalled();
    expect(result).toEqual({ text: 'claude result', durationMs: 20 });
  });

  it('passes systemPrompt and text through unchanged', async () => {
    vi.mocked(correctTextBonsai).mockResolvedValue({ text: 'ok', durationMs: 1 });

    await correctText('my system prompt', 'my text', bonsaiConfig);

    expect(correctTextBonsai).toHaveBeenCalledWith('my system prompt', 'my text');
  });
});

describe('correctTextStreaming', () => {
  it('routes to correctTextBonsaiStreaming for bonsai engine', async () => {
    vi.mocked(correctTextBonsaiStreaming).mockResolvedValue({ text: 'bonsai streamed', durationMs: 5 });

    const onChunk = vi.fn();
    const result = await correctTextStreaming('prompt', 'text', onChunk, bonsaiConfig);

    expect(correctTextBonsaiStreaming).toHaveBeenCalledWith('prompt', 'text', onChunk);
    expect(correctTextLocalStreaming).not.toHaveBeenCalled();
    expect(correctTextStreamingCLI).not.toHaveBeenCalled();
    expect(result).toEqual({ text: 'bonsai streamed', durationMs: 5 });
  });

  it('routes to correctTextLocalStreaming for t5 engine', async () => {
    vi.mocked(correctTextLocalStreaming).mockResolvedValue({ text: 't5 streamed', durationMs: 8 });

    const onChunk = vi.fn();
    const result = await correctTextStreaming('prompt', 'text', onChunk, t5Config);

    expect(correctTextLocalStreaming).toHaveBeenCalledWith('prompt', 'text', onChunk);
    expect(correctTextBonsaiStreaming).not.toHaveBeenCalled();
    expect(result).toEqual({ text: 't5 streamed', durationMs: 8 });
  });

  it('routes to correctTextStreamingCLI for CLI providers', async () => {
    vi.mocked(correctTextStreamingCLI).mockResolvedValue({ text: 'gemini out', durationMs: 30 });

    const onChunk = vi.fn();
    const result = await correctTextStreaming('prompt', 'text', onChunk, geminiConfig);

    expect(correctTextStreamingCLI).toHaveBeenCalledWith('prompt', 'text', onChunk, geminiConfig);
    expect(correctTextLocalStreaming).not.toHaveBeenCalled();
    expect(correctTextBonsaiStreaming).not.toHaveBeenCalled();
    expect(result).toEqual({ text: 'gemini out', durationMs: 30 });
  });

  it('returns the result from whichever runner is called', async () => {
    vi.mocked(correctTextStreamingCLI).mockResolvedValue({ text: 'codex', durationMs: 15 });

    const result = await correctTextStreaming('p', 't', vi.fn(), codexConfig);

    expect(result.text).toBe('codex');
    expect(result.durationMs).toBe(15);
  });
});
