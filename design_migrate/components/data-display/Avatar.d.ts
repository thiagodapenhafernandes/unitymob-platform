import React from "react";
export interface AvatarProps {
  /** Initials to render (e.g. "MC"). */
  initials?: string;
  /** Bootstrap Icons name, used instead of initials. */
  icon?: string;
  /** Pixel size (square). Default 30. */
  size?: number;
  className?: string;
  style?: React.CSSProperties;
}
/** Avatar — circular initials or icon chip in the primary tint. */
export function Avatar(props: AvatarProps): JSX.Element;
