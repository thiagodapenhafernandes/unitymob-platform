import React from "react";
export type BadgeTone = "gray" | "green" | "amber" | "red" | "blue" | "purple" | "cyan";
export interface BadgeProps {
  /** Semantic color. */
  tone?: BadgeTone;
  /** Prepend a status dot. */
  dot?: boolean;
  children?: React.ReactNode;
  className?: string;
}
/** Badge — compact status pill in the semantic palette. */
export function Badge(props: BadgeProps): JSX.Element;
