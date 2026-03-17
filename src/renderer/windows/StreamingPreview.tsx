import React, { useEffect, useState, useMemo } from 'react';
import DiffMatchPatch from 'diff-match-patch';
import DiffView from '../components/DiffView';
import type { DiffSegment } from '../../shared/types';

/**
 * Read-only diff overlay that auto-dismisses after 5 seconds.
 * Shows original vs corrected text side-by-side.
 * The corrected text has already been pasted — this is informational only.
 */

const dmp = new DiffMatchPatch();

function computeDiff(original: string, corrected: string): DiffSegment[] {
  const diffs = dmp.diff_main(original, corrected);
  dmp.diff_cleanupSemantic(diffs);

  return diffs.map(([op, text]: [number, string]) => ({
    kind: op === 0 ? 'equal' : op === -1 ? 'deletion' : 'insertion',
    text,
  })) as DiffSegment[];
}

export default function StreamingPreview() {
  const [original, setOriginal] = useState('');
  const [corrected, setCorrected] = useState('');
  const [countdown, setCountdown] = useState(5);

  useEffect(() => {
    const offOriginal = window.ghostedit.onSetPreviewOriginal((text) => {
      setOriginal(text);
    });

    const offDone = window.ghostedit.onStreamingDone((text) => {
      setCorrected(text);
    });

    return () => {
      offOriginal();
      offDone();
    };
  }, []);

  // Countdown timer — auto-close after 5 seconds
  useEffect(() => {
    if (!corrected) return;

    const interval = setInterval(() => {
      setCountdown((prev) => {
        if (prev <= 1) {
          clearInterval(interval);
          window.close();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => clearInterval(interval);
  }, [corrected]);

  // Esc to dismiss early, click anywhere to dismiss
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') window.close();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);

  const segments = useMemo(
    () => (original && corrected ? computeDiff(original, corrected) : []),
    [original, corrected],
  );

  const additions = segments.filter((s) => s.kind === 'insertion').length;
  const deletions = segments.filter((s) => s.kind === 'deletion').length;

  return (
    <div
      className="flex flex-col h-screen backdrop-blur-2xl bg-black/65 border border-white/[0.08] rounded-xl overflow-hidden text-white/90"
      onClick={() => window.close()}
    >
      {/* Title bar */}
      <div className="h-10 flex items-center justify-between px-4 border-b border-white/[0.08] shrink-0">
        <span className="text-sm font-medium text-white/70">
          Correction Applied
        </span>
        <div className="flex items-center gap-3 text-xs text-white/40">
          <span>Closing in {countdown}s</span>
          <span>Esc to dismiss</span>
        </div>
      </div>

      {/* Status bar */}
      <div className="flex items-center gap-3 px-4 py-2 text-xs text-white/40 border-b border-white/[0.08] shrink-0">
        {corrected ? (
          <span>
            {additions} addition{additions !== 1 ? 's' : ''}, {deletions} deletion
            {deletions !== 1 ? 's' : ''}
          </span>
        ) : (
          <div className="flex items-center gap-2">
            <span className="inline-block w-3 h-3 border-2 border-blue-400/40 border-t-blue-400 rounded-full animate-spin" />
            <span>Loading...</span>
          </div>
        )}
      </div>

      {/* Side-by-side diff */}
      <div className="flex flex-1 overflow-hidden">
        <div className="w-1/2 overflow-y-auto p-4 border-r border-white/[0.08]">
          <h3 className="text-xs font-medium text-white/40 uppercase mb-2">Original</h3>
          {segments.length > 0 ? (
            <DiffView segments={segments} side="original" />
          ) : (
            <p className="text-sm text-white/40 whitespace-pre-wrap">{original}</p>
          )}
        </div>
        <div className="w-1/2 overflow-y-auto p-4">
          <h3 className="text-xs font-medium text-white/40 uppercase mb-2">Corrected</h3>
          {segments.length > 0 ? (
            <DiffView segments={segments} side="corrected" />
          ) : (
            <p className="text-sm text-white/40 whitespace-pre-wrap">
              {corrected || 'Waiting...'}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
