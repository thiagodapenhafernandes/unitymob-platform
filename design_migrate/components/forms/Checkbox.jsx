import React from "react";

/** Checkbox — 15px accent-colored checkbox with an optional label (`.ax-check`). */
export function Checkbox({ label, className = "", ...rest }) {
  return (
    <label className={`ax-check ${className}`.trim()}>
      <input type="checkbox" {...rest} />
      {label && <span>{label}</span>}
    </label>
  );
}
