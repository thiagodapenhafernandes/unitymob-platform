import React from "react";

/**
 * Field — label + control wrapper. Renders an `.ax-label` above its
 * children with optional hint and required marker. Compose with Input,
 * Select, Textarea, etc.
 */
export function Field({ label, htmlFor, required = false, hint, children, className = "" }) {
  return (
    <div className={className} style={{ display: "grid", gap: 3 }}>
      {label && (
        <label className="ax-label" htmlFor={htmlFor}>
          {label}
          {required && <span style={{ color: "var(--danger)", marginLeft: 3 }}>*</span>}
        </label>
      )}
      {children}
      {hint && (
        <span style={{ fontSize: "var(--text-sm)", color: "var(--ink-muted)" }}>{hint}</span>
      )}
    </div>
  );
}
