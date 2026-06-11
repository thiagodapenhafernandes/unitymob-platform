const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}'
  ],
  safelist: [
    'bg-primary-500',
    'bg-primary-600',
    'bg-purple-600',
    'bg-green-500',
    'bg-green-600',
    'bg-orange-500',
    'bg-yellow-500',
  ],
  theme: {
    extend: {
      colors: {
        // Salute Imóveis Brand Colors
        primary: {
          50: '#e6f2ff',
          100: '#b3d9ff',
          200: '#80bfff',
          300: '#4da6ff',
          400: '#1a8cff',
          500: '#0073e6',  // Main blue
          600: '#005bb3',
          700: '#004480',
          800: '#002c4d',
          900: '#00151a',
        },
        secondary: {
          50: '#fff9e6',
          100: '#fff0b3',
          200: '#ffe680',
          300: '#ffdd4d',
          400: '#ffd41a',
          500: '#e6be00',  // Main gold
          600: '#b39500',
          700: '#806b00',
          800: '#4d4100',
          900: '#1a1600',
        },
        // Blues from V2
        'blue-one': 'var(--color-secondary)',
        'blue-two': '#1F7A8C',
        'blue-three': 'var(--color-primary)',
        // Golds from V2
        'golden-one': 'var(--color-accent)',
        'golden-two': 'var(--color-accent)', // Or create another variable if needed
        'hero-button': 'var(--color-hero-button)',
        'hero-button-text': 'var(--color-hero-button-text)',
      },
      fontFamily: {
        sans: ['Open Sans', 'Raleway', ...defaultTheme.fontFamily.sans],
        heading: ['Raleway', ...defaultTheme.fontFamily.sans],
      },
      boxShadow: {
        'card': '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
        'card-hover': '0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
        'property-card': '0 2px 8px rgba(0,0,0,0.1)',
        'property-card-hover': '0 8px 16px rgba(0,0,0,0.15)',
      },
      borderRadius: {
        'card': '12px',
      },
      transitionDuration: {
        '400': '400ms',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
    require('@tailwindcss/aspect-ratio'),
  ],
}
