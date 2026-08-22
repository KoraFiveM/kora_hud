import type { Config } from "tailwindcss"

// Token contract mirrors qblib's own web/tailwind.config.ts -- see
// qblib/web/AGENTS.md, the shared design-system reference. No darkMode/class
// toggle -- this is a fixed game overlay with exactly one permanent theme.
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        border: "hsl(var(--border))",
        ring: "hsl(var(--ring))",
        "brand-hover": "hsl(var(--brand-hover))",
        "brand-pressed": "hsl(var(--brand-pressed))",
        "brand-soft": "hsl(var(--brand-soft))",
        "brand-border": "hsl(var(--brand-border))",
        hud: "hsl(var(--hud))",
        success: "hsl(var(--success))",
        warning: "hsl(var(--warning))",
        info: "hsl(var(--info))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive))",
          foreground: "hsl(var(--destructive-foreground))",
        },
      },
      borderRadius: {
        sm: "0.375rem",
        md: "0.5rem",
        lg: "var(--radius)",
      },
      zIndex: {
        hud: "40",
      },
      boxShadow: {
        low: "0 4px 12px rgb(0 0 0 / 28%)",
      },
      fontFamily: {
        mono: ['"SFMono-Regular"', "Consolas", '"Liberation Mono"', "monospace"],
      },
      transitionDuration: {
        fast: "120ms",
      },
    },
  },
  plugins: [],
} satisfies Config
