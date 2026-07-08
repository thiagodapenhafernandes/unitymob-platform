import React from "react";
export interface CheckboxProps extends React.InputHTMLAttributes<HTMLInputElement> {
  /** Optional inline label to the right of the box. */
  label?: string;
}
/** Checkbox — accent-colored box with inline label. */
export function Checkbox(props: CheckboxProps): JSX.Element;
