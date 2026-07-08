import React from "react";

/** EmptyState — centered placeholder for empty lists/panels (`.ax-empty`). */
export function EmptyState({ icon = "inbox", title, children, action, className = "" }) {
  return (
    <div className={`ax-empty ${className}`.trim()}>
      <i className={`bi bi-${icon}`} style={{ fontSize: 28, color: "var(--ink-faint)", display: "block", marginBottom: 8 }} aria-hidden="true" />
      {title && <div style={{ color: "var(--ink)", fontWeight: 700, marginBottom: 4 }}>{title}</div>}
      {children && <div style={{ maxWidth: 340, margin: "0 auto" }}>{children}</div>}
      {action && <div style={{ marginTop: 12 }}>{action}</div>}
    </div>
  );
}
