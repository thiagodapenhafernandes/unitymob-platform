import React from "react";

/**
 * Card — the base surface panel (`.ax-card`). Optional header with title,
 * eyebrow and a right-aligned actions slot; body holds arbitrary content.
 */
export function Card({ title, eyebrow, actions, children, bodyStyle, className = "" }) {
  return (
    <section className={`ax-card ${className}`.trim()}>
      {(title || actions) && (
        <header className="ax-card__header">
          <div style={{ minWidth: 0 }}>
            {eyebrow && <span className="ax-eyebrow">{eyebrow}</span>}
            {title && <div className="ax-card__title">{title}</div>}
          </div>
          {actions && <div style={{ marginLeft: "auto", display: "inline-flex", gap: 6 }}>{actions}</div>}
        </header>
      )}
      <div className="ax-card__body" style={bodyStyle}>{children}</div>
    </section>
  );
}
