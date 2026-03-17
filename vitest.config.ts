import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    include: ['src/**/*.test.{ts,tsx}'],
    environmentMatchGlobs: [
      ['src/renderer/**/*.test.tsx', 'jsdom'],
    ],
  },
});
