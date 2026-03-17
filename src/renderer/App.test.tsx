// @vitest-environment jsdom
import './test-setup';
import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import App from './App';

// Mock the window components to keep tests isolated
vi.mock('./windows/Settings', () => ({
  default: () => <div data-testid="settings">Settings</div>,
}));
vi.mock('./windows/History', () => ({
  default: () => <div data-testid="history">History</div>,
}));
vi.mock('./windows/HudOverlay', () => ({
  default: () => <div data-testid="hud">HudOverlay</div>,
}));
vi.mock('./windows/StreamingPreview', () => ({
  default: () => <div data-testid="streaming-preview">StreamingPreview</div>,
}));

beforeEach(() => {
  vi.clearAllMocks();
});

describe('App', () => {
  it('renders Settings for windowType=settings', () => {
    window.ghostedit.getWindowType = vi.fn().mockReturnValue('settings') as any;
    render(<App />);
    expect(screen.getByTestId('settings')).toBeInTheDocument();
  });

  it('renders History for windowType=history', () => {
    window.ghostedit.getWindowType = vi.fn().mockReturnValue('history') as any;
    render(<App />);
    expect(screen.getByTestId('history')).toBeInTheDocument();
  });

  it('renders HudOverlay for windowType=hud', () => {
    window.ghostedit.getWindowType = vi.fn().mockReturnValue('hud') as any;
    render(<App />);
    expect(screen.getByTestId('hud')).toBeInTheDocument();
  });

  it('renders StreamingPreview for windowType=streaming-preview', () => {
    window.ghostedit.getWindowType = vi.fn().mockReturnValue('streaming-preview') as any;
    render(<App />);
    expect(screen.getByTestId('streaming-preview')).toBeInTheDocument();
  });

  it('defaults to Settings for unknown windowType', () => {
    window.ghostedit.getWindowType = vi.fn().mockReturnValue('unknown-type') as any;
    render(<App />);
    expect(screen.getByTestId('settings')).toBeInTheDocument();
  });
});
