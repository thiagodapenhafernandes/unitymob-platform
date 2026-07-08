import React from "react";

export type ButtonVariant =
  | "default"
  | "primary"
  | "ghost"
  | "danger"
  | "success"
  | "warning"
  | "info";

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  /** Visual style. Default is the neutral outlined button. */
  variant?: ButtonVariant;
  /** 30px (md) or 28px (sm). */
  size?: "md" | "sm";
  /** Bootstrap Icons name for a leading icon (without the `bi-` prefix). */
  icon?: string;
  /** Bootstrap Icons name for a trailing icon. */
  iconRight?: string;
  /** Stretch to full width. */
  block?: boolean;
  /** Render as a different element, e.g. "a". */
  as?: "button" | "a";
  children?: React.ReactNode;
}

/** Button — primary action control for the Unitymob admin. */
export function Button(props: ButtonProps): JSX.Element;
