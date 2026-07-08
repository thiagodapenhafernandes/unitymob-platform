import React from "react";

/**
 * NavLink — a sidebar navigation row (`.ax-nav__link`). Icon + label, with
 * an `active` state (left primary bar). Renders as <a> by default.
 */
export function NavLink({ icon, children, active = false, as = "a", className = "", ...rest }) {
  const Tag = as;
  return (
    <Tag className={`ax-nav__link ${active ? "active" : ""} ${className}`.trim()} aria-current={active ? "page" : undefined} {...rest}>
      {icon && <i className={`bi bi-${icon}`} aria-hidden="true" />}
      <span>{children}</span>
    </Tag>
  );
}
