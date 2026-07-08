import React from "react";
export type LabelColor = "gray" | "green" | "amber" | "red" | "blue" | "purple" | "cyan";
export interface LeadLabelChipProps {
  /** Chip color. */
  color?: LabelColor;
  children?: React.ReactNode;
  className?: string;
}
/** LeadLabelChip — small ringed tag applied to leads and WhatsApp threads. */
export function LeadLabelChip(props: LeadLabelChipProps): JSX.Element;
