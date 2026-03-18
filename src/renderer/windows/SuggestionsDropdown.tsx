import React, { useEffect, useState } from 'react';

interface SpellCheckIssue {
  word: string;
  range: { start: number; end: number };
  kind: 'spelling' | 'grammar' | 'style';
  suggestions: string[];
  source: 'harper' | 'nspell';
}

const KIND_COLOR: Record<string, string> = {
  spelling: '#ef4444',
  grammar: '#ef4444',
  style: '#eab308',
};

export default function SuggestionsDropdown() {
  const [issues, setIssues] = useState<SpellCheckIssue[]>([]);

  useEffect(() => {
    const off = window.ghostedit.onSuggestionsUpdate?.((data: SpellCheckIssue[]) => {
      setIssues(data);
    });
    return () => { off?.(); };
  }, []);

  const handleFix = (index: number) => {
    window.ghostedit.applyFix?.(index);
  };

  const handleFixAll = () => {
    window.ghostedit.applyAllFixes?.();
  };

  return (
    <div className="w-[320px] max-h-[300px] bg-[#1e1e2e]/95 backdrop-blur-xl border border-white/10 rounded-xl shadow-2xl overflow-hidden flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-3 py-2 border-b border-white/[0.06]">
        <span className="text-[12px] font-medium text-white/70">
          {issues.length === 0 ? 'No issues detected' : `${issues.length} issue${issues.length > 1 ? 's' : ''} found`}
        </span>
        {issues.length > 1 && (
          <button
            onClick={handleFixAll}
            className="px-2.5 py-1 rounded-md bg-blue-500/20 text-blue-400 text-[11px] font-medium hover:bg-blue-500/30 transition-colors"
          >
            Fix all
          </button>
        )}
      </div>

      {/* Issue list */}
      <div className="flex-1 overflow-y-auto">
        {issues.length === 0 ? (
          <div className="px-3 py-6 text-center text-[12px] text-white/40">
            Everything looks good
          </div>
        ) : (
          issues.map((issue, index) => (
            <div
              key={`${issue.range.start}-${issue.word}`}
              className="flex items-center gap-2 px-3 py-2 border-b border-white/[0.04] hover:bg-white/[0.03] transition-colors"
            >
              {/* Color dot */}
              <div
                className="w-2 h-2 rounded-full shrink-0"
                style={{ backgroundColor: KIND_COLOR[issue.kind] || '#eab308' }}
              />

              {/* Issue description */}
              <div className="flex-1 min-w-0">
                <div className="text-[12px] text-white/80 truncate">
                  <span className="line-through text-white/40">{issue.word}</span>
                  {issue.suggestions[0] && (
                    <>
                      <span className="text-white/30 mx-1">&rarr;</span>
                      <span className="text-white/90">{issue.suggestions[0]}</span>
                    </>
                  )}
                </div>
                <div className="text-[10px] text-white/30 capitalize">{issue.kind}</div>
              </div>

              {/* Fix button */}
              {issue.suggestions.length > 0 && (
                <button
                  onClick={() => handleFix(index)}
                  className="px-2 py-0.5 rounded-md bg-white/[0.06] text-white/60 text-[11px] hover:bg-white/10 hover:text-white/80 transition-colors shrink-0"
                >
                  Fix
                </button>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
