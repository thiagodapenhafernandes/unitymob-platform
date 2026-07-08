import React from "react";
export interface CardProps {
  /** Header title. */
  title?: React.ReactNode;
  /** Uppercase eyebrow above the title. */
  eyebrow?: string;
  /** Right-aligned header actions (buttons, menus). */
  actions?: React.ReactNode;
  /** Inline style override for the body. */
  bodyStyle?: React.CSSProperties;
  children?: React.ReactNode;
  className?: string;
}
/** Card — base surface panel with optional header. */
export function Card(props: CardProps): JSX.Element;
