import React from "react";

/**
 * ContextPin — the entity chip shown in the navbar context bar. Left border
 * carries the entity accent; `type` picks it. Icon + truncated label.
 */
export function ContextPin({ type = "property", icon, children, onRemove, className = "" }) {
  const defaultIcon = {
    property: "house-door",
    owner: "person-vcard",
    lead: "person-badge",
    proposal: "file-earmark-text",
    whatsapp: "whatsapp",
  }[type];
  return (
    <span className={`ax-context-pin ax-context-pin--${type} ${className}`.trim()}>
      <i className={`bi bi-${icon || defaultIcon}`} aria-hidden="true" />
      <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{children}</span>
      {onRemove && (
        <button onClick={onRemove} aria-label="Remover" style={{ border: 0, background: "transparent", color: "#7b8797", cursor: "pointer", marginLeft: 2, display: "inline-flex" }}>
          <i className="bi bi-x" />
        </button>
      )}
    </span>
  );
}
