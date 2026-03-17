// @vitest-environment jsdom
import '../test-setup';
import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
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

function mockPlatform(platform: string) {
  (window.ghostedit as any).platform = platform;
}

/** Wait for the settings UI to load by checking for the sidebar nav */
async function waitForSettingsLoaded() {
  await waitFor(() => {
    expect(screen.getByRole('navigation')).toBeInTheDocument();
  });
}

/** Get the sidebar nav element */
function getSidebar() {
  return screen.getByRole('navigation');
}

beforeEach(() => {
  vi.clearAllMocks();
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
  (window.ghostedit as any).platform = 'darwin';
  (window.ghostedit as any).windowControls = { close: vi.fn(), minimize: vi.fn() };
});

describe('Settings component', () => {
  it('renders Welcome when firstRunComplete=false', async () => {
    window.ghostedit.getConfig = vi.fn().mockResolvedValue({
      ...DEFAULT_CONFIG,
      firstRunComplete: false,
    }) as any;

    render(<Settings />);
    expect(screen.getByTestId('welcome')).toBeInTheDocument();
  });

  // ── Sidebar Navigation ──

  it('renders all 5 sidebar section buttons', async () => {
    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    expect(within(nav).getByText('General')).toBeInTheDocument();
    expect(within(nav).getByText('Models')).toBeInTheDocument();
    expect(within(nav).getByText('Providers')).toBeInTheDocument();
    expect(within(nav).getByText('Hotkeys')).toBeInTheDocument();
    expect(within(nav).getByText('Behavior')).toBeInTheDocument();
  });

  it('General section is active by default', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('Language')).toBeInTheDocument();
    });
    expect(screen.getByText('Tone Preset')).toBeInTheDocument();
    expect(screen.getByText('Timeout')).toBeInTheDocument();
  });

  it('clicking a sidebar item switches the content area', async () => {
    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    fireEvent.click(within(nav).getByText('Behavior'));

    await waitFor(() => {
      expect(screen.getByText('Fast correction mode')).toBeInTheDocument();
    });
  });

  it('active sidebar item has highlighted styling', async () => {
    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    const generalBtn = within(nav).getByText('General').closest('button');
    expect(generalBtn?.className).toContain('bg-white/10');
  });

  // ── General Section ──

  it('shows Language select with language options', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('Language')).toBeInTheDocument();
    });

    const languageRow = screen.getByText('Language').closest('.settings-row');
    const select = languageRow?.querySelector('select');
    expect(select).toBeTruthy();
  });

  it('shows Tone Preset select with 5 options', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('Tone Preset')).toBeInTheDocument();
    });

    const toneRow = screen.getByText('Tone Preset').closest('.settings-row');
    const select = toneRow?.querySelector('select');
    expect(select).toBeTruthy();
    const options = select!.querySelectorAll('option');
    expect(options).toHaveLength(5);
  });

  it('changing language calls saveConfig', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('Language')).toBeInTheDocument();
    });

    const languageRow = screen.getByText('Language').closest('.settings-row');
    const select = languageRow?.querySelector('select');
    if (select) {
      fireEvent.change(select, { target: { value: 'es' } });
    }

    await waitFor(() => {
      expect(window.ghostedit.saveConfig).toHaveBeenCalled();
    });
  });

  // ── Models Section ──

  it('Models section shows variant info', async () => {
    window.ghostedit.getLocalModelStatus = vi.fn().mockResolvedValue({
      ready: true,
      activeVariant: 'fp32',
      variants: [
        { variant: 'fp32', displayName: 'FP32 (Best)', sizeMB: 963, available: true, bundled: true },
      ],
    }) as any;

    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    fireEvent.click(within(nav).getByText('Models'));

    await waitFor(() => {
      expect(screen.getByText('Active Variant')).toBeInTheDocument();
    });
    expect(screen.getByText('Bundled')).toBeInTheDocument();
  });

  it('Models section shows Download button for unavailable variants', async () => {
    window.ghostedit.getLocalModelStatus = vi.fn().mockResolvedValue({
      ready: true,
      activeVariant: 'fp32',
      variants: [
        { variant: 'fp32', displayName: 'FP32 (Best)', sizeMB: 963, available: true, bundled: true },
        { variant: 'fp16', displayName: 'FP16 (Fast)', sizeMB: 482, available: false, bundled: false },
      ],
    }) as any;

    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    fireEvent.click(within(nav).getByText('Models'));

    await waitFor(() => {
      expect(screen.getByText('Download')).toBeInTheDocument();
    });
  });

  // ── Providers Section ──

  it('Providers section shows CLI provider selector with 3 providers', async () => {
    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    fireEvent.click(within(nav).getByText('Providers'));

    await waitFor(() => {
      // "Provider" appears as row label in the content area
      expect(screen.getByText('Provider')).toBeInTheDocument();
    });

    const providerRow = screen.getByText('Provider').closest('.settings-row');
    const select = providerRow?.querySelector('select');
    expect(select).toBeTruthy();
    const options = select!.querySelectorAll('option');
    expect(options).toHaveLength(3);
  });

  // ── Hotkeys Section ──

  it('Hotkeys section shows two HotkeyInput components', async () => {
    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    fireEvent.click(within(nav).getByText('Hotkeys'));

    await waitFor(() => {
      const inputs = screen.getAllByTestId('hotkey-input');
      expect(inputs).toHaveLength(2);
    });
  });

  // ── Behavior Section ──

  it('Behavior section shows fast-correction toggle', async () => {
    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    fireEvent.click(within(nav).getByText('Behavior'));

    await waitFor(() => {
      expect(screen.getByText('Fast correction mode')).toBeInTheDocument();
    });
  });

  it('Behavior section shows all 6 toggles', async () => {
    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    fireEvent.click(within(nav).getByText('Behavior'));

    await waitFor(() => {
      expect(screen.getByText('Fast correction mode')).toBeInTheDocument();
    });
    expect(screen.getByText('Clipboard-only mode')).toBeInTheDocument();
    expect(screen.getByText('Show diff preview')).toBeInTheDocument();
    expect(screen.getByText('Sound feedback')).toBeInTheDocument();
    expect(screen.getByText('Notify on success')).toBeInTheDocument();
    expect(screen.getByText('Developer mode')).toBeInTheDocument();
  });

  it('Behavior section shows History limit input', async () => {
    render(<Settings />);
    await waitForSettingsLoaded();

    const nav = getSidebar();
    fireEvent.click(within(nav).getByText('Behavior'));

    await waitFor(() => {
      expect(screen.getByText('History limit')).toBeInTheDocument();
    });
  });

  // ── Save Feedback ──

  it('floating toast appears after config change', async () => {
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('Language')).toBeInTheDocument();
    });

    const languageRow = screen.getByText('Language').closest('.settings-row');
    const select = languageRow?.querySelector('select');
    if (select) {
      fireEvent.change(select, { target: { value: 'es' } });
    }

    await waitFor(() => {
      expect(screen.getByText('Settings saved')).toBeInTheDocument();
    });
  });

  // ── Cross-Platform Title Bar ──

  it('macOS: no window control buttons rendered', async () => {
    mockPlatform('darwin');
    render(<Settings />);
    await waitForSettingsLoaded();

    expect(screen.queryByLabelText('Close')).not.toBeInTheDocument();
    expect(screen.queryByLabelText('Minimize')).not.toBeInTheDocument();
  });

  it('non-macOS: renders close and minimize buttons', async () => {
    mockPlatform('win32');
    render(<Settings />);
    await waitForSettingsLoaded();

    expect(screen.getByLabelText('Close')).toBeInTheDocument();
    expect(screen.getByLabelText('Minimize')).toBeInTheDocument();
  });

  it('non-macOS: title text is visible', async () => {
    mockPlatform('win32');
    render(<Settings />);

    await waitFor(() => {
      expect(screen.getByText('GhostEdit Settings')).toBeInTheDocument();
    });
  });

  it('non-macOS: close button calls windowControls.close()', async () => {
    mockPlatform('win32');
    render(<Settings />);
    await waitForSettingsLoaded();

    fireEvent.click(screen.getByLabelText('Close'));
    expect(window.ghostedit.windowControls.close).toHaveBeenCalled();
  });

  it('non-macOS: minimize button calls windowControls.minimize()', async () => {
    mockPlatform('win32');
    render(<Settings />);
    await waitForSettingsLoaded();

    fireEvent.click(screen.getByLabelText('Minimize'));
    expect(window.ghostedit.windowControls.minimize).toHaveBeenCalled();
  });
});
