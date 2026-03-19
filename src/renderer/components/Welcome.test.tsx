// @vitest-environment jsdom
import '../test-setup';
import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import Welcome from './Welcome';
import { DEFAULT_CONFIG } from '../../shared/constants';

const defaultProps = {
  config: { ...DEFAULT_CONFIG },
  onComplete: vi.fn(),
};

describe('Welcome component', () => {
  it('step 0 renders menu bar description', () => {
    render(<Welcome {...defaultProps} />);
    expect(screen.getByText(/lives in your menu bar/i)).toBeInTheDocument();
  });

  it('step 1 shows both hotkeys with Local Model and CLI Provider labels', () => {
    render(<Welcome {...defaultProps} />);
    // Navigate to step 1
    fireEvent.click(screen.getByText('Next'));

    expect(screen.getByText('Local Model')).toBeInTheDocument();
    expect(screen.getByText('CLI Provider')).toBeInTheDocument();
  });

  it('step 2 shows all 4 provider buttons', () => {
    render(<Welcome {...defaultProps} />);
    // Navigate to step 2
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Next'));

    expect(screen.getByText('Claude')).toBeInTheDocument();
    expect(screen.getByText('Codex')).toBeInTheDocument();
    expect(screen.getByText('Gemini')).toBeInTheDocument();
    expect(screen.getByText('Built-in (Offline)')).toBeInTheDocument();
  });

  it('step 3 shows "Try it now" with sample text and Fix it button', () => {
    render(<Welcome {...defaultProps} />);
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Next'));

    expect(screen.getByText(/Try it now/i)).toBeInTheDocument();
    expect(screen.getByText('Fix it')).toBeInTheDocument();
    expect(screen.getByDisplayValue(/tset of GhostEdit/)).toBeInTheDocument();
  });

  it('completing onboarding with local calls onComplete with firstRunComplete only', () => {
    const onComplete = vi.fn();
    render(<Welcome {...defaultProps} onComplete={onComplete} />);

    // Navigate to last step (step 3)
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Next'));
    // Default is local; click Get Started
    fireEvent.click(screen.getByText('Get Started'));

    expect(onComplete).toHaveBeenCalledWith({ firstRunComplete: true });
  });

  it('completing onboarding with CLI provider sets cliProvider and cliModel', () => {
    const onComplete = vi.fn();
    render(<Welcome {...defaultProps} onComplete={onComplete} />);

    // Navigate to provider selection step
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Next'));
    // Select Claude
    fireEvent.click(screen.getByText('Claude'));
    // Navigate to "Try it now" step
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Get Started'));

    expect(onComplete).toHaveBeenCalledWith(
      expect.objectContaining({
        firstRunComplete: true,
        cliProvider: 'claude',
        cliModel: 'sonnet',
      }),
    );
  });

  it('provider selection highlights the selected button', () => {
    render(<Welcome {...defaultProps} />);
    // Navigate to step 2 (provider selection)
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Next'));

    // Click Claude
    fireEvent.click(screen.getByText('Claude'));
    // The button should have highlighted styling (bg-blue-500/20)
    const claudeButton = screen.getByText('Claude').closest('button');
    expect(claudeButton?.className).toContain('bg-blue-500/20');
  });

  it('back button disabled on step 0', () => {
    render(<Welcome {...defaultProps} />);
    const backButton = screen.getByText('Back');
    expect(backButton).toBeDisabled();
  });

  it('back button works on step 1', () => {
    render(<Welcome {...defaultProps} />);
    fireEvent.click(screen.getByText('Next'));
    expect(screen.getByText(/press your hotkey/i)).toBeInTheDocument();

    fireEvent.click(screen.getByText('Back'));
    expect(screen.getByText(/lives in your menu bar/i)).toBeInTheDocument();
  });

  it('last step button says Get Started', () => {
    render(<Welcome {...defaultProps} />);
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Next'));

    expect(screen.getByText('Get Started')).toBeInTheDocument();
  });
});
