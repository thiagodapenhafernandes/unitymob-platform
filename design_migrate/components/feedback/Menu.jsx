import React from "react";

/**
 * Menu — floating action menu (`.ax-menu`). Renders a list of items; each
 * item accepts an icon, label, danger flag and onClick. Separators via
 * `{ separator: true }`.
 */
export function Menu({ items = [], className = "", style }) {
  return (
    <div className={`ax-menu ${className}`.trim()} role="menu" style={style}>
      {items.map((it, i) =>
        it.separator ? (
          <div key={i} className="ax-menu__sep" />
        ) : (
          <button
            key={i}
            role="menuitem"
            className={`ax-menu__item ${it.danger ? "ax-menu__item--danger" : ""}`.trim()}
            onClick={it.onClick}
          >
            {it.icon && <i className={`bi bi-${it.icon}`} aria-hidden="true" />}
            <span>{it.label}</span>
          </button>
        )
      )}
    </div>
  );
}
