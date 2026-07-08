import React from "react";

/** SearchInput — 34px field with a leading magnifier (`.ax-search`). */
export function SearchInput({ className = "", placeholder = "Buscar…", ...rest }) {
  return <input type="search" className={`ax-search ${className}`.trim()} placeholder={placeholder} {...rest} />;
}
