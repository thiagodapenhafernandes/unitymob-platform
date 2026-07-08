import React from "react";
export interface SwitchProps extends React.InputHTMLAttributes<HTMLInputElement> {
  /** Optional trailing label. */
  label?: string;
}
/** Switch — pill on/off toggle; track turns primary when checked. */
export function Switch(props: SwitchProps): JSX.Element;
