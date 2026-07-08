export interface MenuItem {
  label?: string;
  /** Bootstrap Icons name. */
  icon?: string;
  /** Render in danger red. */
  danger?: boolean;
  onClick?: () => void;
  /** Render a divider instead of an item. */
  separator?: boolean;
}
export interface MenuProps {
  items: MenuItem[];
  className?: string;
  style?: React.CSSProperties;
}
/** Menu — floating dropdown/action menu with icons and separators. */
export function Menu(props: MenuProps): JSX.Element;
