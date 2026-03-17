import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import type { CLIProviderName } from '../shared/types';
import { CLI_PROVIDERS } from '../shared/constants';

/**
 * Build the CLI argument array for a given provider.
 * Port of ClaudeRuntimeSupport.cliArguments() from the Swift app.
 */
export function buildCLIArguments(
  provider: CLIProviderName,
  prompt: string,
  model?: string,
): string[] {
  switch (provider) {
    case 'claude': {
      const args = ['-p', prompt, '--setting-sources', 'user', '--tools', ''];
      if (model) args.push('--model', model);
      return args;
    }
    case 'codex': {
      const args = [
        'exec',
        '--skip-git-repo-check',
        '--sandbox', 'read-only',
        '-c', "model_reasoning_effort='low'",
      ];
      if (model) args.push('--model', model);
      args.push(prompt);
      return args;
    }
    case 'gemini': {
      const args = ['--prompt', prompt, '--output-format', 'text'];
      if (model) args.push('--model', model);
      return args;
    }
    default:
      throw new Error(`Unknown provider: ${provider}`);
  }
}

/**
 * Return platform-specific search paths for a CLI executable.
 * Port of ClaudeRuntimeSupport.cliSearchPaths() from the Swift app.
 */
export function cliSearchPaths(provider: CLIProviderName): string[] {
  const home = os.homedir();
  const executable = CLI_PROVIDERS[provider].executableName;
  const paths: string[] = [];

  if (process.platform === 'win32') {
    // Windows-specific paths
    const appData = process.env.APPDATA || path.join(home, 'AppData', 'Roaming');
    const localAppData = process.env.LOCALAPPDATA || path.join(home, 'AppData', 'Local');
    paths.push(
      path.join(appData, 'npm', `${executable}.cmd`),
      path.join(localAppData, 'Programs', executable, `${executable}.exe`),
      path.join(home, 'scoop', 'shims', `${executable}.exe`),
    );
  } else {
    // macOS / Linux paths
    paths.push(
      path.join(home, '.local', 'bin', executable),
      `/opt/homebrew/bin/${executable}`,
      `/usr/local/bin/${executable}`,
      `/usr/bin/${executable}`,
      path.join(home, 'bin', executable),
    );
  }

  // Also check PATH entries
  const pathEnv = process.env.PATH || '';
  const separator = process.platform === 'win32' ? ';' : ':';
  for (const dir of pathEnv.split(separator)) {
    if (!dir) continue;
    const ext = process.platform === 'win32' ? '.cmd' : '';
    const candidate = path.join(dir, `${executable}${ext}`);
    if (!paths.includes(candidate)) {
      paths.push(candidate);
    }
  }

  return paths;
}

/**
 * Resolve the full path to a CLI executable.
 * Returns the first path that exists, or null.
 */
export function resolveCLIPath(
  provider: CLIProviderName,
  customPath?: string,
): string | null {
  // Prefer user-configured custom path
  if (customPath && fs.existsSync(customPath)) {
    return customPath;
  }

  for (const candidate of cliSearchPaths(provider)) {
    try {
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    } catch {
      // permission error, skip
    }
  }

  return null;
}

/**
 * Build the PATH environment variable with all known CLI directories.
 * Ensures spawned processes can find the CLI even if Electron's PATH is limited.
 */
export function buildRuntimePath(): string {
  const home = os.homedir();
  const separator = process.platform === 'win32' ? ';' : ':';
  const extra: string[] = [];

  if (process.platform === 'win32') {
    const appData = process.env.APPDATA || path.join(home, 'AppData', 'Roaming');
    extra.push(path.join(appData, 'npm'));
  } else {
    extra.push(
      path.join(home, '.local', 'bin'),
      '/opt/homebrew/bin',
      '/usr/local/bin',
      path.join(home, 'bin'),
    );
  }

  const existing = process.env.PATH || '';
  return [...extra, existing].join(separator);
}

/**
 * Detect authentication errors from CLI output.
 */
export function isAuthenticationError(stdout: string, stderr: string): boolean {
  const combined = `${stdout}\n${stderr}`.toLowerCase();
  const markers = [
    'failed to authenticate',
    'authentication_error',
    'token has expired',
    'oauth token',
    'api error: 401',
    'unauthorized',
    'invalid credentials',
    'not logged in',
    'please log in',
  ];
  return markers.some((m) => combined.includes(m));
}
