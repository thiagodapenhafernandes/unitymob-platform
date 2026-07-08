import React from "react";
export interface EmptyStateProps {
  /** Bootstrap Icons name. Default "inbox". */
  icon?: string;
  title?: React.ReactNode;
  /** Call-to-action element (e.g. a Button). */
  action?: React.ReactNode;
  children?: React.ReactNode;
  className?: string;
}
/** EmptyState — centered icon + message for empty lists and panels. */
export function EmptyState(props: EmptyStateProps): JSX.Element;
