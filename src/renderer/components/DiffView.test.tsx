// @vitest-environment jsdom
import '../test-setup';
import React from 'react';
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import DiffView from './DiffView';
import type { DiffSegment } from '../../shared/types';

describe('DiffView', () => {
  // ── Equal segments ──

  it('renders equal segments on the original side', () => {
    const segments: DiffSegment[] = [{ kind: 'equal', text: 'hello world' }];
    render(<DiffView segments={segments} side="original" />);
    expect(screen.getByText('hello world')).toBeInTheDocument();
  });

  it('renders equal segments on the corrected side', () => {
    const segments: DiffSegment[] = [{ kind: 'equal', text: 'hello world' }];
    render(<DiffView segments={segments} side="corrected" />);
    expect(screen.getByText('hello world')).toBeInTheDocument();
  });

  // ── Original side ──

  it('shows deletions with line-through on original side', () => {
    const segments: DiffSegment[] = [{ kind: 'deletion', text: 'removed' }];
    render(<DiffView segments={segments} side="original" />);
    const el = screen.getByText('removed');
    expect(el.className).toContain('line-through');
    expect(el.className).toContain('bg-red-500/20');
  });

  it('hides insertions on original side', () => {
    const segments: DiffSegment[] = [{ kind: 'insertion', text: 'added' }];
    render(<DiffView segments={segments} side="original" />);
    expect(screen.queryByText('added')).not.toBeInTheDocument();
  });

  // ── Corrected side ──

  it('shows insertions with underline on corrected side', () => {
    const segments: DiffSegment[] = [{ kind: 'insertion', text: 'added' }];
    render(<DiffView segments={segments} side="corrected" />);
    const el = screen.getByText('added');
    expect(el.className).toContain('underline');
    expect(el.className).toContain('bg-green-500/20');
  });

  it('hides deletions on corrected side', () => {
    const segments: DiffSegment[] = [{ kind: 'deletion', text: 'removed' }];
    render(<DiffView segments={segments} side="corrected" />);
    expect(screen.queryByText('removed')).not.toBeInTheDocument();
  });

  // ── Mixed segments ──

  it('original side shows equal + deletions only', () => {
    const segments: DiffSegment[] = [
      { kind: 'equal', text: 'hello ' },
      { kind: 'deletion', text: 'old' },
      { kind: 'insertion', text: 'new' },
      { kind: 'equal', text: ' world' },
    ];
    render(<DiffView segments={segments} side="original" />);
    expect(screen.getByText('hello')).toBeInTheDocument();
    expect(screen.getByText('old')).toBeInTheDocument();
    expect(screen.queryByText('new')).not.toBeInTheDocument();
    expect(screen.getByText('world')).toBeInTheDocument();
  });

  it('corrected side shows equal + insertions only', () => {
    const segments: DiffSegment[] = [
      { kind: 'equal', text: 'hello ' },
      { kind: 'deletion', text: 'old' },
      { kind: 'insertion', text: 'new' },
      { kind: 'equal', text: ' world' },
    ];
    render(<DiffView segments={segments} side="corrected" />);
    expect(screen.getByText('hello')).toBeInTheDocument();
    expect(screen.queryByText('old')).not.toBeInTheDocument();
    expect(screen.getByText('new')).toBeInTheDocument();
    expect(screen.getByText('world')).toBeInTheDocument();
  });

  // ── Edge cases ──

  it('renders without crash when segments array is empty', () => {
    const { container } = render(<DiffView segments={[]} side="original" />);
    expect(container.firstChild).toBeInTheDocument();
  });
});
