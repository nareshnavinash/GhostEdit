import { execFile } from 'node:child_process';

/**
 * Play system sounds for correction feedback.
 * Uses platform-native sound playback (no bundled audio files needed).
 */

function playSound(soundFile: string): void {
  if (process.platform === 'darwin') {
    execFile('afplay', [soundFile], (err) => {
      if (err) console.warn('[GhostEdit] Sound playback failed:', err.message);
    });
  } else if (process.platform === 'win32') {
    // Windows: use PowerShell to play system sounds
    const psCommand = soundFile === 'success'
      ? '[System.Media.SystemSounds]::Asterisk.Play()'
      : '[System.Media.SystemSounds]::Hand.Play()';
    execFile('powershell', ['-NoProfile', '-Command', psCommand], (err) => {
      if (err) console.warn('[GhostEdit] Sound playback failed:', err.message);
    });
  } else {
    // Linux: try paplay with freedesktop sounds
    const linuxSound = soundFile === 'success'
      ? '/usr/share/sounds/freedesktop/stereo/complete.oga'
      : '/usr/share/sounds/freedesktop/stereo/dialog-error.oga';
    execFile('paplay', [linuxSound], (err) => {
      if (err) console.warn('[GhostEdit] Sound playback failed:', err.message);
    });
  }
}

export function playSuccessSound(): void {
  if (process.platform === 'darwin') {
    playSound('/System/Library/Sounds/Glass.aiff');
  } else {
    playSound('success');
  }
}

export function playErrorSound(): void {
  if (process.platform === 'darwin') {
    playSound('/System/Library/Sounds/Basso.aiff');
  } else {
    playSound('error');
  }
}
