import React from 'react';
import type { ProviderName } from '../../shared/types';
import { ALL_PROVIDERS } from '../../shared/constants';

interface ProviderSelectorProps {
  value: ProviderName;
  onChange: (provider: ProviderName) => void;
  cliStatus?: Record<string, { found: boolean }>;
}

export default function ProviderSelector({ value, onChange, cliStatus }: ProviderSelectorProps) {
  return (
    <div className="flex gap-2">
      {Object.values(ALL_PROVIDERS).map((p) => {
        const found = p.name === 'local' ? true : cliStatus?.[p.name]?.found;
        const isActive = value === p.name;
        return (
          <button
            key={p.name}
            onClick={() => onChange(p.name)}
            className={`px-3 py-1.5 rounded text-sm font-medium transition-colors ${
              isActive
                ? 'bg-blue-500 text-white'
                : 'bg-white/10 text-ghost-muted hover:bg-white/15 hover:text-white'
            }`}
          >
            {p.displayName}
            {found === false && (
              <span className="ml-1 text-xs text-ghost-warning">!</span>
            )}
          </button>
        );
      })}
    </div>
  );
}
