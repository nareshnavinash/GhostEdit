import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    outDir: '.vite/preload',
    rollupOptions: {
      output: {
        format: 'cjs',
        entryFileNames: '[name].js',
      },
    },
  },
});
