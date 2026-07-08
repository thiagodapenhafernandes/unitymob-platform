export interface TabItem {
  value: string;
  label: string;
  /** Optional Bootstrap Icons name. */
  icon?: string;
}
export interface TabsProps {
  tabs: TabItem[];
  /** Currently selected tab value. */
  value?: string;
  onChange?: (value: string) => void;
  className?: string;
}
/** Tabs — segmented control for switching views within a panel. */
export function Tabs(props: TabsProps): JSX.Element;
