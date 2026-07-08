import React from "react";
export interface NavLinkProps extends React.AnchorHTMLAttributes<HTMLElement> {
  /** Bootstrap Icons name. */
  icon?: string;
  /** Active/current state — adds the left primary bar. */
  active?: boolean;
  as?: "a" | "button";
  children?: React.ReactNode;
}
/** NavLink — a sidebar navigation row with icon, label and active state. */
export function NavLink(props: NavLinkProps): JSX.Element;
