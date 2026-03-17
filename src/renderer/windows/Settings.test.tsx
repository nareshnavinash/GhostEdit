// @vitest-environment jsdom
import '../test-setup';
import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import Settings from './Settings';
import { DEFAULT_CONFIG } from '../../shared/constants';

// Mock HotkeyInput
vi.mock('../components/HotkeyInput', () => ({
  default: ({ value, onChange }: { value: string; onChange: (v: string) => void }) => (
    <input data-testid="hotkey-input" value={value} onChange={(e) => onChange(e.target.value)} />
  ),
}));

// Mock Welcome
vi.mock('../components/Welcome', () => ({
  default: ({ onComplete }: { onComplete: (u: any) => void }) => (
    <div data-testid="welcome">
      <button onClick={() => onComplete({ firstRunComplete: true })}>Complete</button>
    </div>
  ),
}));

beforeEach(() => {
  vi.clearAllMocks();
  // Default: first run complete so we see the main Settings UI
  window.ghostedit.getConfig = vi.fn().mockResolvedValue({
    ...DEFAULT_CONFIG,
    firstRunComplete: true,
  }) as any;
  window.ghostedit.getCLIStatus = vi.fn().mockResolvedValue({}) as any;
  window.ghostedit.getLocalModelStatus = vi.fn().mockResolvedValue({
    ready: false,
    activeVariant: 'fp32',
    variants: [],
  }) as any;
  window.ghostedit.getInferenceDevice = vi.fn().mockResolvedValue(null) as any;
  window.ghostedit.saveConfig = vi.fn().mockResolvedValue({ success: true }) as any;
  window.ghostedit.onDownloadVariantProgress = vi.fn().mockReturnValue(() => {}) as any;
});

describe('Settings component', () => {
  it('renders Welcome when firstRunComplete=false', async () => {
    window.ghostedit.getConfig = vi.fn().mockResolvedValue({
      ...DEFAULT_CONFIG,
      firstRunComplete: false,
    }) as any;

    render(<Settings />);
    // Default state has firstRunComplete=false from DEFAULT_CONFIG
    expect(screen.getByTestId('welcome')).toBeInTheDocument();
  });

  it('renders tabs when firstRunComplete=true', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('general')).toBeInTheDocument();
    });
    expect(screen.getByText('hotkey')).toBeInTheDocument();
    expect(screen.getByText('behavior')).toBeInTheDocument();
  });

  it('general tab shows both hotkey labels Local: and CLI:', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText(/^Local:/)).toBeInTheDocument();
    });
    expect(screen.getByText(/^CLI:/)).toBeInTheDocument();
  });

  it('hotkey tab shows two HotkeyInput components', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('hotkey')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('hotkey'));

    await waitFor(() => {
      const inputs = screen.getAllByTestId('hotkey-input');
      expect(inputs).toHaveLength(2);
    });
  });

  it('CLI provider selector has 3 CLI providers', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('CLI Provider')).toBeInTheDocument();
    });

    // The Provider select inside the CLI Provider section has 3 options (claude, codex, gemini)
    const cliSection = screen.getByText('CLI Provider').closest('div.rounded-lg');
    const select = cliSection?.querySelector('select');
    expect(select).toBeDefined();
    const options = select!.querySelectorAll('option');
    expect(options).toHaveLength(3);
  });

  it('behavior tab always shows fast-correction toggle', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('behavior')).toBeInTheDocument();
    });

    fireEvent.click(screen.getByText('behavior'));

    await waitFor(() => {
      expect(screen.getByText('Fast correction mode')).toBeInTheDocument();
    });
  });

  it('save indicator appears briefly after change', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('Language')).toBeInTheDocument();
    });

    // Change language to trigger save
    const languageSelect = screen.getByText('Language').closest('div')?.querySelector('select');
    if (languageSelect) {
      fireEvent.change(languageSelect, { target: { value: 'es' } });
    }

    await waitFor(() => {
      expect(screen.getByText('Settings saved')).toBeInTheDocument();
    });
  });

  it('local Model Info panel always shows', async () => {
    window.ghostedit.getLocalModelStatus = vi.fn().mockResolvedValue({
      ready: true,
      activeVariant: 'fp32',
      variants: [
        { variant: 'fp32', displayName: 'FP32 (Best)', sizeMB: 963, available: true, bundled: true },
      ],
    }) as any;

    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('Local Model')).toBeInTheDocument();
    });
    expect(screen.getByText(/T5 Grammar Correction/)).toBeInTheDocument();
  });
});
