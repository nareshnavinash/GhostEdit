import type { ShellRunnerErrorType } from '../shared/types';
import { CLI_PROVIDERS } from '../shared/constants';
import { configManager } from './config-manager';

/**
 * Convert a ShellRunnerErrorType (or generic error) into a user-friendly message.
 */
export function errorToUserMessage(err: any, developerMode = false): string {
  const type: ShellRunnerErrorType | undefined = err?.type;
  const config = configManager.load();
  const provider = CLI_PROVIDERS[config.cliProvider];

  switch (type) {
    case 'cli-not-found':
      return `CLI not found. Open Settings to set the path.`;
    case 'authentication-required':
      return `Authentication needed. Run \`${provider?.authCommand ?? 'auth'}\` in Terminal.`;
    case 'timed-out':
      return `Timed out. Try increasing the timeout in Settings.`;
    case 'empty-response':
      return `The AI returned nothing. Try again or switch providers.`;
    case 'process-failed':
    case 'launch-failed':
      return `Could not run the AI. Check CLI path in Settings.`;
    case 'protected-tokens-modified':
      return `Some formatting was lost during correction. Please check the result.`;
    default:
      break;
  }

  // Generic fallback: prefer err.message over raw toString
  const msg = err?.message || String(err || 'Correction failed');

  if (developerMode) {
    const cause = err?.cause?.message ? ` [cause: ${err.cause.message}]` : '';
    return msg + cause;
  }

  if (msg.length > 80) {
    return msg.slice(0, 77) + '...';
  }
  return msg;
}
