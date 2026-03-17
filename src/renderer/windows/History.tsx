import React, { useEffect, useState, useMemo } from 'react';
import type { CorrectionHistoryEntry } from '../../shared/types';

export default function History() {
  const [entries, setEntries] = useState<CorrectionHistoryEntry[]>([]);
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<CorrectionHistoryEntry | null>(null);

  useEffect(() => {
    window.ghostedit.getHistory().then((h) => setEntries(h.reverse()));
  }, []);

  const filtered = useMemo(
    () =>
      search
        ? entries.filter(
            (e) =>
              e.originalText.toLowerCase().includes(search.toLowerCase()) ||
              e.generatedText.toLowerCase().includes(search.toLowerCase()),
          )
        : entries,
    [search, entries],
  );

  const handleClear = async () => {
    await window.ghostedit.clearHistory();
    setEntries([]);
    setSelected(null);
  };

  return (
    <div className="flex flex-col h-screen bg-ghost-bg text-ghost-text">
      {/* Title bar */}
      <div className="drag-region h-10 flex items-center justify-center pl-[72px] border-b border-white/10 shrink-0">
        <span className="text-sm font-medium text-ghost-muted">Correction History</span>
      </div>

      {/* Search + clear */}
      <div className="flex items-center gap-2 p-3 border-b border-white/10 shrink-0">
        <input
          type="text"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search history..."
          className="input flex-1"
        />
        <button
          onClick={handleClear}
          className="text-xs text-ghost-error hover:text-red-300 px-2 py-1"
        >
          Clear All
        </button>
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
              onClick={() => setSelected(entry)}
              className={`w-full text-left p-3 border-b border-white/5 hover:bg-white/5 transition-colors ${
                selected?.id === entry.id ? 'bg-white/10' : ''
              }`}
            >
              <div className="flex items-center justify-between mb-1">
                <span
                  className={`text-xs font-medium px-1.5 py-0.5 rounded ${
                    entry.succeeded
                      ? 'bg-ghost-success/20 text-ghost-success'
                      : 'bg-ghost-error/20 text-ghost-error'
                  }`}
                >
                  {entry.succeeded ? 'OK' : 'Failed'}
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
              <div>
                <h3 className="text-xs font-medium text-ghost-muted uppercase mb-1">Original</h3>
                <p className="text-sm whitespace-pre-wrap bg-white/5 rounded p-2">
                  {selected.originalText || '(empty)'}
                </p>
              </div>
              <div>
                <h3 className="text-xs font-medium text-ghost-muted uppercase mb-1">Corrected</h3>
                <p className="text-sm whitespace-pre-wrap bg-white/5 rounded p-2">
                  {selected.generatedText || '(empty)'}
                </p>
              </div>
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
    </div>
  );
}
