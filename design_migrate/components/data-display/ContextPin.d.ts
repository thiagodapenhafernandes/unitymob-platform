import React from "react";
export type EntityType = "property" | "owner" | "lead" | "proposal" | "whatsapp";
export interface ContextPinProps {
  /** Which CRM object — sets the accent color and default icon. */
  type?: EntityType;
  /** Override the default Bootstrap Icons name. */
  icon?: string;
  /** Optional remove handler (renders an × button). */
  onRemove?: () => void;
  children?: React.ReactNode;
  className?: string;
}
/** ContextPin — entity chip with a left accent border for the navbar context bar. */
export function ContextPin(props: ContextPinProps): JSX.Element;
