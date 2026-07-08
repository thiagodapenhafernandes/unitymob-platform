import React from "react";

/**
 * Button — the platform's primary action control.
 * Thin wrapper over the shipped `.ax-btn` classes (30px tall, 6px radius,
 * weight 750). Icons are Bootstrap Icons class names (e.g. "plus-lg").
 */
export function Button({
  children,
  variant = "default",
  size = "md",
  icon,
  iconRight,
  block = false,
  disabled = false,
  as = "button",
  className = "",
  ...rest
}) {
  const cls = [
    "ax-btn",
    variant !== "default" && `ax-btn--${variant}`,
    size === "sm" && "ax-btn--sm",
    block && "ax-btn--block",
    className,
  ]
    .filter(Boolean)
    .join(" ");

  const Tag = as;
  return (
    <Tag className={cls} disabled={Tag === "button" ? disabled : undefined} aria-disabled={disabled || undefined} {...rest}>
      {icon && <i className={`bi bi-${icon}`} aria-hidden="true" />}
      {children && <span>{children}</span>}
      {iconRight && <i className={`bi bi-${iconRight}`} aria-hidden="true" />}
    </Tag>
  );
}
