import React, { useEffect, useState, useMemo } from 'react';
import DiffMatchPatch from 'diff-match-patch';
import DiffView from '../components/DiffView';
import type { DiffSegment, DiffPreviewMode } from '../../shared/types';

/**
 * Interactive diff preview overlay.
 * Shows original vs corrected text side-by-side with Accept/Reject buttons.
 * User must explicitly accept to paste, or reject/close to cancel.
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
  const [autoPasteDelay, setAutoPasteDelay] = useState(0);
  const [countdown, setCountdown] = useState<number | null>(null);
  const [previewMode, setPreviewMode] = useState<DiffPreviewMode>('interactive');
  const [passiveCountdown, setPassiveCountdown] = useState<number | null>(null);

  useEffect(() => {
    const offOriginal = window.ghostedit.onSetPreviewOriginal((text) => {
      setOriginal(text);
    });

    const offDone = window.ghostedit.onStreamingDone((text) => {
      setCorrected(text);
    });

    const offConfig = window.ghostedit.onSetPreviewConfig((cfg) => {
      setAutoPasteDelay(cfg.autoPasteDelaySeconds);
      setPreviewMode(cfg.diffPreviewMode);
      if (cfg.diffPreviewMode === 'passive' && cfg.passivePreviewSeconds > 0) {
        setPassiveCountdown(cfg.passivePreviewSeconds);
      }
    });

    return () => {
      offOriginal();
      offDone();
      offConfig();
    };
  }, []);

  // Start countdown when corrected text arrives and autoPasteDelay > 0 (interactive mode)
  useEffect(() => {
    if (previewMode !== 'interactive' || !corrected || autoPasteDelay <= 0) return;
    setCountdown(autoPasteDelay);
    const interval = setInterval(() => {
      setCountdown((prev) => {
        if (prev === null || prev <= 1) {
          clearInterval(interval);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => clearInterval(interval);
  }, [corrected, autoPasteDelay, previewMode]);

  // Passive countdown (visual only — main process handles the actual close)
  useEffect(() => {
    if (previewMode !== 'passive' || passiveCountdown === null || passiveCountdown <= 0) return;
    const interval = setInterval(() => {
      setPassiveCountdown((prev) => {
        if (prev === null || prev <= 1) {
          clearInterval(interval);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => clearInterval(interval);
  }, [previewMode, passiveCountdown]);

  // Auto-accept when countdown reaches 0
  useEffect(() => {
    if (countdown === 0) {
      handleAccept();
    }
  }, [countdown]);

  // Esc to reject, Enter to accept (interactive mode only)
  useEffect(() => {
    if (previewMode !== 'interactive') return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        handleReject();
      }
      if (e.key === 'Enter') {
        handleAccept();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [corrected, previewMode]);

  const handleAccept = async () => {
    if (!corrected) return;
    await window.ghostedit.acceptCorrection(corrected);
    window.close();
  };

  const handleReject = async () => {
    setCountdown(null);
    await window.ghostedit.rejectCorrection();
    window.close();
  };

  const segments = useMemo(
    () => (original && corrected ? computeDiff(original, corrected) : []),
    [original, corrected],
  );

  const additions = segments.filter((s) => s.kind === 'insertion').length;
  const deletions = segments.filter((s) => s.kind === 'deletion').length;

  const isPassive = previewMode === 'passive';

  return (
    <div className={`flex flex-col h-screen backdrop-blur-2xl bg-black/65 border border-white/[0.08] rounded-xl overflow-hidden text-white/90${isPassive ? ' pointer-events-none' : ''}`}>
      {/* Title bar */}
      <div className="h-10 flex items-center justify-between px-4 border-b border-white/[0.08] shrink-0">
        <span className="text-sm font-medium text-white/70">
          {isPassive ? 'Correction Applied' : 'Review Correction'}
        </span>
        <div className="flex items-center gap-3 text-xs text-white/40">
          {isPassive ? (
            passiveCountdown !== null && passiveCountdown > 0 && (
              <span>Closing in {passiveCountdown}s</span>
            )
          ) : (
            <>
              <span>Enter to accept</span>
              <span>Esc to reject</span>
            </>
          )}
        </div>
      </div>

      {/* Status bar */}
      <div className="flex items-center gap-3 px-4 py-2 text-xs text-white/40 border-b border-white/[0.08] shrink-0">
        {corrected ? (
          <span>
            {additions} addition{additions !== 1 ? 's' : ''}, {deletions} deletion
            {deletions !== 1 ? 's' : ''}
            {isPassive ? (
              passiveCountdown !== null && passiveCountdown > 0 && (
                <span className="ml-2 text-green-400">— Applied — closing in {passiveCountdown}s</span>
              )
            ) : (
              countdown !== null && countdown > 0 && (
                <span className="ml-2 text-blue-400">— Auto-applying in {countdown}s</span>
              )
            )}
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

      {/* Action buttons (interactive mode only) */}
      {corrected && !isPassive && (
        <div className="flex items-center justify-end gap-3 px-4 py-3 border-t border-white/[0.08] shrink-0">
          <button
            onClick={handleReject}
            className="px-4 py-1.5 rounded-lg bg-white/10 text-white/70 text-[13px] font-medium hover:bg-white/15 transition-colors"
          >
            Reject
          </button>
          <button
            onClick={handleAccept}
            className="px-4 py-1.5 rounded-lg bg-blue-500 text-white text-[13px] font-medium hover:bg-blue-400 transition-colors"
          >
            {countdown !== null && countdown > 0 ? `Accept (${countdown}s)` : 'Accept'}
          </button>
        </div>
      )}
    </div>
  );
}
