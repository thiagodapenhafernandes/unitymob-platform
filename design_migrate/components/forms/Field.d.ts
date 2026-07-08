import React from "react";
export interface FieldProps {
  /** Field label text. */
  label?: string;
  /** id of the control this labels. */
  htmlFor?: string;
  /** Show a red required asterisk. */
  required?: boolean;
  /** Helper text below the control. */
  hint?: string;
  children?: React.ReactNode;
  className?: string;
}
/** Field — label + hint wrapper around a form control. */
export function Field(props: FieldProps): JSX.Element;
