import React from 'react';
import type { DiffSegment } from '../../shared/types';

interface DiffViewProps {
  segments: DiffSegment[];
  side: 'original' | 'corrected';
}

/**
 * Renders a diff with color-coded insertions and deletions.
 * - Original side: shows equal + deletions (red strikethrough)
 * - Corrected side: shows equal + insertions (green underline)
 */
const DiffView = React.memo(function DiffView({ segments, side }: DiffViewProps) {
  return (
    <div className="text-sm whitespace-pre-wrap leading-relaxed font-mono">
      {segments.map((seg, i) => {
        if (seg.kind === 'equal') {
          return <span key={i}>{seg.text}</span>;
        }
        if (seg.kind === 'deletion' && side === 'original') {
          return (
            <span
              key={i}
              className="bg-red-500/20 text-red-300 line-through decoration-red-400"
            >
              {seg.text}
            </span>
          );
        }
        if (seg.kind === 'insertion' && side === 'corrected') {
          return (
            <span
              key={i}
              className="bg-green-500/20 text-green-300 underline decoration-green-400"
            >
              {seg.text}
            </span>
          );
        }
        // Don't show insertions on original side, or deletions on corrected side
        return null;
      })}
    </div>
  );
});

export default DiffView;
