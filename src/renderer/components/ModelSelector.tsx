import React from 'react';
import type { ProviderName } from '../../shared/types';
import { ALL_PROVIDERS } from '../../shared/constants';

interface ModelSelectorProps {
  provider: ProviderName;
  value: string;
  onChange: (model: string) => void;
}

export default function ModelSelector({ provider, value, onChange }: ModelSelectorProps) {
  const models = ALL_PROVIDERS[provider]?.availableModels ?? [];

  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="input"
    >
      {models.map((m) => (
        <option key={m} value={m}>
          {m}
        </option>
      ))}
    </select>
  );
}
