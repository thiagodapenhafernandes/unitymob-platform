const defaultTheme = require("tailwindcss/defaultTheme")

module.exports = {
  prefix: "tw-",
  important: false,
  corePlugins: {
    preflight: false,
  },
  content: [
    "./public/analytics-builder-design-system/index.html",
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: "var(--admin-primary)",
          fg: "var(--admin-primary-fg)",
          soft: "var(--admin-primary-soft)",
        },
        ink: {
          DEFAULT: "#1f2733",
          soft: "#3b4656",
          muted: "#697586",
          faint: "#98a2b3",
        },
        line: {
          DEFAULT: "#e6e8eb",
          strong: "#d2d6db",
        },
        surface: {
          DEFAULT: "#ffffff",
          soft: "#f7f8fa",
          header: "#f2f4f7",
          zebra: "#fafbfc",
        },
      },
      fontFamily: {
        sans: ["Inter", "Segoe UI", ...defaultTheme.fontFamily.sans],
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "Monaco", "Consolas", "monospace"],
      },
      fontSize: {
        "2xs": ["0.6875rem", { lineHeight: "1rem" }],
      },
      borderRadius: {
        DEFAULT: "6px",
        md: "6px",
        lg: "8px",
      },
      boxShadow: {
        card: "0 1px 2px rgb(16 24 40 / 0.06), 0 1px 3px rgb(16 24 40 / 0.04)",
        pop: "0 8px 24px rgb(16 24 40 / 0.12)",
      },
    },
  },
  plugins: [],
}
