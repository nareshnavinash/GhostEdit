import { defineConfig } from 'vite';

export default defineConfig({
  resolve: {
    conditions: ['node'],
  },
  build: {
    rollupOptions: {
      external: ['@nut-tree-fork/nut-js', '@huggingface/transformers', 'harper.js', 'nspell', 'dictionary-en', 'uiohook-napi'],
    },
  },
});
