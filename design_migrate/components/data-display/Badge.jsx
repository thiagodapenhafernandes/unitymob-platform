import React from "react";

/**
 * Badge — compact status pill (`.ax-badge`). `tone` maps to the semantic
 * palette; `dot` prepends a small status dot.
 */
export function Badge({ children, tone = "gray", dot = false, className = "" }) {
  const cls = ["ax-badge", `ax-badge--${tone}`, dot && "ax-badge--dot", className]
    .filter(Boolean)
    .join(" ");
  return <span className={cls}>{children}</span>;
}
