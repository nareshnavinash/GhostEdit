import type { ShellRunnerErrorType } from '../shared/types';
import { CLI_PROVIDERS } from '../shared/constants';
import { configManager } from './config-manager';

export type ErrorAction = 'open-settings' | 'copy-command' | null;

export interface ErrorInfo {
  message: string;
  action: ErrorAction;
  actionLabel?: string;
  actionPayload?: string;
}

/**
 * Convert a ShellRunnerErrorType (or generic error) into a user-friendly message.
 */
export function errorToUserMessage(err: any, developerMode = false): string {
  return errorToUserInfo(err, developerMode).message;
}

/**
 * Convert a ShellRunnerErrorType (or generic error) into structured error info
 * with an optional action for the UI.
 */
export function errorToUserInfo(err: any, developerMode = false): ErrorInfo {
  const type: ShellRunnerErrorType | undefined = err?.type;
  const config = configManager.load();
  const provider = CLI_PROVIDERS[config.cliProvider];

  switch (type) {
    case 'cli-not-found':
      return {
        message: 'CLI not found. Open Settings to set the path.',
        action: 'open-settings',
        actionLabel: 'Open Settings',
      };
    case 'authentication-required':
      return {
        message: `Authentication needed. Run \`${provider?.authCommand ?? 'auth'}\` in Terminal.`,
        action: 'copy-command',
        actionLabel: 'Copy Command',
        actionPayload: provider?.authCommand ?? 'auth',
      };
    case 'timed-out':
      return {
        message: 'Timed out. Try increasing the timeout in Settings.',
        action: 'open-settings',
        actionLabel: 'Open Settings',
      };
    case 'empty-response':
      return {
        message: 'The AI returned nothing. Try again or switch providers.',
        action: null,
      };
    case 'process-failed':
    case 'launch-failed':
      return {
        message: 'Could not run the AI. Check CLI path in Settings.',
        action: 'open-settings',
        actionLabel: 'Open Settings',
      };
    case 'protected-tokens-modified':
      return {
        message: 'Some formatting was lost during correction. Please check the result.',
        action: null,
      };
    default:
      break;
  }

  // Generic fallback: prefer err.message over raw toString
  let msg = err?.message || String(err || 'Correction failed');

  if (developerMode) {
    const cause = err?.cause?.message ? ` [cause: ${err.cause.message}]` : '';
    msg = msg + cause;
  } else if (msg.length > 80) {
    msg = msg.slice(0, 77) + '...';
  }

  return { message: msg, action: null };
}
