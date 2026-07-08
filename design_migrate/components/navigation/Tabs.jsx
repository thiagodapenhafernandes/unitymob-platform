import React from "react";

/**
 * Tabs — segmented control (`.ax-tabs`). Controlled: pass `value`, `tabs`
 * (array of {value,label,icon}) and `onChange`.
 */
export function Tabs({ tabs = [], value, onChange, className = "" }) {
  return (
    <div className={`ax-tabs ${className}`.trim()} role="tablist">
      {tabs.map((t) => (
        <button
          key={t.value}
          role="tab"
          aria-selected={t.value === value}
          className={`ax-tab ${t.value === value ? "is-active" : ""}`.trim()}
          onClick={() => onChange && onChange(t.value)}
        >
          {t.icon && <i className={`bi bi-${t.icon}`} style={{ marginRight: 6 }} aria-hidden="true" />}
          {t.label}
        </button>
      ))}
    </div>
  );
}
