import React, { useState, useCallback } from 'react';
import type { DiffSegment } from '../../shared/types';

interface DiffViewProps {
  segments: DiffSegment[];
  side: 'original' | 'corrected';
}

/**
 * Renders a diff with color-coded insertions and deletions.
 * - Original side: shows equal + deletions (red strikethrough)
 * - Corrected side: shows equal + insertions (green underline) with "Why?" tooltip
 */
const DiffView = React.memo(function DiffView({ segments, side }: DiffViewProps) {
  const [activeTooltip, setActiveTooltip] = useState<number | null>(null);
  const [tooltipText, setTooltipText] = useState<string>('');
  const [loading, setLoading] = useState(false);

  const handleWhyClick = useCallback(async (index: number, seg: DiffSegment) => {
    if (activeTooltip === index) {
      setActiveTooltip(null);
      return;
    }

    setActiveTooltip(index);
    setLoading(true);
    setTooltipText('');

    // Find the adjacent deletion to pair with this insertion
    const prevSeg = index > 0 ? segments[index - 1] : null;
    const originalText = prevSeg?.kind === 'deletion' ? prevSeg.text : '';

    try {
      const result = await window.ghostedit.explainDiff(originalText, seg.text);
      if (result.success && result.explanation) {
        setTooltipText(result.explanation);
      } else {
        setTooltipText('Spelling or grammar correction');
      }
    } catch {
      setTooltipText('Spelling or grammar correction');
    } finally {
      setLoading(false);
    }
  }, [activeTooltip, segments]);

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
            <span key={i} className="relative inline">
              <span
                className="bg-green-500/20 text-green-300 underline decoration-green-400 cursor-pointer"
                onClick={() => handleWhyClick(i, seg)}
                title="Click to see why this was changed"
              >
                {seg.text}
              </span>
              {activeTooltip === i && (
                <span className="absolute left-0 top-full mt-1 z-10 px-2 py-1 rounded bg-white/10 backdrop-blur-sm border border-white/20 text-[11px] text-white/80 whitespace-nowrap max-w-[250px] whitespace-normal">
                  {loading ? 'Analyzing...' : tooltipText}
                </span>
              )}
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
