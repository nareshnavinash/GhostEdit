import React, { useState, useCallback } from 'react';

interface HotkeyInputProps {
  value: string;
  onChange: (accelerator: string) => void;
}

/**
 * Records a keyboard shortcut and converts it to an Electron accelerator string.
 */
export default function HotkeyInput({ value, onChange }: HotkeyInputProps) {
  const [recording, setRecording] = useState(false);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (!recording) return;
      e.preventDefault();

      // Skip modifier-only presses
      if (['Control', 'Shift', 'Alt', 'Meta'].includes(e.key)) return;

      const parts: string[] = [];
      if (e.metaKey || e.ctrlKey) parts.push('CommandOrControl');
      if (e.shiftKey) parts.push('Shift');
      if (e.altKey) parts.push('Alt');

      // Normalize key name
      let key = e.key.length === 1 ? e.key.toUpperCase() : e.key;
      parts.push(key);

      const accelerator = parts.join('+');
      onChange(accelerator);
      setRecording(false);
    },
    [recording, onChange],
  );

  return (
    <div className="flex items-center gap-2">
      <input
        type="text"
        value={recording ? 'Press a key combination...' : value}
        readOnly
        onKeyDown={handleKeyDown}
        className={`input flex-1 ${recording ? 'ring-2 ring-blue-400/50' : ''}`}
      />
      <button
        onClick={() => setRecording(!recording)}
        className={`px-3.5 py-2 rounded-lg text-[13px] font-medium transition-colors ${
          recording
            ? 'bg-red-500 text-white'
            : 'bg-white/10 text-ghost-muted hover:bg-white/15'
        }`}
      >
        {recording ? 'Cancel' : 'Record'}
      </button>
    </div>
  );
}
