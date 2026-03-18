// @vitest-environment jsdom
import '../test-setup';
import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, act } from '@testing-library/react';
import HudOverlay from './HudOverlay';

let hudShowCb: (msg: string) => void;
let hudHideCb: () => void;

beforeEach(() => {
  vi.clearAllMocks();
  window.ghostedit.onHudShow = vi.fn((cb) => {
    hudShowCb = cb;
    return () => {};
  }) as any;
  window.ghostedit.onHudHide = vi.fn((cb) => {
    hudHideCb = cb;
    return () => {};
  }) as any;
});

describe('HudOverlay', () => {
  // ── Visibility ──

  it('starts with opacity-0', () => {
    const { container } = render(<HudOverlay />);
    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper.className).toContain('opacity-0');
  });

  it('becomes opacity-100 after onHudShow fires', () => {
    const { container } = render(<HudOverlay />);
    act(() => hudShowCb('Working...'));
    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper.className).toContain('opacity-100');
  });

  it('returns to opacity-0 after onHudHide fires', () => {
    const { container } = render(<HudOverlay />);
    act(() => hudShowCb('Working...'));
    act(() => hudHideCb());
    const wrapper = container.firstChild as HTMLElement;
    expect(wrapper.className).toContain('opacity-0');
  });

  // ── Message display ──

  it('displays the text from onHudShow', () => {
    render(<HudOverlay />);
    act(() => hudShowCb('Processing text...'));
    expect(screen.getByText('Processing text...')).toBeInTheDocument();
  });

  // ── Styling variants ──

  it('applies error styling for messages starting with "Error"', () => {
    const { container } = render(<HudOverlay />);
    act(() => hudShowCb('Error: API key missing'));
    // The badge div with bg-* is the parent of the flex container
    const badge = container.querySelector('[class*="bg-red-900"]');
    expect(badge).toBeInTheDocument();
  });

  it('applies success styling for "Done!"', () => {
    const { container } = render(<HudOverlay />);
    act(() => hudShowCb('Done!'));
    const badge = container.querySelector('[class*="bg-green-900"]');
    expect(badge).toBeInTheDocument();
  });

  it('applies success styling for messages containing "clipboard"', () => {
    const { container } = render(<HudOverlay />);
    act(() => hudShowCb('Copied to clipboard'));
    const badge = container.querySelector('[class*="bg-green-900"]');
    expect(badge).toBeInTheDocument();
  });

  // ── Spinner ──

  it('shows spinner for working state (not error, not done)', () => {
    const { container } = render(<HudOverlay />);
    act(() => hudShowCb('Working...'));
    expect(container.querySelector('.animate-spin')).toBeInTheDocument();
  });

  it('does not show spinner for error state', () => {
    const { container } = render(<HudOverlay />);
    act(() => hudShowCb('Error: failed'));
    expect(container.querySelector('.animate-spin')).not.toBeInTheDocument();
  });

  it('does not show spinner for done state', () => {
    const { container } = render(<HudOverlay />);
    act(() => hudShowCb('Done!'));
    expect(container.querySelector('.animate-spin')).not.toBeInTheDocument();
  });
});
