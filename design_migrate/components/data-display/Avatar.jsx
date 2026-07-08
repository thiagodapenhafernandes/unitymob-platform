import React from "react";

/** Avatar — circular initials/icon chip (`.ax-avatar`). */
export function Avatar({ initials, icon, size = 30, className = "", style }) {
  return (
    <span className={`ax-avatar ${className}`.trim()} style={{ width: size, height: size, ...style }}>
      {icon ? <i className={`bi bi-${icon}`} aria-hidden="true" /> : initials}
    </span>
  );
}
