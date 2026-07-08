import React from "react";

/**
 * IconButton — square, icon-only control. Two flavours:
 * `bare` (transparent, hover fill) for toolbars, and `outlined`
 * (bordered white) for standalone actions. Always pass an aria-label.
 */
export function IconButton({ icon, variant = "bare", className = "", label, ...rest }) {
  const cls = [variant === "bare" ? "ax-ico-btn" : "ax-btn ax-btn--icon", className]
    .filter(Boolean)
    .join(" ");
  return (
    <button className={cls} aria-label={label} title={label} {...rest}>
      <i className={`bi bi-${icon}`} aria-hidden="true" />
    </button>
  );
}
