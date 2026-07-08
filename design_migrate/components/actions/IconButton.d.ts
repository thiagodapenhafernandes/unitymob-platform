import React from "react";

export interface IconButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  /** Bootstrap Icons name (without `bi-`). */
  icon: string;
  /** `bare` = transparent toolbar button; `outlined` = bordered. */
  variant?: "bare" | "outlined";
  /** Accessible label (also used as tooltip title). */
  label?: string;
}

/** IconButton — compact icon-only control for toolbars and row actions. */
export function IconButton(props: IconButtonProps): JSX.Element;
