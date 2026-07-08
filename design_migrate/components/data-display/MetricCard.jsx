import React from "react";

/**
 * MetricCard — KPI tile used across the dashboard. Shows an uppercase
 * label, a large tabular value, an optional badge and hint line, and an
 * optional progress bar.
 */
export function MetricCard({ label, value, badge, hint, progress, className = "" }) {
  return (
    <div className={`ax-card ${className}`.trim()} style={{ padding: "14px 16px", display: "grid", gap: 6 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8 }}>
        <span className="ax-stat-label">{label}</span>
        {badge}
      </div>
      <span className="ax-stat-value ax-num">{value}</span>
      {typeof progress === "number" && (
        <div className="ax-progress" style={{ marginTop: 2 }}>
          <i style={{ width: `${Math.max(0, Math.min(100, progress))}%` }} />
        </div>
      )}
      {hint && <span style={{ fontSize: "var(--text-sm)", color: "var(--ink-muted)" }}>{hint}</span>}
    </div>
  );
}
