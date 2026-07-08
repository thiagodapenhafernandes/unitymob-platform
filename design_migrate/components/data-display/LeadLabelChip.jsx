import React from "react";

/** LeadLabelChip — small tag used on leads/conversations (`.lead-label-chip`). */
export function LeadLabelChip({ children, color = "blue", className = "" }) {
  return <span className={`lead-label-chip lead-label-chip--${color} ${className}`.trim()}>{children}</span>;
}
