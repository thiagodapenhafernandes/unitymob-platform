import React from "react";
export interface AlertProps {
  /** Color tone. */
  tone?: "default" | "danger" | "warning" | "success";
  /** Bootstrap Icons name (defaults per tone). */
  icon?: string;
  /** Bold title line. */
  title?: React.ReactNode;
  /** Right-aligned action buttons. */
  actions?: React.ReactNode;
  children?: React.ReactNode;
  className?: string;
}
/** Alert — inline colored message block with icon and optional actions. */
export function Alert(props: AlertProps): JSX.Element;
