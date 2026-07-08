import React from "react";

/** Textarea — multi-line field (`.ax-textarea`), vertically resizable. */
export function Textarea({ className = "", rows = 4, ...rest }) {
  return <textarea className={`ax-textarea ${className}`.trim()} rows={rows} {...rest} />;
}
