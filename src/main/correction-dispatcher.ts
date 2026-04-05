import { correctText as correctTextCLI, correctTextStreaming as correctTextStreamingCLI } from './cli-runner';
import { correctTextLocal, correctTextLocalStreaming } from './local-model-runner';
import { correctTextBonsai, correctTextBonsaiStreaming } from './bonsai-inference';
import type { AppConfig, CorrectionResult } from '../shared/types';

export async function correctText(
  systemPrompt: string,
  text: string,
  config: AppConfig,
): Promise<CorrectionResult> {
  if (config.provider === 'local') {
    if (config.localModelEngine === 't5') {
      return correctTextLocal(systemPrompt, text);
    }
    return correctTextBonsai(systemPrompt, text);
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
    if (config.localModelEngine === 't5') {
      return correctTextLocalStreaming(systemPrompt, text, onChunk);
    }
    return correctTextBonsaiStreaming(systemPrompt, text, onChunk);
  }
  return correctTextStreamingCLI(systemPrompt, text, onChunk, config);
}
