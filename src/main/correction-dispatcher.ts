import { correctText as correctTextCLI, correctTextStreaming as correctTextStreamingCLI } from './cli-runner';
import { correctTextLocal, correctTextLocalStreaming } from './local-model-runner';
import type { AppConfig, CorrectionResult } from '../shared/types';

export async function correctText(
  systemPrompt: string,
  text: string,
  config: AppConfig,
): Promise<CorrectionResult> {
  if (config.provider === 'local') {
    return correctTextLocal(systemPrompt, text);
  }
  return correctTextCLI(systemPrompt, text, config);
}

export async function correctTextStreaming(
  systemPrompt: string,
  text: string,
  onChunk: (chunk: string) => void,
  config: AppConfig,
): Promise<CorrectionResult> {
  if (config.provider === 'local') {
    return correctTextLocalStreaming(systemPrompt, text, onChunk);
  }
  return correctTextStreamingCLI(systemPrompt, text, onChunk, config);
}
