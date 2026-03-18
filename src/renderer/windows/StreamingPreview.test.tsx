// @vitest-environment jsdom
import '../test-setup';
import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, act, fireEvent, waitFor } from '@testing-library/react';
import StreamingPreview from './StreamingPreview';

// ── Capture IPC callbacks ──

let onOriginalCb: (text: string) => void;
let onDoneCb: (text: string) => void;
let onConfigCb: (cfg: any) => void;

// Mock diff-match-patch — must be a constructor (used with `new`)
vi.mock('diff-match-patch', () => {
  return {
    default: function DiffMatchPatch(this: any) {
      this.diff_main = (a: string, b: string) => {
        if (a && b && a !== b) return [[-1, a], [1, b]];
        if (a === b) return [[0, a]];
        return [[0, a || b]];
      };
      this.diff_cleanupSemantic = () => {};
    },
  };
});

beforeEach(() => {
  vi.clearAllMocks();

  window.ghostedit.onSetPreviewOriginal = vi.fn((cb) => {
    onOriginalCb = cb;
    return () => {};
  }) as any;
  window.ghostedit.onStreamingDone = vi.fn((cb) => {
    onDoneCb = cb;
    return () => {};
  }) as any;
  window.ghostedit.onSetPreviewConfig = vi.fn((cb) => {
    onConfigCb = cb;
    return () => {};
  }) as any;
  window.ghostedit.acceptCorrection = vi.fn().mockResolvedValue(undefined) as any;
  window.ghostedit.rejectCorrection = vi.fn().mockResolvedValue(undefined) as any;
  window.close = vi.fn();
});

describe('StreamingPreview', () => {
  // ── Initial state ──

  it('shows "Waiting..." when no corrected text received', () => {
    render(<StreamingPreview />);
    expect(screen.getByText('Waiting...')).toBeInTheDocument();
  });

  it('shows loading spinner before corrected text arrives', () => {
    const { container } = render(<StreamingPreview />);
    expect(container.querySelector('.animate-spin')).toBeInTheDocument();
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });

  // ── IPC data flow ──

  it('onSetPreviewOriginal fires → original text visible', () => {
    render(<StreamingPreview />);
    act(() => onOriginalCb('Hello wrold'));
    expect(screen.getByText('Hello wrold')).toBeInTheDocument();
  });

  it('onStreamingDone fires → corrected text visible, spinner gone', () => {
    const { container } = render(<StreamingPreview />);
    act(() => onDoneCb('Hello world'));
    // Spinner should be gone when corrected text arrives
    expect(container.querySelector('.animate-spin')).not.toBeInTheDocument();
  });

  it('both fire → diff segments rendered', () => {
    render(<StreamingPreview />);
    act(() => onOriginalCb('Hello wrold'));
    act(() => onDoneCb('Hello world'));
    // Diff segments are rendered — "Original" and "Corrected" headings should be present
    expect(screen.getByText('Original')).toBeInTheDocument();
    expect(screen.getByText('Corrected')).toBeInTheDocument();
  });

  // ── Interactive mode ──

  it('Accept/Reject buttons visible when corrected text arrives in interactive mode', () => {
    render(<StreamingPreview />);
    act(() => {
      onConfigCb({ autoPasteDelaySeconds: 0, diffPreviewMode: 'interactive', passivePreviewSeconds: 0 });
    });
    act(() => onDoneCb('corrected text'));
    expect(screen.getByText('Accept')).toBeInTheDocument();
    expect(screen.getByText('Reject')).toBeInTheDocument();
  });

  it('Accept calls acceptCorrection + window.close', async () => {
    render(<StreamingPreview />);
    act(() => {
      onConfigCb({ autoPasteDelaySeconds: 0, diffPreviewMode: 'interactive', passivePreviewSeconds: 0 });
    });
    act(() => onDoneCb('corrected text'));

    await act(async () => {
      fireEvent.click(screen.getByText('Accept'));
    });

    expect(window.ghostedit.acceptCorrection).toHaveBeenCalledWith('corrected text');
    expect(window.close).toHaveBeenCalled();
  });

  it('Reject calls rejectCorrection + window.close', async () => {
    render(<StreamingPreview />);
    act(() => {
      onConfigCb({ autoPasteDelaySeconds: 0, diffPreviewMode: 'interactive', passivePreviewSeconds: 0 });
    });
    act(() => onDoneCb('corrected text'));

    await act(async () => {
      fireEvent.click(screen.getByText('Reject'));
    });

    expect(window.ghostedit.rejectCorrection).toHaveBeenCalled();
    expect(window.close).toHaveBeenCalled();
  });

  it('Enter key triggers accept in interactive mode', async () => {
    render(<StreamingPreview />);
    act(() => {
      onConfigCb({ autoPasteDelaySeconds: 0, diffPreviewMode: 'interactive', passivePreviewSeconds: 0 });
    });
    act(() => onDoneCb('corrected text'));

    await act(async () => {
      fireEvent.keyDown(window, { key: 'Enter' });
    });

    expect(window.ghostedit.acceptCorrection).toHaveBeenCalledWith('corrected text');
  });

  it('Escape key triggers reject in interactive mode', async () => {
    render(<StreamingPreview />);
    act(() => {
      onConfigCb({ autoPasteDelaySeconds: 0, diffPreviewMode: 'interactive', passivePreviewSeconds: 0 });
    });
    act(() => onDoneCb('corrected text'));

    await act(async () => {
      fireEvent.keyDown(window, { key: 'Escape' });
    });

    expect(window.ghostedit.rejectCorrection).toHaveBeenCalled();
  });

  // ── Passive mode ──

  it('no Accept/Reject buttons in passive mode', () => {
    render(<StreamingPreview />);
    act(() => {
      onConfigCb({ autoPasteDelaySeconds: 0, diffPreviewMode: 'passive', passivePreviewSeconds: 5 });
    });
    act(() => onDoneCb('corrected text'));
    expect(screen.queryByText('Accept')).not.toBeInTheDocument();
    expect(screen.queryByText('Reject')).not.toBeInTheDocument();
  });

  it('title shows "Correction Applied" in passive mode', () => {
    render(<StreamingPreview />);
    act(() => {
      onConfigCb({ autoPasteDelaySeconds: 0, diffPreviewMode: 'passive', passivePreviewSeconds: 5 });
    });
    expect(screen.getByText('Correction Applied')).toBeInTheDocument();
  });

  it('shows "Closing in Xs" text in passive mode with countdown', () => {
    render(<StreamingPreview />);
    act(() => {
      onConfigCb({ autoPasteDelaySeconds: 0, diffPreviewMode: 'passive', passivePreviewSeconds: 5 });
    });
    expect(screen.getByText('Closing in 5s')).toBeInTheDocument();
  });
});
