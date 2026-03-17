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
          sidebar: 'rgba(255, 255, 255, 0.03)',
          'row-border': 'rgba(255, 255, 255, 0.06)',
        },
      },
      keyframes: {
        'content-in': {
          from: { opacity: '0', transform: 'translateY(4px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
      },
      animation: {
        'content-in': 'content-in 150ms ease-out',
      },
    },
  },
  plugins: [],
};

export default config;
