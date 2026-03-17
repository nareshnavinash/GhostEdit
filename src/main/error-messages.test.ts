import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock config-manager
const mockLoad = vi.fn();
vi.mock('./config-manager', () => ({
  configManager: { load: () => mockLoad() },
}));

import { errorToUserMessage } from './error-messages';

beforeEach(() => {
  vi.clearAllMocks();
  mockLoad.mockReturnValue({ cliProvider: 'claude' });
});

describe('errorToUserMessage', () => {
  it('returns CLI not found message for cli-not-found', () => {
    const msg = errorToUserMessage({ type: 'cli-not-found' });
    expect(msg).toContain('CLI not found');
  });

  it('returns authentication message with auth command for authentication-required', () => {
    const msg = errorToUserMessage({ type: 'authentication-required' });
    expect(msg).toContain('Authentication needed');
    expect(msg).toContain('claude auth login');
  });

  it('returns timeout message for timed-out', () => {
    const msg = errorToUserMessage({ type: 'timed-out' });
    expect(msg).toContain('Timed out');
  });

  it('returns empty response message for empty-response', () => {
    const msg = errorToUserMessage({ type: 'empty-response' });
    expect(msg).toContain('returned nothing');
  });

  it('returns process failed message for process-failed', () => {
    const msg = errorToUserMessage({ type: 'process-failed' });
    expect(msg).toContain('Could not run');
  });

  it('returns protected tokens message for protected-tokens-modified', () => {
    const msg = errorToUserMessage({ type: 'protected-tokens-modified' });
    expect(msg).toContain('formatting was lost');
  });

  it('uses err.message for unknown error types', () => {
    const msg = errorToUserMessage({ message: 'Something went wrong' });
    expect(msg).toBe('Something went wrong');
  });

  it('truncates long messages to 80 chars', () => {
    const longMsg = 'A'.repeat(100);
    const msg = errorToUserMessage({ message: longMsg });
    expect(msg.length).toBeLessThanOrEqual(80);
    expect(msg).toMatch(/\.\.\.$/);
  });

  describe('developerMode', () => {
    it('does not truncate long messages when developerMode is true', () => {
      const longMsg = 'A'.repeat(100);
      const msg = errorToUserMessage({ message: longMsg }, true);
      expect(msg).toBe(longMsg);
    });

    it('appends cause message when developerMode is true', () => {
      const err = { message: 'Key simulation failed', cause: { message: 'Cannot find module bindings' } };
      const msg = errorToUserMessage(err, true);
      expect(msg).toBe('Key simulation failed [cause: Cannot find module bindings]');
    });

    it('does not append cause when developerMode is false', () => {
      const err = { message: 'Key simulation failed', cause: { message: 'Cannot find module bindings' } };
      const msg = errorToUserMessage(err, false);
      expect(msg).toBe('Key simulation failed');
    });

    it('still returns typed error messages unchanged in developerMode', () => {
      const msg = errorToUserMessage({ type: 'cli-not-found' }, true);
      expect(msg).toContain('CLI not found');
    });
  });
});
