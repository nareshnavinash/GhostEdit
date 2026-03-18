// @vitest-environment jsdom
import '../test-setup';
import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import History from './History';
import type { CorrectionHistoryEntry, ErrorLogEntry } from '../../shared/types';

// Mock diff-match-patch — must be a constructor (used with `new`)
vi.mock('diff-match-patch', () => ({
  default: function DiffMatchPatch(this: any) {
    this.diff_main = (a: string, b: string) => {
      if (a && b && a !== b) return [[-1, a], [1, b]];
      if (a === b) return [[0, a]];
      return [[0, a || b]];
    };
    this.diff_cleanupSemantic = () => {};
  },
}));

function makeEntry(overrides?: Partial<CorrectionHistoryEntry>): CorrectionHistoryEntry {
  return {
    id: `entry-${Math.random().toString(36).slice(2, 8)}`,
    timestamp: '2025-01-15T10:00:00.000Z',
    originalText: 'teh quick fox',
    generatedText: 'the quick fox',
    provider: 'local',
    model: 't5-grammar',
    durationMilliseconds: 150,
    succeeded: true,
    ...overrides,
  };
}

function makeError(overrides?: Partial<ErrorLogEntry>): ErrorLogEntry {
  return {
    id: `err-${Math.random().toString(36).slice(2, 8)}`,
    timestamp: '2025-01-15T10:00:00.000Z',
    message: 'API request failed',
    provider: 'claude',
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  window.ghostedit.getHistory = vi.fn().mockResolvedValue([]) as any;
  window.ghostedit.getErrorLog = vi.fn().mockResolvedValue([]) as any;
  window.ghostedit.clearHistory = vi.fn().mockResolvedValue({ success: true }) as any;
  window.ghostedit.exportHistory = vi.fn().mockResolvedValue({ success: true }) as any;
  (window.ghostedit as any).platform = 'darwin';

  // Mock navigator.clipboard
  Object.assign(navigator, {
    clipboard: { writeText: vi.fn().mockResolvedValue(undefined) },
  });
});

async function renderAndWait(entries: CorrectionHistoryEntry[] = [], errors: ErrorLogEntry[] = []) {
  window.ghostedit.getHistory = vi.fn().mockResolvedValue(entries) as any;
  window.ghostedit.getErrorLog = vi.fn().mockResolvedValue(errors) as any;
  render(<History />);
  // Wait for async data load
  await waitFor(() => {
    expect(window.ghostedit.getHistory).toHaveBeenCalled();
  });
}

describe('History', () => {
  // ── Tabs ──

  it('History tab active by default (search input visible)', async () => {
    await renderAndWait();
    expect(screen.getByPlaceholderText('Search history...')).toBeInTheDocument();
  });

  it('clicking Errors tab switches view', async () => {
    await renderAndWait([], [makeError()]);
    fireEvent.click(screen.getByText(/Errors/));
    await waitFor(() => {
      expect(screen.getByText('API request failed')).toBeInTheDocument();
    });
  });

  it('error count badge shows (N) when errors exist', async () => {
    await renderAndWait([], [makeError(), makeError()]);
    expect(screen.getByText(/Errors \(2\)/)).toBeInTheDocument();
  });

  // ── History list ──

  it('"No corrections yet" when empty', async () => {
    await renderAndWait();
    expect(screen.getByText('No corrections yet')).toBeInTheDocument();
  });

  it('entries rendered with correct status badges', async () => {
    const entries = [
      makeEntry({ id: 'ok', succeeded: true }),
      makeEntry({ id: 'fail', succeeded: false }),
      makeEntry({ id: 'rej', succeeded: false, rejected: true }),
    ];
    await renderAndWait(entries);

    await waitFor(() => {
      expect(screen.getByText('OK')).toBeInTheDocument();
    });
    // "Failed" also exists in the status <option>, so use getAllByText
    const failedElements = screen.getAllByText('Failed');
    expect(failedElements.length).toBeGreaterThanOrEqual(2); // option + badge
    expect(screen.getByText('Rejected')).toBeInTheDocument();
  });

  it('search filters by originalText and generatedText', async () => {
    const entries = [
      makeEntry({ id: 'e1', originalText: 'hello world' }),
      makeEntry({ id: 'e2', originalText: 'goodbye moon' }),
    ];
    await renderAndWait(entries);

    await waitFor(() => {
      expect(screen.getByText('hello world')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByPlaceholderText('Search history...'), {
      target: { value: 'goodbye' },
    });

    await waitFor(() => {
      expect(screen.queryByText('hello world')).not.toBeInTheDocument();
    });
    expect(screen.getByText('goodbye moon')).toBeInTheDocument();
  });

  // ── Status/provider filtering ──

  it('status dropdown filters to succeeded-only', async () => {
    const entries = [
      makeEntry({ id: 'ok', succeeded: true, originalText: 'success text' }),
      makeEntry({ id: 'fail', succeeded: false, originalText: 'failure text' }),
    ];
    await renderAndWait(entries);

    await waitFor(() => {
      expect(screen.getByText('success text')).toBeInTheDocument();
    });

    const statusSelect = screen.getByDisplayValue('All Status');
    fireEvent.change(statusSelect, { target: { value: 'succeeded' } });

    await waitFor(() => {
      expect(screen.queryByText('failure text')).not.toBeInTheDocument();
    });
    expect(screen.getByText('success text')).toBeInTheDocument();
  });

  it('provider dropdown filters by provider name', async () => {
    const entries = [
      makeEntry({ id: 'e1', provider: 'claude', originalText: 'claude text' }),
      makeEntry({ id: 'e2', provider: 'local', originalText: 'local text' }),
    ];
    await renderAndWait(entries);

    await waitFor(() => {
      expect(screen.getByText('claude text')).toBeInTheDocument();
    });

    // Provider dropdown only shows when > 1 provider
    const providerSelect = screen.getByDisplayValue('All Providers');
    fireEvent.change(providerSelect, { target: { value: 'claude' } });

    await waitFor(() => {
      expect(screen.queryByText('local text')).not.toBeInTheDocument();
    });
    expect(screen.getByText('claude text')).toBeInTheDocument();
  });

  // ── Detail view ──

  it('"Select an entry" placeholder initially', async () => {
    await renderAndWait([makeEntry()]);
    await waitFor(() => {
      expect(screen.getByText('Select an entry to view details')).toBeInTheDocument();
    });
  });

  it('clicking entry shows original + corrected text', async () => {
    const entry = makeEntry({ originalText: 'teh world', generatedText: 'the world' });
    await renderAndWait([entry]);

    await waitFor(() => {
      expect(screen.getByText('teh world')).toBeInTheDocument();
    });

    // Click the entry button
    fireEvent.click(screen.getByText('teh world'));

    await waitFor(() => {
      // Detail pane should now show both texts
      expect(screen.getByText('the world')).toBeInTheDocument();
    });
  });

  it('"Show Diff" toggle renders DiffView', async () => {
    const entry = makeEntry({ originalText: 'teh', generatedText: 'the', succeeded: true });
    await renderAndWait([entry]);

    await waitFor(() => {
      expect(screen.getByText('teh')).toBeInTheDocument();
    });

    // Select entry
    fireEvent.click(screen.getByText('teh'));

    await waitFor(() => {
      expect(screen.getByText('Show Diff')).toBeInTheDocument();
    });

    // Toggle diff
    fireEvent.click(screen.getByText('Show Diff'));

    await waitFor(() => {
      expect(screen.getByText('Hide Diff')).toBeInTheDocument();
    });
  });

  // ── Actions ──

  it('"Clear All" calls clearHistory() and empties list', async () => {
    await renderAndWait([makeEntry({ originalText: 'some text' })]);

    await waitFor(() => {
      expect(screen.getByText('some text')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('Clear All'));

    await waitFor(() => {
      expect(window.ghostedit.clearHistory).toHaveBeenCalled();
    });
    expect(screen.getByText('No corrections yet')).toBeInTheDocument();
  });

  it('JSON export calls exportHistory("json")', async () => {
    await renderAndWait([makeEntry()]);
    fireEvent.click(screen.getByText('JSON'));
    await waitFor(() => {
      expect(window.ghostedit.exportHistory).toHaveBeenCalledWith('json');
    });
  });

  it('CSV export calls exportHistory("csv")', async () => {
    await renderAndWait([makeEntry()]);
    fireEvent.click(screen.getByText('CSV'));
    await waitFor(() => {
      expect(window.ghostedit.exportHistory).toHaveBeenCalledWith('csv');
    });
  });

  it('Copy button calls navigator.clipboard.writeText', async () => {
    const entry = makeEntry({ originalText: 'copy me', generatedText: 'copied text' });
    await renderAndWait([entry]);

    await waitFor(() => {
      expect(screen.getByText('copy me')).toBeInTheDocument();
    });

    // Select entry to show detail view
    fireEvent.click(screen.getByText('copy me'));

    await waitFor(() => {
      // Find and click the Copy button for original text
      const copyButtons = screen.getAllByText('Copy');
      expect(copyButtons.length).toBeGreaterThan(0);
      fireEvent.click(copyButtons[0]);
    });

    await waitFor(() => {
      expect(navigator.clipboard.writeText).toHaveBeenCalledWith('copy me');
    });
  });
});
