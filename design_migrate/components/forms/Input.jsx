import React from "react";

/** Input — standard 34px text field (`.ax-input`). */
export function Input({ className = "", ...rest }) {
  return <input className={`ax-input ${className}`.trim()} {...rest} />;
}
