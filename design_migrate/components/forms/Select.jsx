import React from "react";

/** Select — native select styled with a custom chevron (`.ax-select`). */
export function Select({ className = "", children, ...rest }) {
  return (
    <select className={`ax-select ${className}`.trim()} {...rest}>
      {children}
    </select>
  );
}
