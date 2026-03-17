import { spawn, type ChildProcess } from 'node:child_process';
import type { AppConfig, CLIProviderName, ShellRunnerError, CorrectionResult } from '../shared/types';
import {
  resolveCLIPath,
  buildCLIArguments,
  buildRuntimePath,
  isAuthenticationError,
} from './cli-arguments';
import { CLI_PROVIDERS } from '../shared/constants';

/**
 * Port of ShellRunner.swift — runs CLI subprocesses for text correction.
 */

/** Trim output: strip leading/trailing blank lines, trailing whitespace, em-dashes */
function trimOutput(text: string): string {
  let result = text;
  // Remove leading/trailing em-dashes that some CLIs prepend
  result = result.replace(/^—+\s*/g, '').replace(/\s*—+$/g, '');
  // Strip leading/trailing blank lines but keep internal structure
  const lines = result.split('\n');
  let start = 0;
  while (start < lines.length && lines[start].trim() === '') start++;
  let end = lines.length - 1;
  while (end > start && lines[end].trim() === '') end--;
  return lines.slice(start, end + 1).join('\n').trimEnd();
}

/** Classify process failure into a typed error */
function classifyFailure(
  provider: CLIProviderName,
  exitCode: number,
  stdout: string,
  stderr: string,
): ShellRunnerError {
  if (isAuthenticationError(stdout, stderr)) {
    return {
      type: 'authentication-required',
      message: `${CLI_PROVIDERS[provider].displayName} requires authentication. Run: ${CLI_PROVIDERS[provider].authCommand}`,
      provider,
    };
  }
  return {
    type: 'process-failed',
    message: `${CLI_PROVIDERS[provider].displayName} exited with code ${exitCode}`,
    provider,
    exitCode,
    stderr,
  };
}

/**
 * Run a one-shot CLI correction.
 */
export async function correctText(
  systemPrompt: string,
  selectedText: string,
  config: AppConfig,
): Promise<CorrectionResult> {
  if (config.provider === 'local') {
    throw {
      type: 'launch-failed',
      message: 'Local provider should use local-model-runner',
    } satisfies ShellRunnerError;
  }

  const provider = config.provider as CLIProviderName;
  const customPath = config[CLI_PROVIDERS[provider].configPathKey];
  const cliPath = resolveCLIPath(provider, customPath || undefined);

  if (!cliPath) {
    throw {
      type: 'cli-not-found',
      message: `${CLI_PROVIDERS[provider].displayName} CLI not found. Install it or set the path in settings.`,
      provider,
    } satisfies ShellRunnerError;
  }

  const fullPrompt = systemPrompt
    ? `${systemPrompt}\n\nText to correct:\n${selectedText}`
    : selectedText;

  const model = config.model || undefined;
  const args = buildCLIArguments(provider, fullPrompt, model);

  const startTime = Date.now();

  return new Promise<CorrectionResult>((resolve, reject) => {
    const env: Record<string, string | undefined> = {
      ...process.env,
      PATH: buildRuntimePath(),
    };
    // Remove env vars that interfere with Claude CLI
    delete env.CLAUDE_CODE;
    delete env.CLAUDECODE;

    const proc: ChildProcess = spawn(cliPath, args, {
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: config.timeoutSeconds * 1000,
    });

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];

    proc.stdout?.on('data', (chunk: Buffer) => {
      stdoutChunks.push(chunk);
    });

    proc.stderr?.on('data', (chunk: Buffer) => {
      stderrChunks.push(chunk);
    });

    proc.on('error', (err) => {
      reject({
        type: 'launch-failed',
        message: `Failed to launch ${CLI_PROVIDERS[provider].displayName}: ${err.message}`,
        provider,
      } satisfies ShellRunnerError);
    });

    proc.on('close', (code) => {
      const durationMs = Date.now() - startTime;
      const stdout = Buffer.concat(stdoutChunks).toString();
      const stderr = Buffer.concat(stderrChunks).toString();

      if (code === null) {
        reject({
          type: 'timed-out',
          message: `${CLI_PROVIDERS[provider].displayName} timed out after ${config.timeoutSeconds}s`,
          provider,
        } satisfies ShellRunnerError);
        return;
      }

      if (code !== 0) {
        reject(classifyFailure(provider, code, stdout, stderr));
        return;
      }

      const trimmed = trimOutput(stdout);
      if (!trimmed) {
        reject({
          type: 'empty-response',
          message: `${CLI_PROVIDERS[provider].displayName} returned an empty response`,
          provider,
        } satisfies ShellRunnerError);
        return;
      }

      resolve({ text: trimmed, durationMs });
    });

    // Manual timeout fallback (spawn timeout doesn't always fire)
    const killTimer = setTimeout(() => {
      if (proc.exitCode === null) {
        proc.kill('SIGTERM');
        setTimeout(() => {
          if (proc.exitCode === null) proc.kill('SIGKILL');
        }, 2000);
      }
    }, config.timeoutSeconds * 1000);

    // Clean up timer and listeners when process exits
    proc.once('close', () => {
      clearTimeout(killTimer);
      proc.removeAllListeners();
    });
  });
}

/**
 * Run a streaming CLI correction.
 * `onChunk` is called with each stdout chunk as it arrives.
 */
export async function correctTextStreaming(
  systemPrompt: string,
  selectedText: string,
  onChunk: (chunk: string) => void,
  config: AppConfig,
): Promise<CorrectionResult> {
  if (config.provider === 'local') {
    throw {
      type: 'launch-failed',
      message: 'Local provider should use local-model-runner',
    } satisfies ShellRunnerError;
  }

  const provider = config.provider as CLIProviderName;
  const customPath = config[CLI_PROVIDERS[provider].configPathKey];
  const cliPath = resolveCLIPath(provider, customPath || undefined);

  if (!cliPath) {
    throw {
      type: 'cli-not-found',
      message: `${CLI_PROVIDERS[provider].displayName} CLI not found.`,
      provider,
    } satisfies ShellRunnerError;
  }

  const fullPrompt = systemPrompt
    ? `${systemPrompt}\n\nText to correct:\n${selectedText}`
    : selectedText;

  const model = config.model || undefined;
  const args = buildCLIArguments(provider, fullPrompt, model);

  const startTime = Date.now();

  return new Promise<CorrectionResult>((resolve, reject) => {
    const env: Record<string, string | undefined> = {
      ...process.env,
      PATH: buildRuntimePath(),
    };
    delete env.CLAUDE_CODE;
    delete env.CLAUDECODE;

    const proc = spawn(cliPath, args, {
      env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    const stdoutChunks: Buffer[] = [];
    const stderrChunks: Buffer[] = [];

    proc.stdout?.on('data', (chunk: Buffer) => {
      const text = chunk.toString();
      stdoutChunks.push(chunk);
      onChunk(text);
    });

    proc.stderr?.on('data', (chunk: Buffer) => {
      stderrChunks.push(chunk);
    });

    proc.on('error', (err) => {
      reject({
        type: 'launch-failed',
        message: err.message,
        provider,
      } satisfies ShellRunnerError);
    });

    proc.on('close', (code) => {
      const durationMs = Date.now() - startTime;
      const stdout = Buffer.concat(stdoutChunks).toString();
      const stderr = Buffer.concat(stderrChunks).toString();

      if (code === null || code !== 0) {
        if (code === null) {
          reject({
            type: 'timed-out',
            message: `${CLI_PROVIDERS[provider].displayName} timed out`,
            provider,
          } satisfies ShellRunnerError);
        } else {
          reject(classifyFailure(provider, code, stdout, stderr));
        }
        return;
      }

      const trimmed = trimOutput(stdout);
      if (!trimmed) {
        reject({
          type: 'empty-response',
          message: 'Empty response',
          provider,
        } satisfies ShellRunnerError);
        return;
      }

      resolve({ text: trimmed, durationMs });
    });

    const killTimer = setTimeout(() => {
      if (proc.exitCode === null) {
        proc.kill('SIGTERM');
      }
    }, config.timeoutSeconds * 1000);

    // Clean up timer and listeners when process exits
    proc.once('close', () => {
      clearTimeout(killTimer);
      proc.removeAllListeners();
    });
  });
}
