import React from "react";

/**
 * Switch — pill toggle (`.ax-switch`). Controlled via `checked`/`onChange`.
 * Track turns primary when on; 34×20 with a 14px thumb.
 */
export function Switch({ label, className = "", ...rest }) {
  return (
    <label className={`ax-switch ${className}`.trim()}>
      <input type="checkbox" {...rest} />
      <span className="ax-switch__track" aria-hidden="true" />
      {label && <span>{label}</span>}
    </label>
  );
}
