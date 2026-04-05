import type { CorrectionResult } from '../shared/types';
import { DEFAULT_SYSTEM_PROMPT, BONSAI_DEFAULT_SYSTEM_PROMPT } from '../shared/constants';
import { configManager } from './config-manager';
import { ensureLlamaServer, resetIdleTimer } from './llama-server-manager';

// ── Response Filtering ──

function filterToolCallTags(text: string): string {
  return text.replace(/<tool_call>[\s\S]*?<\/tool_call>/g, '').trim();
}

// ── System Prompt Resolution ──

function resolveSystemPrompt(systemPrompt: string): string {
  // If the prompt is the generic CLI default, use the bonsai-optimized Teacher prompt
  if (systemPrompt === DEFAULT_SYSTEM_PROMPT) {
    return BONSAI_DEFAULT_SYSTEM_PROMPT;
  }
  // User-customized or tone-based prompt: use as-is
  return systemPrompt;
}

// ── Non-Streaming Correction ──

export async function correctTextBonsai(
  systemPrompt: string,
  text: string,
): Promise<CorrectionResult> {
  const config = configManager.load();
  const port = await ensureLlamaServer(config.bonsaiModelSize);
  const resolvedPrompt = resolveSystemPrompt(systemPrompt);
  const startTime = Date.now();

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutSeconds * 1000);

  try {
    const resp = await fetch(`http://127.0.0.1:${port}/v1/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'bonsai',
        messages: [
          { role: 'system', content: resolvedPrompt },
          { role: 'user', content: text },
        ],
        stream: false,
        temperature: 0.1,
        max_tokens: Math.min(text.length * 3, 2048),
      }),
      signal: controller.signal,
    });

    if (!resp.ok) {
      const errBody = await resp.text().catch(() => '');
      throw new Error(`llama-server returned HTTP ${resp.status}: ${errBody}`);
    }

    const data = await resp.json();
    const content = data?.choices?.[0]?.message?.content ?? '';
    const output = filterToolCallTags(content);

    if (!output) {
      throw new Error('Empty response from bonsai model');
    }

    resetIdleTimer();
    return { text: output, durationMs: Date.now() - startTime };
  } finally {
    clearTimeout(timeout);
  }
}

// ── Streaming Correction ──

export async function correctTextBonsaiStreaming(
  systemPrompt: string,
  text: string,
  onChunk: (chunk: string) => void,
): Promise<CorrectionResult> {
  const config = configManager.load();
  const port = await ensureLlamaServer(config.bonsaiModelSize);
  const resolvedPrompt = resolveSystemPrompt(systemPrompt);
  const startTime = Date.now();

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), config.timeoutSeconds * 1000);

  try {
    const resp = await fetch(`http://127.0.0.1:${port}/v1/chat/completions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'bonsai',
        messages: [
          { role: 'system', content: resolvedPrompt },
          { role: 'user', content: text },
        ],
        stream: true,
        temperature: 0.1,
        max_tokens: Math.min(text.length * 3, 2048),
      }),
      signal: controller.signal,
    });

    if (!resp.ok) {
      const errBody = await resp.text().catch(() => '');
      throw new Error(`llama-server returned HTTP ${resp.status}: ${errBody}`);
    }

    let fullText = '';
    const reader = resp.body?.getReader();
    if (!reader) {
      throw new Error('No response body stream');
    }

    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      // Process complete SSE lines
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? ''; // Keep incomplete last line in buffer

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || !trimmed.startsWith('data: ')) continue;

        const data = trimmed.slice(6); // Remove "data: " prefix
        if (data === '[DONE]') break;

        try {
          const parsed = JSON.parse(data);
          const content = parsed?.choices?.[0]?.delta?.content;
          if (content) {
            // Filter tool_call tags inline
            const filtered = content
              .replace(/<tool_call>/g, '')
              .replace(/<\/tool_call>/g, '');
            if (filtered) {
              fullText += filtered;
              onChunk(filtered);
            }
          }
        } catch {
          // Skip malformed chunks
        }
      }
    }

    const output = fullText.trim();
    if (!output) {
      throw new Error('Empty response from bonsai model');
    }

    resetIdleTimer();
    return { text: output, durationMs: Date.now() - startTime };
  } finally {
    clearTimeout(timeout);
  }
}
