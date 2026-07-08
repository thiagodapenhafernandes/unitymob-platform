import React from "react";

/**
 * Alert — inline message block (`.ax-alert`). `tone` sets the color;
 * `icon` is a Bootstrap Icons name. Title + free-form children.
 */
export function Alert({ tone = "default", icon, title, children, actions, className = "" }) {
  const cls = ["ax-alert", tone !== "default" && `ax-alert--${tone}`, className].filter(Boolean).join(" ");
  const defaultIcon = { danger: "exclamation-octagon", warning: "exclamation-triangle", success: "check-circle", default: "info-circle" }[tone];
  return (
    <div className={cls} role="alert">
      <i className={`bi bi-${icon || defaultIcon}`} style={{ fontSize: 16, flex: "none", marginTop: 1 }} aria-hidden="true" />
      <div style={{ minWidth: 0, flex: 1 }}>
        {title && <div className="ax-alert__title">{title}</div>}
        {children && <div style={{ fontSize: "var(--text-base)", marginTop: title ? 3 : 0 }}>{children}</div>}
      </div>
      {actions && <div style={{ display: "inline-flex", gap: 6, marginLeft: "auto" }}>{actions}</div>}
    </div>
  );
}
