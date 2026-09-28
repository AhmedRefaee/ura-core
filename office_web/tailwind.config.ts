import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: '#D97706',
        'primary-fill': '#F59E0B',
        secondary: '#65A30D',
        'secondary-light': '#16A34A',
        surface: '#F8FAFC',
        'surface-card': '#FFFFFF',
        'surface-inset': '#F1F5F9',
        'border-subtle': '#E2E8F0',
        'text-high': '#0F172A',
        'text-medium': '#334155',
        'text-low': '#64748B',
        success: '#15803D',
        'success-bg': '#F0FDF4',
        warning: '#B45309',
        'warning-bg': '#FEF3C7',
        error: '#B91C1C',
        'error-bg': '#FEF2F2',
      },
      fontFamily: {
        sans: ['"Cairo"', 'sans-serif'],
      },
      borderRadius: {
        input: '4px',
        button: '6px',
        card: '8px',
      },
    },
  },
  plugins: [],
} satisfies Config;
