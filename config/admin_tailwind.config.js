const defaultTheme = require('tailwindcss/defaultTheme')

/*
 * Tailwind do CRM (/admin) — build SEPARADO do front.
 * - prefix 'tw-'  : evita colisão com o Bootstrap durante a transição (.table, .container, .border...).
 *                   Quando o Bootstrap sair de vez, removemos o prefixo e unificamos com o build do front.
 * - preflight off : não reseta a base, então as telas ainda-Bootstrap continuam intactas.
 * - primária via CSS var --admin-primary (white-label por cliente, injetada no <head> do layout admin).
 */
module.exports = {
  prefix: 'tw-',
  important: false,
  corePlugins: {
    preflight: false,
  },
  content: [
    './app/views/admin/**/*.{erb,haml,html,slim}',
    './app/views/layouts/admin*.{erb,html}',
    './app/views/layouts/_*.{erb,html}',
    './app/javascript/controllers/**/*.js',
    './app/helpers/**/*.rb',
  ],
  theme: {
    extend: {
      colors: {
        // Primária white-label (vem do LayoutSetting.admin_primary_color)
        primary: {
          DEFAULT: 'var(--admin-primary)',
          fg: 'var(--admin-primary-fg)',
          soft: 'var(--admin-primary-soft)',
        },
        // Base neutra corporativa (Power BI): cinzas frios
        ink: {
          DEFAULT: '#1f2733',
          soft: '#3b4656',
          muted: '#697586',
          faint: '#98a2b3',
        },
        line: {
          DEFAULT: '#e6e8eb',
          strong: '#d2d6db',
        },
        surface: {
          DEFAULT: '#ffffff',
          soft: '#f7f8fa',
          header: '#f2f4f7',
          zebra: '#fafbfc',
        },
      },
      fontFamily: {
        sans: ['Inter', 'Segoe UI', ...defaultTheme.fontFamily.sans],
      },
      fontSize: {
        // Escala compacta
        '2xs': ['0.6875rem', { lineHeight: '1rem' }], // 11px
      },
      borderRadius: {
        DEFAULT: '6px',
        md: '6px',
        lg: '8px',
      },
      boxShadow: {
        card: '0 1px 2px rgb(16 24 40 / 0.06), 0 1px 3px rgb(16 24 40 / 0.04)',
        pop: '0 8px 24px rgb(16 24 40 / 0.12)',
      },
    },
  },
  plugins: [],
}
