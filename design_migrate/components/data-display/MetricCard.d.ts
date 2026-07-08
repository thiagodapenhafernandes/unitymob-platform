import React from "react";
export interface MetricCardProps {
  /** Uppercase KPI label. */
  label: string;
  /** Large value (string or number). */
  value: React.ReactNode;
  /** Optional Badge element to the right of the label. */
  badge?: React.ReactNode;
  /** Secondary hint line below the value. */
  hint?: string;
  /** 0–100 progress bar under the value. */
  progress?: number;
  className?: string;
}
/** MetricCard — dashboard KPI tile. */
export function MetricCard(props: MetricCardProps): JSX.Element;
