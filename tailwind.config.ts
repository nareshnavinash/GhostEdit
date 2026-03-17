import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/renderer/**/*.{tsx,ts,html}', './index.html'],
  theme: {
    extend: {
      colors: {
        ghost: {
          bg: 'rgba(26, 26, 46, 0.80)',
          surface: 'rgba(22, 33, 62, 0.75)',
          accent: 'rgba(15, 52, 96, 0.70)',
          text: '#e0e0e0',
          muted: '#888',
          success: '#4ade80',
          error: '#f87171',
          warning: '#fbbf24',
        },
      },
    },
  },
  plugins: [],
};

export default config;
