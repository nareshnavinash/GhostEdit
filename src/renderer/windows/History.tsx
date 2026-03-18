import React, { useEffect, useState, useMemo, useCallback } from 'react';
import DiffMatchPatch from 'diff-match-patch';
import DiffView from '../components/DiffView';
import type { CorrectionHistoryEntry, ErrorLogEntry, DiffSegment } from '../../shared/types';

type StatusFilter = 'all' | 'succeeded' | 'failed';
type Tab = 'history' | 'errors';

const dmp = new DiffMatchPatch();

function computeDiff(original: string, corrected: string): DiffSegment[] {
  if (!original || !corrected) return [];
  const diffs = dmp.diff_main(original, corrected);
  dmp.diff_cleanupSemantic(diffs);
  return diffs.map(([op, text]: [number, string]) => ({
    kind: op === 0 ? 'equal' : op === -1 ? 'deletion' : 'insertion',
    text,
  })) as DiffSegment[];
}

export default function History() {
  const isMac = window.ghostedit.platform === 'darwin';
  const [entries, setEntries] = useState<CorrectionHistoryEntry[]>([]);
  const [errors, setErrors] = useState<ErrorLogEntry[]>([]);
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<CorrectionHistoryEntry | null>(null);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [providerFilter, setProviderFilter] = useState<string>('all');
  const [tab, setTab] = useState<Tab>('history');
  const [copied, setCopied] = useState<'original' | 'corrected' | null>(null);
  const [showDiff, setShowDiff] = useState(false);

  useEffect(() => {
    window.ghostedit.getHistory().then((h) => setEntries(h.reverse()));
    window.ghostedit.getErrorLog().then(setErrors);
  }, []);

  const providers = useMemo(() => {
    const set = new Set(entries.map((e) => e.provider));
    return Array.from(set);
  }, [entries]);

  const filtered = useMemo(() => {
    let result = entries;
    if (search) {
      const q = search.toLowerCase();
      result = result.filter(
        (e) =>
          e.originalText.toLowerCase().includes(q) ||
          e.generatedText.toLowerCase().includes(q),
      );
    }
    if (statusFilter !== 'all') {
      result = result.filter((e) =>
        statusFilter === 'succeeded' ? e.succeeded : !e.succeeded,
      );
    }
    if (providerFilter !== 'all') {
      result = result.filter((e) => e.provider === providerFilter);
    }
    return result;
  }, [search, entries, statusFilter, providerFilter]);

  const handleClear = async () => {
    await window.ghostedit.clearHistory();
    setEntries([]);
    setSelected(null);
  };

  const handleExport = useCallback(async (format: 'json' | 'csv') => {
    await window.ghostedit.exportHistory(format);
  }, []);

  const handleCopy = useCallback(async (text: string, which: 'original' | 'corrected') => {
    await navigator.clipboard.writeText(text);
    setCopied(which);
    setTimeout(() => setCopied(null), 1500);
  }, []);

  const diffSegments = useMemo(
    () => (selected && showDiff ? computeDiff(selected.originalText, selected.generatedText) : []),
    [selected, showDiff],
  );

  return (
    <div className="flex flex-col h-screen bg-ghost-bg text-ghost-text">
      {/* Title bar */}
      <div className={`drag-region h-10 flex items-center justify-between border-b border-white/10 shrink-0 ${isMac ? 'pl-[72px]' : 'pl-4'} pr-4`}>
        <div className="flex items-center gap-4">
          <span className="text-sm font-medium text-ghost-muted">Correction History</span>
          {/* Tabs */}
          <div className="no-drag flex items-center gap-1 bg-white/5 rounded-lg p-0.5">
            <button
              onClick={() => setTab('history')}
              className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                tab === 'history' ? 'bg-white/10 text-white' : 'text-ghost-muted hover:text-white/70'
              }`}
            >
              History
            </button>
            <button
              onClick={() => setTab('errors')}
              className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                tab === 'errors' ? 'bg-white/10 text-white' : 'text-ghost-muted hover:text-white/70'
              }`}
            >
              Errors {errors.length > 0 && `(${errors.length})`}
            </button>
          </div>
        </div>
        {!isMac && (
          <div className="no-drag flex items-center gap-1">
            <button
              onClick={() => window.ghostedit.windowControls.minimize()}
              className="w-8 h-8 flex items-center justify-center rounded hover:bg-white/10 text-ghost-muted"
              aria-label="Minimize"
            >
              <svg width={12} height={12} viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round"><path d="M2 6h8" /></svg>
            </button>
            <button
              onClick={() => window.ghostedit.windowControls.close()}
              className="w-8 h-8 flex items-center justify-center rounded hover:bg-red-500/80 hover:text-white text-ghost-muted"
              aria-label="Close"
            >
              <svg width={12} height={12} viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round"><path d="M2 2l8 8M10 2l-8 8" /></svg>
            </button>
          </div>
        )}
      </div>

      {tab === 'history' ? (
        <>
          {/* Search + filters + actions */}
          <div className="flex items-center gap-2 p-3 border-b border-white/10 shrink-0 flex-wrap">
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search history..."
              className="input flex-1 min-w-[120px]"
            />
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as StatusFilter)}
              className="input w-28"
            >
              <option value="all">All Status</option>
              <option value="succeeded">Succeeded</option>
              <option value="failed">Failed</option>
            </select>
            {providers.length > 1 && (
              <select
                value={providerFilter}
                onChange={(e) => setProviderFilter(e.target.value)}
                className="input w-28"
              >
                <option value="all">All Providers</option>
                {providers.map((p) => (
                  <option key={p} value={p}>{p}</option>
                ))}
              </select>
            )}
            <div className="flex items-center gap-1">
              <button
                onClick={() => handleExport('json')}
                className="text-xs text-blue-400 hover:text-blue-300 px-2 py-1"
                title="Export as JSON"
              >
                JSON
              </button>
              <button
                onClick={() => handleExport('csv')}
                className="text-xs text-blue-400 hover:text-blue-300 px-2 py-1"
                title="Export as CSV"
              >
                CSV
              </button>
              <button
                onClick={handleClear}
                className="text-xs text-ghost-error hover:text-red-300 px-2 py-1"
              >
                Clear All
              </button>
            </div>
          </div>

          <div className="flex flex-1 overflow-hidden">
            {/* List */}
            <div className="w-1/2 overflow-y-auto border-r border-white/10">
              {filtered.length === 0 && (
                <p className="text-ghost-muted text-sm p-4 text-center">No corrections yet</p>
              )}
              {filtered.map((entry) => (
                <button
                  key={entry.id}
                  onClick={() => { setSelected(entry); setShowDiff(false); }}
                  className={`w-full text-left p-3 border-b border-white/5 hover:bg-white/5 transition-colors ${
                    selected?.id === entry.id ? 'bg-white/10' : ''
                  }`}
                >
                  <div className="flex items-center justify-between mb-1">
                    <span
                      className={`text-xs font-medium px-1.5 py-0.5 rounded ${
                        entry.succeeded
                          ? 'bg-ghost-success/20 text-ghost-success'
                          : entry.rejected
                            ? 'bg-yellow-500/20 text-yellow-400'
                            : 'bg-ghost-error/20 text-ghost-error'
                      }`}
                    >
                      {entry.succeeded ? 'OK' : entry.rejected ? 'Rejected' : 'Failed'}
                    </span>
                    <span className="text-xs text-ghost-muted">
                      {new Date(entry.timestamp).toLocaleString()}
                    </span>
                  </div>
                  <p className="text-sm truncate">{entry.originalText || '(empty)'}</p>
                  <p className="text-xs text-ghost-muted mt-0.5">
                    {entry.provider} / {entry.model} &middot; {entry.durationMilliseconds}ms
                  </p>
                </button>
              ))}
            </div>

            {/* Detail */}
            <div className="w-1/2 overflow-y-auto p-4">
              {selected ? (
                <div className="space-y-4">
                  {/* Diff toggle */}
                  {selected.succeeded && selected.generatedText && (
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => setShowDiff(!showDiff)}
                        className={`text-xs font-medium px-2.5 py-1 rounded-lg transition-colors ${
                          showDiff
                            ? 'bg-blue-500/20 text-blue-400'
                            : 'bg-white/5 text-ghost-muted hover:text-white/70'
                        }`}
                      >
                        {showDiff ? 'Hide Diff' : 'Show Diff'}
                      </button>
                    </div>
                  )}

                  {showDiff && diffSegments.length > 0 ? (
                    /* Inline diff view */
                    <div className="space-y-4">
                      <div>
                        <h3 className="text-xs font-medium text-ghost-muted uppercase mb-1">Original</h3>
                        <div className="selectable-text bg-white/5 rounded p-2">
                          <DiffView segments={diffSegments} side="original" />
                        </div>
                      </div>
                      <div>
                        <h3 className="text-xs font-medium text-ghost-muted uppercase mb-1">Corrected</h3>
                        <div className="selectable-text bg-white/5 rounded p-2">
                          <DiffView segments={diffSegments} side="corrected" />
                        </div>
                      </div>
                    </div>
                  ) : (
                    /* Plain text view */
                    <>
                      <div>
                        <div className="flex items-center justify-between mb-1">
                          <h3 className="text-xs font-medium text-ghost-muted uppercase">Original</h3>
                          <button
                            onClick={() => handleCopy(selected.originalText, 'original')}
                            className="text-xs text-blue-400 hover:text-blue-300 px-1.5 py-0.5"
                          >
                            {copied === 'original' ? 'Copied!' : 'Copy'}
                          </button>
                        </div>
                        <p className="selectable-text text-sm whitespace-pre-wrap bg-white/5 rounded p-2">
                          {selected.originalText || '(empty)'}
                        </p>
                      </div>
                      <div>
                        <div className="flex items-center justify-between mb-1">
                          <h3 className="text-xs font-medium text-ghost-muted uppercase">Corrected</h3>
                          <button
                            onClick={() => handleCopy(selected.generatedText, 'corrected')}
                            className="text-xs text-blue-400 hover:text-blue-300 px-1.5 py-0.5"
                          >
                            {copied === 'corrected' ? 'Copied!' : 'Copy'}
                          </button>
                        </div>
                        <p className="selectable-text text-sm whitespace-pre-wrap bg-white/5 rounded p-2">
                          {selected.generatedText || '(empty)'}
                        </p>
                      </div>
                    </>
                  )}

                  <div className="flex gap-4 text-xs text-ghost-muted">
                    <span>Provider: {selected.provider}</span>
                    <span>Model: {selected.model}</span>
                    <span>Duration: {selected.durationMilliseconds}ms</span>
                  </div>
                </div>
              ) : (
                <p className="text-ghost-muted text-sm text-center mt-8">
                  Select an entry to view details
                </p>
              )}
            </div>
          </div>
        </>
      ) : (
        /* Error log tab */
        <div className="flex-1 overflow-y-auto p-4">
          {errors.length === 0 ? (
            <p className="text-ghost-muted text-sm text-center mt-8">No recent errors</p>
          ) : (
            <div className="space-y-2">
              {errors.map((err) => (
                <div
                  key={err.id}
                  className="bg-ghost-error/5 border border-ghost-error/10 rounded-lg p-3"
                >
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-xs text-ghost-error font-medium">
                      {err.provider ? `${err.provider} error` : 'Error'}
                    </span>
                    <span className="text-xs text-ghost-muted">
                      {new Date(err.timestamp).toLocaleString()}
                    </span>
                  </div>
                  <p className="selectable-text text-sm text-ghost-text">{err.message}</p>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
