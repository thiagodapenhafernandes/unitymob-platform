/* @ds-bundle: {"format":4,"namespace":"UnitymobDesignSystem_2a309d","components":[{"name":"Button","sourcePath":"components/actions/Button.jsx"},{"name":"IconButton","sourcePath":"components/actions/IconButton.jsx"},{"name":"Avatar","sourcePath":"components/data-display/Avatar.jsx"},{"name":"Badge","sourcePath":"components/data-display/Badge.jsx"},{"name":"Card","sourcePath":"components/data-display/Card.jsx"},{"name":"ContextPin","sourcePath":"components/data-display/ContextPin.jsx"},{"name":"LeadLabelChip","sourcePath":"components/data-display/LeadLabelChip.jsx"},{"name":"MetricCard","sourcePath":"components/data-display/MetricCard.jsx"},{"name":"Alert","sourcePath":"components/feedback/Alert.jsx"},{"name":"EmptyState","sourcePath":"components/feedback/EmptyState.jsx"},{"name":"Menu","sourcePath":"components/feedback/Menu.jsx"},{"name":"Checkbox","sourcePath":"components/forms/Checkbox.jsx"},{"name":"Field","sourcePath":"components/forms/Field.jsx"},{"name":"Input","sourcePath":"components/forms/Input.jsx"},{"name":"SearchInput","sourcePath":"components/forms/SearchInput.jsx"},{"name":"Select","sourcePath":"components/forms/Select.jsx"},{"name":"Switch","sourcePath":"components/forms/Switch.jsx"},{"name":"Textarea","sourcePath":"components/forms/Textarea.jsx"},{"name":"NavLink","sourcePath":"components/navigation/NavLink.jsx"},{"name":"Tabs","sourcePath":"components/navigation/Tabs.jsx"}],"sourceHashes":{"components/actions/Button.jsx":"38ed1d5e77b9","components/actions/IconButton.jsx":"0b90058381cc","components/data-display/Avatar.jsx":"8b96e6820b0e","components/data-display/Badge.jsx":"c17416706687","components/data-display/Card.jsx":"1a1ade93d713","components/data-display/ContextPin.jsx":"04387c1c5314","components/data-display/LeadLabelChip.jsx":"a8af40f1525f","components/data-display/MetricCard.jsx":"11662382a135","components/feedback/Alert.jsx":"84aef69e3555","components/feedback/EmptyState.jsx":"df2057f6cd9f","components/feedback/Menu.jsx":"6c2188bfc7c3","components/forms/Checkbox.jsx":"2e8734d4a4af","components/forms/Field.jsx":"594b98f3ea35","components/forms/Input.jsx":"c4fbb811df60","components/forms/SearchInput.jsx":"6bfbf760ee77","components/forms/Select.jsx":"e37a3388011e","components/forms/Switch.jsx":"79bb5ff852a2","components/forms/Textarea.jsx":"d045a2b57f2a","components/navigation/NavLink.jsx":"cf7d06f9e26d","components/navigation/Tabs.jsx":"6d953dc59a37","redesign/distribution-rules-new/app.js":"47feefb37aec","redesign/habitations-new/app.js":"efca6455b256","ui_kits/admin-crm/App.jsx":"1568712960e6","ui_kits/admin-crm/DashboardScreen.jsx":"a77f963a9665","ui_kits/admin-crm/DisparosScreen.jsx":"268096dd25a4","ui_kits/admin-crm/ImoveisScreen.jsx":"8289e1c953b9","ui_kits/admin-crm/ImovelFormScreen.jsx":"39049da39be7","ui_kits/admin-crm/LeadDetailScreen.jsx":"f7bf6e3dd7c6","ui_kits/admin-crm/LeadsScreen.jsx":"8f5b8bcfe0ad","ui_kits/admin-crm/TemplatesScreen.jsx":"3cc3689140ee","ui_kits/admin-crm/WhatsAppScreen.jsx":"c23882971b82"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.UnitymobDesignSystem_2a309d = window.UnitymobDesignSystem_2a309d || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/actions/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Button — the platform's primary action control.
 * Thin wrapper over the shipped `.ax-btn` classes (30px tall, 6px radius,
 * weight 750). Icons are Bootstrap Icons class names (e.g. "plus-lg").
 */
function Button({
  children,
  variant = "default",
  size = "md",
  icon,
  iconRight,
  block = false,
  disabled = false,
  as = "button",
  className = "",
  ...rest
}) {
  const cls = ["ax-btn", variant !== "default" && `ax-btn--${variant}`, size === "sm" && "ax-btn--sm", block && "ax-btn--block", className].filter(Boolean).join(" ");
  const Tag = as;
  return /*#__PURE__*/React.createElement(Tag, _extends({
    className: cls,
    disabled: Tag === "button" ? disabled : undefined,
    "aria-disabled": disabled || undefined
  }, rest), icon && /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${icon}`,
    "aria-hidden": "true"
  }), children && /*#__PURE__*/React.createElement("span", null, children), iconRight && /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${iconRight}`,
    "aria-hidden": "true"
  }));
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/actions/Button.jsx", error: String((e && e.message) || e) }); }

// components/actions/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * IconButton — square, icon-only control. Two flavours:
 * `bare` (transparent, hover fill) for toolbars, and `outlined`
 * (bordered white) for standalone actions. Always pass an aria-label.
 */
function IconButton({
  icon,
  variant = "bare",
  className = "",
  label,
  ...rest
}) {
  const cls = [variant === "bare" ? "ax-ico-btn" : "ax-btn ax-btn--icon", className].filter(Boolean).join(" ");
  return /*#__PURE__*/React.createElement("button", _extends({
    className: cls,
    "aria-label": label,
    title: label
  }, rest), /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${icon}`,
    "aria-hidden": "true"
  }));
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/actions/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/data-display/Avatar.jsx
try { (() => {
/** Avatar — circular initials/icon chip (`.ax-avatar`). */
function Avatar({
  initials,
  icon,
  size = 30,
  className = "",
  style
}) {
  return /*#__PURE__*/React.createElement("span", {
    className: `ax-avatar ${className}`.trim(),
    style: {
      width: size,
      height: size,
      ...style
    }
  }, icon ? /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${icon}`,
    "aria-hidden": "true"
  }) : initials);
}
Object.assign(__ds_scope, { Avatar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data-display/Avatar.jsx", error: String((e && e.message) || e) }); }

// components/data-display/Badge.jsx
try { (() => {
/**
 * Badge — compact status pill (`.ax-badge`). `tone` maps to the semantic
 * palette; `dot` prepends a small status dot.
 */
function Badge({
  children,
  tone = "gray",
  dot = false,
  className = ""
}) {
  const cls = ["ax-badge", `ax-badge--${tone}`, dot && "ax-badge--dot", className].filter(Boolean).join(" ");
  return /*#__PURE__*/React.createElement("span", {
    className: cls
  }, children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data-display/Badge.jsx", error: String((e && e.message) || e) }); }

// components/data-display/Card.jsx
try { (() => {
/**
 * Card — the base surface panel (`.ax-card`). Optional header with title,
 * eyebrow and a right-aligned actions slot; body holds arbitrary content.
 */
function Card({
  title,
  eyebrow,
  actions,
  children,
  bodyStyle,
  className = ""
}) {
  return /*#__PURE__*/React.createElement("section", {
    className: `ax-card ${className}`.trim()
  }, (title || actions) && /*#__PURE__*/React.createElement("header", {
    className: "ax-card__header"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      minWidth: 0
    }
  }, eyebrow && /*#__PURE__*/React.createElement("span", {
    className: "ax-eyebrow"
  }, eyebrow), title && /*#__PURE__*/React.createElement("div", {
    className: "ax-card__title"
  }, title)), actions && /*#__PURE__*/React.createElement("div", {
    style: {
      marginLeft: "auto",
      display: "inline-flex",
      gap: 6
    }
  }, actions)), /*#__PURE__*/React.createElement("div", {
    className: "ax-card__body",
    style: bodyStyle
  }, children));
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data-display/Card.jsx", error: String((e && e.message) || e) }); }

// components/data-display/ContextPin.jsx
try { (() => {
/**
 * ContextPin — the entity chip shown in the navbar context bar. Left border
 * carries the entity accent; `type` picks it. Icon + truncated label.
 */
function ContextPin({
  type = "property",
  icon,
  children,
  onRemove,
  className = ""
}) {
  const defaultIcon = {
    property: "house-door",
    owner: "person-vcard",
    lead: "person-badge",
    proposal: "file-earmark-text",
    whatsapp: "whatsapp"
  }[type];
  return /*#__PURE__*/React.createElement("span", {
    className: `ax-context-pin ax-context-pin--${type} ${className}`.trim()
  }, /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${icon || defaultIcon}`,
    "aria-hidden": "true"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      overflow: "hidden",
      textOverflow: "ellipsis",
      whiteSpace: "nowrap"
    }
  }, children), onRemove && /*#__PURE__*/React.createElement("button", {
    onClick: onRemove,
    "aria-label": "Remover",
    style: {
      border: 0,
      background: "transparent",
      color: "#7b8797",
      cursor: "pointer",
      marginLeft: 2,
      display: "inline-flex"
    }
  }, /*#__PURE__*/React.createElement("i", {
    className: "bi bi-x"
  })));
}
Object.assign(__ds_scope, { ContextPin });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data-display/ContextPin.jsx", error: String((e && e.message) || e) }); }

// components/data-display/LeadLabelChip.jsx
try { (() => {
/** LeadLabelChip — small tag used on leads/conversations (`.lead-label-chip`). */
function LeadLabelChip({
  children,
  color = "blue",
  className = ""
}) {
  return /*#__PURE__*/React.createElement("span", {
    className: `lead-label-chip lead-label-chip--${color} ${className}`.trim()
  }, children);
}
Object.assign(__ds_scope, { LeadLabelChip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data-display/LeadLabelChip.jsx", error: String((e && e.message) || e) }); }

// components/data-display/MetricCard.jsx
try { (() => {
/**
 * MetricCard — KPI tile used across the dashboard. Shows an uppercase
 * label, a large tabular value, an optional badge and hint line, and an
 * optional progress bar.
 */
function MetricCard({
  label,
  value,
  badge,
  hint,
  progress,
  className = ""
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: `ax-card ${className}`.trim(),
    style: {
      padding: "14px 16px",
      display: "grid",
      gap: 6
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: "flex",
      alignItems: "center",
      justifyContent: "space-between",
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "ax-stat-label"
  }, label), badge), /*#__PURE__*/React.createElement("span", {
    className: "ax-stat-value ax-num"
  }, value), typeof progress === "number" && /*#__PURE__*/React.createElement("div", {
    className: "ax-progress",
    style: {
      marginTop: 2
    }
  }, /*#__PURE__*/React.createElement("i", {
    style: {
      width: `${Math.max(0, Math.min(100, progress))}%`
    }
  })), hint && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--text-sm)",
      color: "var(--ink-muted)"
    }
  }, hint));
}
Object.assign(__ds_scope, { MetricCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/data-display/MetricCard.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Alert.jsx
try { (() => {
/**
 * Alert — inline message block (`.ax-alert`). `tone` sets the color;
 * `icon` is a Bootstrap Icons name. Title + free-form children.
 */
function Alert({
  tone = "default",
  icon,
  title,
  children,
  actions,
  className = ""
}) {
  const cls = ["ax-alert", tone !== "default" && `ax-alert--${tone}`, className].filter(Boolean).join(" ");
  const defaultIcon = {
    danger: "exclamation-octagon",
    warning: "exclamation-triangle",
    success: "check-circle",
    default: "info-circle"
  }[tone];
  return /*#__PURE__*/React.createElement("div", {
    className: cls,
    role: "alert"
  }, /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${icon || defaultIcon}`,
    style: {
      fontSize: 16,
      flex: "none",
      marginTop: 1
    },
    "aria-hidden": "true"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      minWidth: 0,
      flex: 1
    }
  }, title && /*#__PURE__*/React.createElement("div", {
    className: "ax-alert__title"
  }, title), children && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: "var(--text-base)",
      marginTop: title ? 3 : 0
    }
  }, children)), actions && /*#__PURE__*/React.createElement("div", {
    style: {
      display: "inline-flex",
      gap: 6,
      marginLeft: "auto"
    }
  }, actions));
}
Object.assign(__ds_scope, { Alert });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Alert.jsx", error: String((e && e.message) || e) }); }

// components/feedback/EmptyState.jsx
try { (() => {
/** EmptyState — centered placeholder for empty lists/panels (`.ax-empty`). */
function EmptyState({
  icon = "inbox",
  title,
  children,
  action,
  className = ""
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: `ax-empty ${className}`.trim()
  }, /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${icon}`,
    style: {
      fontSize: 28,
      color: "var(--ink-faint)",
      display: "block",
      marginBottom: 8
    },
    "aria-hidden": "true"
  }), title && /*#__PURE__*/React.createElement("div", {
    style: {
      color: "var(--ink)",
      fontWeight: 700,
      marginBottom: 4
    }
  }, title), children && /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 340,
      margin: "0 auto"
    }
  }, children), action && /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 12
    }
  }, action));
}
Object.assign(__ds_scope, { EmptyState });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/EmptyState.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Menu.jsx
try { (() => {
/**
 * Menu — floating action menu (`.ax-menu`). Renders a list of items; each
 * item accepts an icon, label, danger flag and onClick. Separators via
 * `{ separator: true }`.
 */
function Menu({
  items = [],
  className = "",
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: `ax-menu ${className}`.trim(),
    role: "menu",
    style: style
  }, items.map((it, i) => it.separator ? /*#__PURE__*/React.createElement("div", {
    key: i,
    className: "ax-menu__sep"
  }) : /*#__PURE__*/React.createElement("button", {
    key: i,
    role: "menuitem",
    className: `ax-menu__item ${it.danger ? "ax-menu__item--danger" : ""}`.trim(),
    onClick: it.onClick
  }, it.icon && /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${it.icon}`,
    "aria-hidden": "true"
  }), /*#__PURE__*/React.createElement("span", null, it.label))));
}
Object.assign(__ds_scope, { Menu });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Menu.jsx", error: String((e && e.message) || e) }); }

// components/forms/Checkbox.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Checkbox — 15px accent-colored checkbox with an optional label (`.ax-check`). */
function Checkbox({
  label,
  className = "",
  ...rest
}) {
  return /*#__PURE__*/React.createElement("label", {
    className: `ax-check ${className}`.trim()
  }, /*#__PURE__*/React.createElement("input", _extends({
    type: "checkbox"
  }, rest)), label && /*#__PURE__*/React.createElement("span", null, label));
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/forms/Field.jsx
try { (() => {
/**
 * Field — label + control wrapper. Renders an `.ax-label` above its
 * children with optional hint and required marker. Compose with Input,
 * Select, Textarea, etc.
 */
function Field({
  label,
  htmlFor,
  required = false,
  hint,
  children,
  className = ""
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: className,
    style: {
      display: "grid",
      gap: 3
    }
  }, label && /*#__PURE__*/React.createElement("label", {
    className: "ax-label",
    htmlFor: htmlFor
  }, label, required && /*#__PURE__*/React.createElement("span", {
    style: {
      color: "var(--danger)",
      marginLeft: 3
    }
  }, "*")), children, hint && /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: "var(--text-sm)",
      color: "var(--ink-muted)"
    }
  }, hint));
}
Object.assign(__ds_scope, { Field });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Field.jsx", error: String((e && e.message) || e) }); }

// components/forms/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Input — standard 34px text field (`.ax-input`). */
function Input({
  className = "",
  ...rest
}) {
  return /*#__PURE__*/React.createElement("input", _extends({
    className: `ax-input ${className}`.trim()
  }, rest));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Input.jsx", error: String((e && e.message) || e) }); }

// components/forms/SearchInput.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** SearchInput — 34px field with a leading magnifier (`.ax-search`). */
function SearchInput({
  className = "",
  placeholder = "Buscar…",
  ...rest
}) {
  return /*#__PURE__*/React.createElement("input", _extends({
    type: "search",
    className: `ax-search ${className}`.trim(),
    placeholder: placeholder
  }, rest));
}
Object.assign(__ds_scope, { SearchInput });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/SearchInput.jsx", error: String((e && e.message) || e) }); }

// components/forms/Select.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Select — native select styled with a custom chevron (`.ax-select`). */
function Select({
  className = "",
  children,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("select", _extends({
    className: `ax-select ${className}`.trim()
  }, rest), children);
}
Object.assign(__ds_scope, { Select });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Select.jsx", error: String((e && e.message) || e) }); }

// components/forms/Switch.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * Switch — pill toggle (`.ax-switch`). Controlled via `checked`/`onChange`.
 * Track turns primary when on; 34×20 with a 14px thumb.
 */
function Switch({
  label,
  className = "",
  ...rest
}) {
  return /*#__PURE__*/React.createElement("label", {
    className: `ax-switch ${className}`.trim()
  }, /*#__PURE__*/React.createElement("input", _extends({
    type: "checkbox"
  }, rest)), /*#__PURE__*/React.createElement("span", {
    className: "ax-switch__track",
    "aria-hidden": "true"
  }), label && /*#__PURE__*/React.createElement("span", null, label));
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Switch.jsx", error: String((e && e.message) || e) }); }

// components/forms/Textarea.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/** Textarea — multi-line field (`.ax-textarea`), vertically resizable. */
function Textarea({
  className = "",
  rows = 4,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("textarea", _extends({
    className: `ax-textarea ${className}`.trim(),
    rows: rows
  }, rest));
}
Object.assign(__ds_scope, { Textarea });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Textarea.jsx", error: String((e && e.message) || e) }); }

// components/navigation/NavLink.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/**
 * NavLink — a sidebar navigation row (`.ax-nav__link`). Icon + label, with
 * an `active` state (left primary bar). Renders as <a> by default.
 */
function NavLink({
  icon,
  children,
  active = false,
  as = "a",
  className = "",
  ...rest
}) {
  const Tag = as;
  return /*#__PURE__*/React.createElement(Tag, _extends({
    className: `ax-nav__link ${active ? "active" : ""} ${className}`.trim(),
    "aria-current": active ? "page" : undefined
  }, rest), icon && /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${icon}`,
    "aria-hidden": "true"
  }), /*#__PURE__*/React.createElement("span", null, children));
}
Object.assign(__ds_scope, { NavLink });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/NavLink.jsx", error: String((e && e.message) || e) }); }

// components/navigation/Tabs.jsx
try { (() => {
/**
 * Tabs — segmented control (`.ax-tabs`). Controlled: pass `value`, `tabs`
 * (array of {value,label,icon}) and `onChange`.
 */
function Tabs({
  tabs = [],
  value,
  onChange,
  className = ""
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: `ax-tabs ${className}`.trim(),
    role: "tablist"
  }, tabs.map(t => /*#__PURE__*/React.createElement("button", {
    key: t.value,
    role: "tab",
    "aria-selected": t.value === value,
    className: `ax-tab ${t.value === value ? "is-active" : ""}`.trim(),
    onClick: () => onChange && onChange(t.value)
  }, t.icon && /*#__PURE__*/React.createElement("i", {
    className: `bi bi-${t.icon}`,
    style: {
      marginRight: 6
    },
    "aria-hidden": "true"
  }), t.label)));
}
Object.assign(__ds_scope, { Tabs });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/Tabs.jsx", error: String((e && e.message) || e) }); }

// redesign/distribution-rules-new/app.js
try { (() => {
/* ============================================================
   Redesign — Nova regra de distribuição — dinâmicas simuladas
   Vanilla JS reproducing the Stimulus behaviors of the real screen:
   distribution-rule, team-rules, meta-rules, ax-aside, ax-modal.
   ============================================================ */

/* ---------- Fake data (stands in for @all_agents, @meta_structure, Store.active) ---------- */
const AGENTS = [{
  id: 1,
  name: "Ana Beatriz Souza",
  email: "ana.souza@imob.com"
}, {
  id: 2,
  name: "Carlos Mendes",
  email: "carlos.mendes@imob.com"
}, {
  id: 3,
  name: "Débora Lima",
  email: "debora.lima@imob.com"
}, {
  id: 4,
  name: "Eduardo Rocha",
  email: "eduardo.rocha@imob.com"
}, {
  id: 5,
  name: "Fernanda Alves",
  email: "fernanda.alves@imob.com"
}, {
  id: 6,
  name: "Gustavo Pereira",
  email: "gustavo.pereira@imob.com"
}];
const META_PAGES = [{
  id: "p1",
  name: "Imobiliária Zona Sul"
}, {
  id: "p2",
  name: "Lançamentos Premium"
}, {
  id: "p3",
  name: "Aluguel Rápido"
}];
const META_FORMS = {
  p1: [{
    id: "f1",
    name: "Formulário — Apartamentos"
  }, {
    id: "f2",
    name: "Formulário — Casas"
  }],
  p2: [{
    id: "f3",
    name: "Interesse — Lançamento Marina"
  }, {
    id: "f4",
    name: "VIP — Cobertura"
  }],
  p3: [{
    id: "f5",
    name: "Locação — 2 quartos"
  }]
};
const STORES = [{
  id: "s1",
  name: "Loja Centro"
}, {
  id: "s2",
  name: "Loja Zona Sul"
}, {
  id: "s3",
  name: "Loja Norte"
}];
const DAY_LABELS = {
  mon: "Segunda",
  tue: "Terça",
  wed: "Quarta",
  thu: "Quinta",
  fri: "Sexta",
  sat: "Sábado",
  sun: "Domingo"
};

/* ============================================================
   Toggle chips — reflect checkbox state + optional section control
   ============================================================ */
function initToggles() {
  document.querySelectorAll("[data-toggle]").forEach(chip => {
    const input = chip.querySelector('input[type="checkbox"]');
    const sync = () => chip.classList.toggle("is-checked", input.checked);
    sync();
    chip.addEventListener("click", e => {
      if (e.target.closest("a")) return;
      e.preventDefault();
      if (chip.classList.contains("is-disabled")) return;

      // Channel guard: block activating an unconfigured channel
      if (chip.dataset.channel && chip.dataset.configured === "false" && !input.checked) {
        openChannelModal(chip);
        return;
      }
      input.checked = !input.checked;
      sync();

      // Controls a collapsible section
      const target = chip.dataset.controls;
      if (target) {
        const el = document.getElementById(target);
        if (el) el.classList.toggle("hidden", !input.checked);
      }
      // Meta "Conectado" badge
      if (chip.dataset.summary === "meta") {
        document.getElementById("metaBadge").classList.toggle("hidden", !input.checked);
      }
      // Clear webhook error when re-enabling
      if (chip.dataset.controls === "notifyWebhookSection" && input.checked) {
        document.getElementById("notifyWebhookError").classList.add("hidden");
      }
      updateSummary();
    });
  });
}

/* ============================================================
   Multiselect (tom-select simulation)
   ============================================================ */
class MultiSelect {
  constructor(wrap, opts) {
    this.wrap = wrap;
    this.options = opts.options || [];
    this.creatable = opts.creatable || false;
    this.placeholder = opts.placeholder || "Selecione...";
    this.onChange = opts.onChange || (() => {});
    this.selected = [];
    this.render();
    this.menuOpen = false;
  }
  setOptions(options) {
    this.options = options;
    // drop selected no longer valid
    this.selected = this.selected.filter(s => options.find(o => o.id === s.id) || this.creatable);
    this.render();
    this.onChange(this.selected);
  }
  render() {
    this.wrap.innerHTML = "";
    const box = document.createElement("div");
    box.className = "multiselect";
    this.selected.forEach(item => {
      const tag = document.createElement("span");
      tag.className = "ms-tag";
      tag.innerHTML = `<span>${item.name}</span>`;
      const x = document.createElement("button");
      x.type = "button";
      x.innerHTML = '<i class="bi bi-x"></i>';
      x.addEventListener("click", e => {
        e.stopPropagation();
        this.remove(item.id);
      });
      tag.appendChild(x);
      box.appendChild(tag);
    });
    const input = document.createElement("input");
    input.className = "ms-input";
    input.placeholder = this.selected.length ? "" : this.placeholder;
    this.input = input;
    box.appendChild(input);
    this.wrap.appendChild(box);
    box.addEventListener("click", () => {
      input.focus();
      this.openMenu();
    });
    input.addEventListener("focus", () => this.openMenu());
    input.addEventListener("input", () => this.openMenu());
    input.addEventListener("keydown", e => {
      if (e.key === "Enter" && this.creatable && input.value.trim()) {
        e.preventDefault();
        this.add({
          id: input.value.trim(),
          name: input.value.trim()
        });
        input.value = "";
      }
      if (e.key === "Backspace" && !input.value && this.selected.length) {
        this.remove(this.selected[this.selected.length - 1].id);
      }
    });
    document.addEventListener("click", e => {
      if (!this.wrap.contains(e.target)) this.closeMenu();
    });
  }
  openMenu() {
    this.closeMenu();
    const q = (this.input.value || "").toLowerCase();
    const avail = this.options.filter(o => !this.selected.find(s => s.id === o.id) && o.name.toLowerCase().includes(q));
    const menu = document.createElement("div");
    menu.className = "ms-menu";
    if (!avail.length && !(this.creatable && this.input.value.trim())) {
      const empty = document.createElement("div");
      empty.className = "ms-option is-empty";
      empty.textContent = this.options.length ? "Nenhuma opção" : "Selecione uma página primeiro";
      menu.appendChild(empty);
    }
    avail.forEach(o => {
      const opt = document.createElement("div");
      opt.className = "ms-option";
      opt.textContent = o.name;
      opt.addEventListener("click", e => {
        e.stopPropagation();
        this.add(o);
        this.input.value = "";
        this.input.focus();
      });
      menu.appendChild(opt);
    });
    if (this.creatable && this.input.value.trim() && !avail.find(o => o.name === this.input.value.trim())) {
      const opt = document.createElement("div");
      opt.className = "ms-option";
      opt.innerHTML = `<i class="bi bi-plus-lg"></i> Adicionar "${this.input.value.trim()}"`;
      opt.addEventListener("click", e => {
        e.stopPropagation();
        this.add({
          id: this.input.value.trim(),
          name: this.input.value.trim()
        });
        this.input.value = "";
        this.input.focus();
      });
      menu.appendChild(opt);
    }
    this.wrap.appendChild(menu);
    this.menu = menu;
  }
  closeMenu() {
    if (this.menu) {
      this.menu.remove();
      this.menu = null;
    }
  }
  add(item) {
    if (this.selected.find(s => s.id === item.id)) return;
    this.selected.push(item);
    this.render();
    this.closeMenu();
    this.onChange(this.selected);
  }
  remove(id) {
    this.selected = this.selected.filter(s => s.id !== id);
    this.render();
    this.onChange(this.selected);
  }
}

/* ============================================================
   Team queue — add/remove/reorder agents, mode-driven fields
   ============================================================ */
const AgentQueue = {
  items: [],
  // {id, name, email, weight, el}
  listEl: null,
  init() {
    this.listEl = document.getElementById("agentList");
  },
  sync() {
    const list = this.listEl;
    list.innerHTML = "";
    if (!this.items.length) {
      list.classList.add("is-empty");
      const empty = document.createElement("div");
      empty.className = "agent-empty";
      empty.textContent = "Nenhum corretor na fila. Adicione acima para montar a distribuição.";
      list.appendChild(empty);
    } else {
      list.classList.remove("is-empty");
      this.items.forEach((it, idx) => list.appendChild(this.row(it, idx)));
    }
    document.getElementById("agentCount").textContent = this.items.length;
    applyMode(currentMode());
    updateSummary();
  },
  row(it, idx) {
    const initial = it.name.trim().charAt(0).toUpperCase();
    const row = document.createElement("div");
    row.className = "agent-item";
    row.draggable = true;
    row.dataset.id = it.id;
    row.innerHTML = `
      <span class="agent__handle" title="Arrastar para reordenar"><i class="bi bi-grip-vertical"></i></span>
      <span class="agent__avatar">${initial}</span>
      <div class="agent__main"><strong>${it.name}</strong><span>${it.email}</span></div>
      <div class="agent__actions">
        <div class="performance-field agent__weight hidden">
          <div class="input-group">
            <span class="input-group__affix">Ciclos</span>
            <input type="number" min="1" value="${it.weight || 1}" class="ax-control ax-control--sm">
          </div>
        </div>
        <div class="rotary-field hidden"><span class="badge-pos">#${idx + 1}</span></div>
        <button type="button" class="ax-ico-btn" title="Remover"><i class="bi bi-trash"></i></button>
      </div>`;
    row.querySelector(".ax-ico-btn").addEventListener("click", () => this.remove(it.id));
    row.querySelector('input[type="number"]')?.addEventListener("input", e => {
      it.weight = parseInt(e.target.value) || 1;
    });
    this.wireDrag(row);
    return row;
  },
  wireDrag(row) {
    row.addEventListener("dragstart", e => {
      row.classList.add("dragging");
      e.dataTransfer.effectAllowed = "move";
    });
    row.addEventListener("dragend", () => {
      row.classList.remove("dragging");
      this.readOrder();
    });
    row.addEventListener("dragover", e => {
      e.preventDefault();
      const dragging = this.listEl.querySelector(".dragging");
      if (!dragging || dragging === row) return;
      const rect = row.getBoundingClientRect();
      const after = e.clientY > rect.top + rect.height / 2;
      this.listEl.insertBefore(dragging, after ? row.nextSibling : row);
    });
  },
  readOrder() {
    const ids = [...this.listEl.querySelectorAll(".agent-item")].map(r => r.dataset.id);
    this.items.sort((a, b) => ids.indexOf(String(a.id)) - ids.indexOf(String(b.id)));
    this.sync();
  },
  setFromSelection(selected) {
    // preserve existing (weights/order), add new, drop removed
    const keep = this.items.filter(it => selected.find(s => String(s.id) === String(it.id)));
    selected.forEach(s => {
      if (!keep.find(it => String(it.id) === String(s.id))) {
        keep.push({
          id: s.id,
          name: s.name,
          email: s.email || "",
          weight: 1
        });
      }
    });
    this.items = keep;
    this.sync();
  },
  remove(id) {
    this.items = this.items.filter(it => String(it.id) !== String(id));
    // reflect back in the select
    agentSelect.selected = agentSelect.selected.filter(s => String(s.id) !== String(id));
    agentSelect.render();
    this.sync();
  }
};

/* ============================================================
   Distribution mode
   ============================================================ */
function currentMode() {
  return document.querySelector('input[name="mode"]:checked')?.value || "rotary";
}
function applyMode(mode) {
  document.querySelectorAll(".performance-field").forEach(el => el.classList.toggle("hidden", mode !== "performance"));
  document.querySelectorAll(".rotary-field").forEach(el => el.classList.toggle("hidden", mode !== "rotary"));
}
function initModes() {
  document.querySelectorAll(".mode-card").forEach(card => {
    card.addEventListener("click", e => {
      if (e.target.closest(".mode-info")) return;
      const input = card.querySelector("input");
      input.checked = true;
      document.querySelectorAll(".mode-card").forEach(c => c.classList.toggle("is-selected", c === card));
      applyMode(input.value);
      updateSummary();
    });
  });
}

/* ============================================================
   Modals + channel guard
   ============================================================ */
function openModal(id) {
  document.getElementById(id)?.classList.add("is-open");
}
function closeModal(el) {
  el.closest(".modal-overlay")?.classList.remove("is-open");
}
function openChannelModal(chip) {
  document.getElementById("channelModalName").textContent = chip.dataset.channelLabel || "este canal";
  document.getElementById("channelModalInstructions").textContent = chip.dataset.configInstructions || "";
  document.getElementById("channelModalLink").href = chip.dataset.configPath || "#";
  openModal("channelModal");
}
function initModals() {
  document.querySelectorAll("[data-open-modal]").forEach(b => b.addEventListener("click", () => openModal(b.dataset.openModal)));
  document.querySelectorAll("[data-close-modal]").forEach(b => b.addEventListener("click", () => closeModal(b)));
  document.querySelectorAll(".modal-overlay").forEach(o => o.addEventListener("click", e => {
    if (e.target === o) o.classList.remove("is-open");
  }));
  document.addEventListener("keydown", e => {
    if (e.key === "Escape") document.querySelectorAll(".modal-overlay.is-open").forEach(o => o.classList.remove("is-open"));
  });
}

/* ============================================================
   Aside collapse
   ============================================================ */
function initAside() {
  document.querySelectorAll("[data-aside-toggle]").forEach(b => b.addEventListener("click", () => document.getElementById("workspace").classList.toggle("aside-collapsed")));
}

/* ============================================================
   Submit validation (channel guard + webhook URL required)
   ============================================================ */
function initSubmit() {
  document.getElementById("saveBtn").addEventListener("click", () => {
    // guarded channels
    for (const chip of document.querySelectorAll("[data-channel]")) {
      const input = chip.querySelector("input");
      if (input.checked && chip.dataset.configured !== "true") {
        openChannelModal(chip);
        return;
      }
    }
    // webhook URLs required
    const webhookChip = [...document.querySelectorAll("[data-controls='notifyWebhookSection']")][0];
    const webhookOn = webhookChip?.querySelector("input").checked;
    if (webhookOn && notifyUrlsSelect.selected.length === 0) {
      document.getElementById("notifyWebhookSection").classList.remove("hidden");
      document.getElementById("notifyWebhookError").classList.remove("hidden");
      document.getElementById("notifyWebhookError").scrollIntoView({
        behavior: "smooth",
        block: "center"
      });
      return;
    }
    // success feedback (demo)
    const btn = document.getElementById("saveBtn");
    const orig = btn.innerHTML;
    btn.innerHTML = '<i class="bi bi-check-circle"></i><span>Regra válida ✓</span>';
    setTimeout(() => btn.innerHTML = orig, 1600);
  });
}

/* ============================================================
   Schedule table
   ============================================================ */
function initSchedule() {
  const body = document.getElementById("scheduleBody");
  Object.entries(DAY_LABELS).forEach(([day, label]) => {
    const weekend = day === "sat" || day === "sun";
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td class="day">${label}</td>
      <td class="num"><input type="checkbox" ${weekend ? "" : "checked"}></td>
      <td><input type="time" value="09:00" class="ax-control ax-control--sm"></td>
      <td><input type="time" value="18:00" class="ax-control ax-control--sm"></td>`;
    body.appendChild(tr);
  });
}

/* ============================================================
   Live summary (product-grade improvement)
   ============================================================ */
let agentSelect, notifyUrlsSelect;
function updateSummary() {
  const modeLabels = {
    rotary: "fila rotativa",
    performance: "sorteio por performance",
    shark_tank: "shark tank (primeiro a aceitar)"
  };
  const sources = [];
  if (isOn("meta")) sources.push("Meta Ads");
  if (isOn("webhook")) sources.push("Webhooks");
  if (isOn("site")) sources.push("Site");
  if (isOn("portal")) sources.push("Portais");
  const n = AgentQueue.items.length;
  const line = document.getElementById("summaryLine");
  const srcTxt = sources.length ? `<b>${sources.join(", ")}</b>` : "<b>nenhuma origem</b>";
  const agentTxt = n ? `<b>${n} corretor${n > 1 ? "es" : ""}</b>` : "<b>sem corretores</b>";
  line.innerHTML = `Leads de ${srcTxt} → ${agentTxt} em <b>${modeLabels[currentMode()]}</b>.`;
  const chips = document.getElementById("summaryChips");
  chips.innerHTML = "";
  const addChip = (icon, txt, on = true) => {
    const c = document.createElement("span");
    c.className = "summary-chip" + (on ? "" : " off");
    c.innerHTML = `<i class="bi bi-${icon}"></i> ${txt}`;
    chips.appendChild(c);
  };
  addChip("whatsapp", "WhatsApp", isChannelOn("whatsapp"));
  addChip("clock-history", isOn("represamento") ? "Bolsão ativo" : "Sem bolsão", isOn("represamento"));
  addChip("hourglass-split", isOn("pocket") ? "Pocket" : "Sem tempo limite", isOn("pocket"));
}
function isOn(summary) {
  if (summary === "represamento") return !document.getElementById("represamentoSection").classList.contains("hidden");
  if (summary === "pocket") return !document.getElementById("pocketSection").classList.contains("hidden");
  const chip = document.querySelector(`[data-summary="${summary}"]`);
  return chip ? chip.querySelector("input").checked : false;
}
function isChannelOn(ch) {
  const chip = document.querySelector(`[data-channel="${ch}"]`);
  return chip ? chip.querySelector("input").checked : false;
}

/* ============================================================
   Boot
   ============================================================ */
document.addEventListener("DOMContentLoaded", () => {
  initToggles();
  initModes();
  initModals();
  initAside();
  initSchedule();
  initSubmit();
  AgentQueue.init();

  // Multiselects
  new MultiSelect(document.querySelector('[data-multiselect="tags"]'), {
    creatable: true,
    placeholder: "Digite uma tag e tecle Enter",
    onChange: updateSummary
  });
  new MultiSelect(document.querySelector('[data-multiselect="stores"]'), {
    options: STORES,
    placeholder: "Selecione lojas (vazio = todas)"
  });
  notifyUrlsSelect = new MultiSelect(document.querySelector('[data-multiselect="notifyUrls"]'), {
    creatable: true,
    placeholder: "https://... e Enter"
  });

  // Meta pages → forms dependency
  const formsSelect = new MultiSelect(document.querySelector('[data-multiselect="forms"]'), {
    options: [],
    placeholder: "Selecione uma página primeiro",
    onChange: sel => {
      const label = document.getElementById("formCount");
      label.innerHTML = sel.length ? `<strong>${sel.length}</strong> formulário${sel.length > 1 ? "s" : ""} selecionado${sel.length > 1 ? "s" : ""}` : "Nenhum formulário selecionado";
    }
  });
  new MultiSelect(document.querySelector('[data-multiselect="pages"]'), {
    options: META_PAGES,
    placeholder: "Selecione páginas Meta",
    onChange: sel => {
      const forms = sel.flatMap(p => META_FORMS[p.id] || []);
      formsSelect.setOptions(forms);
      document.getElementById("formCount").innerHTML = forms.length ? "Nenhum formulário selecionado" : "Selecione uma página primeiro";
    }
  });

  // Agents → queue
  agentSelect = new MultiSelect(document.querySelector('[data-multiselect="agents"]'), {
    options: AGENTS.map(a => ({
      id: a.id,
      name: a.name,
      email: a.email
    })),
    placeholder: "Buscar corretor...",
    onChange: sel => AgentQueue.setFromSelection(sel)
  });
  updateSummary();
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "redesign/distribution-rules-new/app.js", error: String((e && e.message) || e) }); }

// redesign/habitations-new/app.js
try { (() => {
/* ============================================================
   Redesign — Cadastro de imóvel — dinâmicas simuladas
   Reproduz os comportamentos do habitation-form Stimulus + afins:
   tabs, tipo→categoria, status→suspensão, empreendimento→autofill,
   CEP, calculadora de aluguel, chips, máscaras, attribute-manager.
   ============================================================ */

/* ---------- Data ---------- */
const CATEGORIES = {
  apartamentos: ["Apartamento", "Cobertura", "Loft", "Studio"],
  comerciais_industriais: ["Sala Comercial", "Loja", "Prédio Comercial", "Galpão", "Galpão Industrial", "Área", "Casa comercial", "Ponto Comercial"],
  empreendimento: ["Empreendimento"],
  imoveis_residenciais: ["Casa", "Casa em Condomínio", "Sobrado", "Rural", "Condomínio", "Chácara", "Sítio"],
  terrenos: ["Terreno", "Terreno em Condomínio", "Área", "Terreno Comercial", "Terreno Industrial"]
};
const DEVELOPMENTS = {
  "EMP-1001": {
    nome: "Residencial Marina",
    proprietor: "3",
    captador: "10",
    delivery: "2026-12-01",
    profile: "Alto padrão",
    address: {
      streetType: "Avenida",
      street: "Av. Beira Mar",
      number: "1500",
      uf: "SC",
      zip: "88015-700",
      neighborhood: "Centro",
      city: "São Paulo"
    }
  },
  "EMP-1002": {
    nome: "Edifício Aurora",
    proprietor: "2",
    captador: "11",
    delivery: "2025-06-15",
    profile: "Médio padrão",
    address: {
      streetType: "Rua",
      street: "Rua das Flores",
      number: "320",
      uf: "SP",
      zip: "01310-100",
      neighborhood: "Jardins",
      city: "São Paulo"
    }
  },
  "EMP-1003": {
    nome: "Condomínio Vista Verde",
    proprietor: "1",
    captador: "10",
    delivery: "2027-03-01",
    profile: "Econômico",
    address: {
      streetType: "Rua",
      street: "Rua Verde",
      number: "45",
      uf: "MG",
      zip: "30140-071",
      neighborhood: "Vila Nova",
      city: "Belo Horizonte"
    }
  }
};
const FEATURES = ["Ar condicionado", "Armários planejados", "Closet", "Cozinha americana", "Despensa", "Escritório", "Lareira", "Lavabo", "Mobiliado", "Piso porcelanato", "Sacada gourmet", "Varanda"];
const INFRA = ["Piscina", "Academia", "Salão de festas", "Playground", "Churrasqueira", "Quadra esportiva", "Sauna", "Espaço gourmet", "Portaria 24h", "Elevador", "Gerador", "Bicicletário"];
const BADGES = ["Vista para o mar", "Reformado", "Pronto para morar", "Aceita pet", "Andar alto", "Documentação ok", "Oportunidade"];
const CEP_DB = {
  seed: {
    streetType: "Avenida",
    street: "Av. Paulista",
    number: "",
    uf: "SP",
    neighborhood: "Centro",
    city: "São Paulo"
  }
};
const TABS = [{
  id: "general",
  icon: "house-door",
  label: "Base",
  desc: "Identificação, vínculo e endereço"
}, {
  id: "features",
  icon: "rulers",
  label: "Estrutura",
  desc: "Dimensões e atributos"
}, {
  id: "infra",
  icon: "building",
  label: "Empreendimento",
  desc: "Edifício e lazer"
}, {
  id: "comercial",
  icon: "briefcase",
  label: "Comercial",
  desc: "Valores, negociação e contatos"
}, {
  id: "seo",
  icon: "globe2",
  label: "Publicação",
  desc: "Site, portais e SEO"
}, {
  id: "media",
  icon: "images",
  label: "Mídia",
  desc: "Fotos, vídeos e tour"
}, {
  id: "documents",
  icon: "folder2",
  label: "Documentos",
  desc: "Fichas e autorizações"
}];
// completion state (simulated): general & features start "success", seo warning until Site flag on
const tabState = {
  general: "success",
  features: "success",
  infra: "neutral",
  comercial: "neutral",
  seo: "warning",
  media: "neutral",
  documents: "neutral"
};
// pending-validation counts per tab (red sinalizador badge). Cleared as fields are filled.
const tabErrors = {
  general: 0,
  features: 0,
  infra: 0,
  comercial: 2,
  seo: 0,
  media: 0,
  documents: 0
};

/* ---------- Tabs ---------- */
let activeTab = "general";
function buildTabs() {
  const nav = document.getElementById("tabsNav");
  const rail = document.getElementById("asideRail");
  nav.innerHTML = "";
  rail.innerHTML = "";
  TABS.forEach(t => {
    const err = tabErrors[t.id] || 0;
    const tone = err > 0 ? "danger" : tabState[t.id];
    let ind;
    if (err > 0) ind = `<span class="tab-error" title="${err} campo(s) com pendência">${err}</span>`;else if (tone === "success") ind = `<i class="bi bi-check-circle-fill tabs-nav__ind tabs-nav__ind--success" title="Completo"></i>`;else if (tone === "warning") ind = `<i class="bi bi-exclamation-circle-fill tabs-nav__ind tabs-nav__ind--warning" title="Atenção"></i>`;else ind = `<span class="tabs-nav__ind--neutral" title="Vazio"></span>`;
    const btn = document.createElement("button");
    btn.className = "tabs-nav__item" + (t.id === activeTab ? " active" : "");
    btn.innerHTML = `
      <span class="tabs-nav__icon"><i class="bi bi-${t.icon}"></i></span>
      <span class="tabs-nav__copy"><strong>${t.label}</strong><span>${t.desc}</span></span>
      <span class="tabs-nav__status">${ind}</span>`;
    btn.addEventListener("click", () => showTab(t.id));
    nav.appendChild(btn);
    const r = document.createElement("button");
    r.className = "aside-rail__item" + (t.id === activeTab ? " active" : "");
    r.title = t.label + (err > 0 ? ` — ${err} pendência(s)` : "");
    r.innerHTML = `<i class="bi bi-${t.icon}"></i>${err > 0 ? `<span class="tab-error">${err}</span>` : ""}`;
    r.addEventListener("click", () => showTab(t.id));
    rail.appendChild(r);
  });
  updateProgress();
}
function showTab(id) {
  activeTab = id;
  document.querySelectorAll(".tab-pane").forEach(p => p.classList.toggle("active", p.id === `tab-${id}`));
  buildTabs();
  document.querySelector(".workspace-main").scrollTo?.({
    top: 0
  });
  window.scrollTo({
    top: 0,
    behavior: "smooth"
  });
}
function updateProgress() {
  const done = TABS.filter(t => tabState[t.id] === "success").length;
  document.getElementById("progCount").textContent = done;
  document.getElementById("progBar").style.width = Math.round(done / TABS.length * 100) + "%";
}

/* ---------- Aside collapse (right editor) + explorer (left) ---------- */
document.getElementById("asideToggle").addEventListener("click", () => document.getElementById("editorAside").classList.toggle("collapsed"));
document.getElementById("explorerToggle").addEventListener("click", () => document.getElementById("explorer").classList.toggle("collapsed"));

/* ---------- Toggle chips ---------- */
function initToggles() {
  document.querySelectorAll("[data-toggle]").forEach(chip => {
    const input = chip.querySelector('input[type="checkbox"]');
    const sync = () => chip.classList.toggle("is-checked", input.checked);
    sync();
    chip.addEventListener("click", e => {
      e.preventDefault();
      if (chip.classList.contains("is-disabled")) return;
      input.checked = !input.checked;
      sync();
      // "Site" flag → seo tab success
      if (chip.querySelector("span:last-child")?.textContent.trim() === "Site") {
        tabState.seo = input.checked ? "success" : "warning";
        buildTabs();
      }
      // portal toggle → expand sub
      if (chip.hasAttribute("data-portal-toggle")) {
        chip.closest("[data-portal]").classList.toggle("is-on", input.checked);
      }
    });
  });
}

/* ---------- Collapsible sections ---------- */
function initSections() {
  document.querySelectorAll("[data-section-toggle]").forEach(head => {
    head.addEventListener("click", e => {
      if (e.target.closest("[data-toggle]") || e.target.closest("button")) return;
      head.closest("[data-section]").classList.toggle("is-collapsed");
    });
  });
}

/* ---------- Cadastro type → categoria + tipo + unitOnly + label ---------- */
function fillCategories(typeKey, keepValue) {
  const sel = document.getElementById("categorySelect");
  const cats = CATEGORIES[typeKey] || [];
  const cur = keepValue ? sel.value : null;
  sel.innerHTML = '<option value="">Selecione...</option>';
  cats.forEach(c => {
    const o = new Option(c, c);
    sel.add(o);
  });
  if (typeKey === "empreendimento") sel.value = "Empreendimento";else if (cur && cats.includes(cur)) sel.value = cur;
}
function applyCadastroType() {
  const typeKey = document.querySelector('input[name="cadastro_type"]:checked').value;
  fillCategories(typeKey, true);
  // unitOnly fields hidden for empreendimento
  const isEmp = typeKey === "empreendimento";
  document.querySelectorAll("[data-unit-only]").forEach(el => el.classList.toggle("hidden", isEmp));
  document.getElementById("devNameLabel").textContent = isEmp ? "Nome do empreendimento" : "Nome do condomínio";
}
function initCadastroType() {
  document.getElementById("cadastroType").addEventListener("change", applyCadastroType);
  fillCategories("apartamentos");
}

/* ---------- Status → suspension reason ---------- */
function initStatus() {
  const sel = document.getElementById("statusSelect");
  sel.addEventListener("change", () => {
    const norm = sel.value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().toLowerCase();
    document.getElementById("suspensionField").classList.toggle("hidden", norm !== "suspenso");
  });
}

/* ---------- Development → autofill ---------- */
function initDevelopment() {
  const sel = document.getElementById("developmentSelect");
  sel.addEventListener("change", () => {
    const code = sel.value;
    const data = DEVELOPMENTS[code];
    const nameField = document.getElementById("developmentName");
    const notice = document.getElementById("devLinkNotice");
    if (!code || !data) {
      nameField.readOnly = false;
      notice.classList.add("hidden");
      return;
    }
    nameField.value = data.nome;
    nameField.readOnly = true;
    notice.classList.remove("hidden");
    notice.querySelector("span").innerHTML = `Vínculo ativo: <strong>${data.nome}</strong>`;
    setVal("proprietorSelect", data.proprietor);
    setVal("captadorSelect", data.captador);
    setVal("deliveryDate", data.delivery);
    setVal("constructionProfile", data.profile);
    // address (only when blank)
    fillAddress(data.address, true);
  });
}
function setVal(id, v) {
  const el = document.getElementById(id);
  if (el && v != null) el.value = v;
}
function fillAddress(addr, onlyBlank) {
  const map = {
    streetType: "streetType",
    street: "street",
    number: "streetNumber",
    uf: "stateSelect",
    zip: "zipCode",
    neighborhood: "neighborhood",
    city: "citySelect"
  };
  Object.entries(map).forEach(([k, id]) => {
    const el = document.getElementById(id);
    if (!el || addr[k] == null) return;
    if (onlyBlank && String(el.value || "").trim() !== "") return;
    // add option if select doesn't have it
    if (el.tagName === "SELECT" && !Array.from(el.options).some(o => o.value === addr[k])) el.add(new Option(addr[k], addr[k]));
    el.value = addr[k];
  });
}

/* ---------- CEP search (simulated) ---------- */
function initCep() {
  document.getElementById("cepSearch").addEventListener("click", () => {
    const btn = document.getElementById("cepSearch");
    const orig = btn.innerHTML;
    btn.innerHTML = '<i class="bi bi-arrow-repeat"></i>';
    setTimeout(() => {
      fillAddress(CEP_DB.seed, false);
      btn.innerHTML = '<i class="bi bi-check2"></i>';
      setTimeout(() => btn.innerHTML = orig, 900);
    }, 600);
  });
}

/* ---------- Rent calculator ---------- */
function parseCurrency(v) {
  return parseFloat((v || "").replace(/\./g, "").replace(",", ".")) || 0;
}
function fmtCurrency(n) {
  return n.toLocaleString("pt-BR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  });
}
function initRentCalc() {
  const scope = document.querySelector("[data-rent-calc]");
  if (!scope) return;
  const total = document.querySelector('[data-rent="total"]');
  const calc = () => {
    const rent = parseCurrency(scope.querySelector('[data-rent="rent"]').value);
    const condo = parseCurrency(scope.querySelector('[data-rent="condo"]').value);
    const iptu = parseCurrency(scope.querySelector('[data-rent="iptu"]').value);
    total.value = fmtCurrency(rent + condo + iptu);
  };
  scope.querySelectorAll('[data-rent="rent"],[data-rent="condo"],[data-rent="iptu"]').forEach(el => el.addEventListener("input", calc));
}

/* ---------- Currency & phone masks ---------- */
function initMasks() {
  document.querySelectorAll('[data-mask="currency"]').forEach(el => {
    el.addEventListener("input", () => {
      let digits = el.value.replace(/\D/g, "");
      if (!digits) {
        el.value = "";
        return;
      }
      const n = parseInt(digits, 10) / 100;
      el.value = fmtCurrency(n);
    });
  });
  document.querySelectorAll('[data-mask="phone"]').forEach(el => {
    el.addEventListener("input", () => {
      let d = el.value.replace(/\D/g, "").slice(0, 11);
      if (d.length > 6) el.value = `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;else if (d.length > 2) el.value = `(${d.slice(0, 2)}) ${d.slice(2)}`;else el.value = d;
    });
  });
  document.querySelectorAll('[data-mask="cep"]').forEach(el => {
    el.addEventListener("input", () => {
      let d = el.value.replace(/\D/g, "").slice(0, 8);
      el.value = d.length > 5 ? `${d.slice(0, 5)}-${d.slice(5)}` : d;
    });
  });
}

/* ---------- Chip grids (features / infra) ---------- */
const chipData = {
  featuresGrid: [...FEATURES],
  infraGrid: [...INFRA]
};
const chipSelected = {
  featuresGrid: new Set(),
  infraGrid: new Set()
};
function renderChipGrid(id) {
  const grid = document.getElementById(id);
  grid.innerHTML = "";
  chipData[id].forEach(item => {
    const label = document.createElement("label");
    label.className = "chip-card" + (chipSelected[id].has(item) ? " is-checked" : "");
    label.innerHTML = `<input type="checkbox" ${chipSelected[id].has(item) ? "checked" : ""}><span title="${item}">${item}</span>`;
    label.addEventListener("click", e => {
      e.preventDefault();
      if (chipSelected[id].has(item)) chipSelected[id].delete(item);else chipSelected[id].add(item);
      renderChipGrid(id);
    });
    grid.appendChild(label);
  });
}

/* ---------- Multiselect ---------- */
class MultiSelect {
  constructor(wrap, opts) {
    this.wrap = wrap;
    this.options = opts.options || [];
    this.creatable = opts.creatable || false;
    this.placeholder = opts.placeholder || "Selecione...";
    this.selected = [];
    this.render();
  }
  setOptions(o) {
    this.options = o;
    this.render();
  }
  render() {
    this.wrap.innerHTML = "";
    const box = document.createElement("div");
    box.className = "multiselect";
    this.selected.forEach(item => {
      const tag = document.createElement("span");
      tag.className = "ms-tag";
      tag.innerHTML = `<span>${item}</span>`;
      const x = document.createElement("button");
      x.type = "button";
      x.innerHTML = '<i class="bi bi-x"></i>';
      x.addEventListener("click", e => {
        e.stopPropagation();
        this.remove(item);
      });
      tag.appendChild(x);
      box.appendChild(tag);
    });
    const input = document.createElement("input");
    input.className = "ms-input";
    input.placeholder = this.selected.length ? "" : this.placeholder;
    this.input = input;
    box.appendChild(input);
    this.wrap.appendChild(box);
    box.addEventListener("click", () => {
      input.focus();
      this.openMenu();
    });
    input.addEventListener("focus", () => this.openMenu());
    input.addEventListener("input", () => this.openMenu());
    input.addEventListener("keydown", e => {
      if (e.key === "Enter" && this.creatable && input.value.trim()) {
        e.preventDefault();
        this.add(input.value.trim());
        input.value = "";
      }
      if (e.key === "Backspace" && !input.value && this.selected.length) this.remove(this.selected[this.selected.length - 1]);
    });
    document.addEventListener("click", e => {
      if (!this.wrap.contains(e.target)) this.closeMenu();
    });
  }
  openMenu() {
    this.closeMenu();
    const q = (this.input.value || "").toLowerCase();
    const avail = this.options.filter(o => !this.selected.includes(o) && o.toLowerCase().includes(q));
    const menu = document.createElement("div");
    menu.className = "ms-menu";
    if (!avail.length && !(this.creatable && this.input.value.trim())) {
      const e = document.createElement("div");
      e.className = "ms-option is-empty";
      e.textContent = "Nenhuma opção";
      menu.appendChild(e);
    }
    avail.forEach(o => {
      const opt = document.createElement("div");
      opt.className = "ms-option";
      opt.textContent = o;
      opt.addEventListener("click", e => {
        e.stopPropagation();
        this.add(o);
        this.input.value = "";
        this.input.focus();
      });
      menu.appendChild(opt);
    });
    if (this.creatable && this.input.value.trim() && !avail.includes(this.input.value.trim())) {
      const opt = document.createElement("div");
      opt.className = "ms-option";
      opt.innerHTML = `<i class="bi bi-plus-lg"></i> Adicionar "${this.input.value.trim()}"`;
      opt.addEventListener("click", e => {
        e.stopPropagation();
        this.add(this.input.value.trim());
        this.input.value = "";
        this.input.focus();
      });
      menu.appendChild(opt);
    }
    this.wrap.appendChild(menu);
    this.menu = menu;
  }
  closeMenu() {
    if (this.menu) {
      this.menu.remove();
      this.menu = null;
    }
  }
  add(item) {
    if (!this.selected.includes(item)) {
      this.selected.push(item);
      this.render();
      this.closeMenu();
    }
  }
  remove(item) {
    this.selected = this.selected.filter(s => s !== item);
    this.render();
  }
}
const msRegistry = {};

/* ---------- Radio pill groups (portais) ---------- */
function initRadios() {
  document.querySelectorAll("[data-radio]").forEach(row => {
    row.querySelectorAll(".radio-pill").forEach(pill => {
      pill.addEventListener("click", () => {
        row.querySelectorAll(".radio-pill").forEach(p => p.classList.remove("is-active"));
        pill.classList.add("is-active");
      });
    });
  });
}

/* ---------- Modals ---------- */
function initModals() {
  document.querySelectorAll("[data-open-modal]").forEach(b => b.addEventListener("click", () => document.getElementById(b.dataset.openModal).classList.add("is-open")));
  document.querySelectorAll("[data-close-modal]").forEach(b => b.addEventListener("click", () => b.closest(".modal-overlay").classList.remove("is-open")));
  document.querySelectorAll(".modal-overlay").forEach(o => o.addEventListener("click", e => {
    if (e.target === o) o.classList.remove("is-open");
  }));
  document.addEventListener("keydown", e => {
    if (e.key === "Escape") document.querySelectorAll(".modal-overlay.is-open").forEach(o => o.classList.remove("is-open"));
  });
}

/* ---------- Attribute manager (chip grids + multiselects) ---------- */
let attrCtx = null;
function initAttrManager() {
  document.querySelectorAll("[data-attr-manager]").forEach(btn => {
    btn.addEventListener("click", () => {
      const title = btn.dataset.attrManager;
      document.getElementById("attrModalTitle").textContent = "Gerenciar " + title;
      if (btn.dataset.target) attrCtx = {
        kind: "chip",
        key: btn.dataset.target
      };else if (btn.dataset.multiselectTarget) attrCtx = {
        kind: "ms",
        key: btn.dataset.multiselectTarget
      };
      renderAttrList();
      document.getElementById("attrModal").classList.add("is-open");
    });
  });
  document.getElementById("attrAdd").addEventListener("click", addAttr);
  document.getElementById("attrInput").addEventListener("keydown", e => {
    if (e.key === "Enter") {
      e.preventDefault();
      addAttr();
    }
  });
}
function currentAttrItems() {
  if (attrCtx.kind === "chip") return chipData[attrCtx.key];
  return msRegistry[attrCtx.key].options;
}
function renderAttrList() {
  const list = document.getElementById("attrList");
  list.innerHTML = "";
  currentAttrItems().forEach((item, i) => {
    const li = document.createElement("li");
    li.className = "attr-item";
    li.innerHTML = `<span>${item}</span>`;
    const del = document.createElement("button");
    del.className = "ax-btn ax-btn--ghost ax-btn--sm ax-text-danger";
    del.innerHTML = '<i class="bi bi-trash"></i>';
    del.addEventListener("click", () => {
      currentAttrItems().splice(i, 1);
      syncAttr();
      renderAttrList();
    });
    li.appendChild(del);
    list.appendChild(li);
  });
}
function addAttr() {
  const input = document.getElementById("attrInput");
  const v = input.value.trim();
  if (!v || currentAttrItems().includes(v)) return;
  currentAttrItems().push(v);
  input.value = "";
  syncAttr();
  renderAttrList();
}
function syncAttr() {
  if (attrCtx.kind === "chip") renderChipGrid(attrCtx.key);else msRegistry[attrCtx.key].setOptions(msRegistry[attrCtx.key].options);
}

/* ---------- Save button ---------- */
document.getElementById("saveBtn").addEventListener("click", () => {
  const btn = document.getElementById("saveBtn");
  const orig = btn.innerHTML;
  btn.innerHTML = '<i class="bi bi-check-circle"></i><span>Salvo ✓</span>';
  setTimeout(() => btn.innerHTML = orig, 1600);
});

/* ---------- Boot ---------- */
document.addEventListener("DOMContentLoaded", () => {
  buildTabs();
  initToggles();
  initSections();
  initCadastroType();
  applyCadastroType();
  initStatus();
  initDevelopment();
  initCep();
  initRentCalc();
  initMasks();
  initRadios();
  initModals();
  renderChipGrid("featuresGrid");
  renderChipGrid("infraGrid");
  msRegistry.imediacoes = new MultiSelect(document.querySelector('[data-multiselect="imediacoes"]'), {
    options: ["Próximo ao metrô", "Perto de escola", "Área comercial", "Praça", "Parque"],
    creatable: true,
    placeholder: "Selecione ou digite..."
  });
  msRegistry.badges = new MultiSelect(document.querySelector('[data-multiselect="badges"]'), {
    options: [...BADGES],
    placeholder: "Selecione..."
  });
  msRegistry.keywords = new MultiSelect(document.querySelector('[data-multiselect="keywords"]'), {
    creatable: true,
    placeholder: "Digite e Enter..."
  });
  initAttrManager();
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "redesign/habitations-new/app.js", error: String((e && e.message) || e) }); }

// ui_kits/admin-crm/App.jsx
try { (() => {
// Admin CRM shell — navbar + sidebar + context bar + screen router.
const UM = window.UnitymobDesignSystem_2a309d;
window.UM_SCREENS = window.UM_SCREENS || {};
if (window.UM_SCREENS.whatsapp) window.UM_SCREENS.wa_atendimento = window.UM_SCREENS.whatsapp;
const NAV = [{
  section: "Produto"
}, {
  id: "dashboard",
  icon: "speedometer2",
  label: "Painel"
}, {
  id: "imoveis",
  icon: "houses",
  label: "Imóveis"
}, {
  id: "leads",
  icon: "person-badge",
  label: "Leads"
}, {
  section: "Operação"
}, {
  id: "whatsapp",
  icon: "whatsapp",
  label: "WhatsApp",
  children: [{
    id: "wa_atendimento",
    icon: "chat-dots",
    label: "Atendimento"
  }, {
    id: "wa_templates",
    icon: "grid-3x2-gap",
    label: "Templates"
  }, {
    id: "wa_disparos",
    icon: "broadcast",
    label: "Disparos"
  }]
}, {
  id: "automacao",
  icon: "lightning-charge",
  label: "Automação"
}, {
  id: "distribuicao",
  icon: "diagram-3",
  label: "Distribuição de Leads"
}, {
  id: "captacoes",
  icon: "journal-plus",
  label: "Captações"
}, {
  section: "Gestão"
}, {
  id: "proprietarios",
  icon: "person-vcard",
  label: "Proprietários"
}, {
  id: "lojas",
  icon: "shop",
  label: "Lojas"
}, {
  id: "usuarios",
  icon: "people",
  label: "Usuários"
}, {
  section: "Crescimento"
}, {
  id: "marketing",
  icon: "megaphone",
  label: "Marketing"
}];
const CONTEXT = {
  dashboard: {
    crumb: ["Painel"],
    title: "Painel",
    eyebrow: "Cockpit operacional"
  },
  imoveis: {
    crumb: ["Imóveis"],
    title: "Imóveis"
  },
  imovel_form: {
    crumb: ["Imóveis", "Novo imóvel"],
    title: "Imóveis"
  },
  leads: {
    crumb: ["Comercial", "Funil de Leads"],
    title: "Leads"
  },
  lead_detail: {
    crumb: ["Comercial", "Funil de Leads", "Detalhe"],
    title: "Leads"
  },
  whatsapp: {
    crumb: ["WhatsApp", "Atendimento"],
    title: "WhatsApp"
  },
  wa_atendimento: {
    crumb: ["WhatsApp", "Atendimento"],
    title: "WhatsApp"
  },
  wa_templates: {
    crumb: ["WhatsApp", "Templates"],
    title: "Templates"
  },
  wa_disparos: {
    crumb: ["WhatsApp", "Disparos"],
    title: "Disparos"
  },
  automacao: {
    crumb: ["Automação"],
    title: "Automação"
  },
  distribuicao: {
    crumb: ["Distribuição de Leads"],
    title: "Distribuição"
  },
  captacoes: {
    crumb: ["Captações"],
    title: "Captações"
  },
  proprietarios: {
    crumb: ["Proprietários"],
    title: "Proprietários"
  },
  lojas: {
    crumb: ["Lojas"],
    title: "Lojas"
  },
  usuarios: {
    crumb: ["Usuários"],
    title: "Usuários"
  },
  marketing: {
    crumb: ["Marketing"],
    title: "Marketing"
  }
};
function NavGroup({
  item,
  current,
  onNavigate
}) {
  const childActive = item.children.some(c => c.id === current);
  const [open, setOpen] = React.useState(childActive);
  React.useEffect(() => {
    if (childActive) setOpen(true);
  }, [childActive]);
  return /*#__PURE__*/React.createElement("li", null, /*#__PURE__*/React.createElement(UM.NavLink, {
    as: "button",
    icon: item.icon,
    active: childActive,
    onClick: () => setOpen(o => !o),
    style: {
      width: "100%"
    }
  }, item.label, /*#__PURE__*/React.createElement("i", {
    className: "bi bi-chevron-down",
    style: {
      marginLeft: 8,
      fontSize: 10,
      opacity: 0.6,
      transition: "transform .15s",
      transform: open ? "rotate(180deg)" : "none"
    }
  })), open && /*#__PURE__*/React.createElement("ul", {
    style: {
      listStyle: "none",
      margin: "1px 0 3px",
      padding: 0
    }
  }, item.children.map(c => /*#__PURE__*/React.createElement("li", {
    key: c.id
  }, /*#__PURE__*/React.createElement(UM.NavLink, {
    as: "button",
    icon: c.icon,
    active: current === c.id,
    onClick: () => onNavigate(c.id),
    style: {
      width: "100%",
      paddingLeft: 30
    }
  }, c.label)))));
}
function Sidebar({
  current,
  onNavigate
}) {
  return /*#__PURE__*/React.createElement("aside", {
    className: "ax-sidebar"
  }, /*#__PURE__*/React.createElement("ul", {
    className: "ax-nav"
  }, NAV.map((item, i) => item.section ? /*#__PURE__*/React.createElement("li", {
    key: i,
    className: "ax-nav__section"
  }, item.section) : item.children ? /*#__PURE__*/React.createElement(NavGroup, {
    key: item.id,
    item: item,
    current: current,
    onNavigate: onNavigate
  }) : /*#__PURE__*/React.createElement("li", {
    key: item.id
  }, /*#__PURE__*/React.createElement(UM.NavLink, {
    as: "button",
    icon: item.icon,
    active: current === item.id,
    onClick: () => onNavigate(item.id),
    style: {
      width: "100%"
    }
  }, item.label)))));
}
function Navbar() {
  return /*#__PURE__*/React.createElement("nav", {
    className: "ax-navbar"
  }, /*#__PURE__*/React.createElement("a", {
    className: "ax-navbar__brand",
    href: "#"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ax-navbar__brand-mark"
  }, /*#__PURE__*/React.createElement("svg", {
    viewBox: "0 0 100 100",
    width: "19",
    height: "19",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "11",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M22 56 L50 33 L78 56"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M31 73 L50 58 L69 73",
    opacity: "0.5"
  }))), /*#__PURE__*/React.createElement("span", {
    className: "ax-navbar__brand-text"
  }, "Unitymob ", /*#__PURE__*/React.createElement("span", null, "Plataforma"))), /*#__PURE__*/React.createElement("div", {
    className: "ax-navbar__spacer"
  }), /*#__PURE__*/React.createElement("div", {
    className: "ax-navbar__search"
  }, /*#__PURE__*/React.createElement("i", {
    className: "bi bi-search",
    style: {
      fontSize: 13
    }
  }), /*#__PURE__*/React.createElement("input", {
    placeholder: "Buscar im\xF3veis, leads, c\xF3digo\u2026"
  })), /*#__PURE__*/React.createElement("a", {
    className: "ax-navbar__primary"
  }, /*#__PURE__*/React.createElement("i", {
    className: "bi bi-plus-lg"
  }), " Novo"), /*#__PURE__*/React.createElement("button", {
    className: "ax-navbar__user-trigger"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ax-avatar",
    style: {
      width: 22,
      height: 22,
      fontSize: 12
    }
  }, "MC"), /*#__PURE__*/React.createElement("span", null, "Marina Costa"), /*#__PURE__*/React.createElement("i", {
    className: "bi bi-chevron-down",
    style: {
      fontSize: 11,
      color: "var(--ink-faint)"
    }
  })));
}
function ContextBar({
  current,
  pins
}) {
  const ctx = CONTEXT[current] || {
    crumb: [current]
  };
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    className: "ax-sidebar-contextbar"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ax-contextbar__title"
  }, /*#__PURE__*/React.createElement("i", {
    className: "bi bi-layout-sidebar"
  }), /*#__PURE__*/React.createElement("span", null, "Explorer")), /*#__PURE__*/React.createElement("button", {
    className: "ax-ico-btn",
    "aria-label": "Recolher"
  }, /*#__PURE__*/React.createElement("i", {
    className: "bi bi-arrow-bar-left"
  }))), /*#__PURE__*/React.createElement("div", {
    className: "ax-contextbar"
  }, /*#__PURE__*/React.createElement("nav", {
    className: "ax-breadcrumb"
  }, /*#__PURE__*/React.createElement("i", {
    className: "bi bi-house-door"
  }), ctx.crumb.map((c, i) => /*#__PURE__*/React.createElement(React.Fragment, {
    key: i
  }, /*#__PURE__*/React.createElement("i", {
    className: "bi bi-chevron-right"
  }), i === ctx.crumb.length - 1 ? /*#__PURE__*/React.createElement("strong", null, c) : /*#__PURE__*/React.createElement("a", {
    href: "#"
  }, c)))), pins && pins.length > 0 && /*#__PURE__*/React.createElement("div", {
    className: "ax-contextbar__pins"
  }, pins.map((p, i) => /*#__PURE__*/React.createElement(UM.ContextPin, {
    key: i,
    type: p.type
  }, p.label))), /*#__PURE__*/React.createElement("div", {
    className: "ax-contextbar__actions"
  }, /*#__PURE__*/React.createElement(UM.Button, {
    size: "sm",
    icon: "funnel"
  }, "Filtros"), /*#__PURE__*/React.createElement(UM.Button, {
    size: "sm",
    variant: "primary",
    icon: "plus-lg"
  }, "Novo"))));
}
function App() {
  const [current, setCurrent] = React.useState("dashboard");
  window.UM_GO = setCurrent;
  const pins = [{
    type: "property",
    label: "Apto 302 · COD-84213"
  }, {
    type: "lead",
    label: "Marina Costa"
  }];
  const Screen = window.UM_SCREENS[current] || (() => /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement("div", {
    className: "ax-dashboard-command",
    style: {
      gridTemplateColumns: "minmax(0,1fr)"
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
    className: "ax-eyebrow"
  }, "M\xF3dulo"), /*#__PURE__*/React.createElement("h1", {
    style: {
      marginTop: 3
    }
  }, CONTEXT[current] && CONTEXT[current].title || current), /*#__PURE__*/React.createElement("p", null, "Tela representada no kit \u2014 selecione Painel, Im\xF3veis, Leads ou WhatsApp para os fluxos completos."))), /*#__PURE__*/React.createElement("div", {
    className: "ax-panel"
  }, /*#__PURE__*/React.createElement(UM.EmptyState, {
    icon: "grid-3x3-gap",
    title: "M\xF3dulo do CRM"
  }, "Este item da navega\xE7\xE3o existe na plataforma Unitymob. Os quatro fluxos principais est\xE3o detalhados neste kit."))));
  return /*#__PURE__*/React.createElement("div", {
    className: "ax-app"
  }, /*#__PURE__*/React.createElement(Navbar, null), /*#__PURE__*/React.createElement(ContextBar, {
    current: current,
    pins: pins
  }), /*#__PURE__*/React.createElement(Sidebar, {
    current: current,
    onNavigate: setCurrent
  }), /*#__PURE__*/React.createElement("main", {
    className: "ax-main"
  }, /*#__PURE__*/React.createElement(Screen, null)));
}
window.UM_App = App;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin-crm/App.jsx", error: String((e && e.message) || e) }); }

// ui_kits/admin-crm/DashboardScreen.jsx
try { (() => {
// Dashboard — operational cockpit.
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const bars = [42, 58, 51, 67, 60, 78, 71, 84, 76, 90, 82, 128];
  const funnel = [{
    label: "Novos",
    value: 128,
    tone: "blue",
    pct: 100
  }, {
    label: "Em atendimento",
    value: 74,
    tone: "cyan",
    pct: 58
  }, {
    label: "Visita agendada",
    value: 39,
    tone: "amber",
    pct: 30
  }, {
    label: "Proposta",
    value: 18,
    tone: "purple",
    pct: 14
  }, {
    label: "Fechado",
    value: 9,
    tone: "green",
    pct: 7
  }];
  const pend = [{
    icon: "file-earmark-text",
    label: "Captações em rascunho",
    count: 6,
    tone: "amber"
  }, {
    icon: "hourglass-split",
    label: "Leads represados",
    count: 9,
    tone: "red"
  }, {
    icon: "hand-index-thumb",
    label: "Pedidos manuais pendentes",
    count: 3,
    tone: "amber"
  }, {
    icon: "exclamation-triangle-fill",
    label: "Imóveis com erro de sync",
    count: 4,
    tone: "red"
  }];
  const brokers = [{
    name: "Rafael Menezes",
    loja: "Centro",
    val: 14
  }, {
    name: "Bianca Toledo",
    loja: "Zona Sul",
    val: 11
  }, {
    name: "Diego Farias",
    loja: "Centro",
    val: 9
  }, {
    name: "Camila Prado",
    loja: "Litoral",
    val: 7
  }];
  function Dashboard() {
    return /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement("header", {
      className: "ax-dashboard-command"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Cockpit operacional"), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 8,
        marginTop: 3
      }
    }, /*#__PURE__*/React.createElement("h1", null, "Boa tarde, Marina"), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "blue"
    }, "Admin")), /*#__PURE__*/React.createElement("p", null, "ter\xE7a-feira, 1 de julho \xB7 Campo ativo: 3 check-ins agora, 128 leads hoje.")), /*#__PURE__*/React.createElement("div", {
      className: "ax-dashboard-command__status"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-hdd-network"
    }), " Opera\xE7\xE3o"), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "green",
      dot: true
    }, "Campo ativo")), /*#__PURE__*/React.createElement("div", {
      className: "ax-dashboard-kpis"
    }, /*#__PURE__*/React.createElement(UM.MetricCard, {
      label: "Im\xF3veis no cat\xE1logo",
      value: "1.284",
      badge: /*#__PURE__*/React.createElement(UM.Badge, {
        tone: "green",
        dot: true
      }, "Ativos"),
      hint: "86 destaques \xB7 12 empreendimentos"
    }), /*#__PURE__*/React.createElement(UM.MetricCard, {
      label: "Leads hoje",
      value: "128",
      badge: /*#__PURE__*/React.createElement(UM.Badge, {
        tone: "gray"
      }, "+312 em 7d"),
      hint: "9 represados \xB7 22 novos"
    }), /*#__PURE__*/React.createElement(UM.MetricCard, {
      label: "Check-ins ativos",
      value: "3",
      badge: /*#__PURE__*/React.createElement(UM.Badge, {
        tone: "green",
        dot: true
      }, "Ao vivo"),
      hint: "18 hoje \xB7 1 suspeito"
    }), /*#__PURE__*/React.createElement(UM.MetricCard, {
      label: "Regras de distribui\xE7\xE3o",
      value: "8/12",
      badge: /*#__PURE__*/React.createElement(UM.Badge, {
        tone: "blue"
      }, "4 c/ check-in"),
      progress: 66
    })), /*#__PURE__*/React.createElement("div", {
      className: "ax-grid",
      style: {
        gridTemplateColumns: "minmax(0,1.6fr) minmax(0,1fr)",
        marginBottom: 12
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__head"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Aquisi\xE7\xE3o"), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__title"
    }, "Leads \u2014 \xFAltimos 30 dias")), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "green",
      dot: true
    }, "+18% vs. m\xEAs anterior")), /*#__PURE__*/React.createElement("div", {
      style: {
        padding: 16
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "flex-end",
        gap: 6,
        height: 168
      }
    }, bars.map((b, i) => /*#__PURE__*/React.createElement("div", {
      key: i,
      style: {
        flex: 1,
        height: `${b / 128 * 100}%`,
        background: i === bars.length - 1 ? "var(--primary)" : "var(--primary-soft)",
        borderRadius: "5px 5px 0 0",
        minHeight: 6
      },
      title: `${b} leads`
    }))))), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__head"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Funil"), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__title"
    }, "Convers\xE3o comercial"))), /*#__PURE__*/React.createElement("div", {
      style: {
        padding: "14px 16px",
        display: "grid",
        gap: 12
      }
    }, funnel.map(f => /*#__PURE__*/React.createElement("div", {
      key: f.label
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        justifyContent: "space-between",
        fontSize: 12.5,
        marginBottom: 4
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        color: "var(--ink-body)"
      }
    }, f.label), /*#__PURE__*/React.createElement("strong", {
      className: "ax-num",
      style: {
        color: "var(--ink)"
      }
    }, f.value)), /*#__PURE__*/React.createElement("div", {
      className: "ax-progress"
    }, /*#__PURE__*/React.createElement("i", {
      style: {
        width: `${f.pct}%`
      }
    }))))))), /*#__PURE__*/React.createElement("div", {
      className: "ax-grid",
      style: {
        gridTemplateColumns: "minmax(0,1fr) minmax(0,1.2fr)"
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__head"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Hoje"), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__title"
    }, "Pend\xEAncias")), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "amber"
    }, "4 pend.")), /*#__PURE__*/React.createElement("div", {
      style: {
        padding: 10,
        display: "grid",
        gap: 6
      }
    }, pend.map(p => /*#__PURE__*/React.createElement("a", {
      key: p.label,
      href: "#",
      style: {
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: 10,
        padding: "9px 10px",
        border: "1px solid var(--line)",
        borderRadius: 8,
        background: "var(--surface-soft)",
        color: "var(--ink-body)",
        fontSize: 12.5
      }
    }, /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("i", {
      className: `bi bi-${p.icon}`,
      style: {
        marginRight: 8,
        color: "var(--ink-muted)"
      }
    }), p.label), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: p.tone
    }, p.count))))), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__head"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Performance"), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__title"
    }, "Top corretores")), /*#__PURE__*/React.createElement("a", {
      href: "#",
      style: {
        fontSize: 12,
        color: "var(--primary)"
      }
    }, "Ver todos")), /*#__PURE__*/React.createElement("table", {
      className: "ax-table"
    }, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", null, /*#__PURE__*/React.createElement("th", null, "Corretor"), /*#__PURE__*/React.createElement("th", null, "Loja"), /*#__PURE__*/React.createElement("th", {
      style: {
        textAlign: "right"
      }
    }, "Fechados"))), /*#__PURE__*/React.createElement("tbody", null, brokers.map((b, i) => /*#__PURE__*/React.createElement("tr", {
      key: b.name
    }, /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("span", {
      style: {
        display: "inline-flex",
        alignItems: "center",
        gap: 8
      }
    }, /*#__PURE__*/React.createElement("span", {
      className: "ax-avatar",
      style: {
        width: 24,
        height: 24,
        fontSize: 11
      }
    }, b.name.split(" ").map(n => n[0]).slice(0, 2).join("")), /*#__PURE__*/React.createElement("span", {
      className: "ax-strong"
    }, b.name))), /*#__PURE__*/React.createElement("td", null, b.loja), /*#__PURE__*/React.createElement("td", {
      className: "ax-num",
      style: {
        textAlign: "right"
      }
    }, /*#__PURE__*/React.createElement("strong", {
      style: {
        color: "var(--ink)"
      }
    }, b.val)))))))));
  }
  window.UM_SCREENS.dashboard = Dashboard;
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin-crm/DashboardScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/admin-crm/DisparosScreen.jsx
try { (() => {
// WhatsApp — Disparos (campanhas por remetente).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const kpis = [{
    label: "Total",
    value: "4.270",
    hint: "no escopo filtrado",
    icon: "envelope",
    tone: "var(--gray)"
  }, {
    label: "Enviadas",
    value: "3.890",
    hint: "mensagens enviadas",
    icon: "send",
    tone: "var(--purple)"
  }, {
    label: "Falhas",
    value: "142",
    hint: "com falha",
    icon: "x-circle",
    tone: "var(--danger)"
  }, {
    label: "Respostas",
    value: "612",
    hint: "recebidas",
    icon: "chat-dots",
    tone: "var(--cyan)"
  }, {
    label: "Atendido",
    value: "418",
    hint: "fluxos atendidos",
    icon: "person-check",
    tone: "var(--success)"
  }, {
    label: "Não atendido",
    value: "194",
    hint: "sem atendimento",
    icon: "person-x",
    tone: "var(--info)"
  }, {
    label: "CPL",
    value: "R$ 3,80",
    hint: "custo por atendimento",
    icon: "calculator",
    tone: "var(--warning)"
  }, {
    label: "Gasto total",
    value: "R$ 14.782",
    hint: "estimativa do período",
    icon: "wallet2",
    tone: "var(--entity-whatsapp)"
  }];
  const camps = [{
    name: "Lançamento Praia Brava",
    desc: "Carrossel · 3 imóveis",
    status: {
      t: "Enviando",
      tone: "blue"
    },
    grupo: "Lançamentos",
    tpl: "lancamento_praia_brava",
    lang: "pt_BR",
    sent: 1240,
    total: 1800,
    by: "Rafael M.",
    date: "01/07"
  }, {
    name: "Reativação 60 dias",
    desc: "Base fria reengajada",
    status: {
      t: "Concluída",
      tone: "green"
    },
    grupo: "Reativação",
    tpl: "reativacao_60d",
    lang: "pt_BR",
    sent: 900,
    total: 900,
    by: "Bianca T.",
    date: "30/06"
  }, {
    name: "Feirão de Imóveis",
    desc: "Campanha de julho",
    status: {
      t: "Falha",
      tone: "red"
    },
    grupo: "Feirão",
    tpl: "feirao_julho",
    lang: "pt_BR",
    sent: 320,
    total: 500,
    by: "Diego F.",
    date: "29/06"
  }, {
    name: "Novos leads Moema",
    desc: "Boas-vindas automáticas",
    status: {
      t: "Agendada",
      tone: "gray"
    },
    grupo: "—",
    tpl: "boas_vindas_lead",
    lang: "pt_BR",
    sent: 0,
    total: 640,
    by: "Camila P.",
    date: "02/07"
  }, {
    name: "Pós-visita julho",
    desc: "Feedback pós-visita",
    status: {
      t: "Enviando",
      tone: "blue"
    },
    grupo: "Follow-up",
    tpl: "pos_visita_feedback",
    lang: "pt_BR",
    sent: 210,
    total: 430,
    by: "Rafael M.",
    date: "01/07"
  }];
  const fLabel = {
    display: "flex",
    flexDirection: "column",
    gap: 3,
    fontSize: 11,
    fontWeight: 600,
    color: "var(--ink-label)"
  };
  function Filter({
    label,
    opts
  }) {
    return /*#__PURE__*/React.createElement("label", {
      style: fLabel
    }, label, /*#__PURE__*/React.createElement("select", {
      className: "ax-input",
      style: {
        height: 34,
        minWidth: 130
      }
    }, opts.map(o => /*#__PURE__*/React.createElement("option", {
      key: o
    }, o))));
  }
  function Disparos() {
    return /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement("div", {
      className: "ax-dashboard-command",
      style: {
        gridTemplateColumns: "minmax(0,1fr) auto"
      }
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "WhatsApp"), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 8,
        marginTop: 3
      }
    }, /*#__PURE__*/React.createElement("h1", null, "Disparos"), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "green",
      dot: true
    }, "Conectado"), /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: "var(--font-mono)",
        fontSize: 12,
        color: "var(--ink-muted)"
      }
    }, "+55 47 99888-1020")), /*#__PURE__*/React.createElement("p", null, "Campanhas por remetente \xB7 volume, filtros comerciais e acompanhamento do envio.")), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "inline-flex",
        gap: 6
      }
    }, /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "grid-3x2-gap"
    }, "Templates"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "plus-lg"
    }, "Nova campanha"))), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gridTemplateColumns: "repeat(4,minmax(0,1fr))",
        gap: 12,
        marginBottom: 12
      }
    }, kpis.map(k => /*#__PURE__*/React.createElement("div", {
      key: k.label,
      className: "ax-panel",
      style: {
        padding: "13px 15px"
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        width: 27,
        height: 27,
        borderRadius: 7,
        background: "var(--surface-header)",
        display: "grid",
        placeItems: "center",
        color: k.tone,
        fontSize: 13
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: `bi bi-${k.icon}`
    })), /*#__PURE__*/React.createElement("div", {
      style: {
        fontSize: 11,
        fontWeight: 700,
        letterSpacing: ".03em",
        textTransform: "uppercase",
        color: "var(--ink-muted)",
        marginTop: 9
      }
    }, k.label), /*#__PURE__*/React.createElement("div", {
      className: "ax-num",
      style: {
        fontFamily: "var(--font-display)",
        fontWeight: 800,
        fontSize: 22,
        color: "var(--ink)",
        lineHeight: 1.1,
        marginTop: 2
      }
    }, k.value), /*#__PURE__*/React.createElement("div", {
      style: {
        fontSize: 11,
        color: "var(--ink-faint)",
        marginTop: 2
      }
    }, k.hint)))), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel",
      style: {
        marginBottom: 12
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "flex-end",
        gap: 10,
        padding: 12,
        flexWrap: "wrap"
      }
    }, /*#__PURE__*/React.createElement(Filter, {
      label: "Status",
      opts: ["Todas", "Enviando", "Concluída", "Agendada", "Falha"]
    }), /*#__PURE__*/React.createElement(Filter, {
      label: "Criada por",
      opts: ["Todos", "Rafael M.", "Bianca T.", "Diego F.", "Camila P."]
    }), /*#__PURE__*/React.createElement(Filter, {
      label: "Grupo",
      opts: ["Todos", "Lançamentos", "Reativação", "Feirão", "Follow-up"]
    }), /*#__PURE__*/React.createElement("label", {
      style: fLabel
    }, "Campanha", /*#__PURE__*/React.createElement("input", {
      className: "ax-input",
      style: {
        height: 34,
        minWidth: 160
      },
      placeholder: "Nome"
    })), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "funnel"
    }, "Filtrar"))), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__head"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "5 campanhas"), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__title"
    }, "Suas campanhas"))), /*#__PURE__*/React.createElement("table", {
      className: "ax-table"
    }, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", null, /*#__PURE__*/React.createElement("th", null, "Campanha"), /*#__PURE__*/React.createElement("th", null, "Status"), /*#__PURE__*/React.createElement("th", null, "Grupo"), /*#__PURE__*/React.createElement("th", null, "Template"), /*#__PURE__*/React.createElement("th", {
      style: {
        width: 170
      }
    }, "Progresso"), /*#__PURE__*/React.createElement("th", null, "Criada por"), /*#__PURE__*/React.createElement("th", null, "Data"))), /*#__PURE__*/React.createElement("tbody", null, camps.map(c => {
      const pct = c.total > 0 ? Math.round(c.sent / c.total * 100) : 0;
      return /*#__PURE__*/React.createElement("tr", {
        key: c.name
      }, /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("a", {
        href: "#",
        className: "ax-strong",
        style: {
          display: "block"
        }
      }, /*#__PURE__*/React.createElement("i", {
        className: "bi bi-megaphone",
        style: {
          marginRight: 6,
          color: "var(--ink-muted)"
        }
      }), c.name), /*#__PURE__*/React.createElement("span", {
        style: {
          fontSize: 11,
          color: "var(--ink-muted)"
        }
      }, c.desc)), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement(UM.Badge, {
        tone: c.status.tone,
        dot: c.status.t === "Enviando"
      }, c.status.t)), /*#__PURE__*/React.createElement("td", null, c.grupo), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("strong", {
        style: {
          color: "var(--ink)",
          fontSize: 12.5,
          fontFamily: "var(--font-mono)"
        }
      }, c.tpl), /*#__PURE__*/React.createElement("span", {
        style: {
          display: "block",
          fontSize: 11,
          color: "var(--ink-muted)"
        }
      }, c.lang)), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("div", {
        style: {
          display: "flex",
          justifyContent: "space-between",
          fontSize: 11.5,
          marginBottom: 3
        }
      }, /*#__PURE__*/React.createElement("span", {
        className: "ax-num",
        style: {
          color: "var(--ink-body)"
        }
      }, c.sent, " / ", c.total), /*#__PURE__*/React.createElement("strong", {
        className: "ax-num",
        style: {
          color: "var(--ink)"
        }
      }, pct, "%")), /*#__PURE__*/React.createElement("div", {
        className: "ax-progress"
      }, /*#__PURE__*/React.createElement("i", {
        style: {
          width: `${pct}%`
        }
      }))), /*#__PURE__*/React.createElement("td", null, c.by), /*#__PURE__*/React.createElement("td", {
        className: "ax-num"
      }, c.date));
    })))));
  }
  window.UM_SCREENS.wa_disparos = Disparos;
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin-crm/DisparosScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/admin-crm/ImoveisScreen.jsx
try { (() => {
// Imóveis — property catalog list.
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const rows = [{
    code: "COD-84213",
    title: "Apartamento 2Q · Vila Mariana",
    tipo: "Apartamento",
    bairro: "Vila Mariana",
    preco: "R$ 680.000",
    trans: "Venda",
    status: {
      c: "green",
      t: "Publicado",
      dot: true
    },
    corretor: "Rafael M.",
    dorm: 2,
    banho: 2,
    vaga: 1,
    area: "68 m²"
  }, {
    code: "COD-84117",
    title: "Cobertura Duplex · Moema",
    tipo: "Cobertura",
    bairro: "Moema",
    preco: "R$ 1.900.000",
    trans: "Venda",
    status: {
      c: "green",
      t: "Publicado",
      dot: true
    },
    corretor: "Bianca T.",
    dorm: 3,
    banho: 4,
    vaga: 3,
    area: "180 m²"
  }, {
    code: "COD-83998",
    title: "Casa Térrea 3Q · Granja Viana",
    tipo: "Casa",
    bairro: "Granja Viana",
    preco: "R$ 920.000",
    trans: "Venda",
    status: {
      c: "amber",
      t: "Em revisão"
    },
    corretor: "Diego F.",
    dorm: 3,
    banho: 3,
    vaga: 4,
    area: "210 m²"
  }, {
    code: "COD-83820",
    title: "Studio Mobiliado · Centro",
    tipo: "Studio",
    bairro: "Centro",
    preco: "R$ 2.400 / mês",
    trans: "Locação",
    status: {
      c: "blue",
      t: "Novo"
    },
    corretor: "Camila P.",
    dorm: 1,
    banho: 1,
    vaga: 0,
    area: "32 m²"
  }, {
    code: "COD-83714",
    title: "Apartamento 3Q · Tatuapé",
    tipo: "Apartamento",
    bairro: "Tatuapé",
    preco: "R$ 750.000",
    trans: "Venda",
    status: {
      c: "red",
      t: "Erro sync"
    },
    corretor: "Rafael M.",
    dorm: 3,
    banho: 2,
    vaga: 2,
    area: "92 m²"
  }, {
    code: "COD-83590",
    title: "Casa Condomínio · Alphaville",
    tipo: "Casa",
    bairro: "Alphaville",
    preco: "R$ 2.400.000",
    trans: "Venda",
    status: {
      c: "gray",
      t: "Rascunho"
    },
    corretor: "Bianca T.",
    dorm: 4,
    banho: 5,
    vaga: 4,
    area: "340 m²"
  }];
  const chips = ["Todos", "Venda", "Locação", "Destaques", "Publicados", "Em revisão", "Com erro"];
  function Imoveis() {
    const [chip, setChip] = React.useState("Todos");
    return /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement("div", {
      className: "ax-dashboard-command",
      style: {
        gridTemplateColumns: "minmax(0,1fr) auto"
      }
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Cat\xE1logo"), /*#__PURE__*/React.createElement("h1", {
      style: {
        marginTop: 3
      }
    }, "Im\xF3veis"), /*#__PURE__*/React.createElement("p", null, "1.284 im\xF3veis \xB7 86 destaques \xB7 sincronizado h\xE1 6 min")), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "inline-flex",
        gap: 6
      }
    }, /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "arrow-repeat"
    }, "Sincronizar"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "download"
    }, "Exportar"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "plus-lg",
      onClick: () => window.UM_GO("imovel_form")
    }, "Novo im\xF3vel"))), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: 12,
        borderBottom: "1px solid var(--line-soft)",
        flexWrap: "wrap"
      }
    }, /*#__PURE__*/React.createElement(UM.SearchInput, {
      placeholder: "Buscar por c\xF3digo, t\xEDtulo, endere\xE7o\u2026",
      style: {
        flex: "1 1 260px"
      }
    }), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "funnel"
    }, "Filtros avan\xE7ados"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "sliders"
    }, "Colunas"), /*#__PURE__*/React.createElement("div", {
      className: "ax-tabs",
      style: {
        marginLeft: "auto"
      }
    }, /*#__PURE__*/React.createElement("button", {
      className: "ax-tab is-active"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-list-ul"
    })), /*#__PURE__*/React.createElement("button", {
      className: "ax-tab"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-grid"
    })), /*#__PURE__*/React.createElement("button", {
      className: "ax-tab"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-geo-alt"
    })))), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        gap: 6,
        padding: "10px 12px",
        borderBottom: "1px solid var(--line-soft)",
        flexWrap: "wrap"
      }
    }, chips.map(c => /*#__PURE__*/React.createElement("button", {
      key: c,
      onClick: () => setChip(c),
      className: c === chip ? "ax-btn ax-btn--sm ax-btn--primary" : "ax-btn ax-btn--sm"
    }, c))), /*#__PURE__*/React.createElement("table", {
      className: "ax-table"
    }, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", null, /*#__PURE__*/React.createElement("th", {
      style: {
        width: 34
      }
    }, /*#__PURE__*/React.createElement("input", {
      type: "checkbox"
    })), /*#__PURE__*/React.createElement("th", null, "Im\xF3vel"), /*#__PURE__*/React.createElement("th", null, "Tipo"), /*#__PURE__*/React.createElement("th", null, "Bairro"), /*#__PURE__*/React.createElement("th", null, "Config."), /*#__PURE__*/React.createElement("th", {
      style: {
        textAlign: "right"
      }
    }, "Pre\xE7o"), /*#__PURE__*/React.createElement("th", null, "Status"), /*#__PURE__*/React.createElement("th", null, "Corretor"), /*#__PURE__*/React.createElement("th", {
      style: {
        width: 44
      }
    }))), /*#__PURE__*/React.createElement("tbody", null, rows.map(r => /*#__PURE__*/React.createElement("tr", {
      key: r.code
    }, /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("input", {
      type: "checkbox"
    })), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 10
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        width: 40,
        height: 40,
        borderRadius: 6,
        background: "var(--surface-header)",
        display: "grid",
        placeItems: "center",
        color: "var(--ink-faint)",
        flex: "none"
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-image"
    })), /*#__PURE__*/React.createElement("div", {
      style: {
        minWidth: 0
      }
    }, /*#__PURE__*/React.createElement("a", {
      href: "#",
      className: "ax-strong",
      style: {
        display: "block",
        cursor: "pointer"
      },
      onClick: e => {
        e.preventDefault();
        window.UM_GO("imovel_form");
      }
    }, r.title), /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 11,
        color: "var(--ink-muted)",
        fontFamily: "var(--font-mono)"
      }
    }, r.code, " \xB7 ", r.trans)))), /*#__PURE__*/React.createElement("td", null, r.tipo), /*#__PURE__*/React.createElement("td", null, r.bairro), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("span", {
      style: {
        display: "inline-flex",
        gap: 9,
        color: "var(--ink-muted)",
        fontSize: 12
      }
    }, /*#__PURE__*/React.createElement("span", {
      title: "Dormit\xF3rios"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-door-closed"
    }), " ", r.dorm), /*#__PURE__*/React.createElement("span", {
      title: "Banheiros"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-droplet"
    }), " ", r.banho), /*#__PURE__*/React.createElement("span", {
      title: "Vagas"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-car-front"
    }), " ", r.vaga), /*#__PURE__*/React.createElement("span", {
      title: "\xC1rea"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-arrows-fullscreen"
    }), " ", r.area))), /*#__PURE__*/React.createElement("td", {
      className: "ax-num",
      style: {
        textAlign: "right"
      }
    }, /*#__PURE__*/React.createElement("strong", {
      style: {
        color: "var(--ink)"
      }
    }, r.preco)), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement(UM.Badge, {
      tone: r.status.c,
      dot: r.status.dot
    }, r.status.t)), /*#__PURE__*/React.createElement("td", null, r.corretor), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("button", {
      className: "ax-ico-btn",
      "aria-label": "A\xE7\xF5es"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-three-dots-vertical"
    }))))))), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        padding: "10px 14px",
        fontSize: 12.5,
        color: "var(--ink-muted)"
      }
    }, /*#__PURE__*/React.createElement("span", null, "Mostrando 1\u20136 de 1.284"), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "inline-flex",
        gap: 6
      }
    }, /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "chevron-left",
      disabled: true
    }, "Anterior"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      iconRight: "chevron-right"
    }, "Pr\xF3ximo")))));
  }
  window.UM_SCREENS.imoveis = Imoveis;
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin-crm/ImoveisScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/admin-crm/ImovelFormScreen.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
// Imóveis — formulário de edição (exemplo preenchido).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const go = id => window.UM_GO && window.UM_GO(id);
  const fld = {
    display: "flex",
    flexDirection: "column",
    gap: 4
  };
  const lbl = {
    fontSize: 11.5,
    fontWeight: 600,
    color: "var(--ink-label)"
  };
  function F({
    label,
    span = 3,
    children
  }) {
    return /*#__PURE__*/React.createElement("label", {
      style: {
        ...fld,
        gridColumn: `span ${span}`
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: lbl
    }, label), children);
  }
  const inp = props => /*#__PURE__*/React.createElement("input", _extends({
    className: "ax-input"
  }, props));
  const sel = (opts, value) => /*#__PURE__*/React.createElement("select", {
    className: "ax-input",
    defaultValue: value
  }, opts.map(o => /*#__PURE__*/React.createElement("option", {
    key: o
  }, o)));
  const grid = {
    display: "grid",
    gridTemplateColumns: "repeat(12,1fr)",
    gap: 14,
    padding: 16
  };
  const head = (eb, t, top) => /*#__PURE__*/React.createElement("div", {
    className: "ax-panel__head",
    style: top ? {
      borderTop: "1px solid var(--line-soft)"
    } : null
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
    className: "ax-eyebrow"
  }, eb), /*#__PURE__*/React.createElement("div", {
    className: "ax-panel__title"
  }, t)));
  const TABS = ["Dados", "Localização", "Características", "Mídia", "Publicação"];
  function ImovelForm() {
    const [tab, setTab] = React.useState("Dados");
    return /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement("div", {
      className: "ax-dashboard-command",
      style: {
        gridTemplateColumns: "minmax(0,1fr) auto"
      }
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("button", {
      className: "ax-btn ax-btn--sm",
      onClick: () => go("imoveis"),
      style: {
        marginBottom: 8
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-arrow-left ax-ico"
    }), " Voltar ao cat\xE1logo"), /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Cat\xE1logo \xB7 Edi\xE7\xE3o"), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 8,
        marginTop: 3
      }
    }, /*#__PURE__*/React.createElement("h1", null, "Editar im\xF3vel"), /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: "var(--font-mono)",
        fontSize: 12.5,
        color: "var(--ink-muted)"
      }
    }, "COD-84213"), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "green",
      dot: true
    }, "Publicado")), /*#__PURE__*/React.createElement("p", null, "Apartamento 2Q \xB7 Vila Mariana \xB7 sincronizado com Vista h\xE1 6 min.")), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "inline-flex",
        gap: 6
      }
    }, /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "eye"
    }, "Ver no site"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "stars"
    }, "Descri\xE7\xE3o por IA"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "check-lg"
    }, "Salvar altera\xE7\xF5es"))), /*#__PURE__*/React.createElement("div", {
      className: "ax-tabs",
      style: {
        marginBottom: 12
      }
    }, TABS.map(t => /*#__PURE__*/React.createElement("button", {
      key: t,
      className: t === tab ? "ax-tab is-active" : "ax-tab",
      onClick: () => setTab(t)
    }, t))), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, head("Identidade", "Dados principais"), /*#__PURE__*/React.createElement("div", {
      style: grid
    }, /*#__PURE__*/React.createElement(F, {
      label: "T\xEDtulo do an\xFAncio",
      span: 8
    }, inp({
      defaultValue: "Apartamento 2Q · Vila Mariana"
    })), /*#__PURE__*/React.createElement(F, {
      label: "C\xF3digo",
      span: 4
    }, inp({
      defaultValue: "COD-84213",
      disabled: true
    })), /*#__PURE__*/React.createElement(F, {
      label: "Tipo",
      span: 3
    }, sel(["Apartamento", "Casa", "Cobertura", "Studio", "Terreno", "Comercial"], "Apartamento")), /*#__PURE__*/React.createElement(F, {
      label: "Transa\xE7\xE3o",
      span: 3
    }, sel(["Venda", "Locação", "Venda e locação"], "Venda")), /*#__PURE__*/React.createElement(F, {
      label: "Status",
      span: 3
    }, sel(["Rascunho", "Em revisão", "Publicado"], "Publicado")), /*#__PURE__*/React.createElement(F, {
      label: "Corretor respons\xE1vel",
      span: 3
    }, sel(["Rafael M.", "Bianca T.", "Diego F.", "Camila P."], "Rafael M."))), head("Valores", "Preço e custos", true), /*#__PURE__*/React.createElement("div", {
      style: grid
    }, /*#__PURE__*/React.createElement(F, {
      label: "Pre\xE7o (R$)",
      span: 4
    }, inp({
      defaultValue: "680.000",
      inputMode: "numeric"
    })), /*#__PURE__*/React.createElement(F, {
      label: "Condom\xEDnio (R$)",
      span: 4
    }, inp({
      defaultValue: "620",
      inputMode: "numeric"
    })), /*#__PURE__*/React.createElement(F, {
      label: "IPTU/ano (R$)",
      span: 4
    }, inp({
      defaultValue: "2.400",
      inputMode: "numeric"
    }))), head("Localização", "Endereço", true), /*#__PURE__*/React.createElement("div", {
      style: grid
    }, /*#__PURE__*/React.createElement(F, {
      label: "CEP",
      span: 3
    }, inp({
      defaultValue: "04101-000"
    })), /*#__PURE__*/React.createElement(F, {
      label: "Logradouro",
      span: 6
    }, inp({
      defaultValue: "Rua Domingos de Morais, 1203"
    })), /*#__PURE__*/React.createElement(F, {
      label: "N\xFAmero",
      span: 3
    }, inp({
      defaultValue: "1203"
    })), /*#__PURE__*/React.createElement(F, {
      label: "Bairro",
      span: 4
    }, inp({
      defaultValue: "Vila Mariana"
    })), /*#__PURE__*/React.createElement(F, {
      label: "Cidade",
      span: 4
    }, inp({
      defaultValue: "São Paulo"
    })), /*#__PURE__*/React.createElement(F, {
      label: "UF",
      span: 4
    }, sel(["SP", "RJ", "MG", "SC", "PR", "RS"], "SP"))), head("Configuração", "Características", true), /*#__PURE__*/React.createElement("div", {
      style: grid
    }, /*#__PURE__*/React.createElement(F, {
      label: "Dormit\xF3rios",
      span: 3
    }, inp({
      type: "number",
      defaultValue: 2
    })), /*#__PURE__*/React.createElement(F, {
      label: "Banheiros",
      span: 3
    }, inp({
      type: "number",
      defaultValue: 2
    })), /*#__PURE__*/React.createElement(F, {
      label: "Vagas",
      span: 3
    }, inp({
      type: "number",
      defaultValue: 1
    })), /*#__PURE__*/React.createElement(F, {
      label: "\xC1rea \xFAtil (m\xB2)",
      span: 3
    }, inp({
      type: "number",
      defaultValue: 68
    })), /*#__PURE__*/React.createElement(F, {
      label: "Descri\xE7\xE3o",
      span: 12
    }, /*#__PURE__*/React.createElement("textarea", {
      className: "ax-input",
      rows: 4,
      style: {
        resize: "vertical",
        height: "auto",
        paddingTop: 8
      },
      defaultValue: "Apartamento reformado de 2 dormit\xF3rios na Vila Mariana, 68m\xB2, 1 vaga, pr\xF3ximo ao metr\xF4 Santa Cruz. Sala ampla, cozinha planejada e varanda com boa vista."
    }))), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        justifyContent: "space-between",
        gap: 8,
        padding: 14,
        borderTop: "1px solid var(--line-soft)",
        position: "sticky",
        bottom: 0,
        background: "var(--surface)"
      }
    }, /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "trash"
    }, "Excluir"), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "inline-flex",
        gap: 8
      }
    }, /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      onClick: () => go("imoveis")
    }, "Cancelar"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "check-lg"
    }, "Salvar altera\xE7\xF5es")))));
  }
  window.UM_SCREENS.imovel_form = ImovelForm;
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin-crm/ImovelFormScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/admin-crm/LeadDetailScreen.jsx
try { (() => {
// Leads — detalhe/edição do lead (exemplo preenchido).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const go = id => window.UM_GO && window.UM_GO(id);
  const timeline = [{
    icon: "whatsapp",
    tone: "var(--entity-whatsapp)",
    t: "Mensagem no WhatsApp",
    d: "Perfeito, podemos agendar a visita?",
    time: "Hoje 12:41"
  }, {
    icon: "telephone",
    tone: "var(--info)",
    t: "Ligação registrada",
    d: "Retornou interesse no apto de Vila Mariana. Pediu 2ª visita.",
    time: "Hoje 10:12"
  }, {
    icon: "envelope",
    tone: "var(--purple)",
    t: "E-mail enviado",
    d: "Ficha completa do imóvel COD-84213.",
    time: "Ontem 19:04"
  }, {
    icon: "person-plus",
    tone: "var(--success)",
    t: "Lead criado",
    d: "Origem: Portal ZAP · distribuído para Rafael M.",
    time: "Ontem 18:30"
  }];
  function Row({
    k,
    v
  }) {
    return /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        justifyContent: "space-between",
        gap: 10,
        padding: "8px 0",
        borderBottom: "1px solid var(--line-soft)",
        fontSize: 12.5
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        color: "var(--ink-muted)"
      }
    }, k), /*#__PURE__*/React.createElement("strong", {
      style: {
        color: "var(--ink)",
        textAlign: "right"
      }
    }, v));
  }
  function LeadDetail() {
    return /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement("div", {
      className: "ax-dashboard-command",
      style: {
        gridTemplateColumns: "minmax(0,1fr) auto"
      }
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("button", {
      className: "ax-btn ax-btn--sm",
      onClick: () => go("leads"),
      style: {
        marginBottom: 8
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-arrow-left ax-ico"
    }), " Voltar ao funil"), /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Comercial \xB7 Lead"), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 8,
        marginTop: 3
      }
    }, /*#__PURE__*/React.createElement("h1", null, "Marina Costa"), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "blue",
      dot: true
    }, "Novo"), /*#__PURE__*/React.createElement(UM.LeadLabelChip, {
      color: "red"
    }, "Quente")), /*#__PURE__*/React.createElement("p", null, "+55 11 98765-4321 \xB7 marina.costa@email.com \xB7 lead h\xE1 1 dia")), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "inline-flex",
        gap: 6
      }
    }, /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "whatsapp",
      onClick: () => go("wa_atendimento")
    }, "Atender"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "pencil"
    }, "Editar"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "file-earmark-text"
    }, "Nova proposta"))), /*#__PURE__*/React.createElement("div", {
      className: "ax-grid",
      style: {
        gridTemplateColumns: "minmax(0,1.4fr) minmax(0,1fr)"
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__head"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Hist\xF3rico"), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__title"
    }, "Linha do tempo")), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "gray"
    }, "4 intera\xE7\xF5es")), /*#__PURE__*/React.createElement("div", {
      style: {
        padding: 16,
        display: "grid",
        gap: 14
      }
    }, timeline.map((e, i) => /*#__PURE__*/React.createElement("div", {
      key: i,
      style: {
        display: "flex",
        gap: 12
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        width: 30,
        height: 30,
        borderRadius: 8,
        background: "var(--surface-header)",
        color: e.tone,
        display: "grid",
        placeItems: "center",
        flex: "none"
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: `bi bi-${e.icon}`
    })), /*#__PURE__*/React.createElement("div", {
      style: {
        minWidth: 0,
        flex: 1
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        justifyContent: "space-between",
        gap: 10
      }
    }, /*#__PURE__*/React.createElement("strong", {
      style: {
        fontSize: 12.5,
        color: "var(--ink)"
      }
    }, e.t), /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 11,
        color: "var(--ink-faint)",
        flex: "none"
      }
    }, e.time)), /*#__PURE__*/React.createElement("div", {
      style: {
        fontSize: 12,
        color: "var(--ink-body)",
        marginTop: 2
      }
    }, e.d))))), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        gap: 8,
        padding: 12,
        borderTop: "1px solid var(--line-soft)"
      }
    }, /*#__PURE__*/React.createElement("input", {
      className: "ax-input",
      placeholder: "Registrar contato ou nota\u2026",
      style: {
        flex: 1
      }
    }), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "send"
    }, "Registrar"))), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "grid",
        gap: 12,
        alignContent: "start"
      }
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__head"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Dados"), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__title"
    }, "Informa\xE7\xF5es do lead"))), /*#__PURE__*/React.createElement("div", {
      style: {
        padding: "6px 16px 12px"
      }
    }, /*#__PURE__*/React.createElement(Row, {
      k: "Origem",
      v: "Portal ZAP"
    }), /*#__PURE__*/React.createElement(Row, {
      k: "Etapa do funil",
      v: "Novo"
    }), /*#__PURE__*/React.createElement(Row, {
      k: "Corretor",
      v: "Rafael M."
    }), /*#__PURE__*/React.createElement(Row, {
      k: "Im\xF3vel de interesse",
      v: "Apto 302 \xB7 Vila Mariana"
    }), /*#__PURE__*/React.createElement(Row, {
      k: "Faixa de valor",
      v: "R$ 650\u2013720 mil"
    }), /*#__PURE__*/React.createElement(Row, {
      k: "Financiamento",
      v: "Sim \xB7 pr\xE9-aprovado"
    }))), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__head"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Contexto"), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel__title"
    }, "V\xEDnculos"))), /*#__PURE__*/React.createElement("div", {
      style: {
        padding: 14,
        display: "grid",
        gap: 8
      }
    }, /*#__PURE__*/React.createElement(UM.ContextPin, {
      type: "property"
    }, "Apto 302 \xB7 Vila Mariana"), /*#__PURE__*/React.createElement(UM.ContextPin, {
      type: "proposal"
    }, "Proposta #1042 \xB7 rascunho"))), /*#__PURE__*/React.createElement(UM.Button, {
      block: true,
      icon: "calendar-event"
    }, "Agendar visita"))));
  }
  window.UM_SCREENS.lead_detail = LeadDetail;
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin-crm/LeadDetailScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/admin-crm/LeadsScreen.jsx
try { (() => {
// Leads — kanban funnel board.
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const COLUMNS = [{
    key: "novo",
    eyebrow: "Entrada",
    title: "Novos",
    tone: "blue",
    cards: [{
      name: "Marina Costa",
      origem: "Portal ZAP",
      imovel: "Apto 2Q · Vila Mariana",
      valor: "R$ 680 mil",
      labels: [{
        c: "red",
        t: "Quente"
      }],
      time: "12 min"
    }, {
      name: "Eduardo Lima",
      origem: "Meta Ads",
      imovel: "Cobertura · Moema",
      valor: "R$ 1,9 mi",
      labels: [{
        c: "cyan",
        t: "Financiamento"
      }],
      time: "38 min"
    }, {
      name: "Patrícia Nunes",
      origem: "WhatsApp",
      imovel: "Casa 3Q · Granja",
      valor: "R$ 920 mil",
      labels: [],
      time: "1 h"
    }]
  }, {
    key: "atendimento",
    eyebrow: "Comercial",
    title: "Em atendimento",
    tone: "cyan",
    cards: [{
      name: "Rafael Souza",
      origem: "Indicação",
      imovel: "Studio · Centro",
      valor: "R$ 340 mil",
      labels: [{
        c: "amber",
        t: "Retornar"
      }],
      time: "3 h"
    }, {
      name: "Juliana Alves",
      origem: "Portal OLX",
      imovel: "Apto 3Q · Tatuapé",
      valor: "R$ 750 mil",
      labels: [{
        c: "green",
        t: "Visita agendada"
      }],
      time: "5 h"
    }]
  }, {
    key: "proposta",
    eyebrow: "Negociação",
    title: "Proposta",
    tone: "purple",
    cards: [{
      name: "Carlos Prado",
      origem: "Site",
      imovel: "Casa · Alphaville",
      valor: "R$ 2,4 mi",
      labels: [{
        c: "purple",
        t: "Proposta enviada"
      }],
      time: "1 d"
    }]
  }, {
    key: "fechado",
    eyebrow: "Ganho",
    title: "Fechado",
    tone: "green",
    cards: [{
      name: "Beatriz Rocha",
      origem: "Portal ZAP",
      imovel: "Apto 2Q · Pinheiros",
      valor: "R$ 890 mil",
      labels: [{
        c: "green",
        t: "Contrato"
      }],
      time: "2 d"
    }]
  }];
  function LeadCard({
    c
  }) {
    return /*#__PURE__*/React.createElement("article", {
      className: "ax-board__card",
      style: {
        cursor: "pointer"
      },
      onClick: () => window.UM_GO("lead_detail")
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: 8
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        display: "inline-flex",
        alignItems: "center",
        gap: 8,
        minWidth: 0
      }
    }, /*#__PURE__*/React.createElement("span", {
      className: "ax-avatar",
      style: {
        width: 26,
        height: 26,
        fontSize: 11
      }
    }, c.name.split(" ").map(n => n[0]).slice(0, 2).join("")), /*#__PURE__*/React.createElement("strong", {
      style: {
        fontSize: 13,
        color: "var(--ink)"
      }
    }, c.name)), /*#__PURE__*/React.createElement("button", {
      className: "ax-ico-btn",
      "aria-label": "Mais"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-three-dots-vertical"
    }))), /*#__PURE__*/React.createElement("div", {
      style: {
        fontSize: 12,
        color: "var(--ink-body)"
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-house-door",
      style: {
        color: "var(--ink-faint)",
        marginRight: 5
      }
    }), c.imovel), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between"
      }
    }, /*#__PURE__*/React.createElement("strong", {
      className: "ax-num",
      style: {
        fontSize: 13,
        color: "var(--ink)"
      }
    }, c.valor), /*#__PURE__*/React.createElement("span", {
      className: "ax-badge ax-badge--gray",
      style: {
        fontSize: 10.5
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-broadcast-pin",
      style: {
        fontSize: 11
      }
    }), c.origem)), c.labels.length > 0 && /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        gap: 4,
        flexWrap: "wrap"
      }
    }, c.labels.map((l, i) => /*#__PURE__*/React.createElement(UM.LeadLabelChip, {
      key: i,
      color: l.c
    }, l.t))), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        borderTop: "1px solid var(--line-soft)",
        paddingTop: 8,
        fontSize: 11,
        color: "var(--ink-muted)"
      }
    }, /*#__PURE__*/React.createElement("span", null, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-clock",
      style: {
        marginRight: 4
      }
    }), c.time), /*#__PURE__*/React.createElement("span", {
      style: {
        display: "inline-flex",
        gap: 6
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-whatsapp",
      style: {
        color: "var(--entity-whatsapp)"
      }
    }), /*#__PURE__*/React.createElement("i", {
      className: "bi bi-telephone"
    }), /*#__PURE__*/React.createElement("i", {
      className: "bi bi-calendar-event"
    }))));
  }
  function Leads() {
    return /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement("div", {
      className: "ax-dashboard-command",
      style: {
        gridTemplateColumns: "minmax(0,1fr) auto"
      }
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "Comercial"), /*#__PURE__*/React.createElement("h1", {
      style: {
        marginTop: 3
      }
    }, "Funil de Leads"), /*#__PURE__*/React.createElement("p", null, "231 leads ativos \xB7 atualizado agora")), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "inline-flex",
        gap: 6
      }
    }, /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "funnel"
    }, "Filtros"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "download"
    }, "Exportar"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "plus-lg",
      onClick: () => window.UM_GO("lead_detail")
    }, "Novo lead"))), /*#__PURE__*/React.createElement("div", {
      className: "ax-board"
    }, COLUMNS.map(col => /*#__PURE__*/React.createElement("div", {
      key: col.key,
      className: "ax-board__column"
    }, /*#__PURE__*/React.createElement("div", {
      className: "ax-board__col-head"
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-board__col-eyebrow"
    }, col.eyebrow), /*#__PURE__*/React.createElement("span", {
      className: "ax-board__col-title"
    }, col.title)), /*#__PURE__*/React.createElement("span", {
      className: "ax-board__col-count"
    }, col.cards.length)), /*#__PURE__*/React.createElement("div", {
      className: "ax-board__col-body"
    }, col.cards.map((c, i) => /*#__PURE__*/React.createElement(LeadCard, {
      key: i,
      c: c
    })))))));
  }
  window.UM_SCREENS.leads = Leads;
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin-crm/LeadsScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/admin-crm/TemplatesScreen.jsx
try { (() => {
// WhatsApp — Templates (modelos aprovados pela Meta).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const rows = [{
    name: "boas_vindas_lead",
    hint: "Disponível para campanhas",
    type: "Texto",
    cat: "Utilidade",
    lang: "pt_BR",
    status: "Aprovado",
    tone: "green",
    approved: true
  }, {
    name: "agendamento_visita",
    hint: "Disponível para campanhas",
    type: "Mídia",
    cat: "Marketing",
    lang: "pt_BR",
    status: "Aprovado",
    tone: "green",
    approved: true
  }, {
    name: "proposta_enviada",
    hint: "Disponível para campanhas",
    type: "Texto",
    cat: "Utilidade",
    lang: "pt_BR",
    status: "Aprovado",
    tone: "green",
    approved: true
  }, {
    name: "lancamento_praia_brava",
    hint: "Disponível para campanhas",
    type: "Carrossel",
    cat: "Marketing",
    lang: "pt_BR",
    status: "Aprovado",
    tone: "green",
    approved: true
  }, {
    name: "reativacao_60d",
    hint: "Aguardando revisão",
    type: "Texto",
    cat: "Marketing",
    lang: "pt_BR",
    status: "Em análise",
    tone: "amber",
    approved: false
  }, {
    name: "pos_visita_feedback",
    hint: "Disponível para campanhas",
    type: "Flow",
    cat: "Utilidade",
    lang: "pt_BR",
    status: "Aprovado",
    tone: "green",
    approved: true
  }, {
    name: "feirao_julho",
    hint: "Reprovado pela Meta",
    type: "Mídia",
    cat: "Marketing",
    lang: "pt_BR",
    status: "Rejeitado",
    tone: "red",
    approved: false
  }];
  const fLabel = {
    display: "flex",
    flexDirection: "column",
    gap: 3,
    fontSize: 11,
    fontWeight: 600,
    color: "var(--ink-label)"
  };
  function Filter({
    label,
    opts
  }) {
    return /*#__PURE__*/React.createElement("label", {
      style: fLabel
    }, label, /*#__PURE__*/React.createElement("select", {
      className: "ax-input",
      style: {
        height: 34,
        minWidth: 132
      }
    }, opts.map(o => /*#__PURE__*/React.createElement("option", {
      key: o
    }, o))));
  }
  function Templates() {
    return /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement("div", {
      className: "ax-dashboard-command",
      style: {
        gridTemplateColumns: "minmax(0,1fr) auto"
      }
    }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow"
    }, "WhatsApp"), /*#__PURE__*/React.createElement("h1", {
      style: {
        marginTop: 3
      }
    }, "Templates"), /*#__PURE__*/React.createElement("p", null, "Modelos aprovados pela Meta \xB7 usados nas campanhas de disparo.")), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "inline-flex",
        gap: 6,
        alignItems: "center"
      }
    }, /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "green",
      dot: true
    }, "12 aprovados"), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "amber",
      dot: true
    }, "3 em an\xE1lise"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "arrow-repeat"
    }, "Sincronizar"), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "plus-lg"
    }, "Novo template"))), /*#__PURE__*/React.createElement("div", {
      className: "ax-panel"
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "flex-end",
        gap: 10,
        padding: 12,
        borderBottom: "1px solid var(--line-soft)",
        flexWrap: "wrap"
      }
    }, /*#__PURE__*/React.createElement(UM.SearchInput, {
      placeholder: "Buscar por nome\u2026",
      style: {
        flex: "1 1 220px"
      }
    }), /*#__PURE__*/React.createElement(Filter, {
      label: "Status",
      opts: ["Todos", "Aprovado", "Em análise", "Rejeitado"]
    }), /*#__PURE__*/React.createElement(Filter, {
      label: "Categoria",
      opts: ["Todas", "Utilidade", "Marketing", "Autenticação"]
    }), /*#__PURE__*/React.createElement(Filter, {
      label: "Tipo",
      opts: ["Todos", "Texto", "Mídia", "Carrossel", "Flow"]
    }), /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "funnel"
    }, "Filtrar")), /*#__PURE__*/React.createElement("table", {
      className: "ax-table"
    }, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", null, /*#__PURE__*/React.createElement("th", null, "Nome"), /*#__PURE__*/React.createElement("th", null, "Tipo"), /*#__PURE__*/React.createElement("th", null, "Categoria"), /*#__PURE__*/React.createElement("th", null, "Idioma"), /*#__PURE__*/React.createElement("th", null, "Status"), /*#__PURE__*/React.createElement("th", {
      style: {
        width: 200
      }
    }, "A\xE7\xF5es"))), /*#__PURE__*/React.createElement("tbody", null, rows.map(r => /*#__PURE__*/React.createElement("tr", {
      key: r.name
    }, /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("a", {
      href: "#",
      className: "ax-strong",
      style: {
        display: "block",
        fontFamily: "var(--font-mono)",
        fontSize: 12.5
      }
    }, r.name), /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 11,
        color: "var(--ink-muted)"
      }
    }, r.hint)), /*#__PURE__*/React.createElement("td", null, r.type), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "gray"
    }, r.cat)), /*#__PURE__*/React.createElement("td", {
      style: {
        fontFamily: "var(--font-mono)",
        fontSize: 12,
        color: "var(--ink-muted)"
      }
    }, r.lang), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement(UM.Badge, {
      tone: r.tone,
      dot: true
    }, r.status)), /*#__PURE__*/React.createElement("td", null, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "inline-flex",
        gap: 6
      }
    }, /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      icon: "eye"
    }, "Pr\xE9via"), r.approved && /*#__PURE__*/React.createElement(UM.Button, {
      size: "sm",
      variant: "primary",
      icon: "megaphone"
    }, "Criar campanha")))))))));
  }
  window.UM_SCREENS.wa_templates = Templates;
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin-crm/TemplatesScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/admin-crm/WhatsAppScreen.jsx
try { (() => {
// WhatsApp — atendimento inbox (conversation list + thread + context).
(function () {
  const UM = window.UnitymobDesignSystem_2a309d;
  window.UM_SCREENS = window.UM_SCREENS || {};
  const convos = [{
    id: 1,
    name: "Marina Costa",
    last: "Perfeito, podemos agendar a visita?",
    time: "12:41",
    unread: 2,
    tag: {
      c: "red",
      t: "Quente"
    },
    active: true
  }, {
    id: 2,
    name: "Eduardo Lima",
    last: "Vou confirmar com o banco e retorno.",
    time: "12:08",
    unread: 0,
    tag: {
      c: "cyan",
      t: "Financiamento"
    }
  }, {
    id: 3,
    name: "Patrícia Nunes",
    last: "Áudio · 0:42",
    time: "11:52",
    unread: 0,
    tag: null
  }, {
    id: 4,
    name: "Rafael Souza",
    last: "Obrigado pelas fotos!",
    time: "10:30",
    unread: 0,
    tag: {
      c: "green",
      t: "Visita agendada"
    }
  }, {
    id: 5,
    name: "Juliana Alves",
    last: "Qual o valor do condomínio?",
    time: "Ontem",
    unread: 0,
    tag: null
  }];
  const thread = [{
    from: "them",
    text: "Oi! Vi o anúncio do apartamento na Vila Mariana. Ainda está disponível?",
    time: "12:18"
  }, {
    from: "me",
    text: "Olá, Marina! Está sim 😊 Apto de 2 quartos, 68m², R$ 680 mil. Quer que eu envie mais fotos?",
    time: "12:20"
  }, {
    from: "them",
    text: "Quero sim, por favor!",
    time: "12:22"
  }, {
    from: "me",
    text: "📎 apto-302-vila-mariana.pdf",
    time: "12:24",
    doc: true
  }, {
    from: "them",
    text: "Perfeito, podemos agendar a visita?",
    time: "12:41"
  }];
  function Convo({
    c
  }) {
    return /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        gap: 10,
        padding: "10px 12px",
        cursor: "pointer",
        borderLeft: `2px solid ${c.active ? "var(--entity-whatsapp)" : "transparent"}`,
        background: c.active ? "var(--surface-soft)" : "transparent"
      }
    }, /*#__PURE__*/React.createElement("span", {
      className: "ax-avatar",
      style: {
        width: 38,
        height: 38,
        flex: "none",
        background: "#dcf5ee",
        color: "var(--entity-whatsapp)"
      }
    }, c.name.split(" ").map(n => n[0]).slice(0, 2).join("")), /*#__PURE__*/React.createElement("div", {
      style: {
        minWidth: 0,
        flex: 1
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        justifyContent: "space-between",
        gap: 8
      }
    }, /*#__PURE__*/React.createElement("strong", {
      style: {
        fontSize: 13,
        color: "var(--ink)",
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap"
      }
    }, c.name), /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 11,
        color: "var(--ink-faint)",
        flex: "none"
      }
    }, c.time)), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        justifyContent: "space-between",
        gap: 8,
        marginTop: 2
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 12,
        color: "var(--ink-muted)",
        overflow: "hidden",
        textOverflow: "ellipsis",
        whiteSpace: "nowrap"
      }
    }, c.last), c.unread > 0 && /*#__PURE__*/React.createElement("span", {
      style: {
        flex: "none",
        minWidth: 18,
        height: 18,
        borderRadius: 999,
        background: "var(--entity-whatsapp)",
        color: "#fff",
        fontSize: 11,
        fontWeight: 700,
        display: "grid",
        placeItems: "center",
        padding: "0 5px"
      }
    }, c.unread)), c.tag && /*#__PURE__*/React.createElement("div", {
      style: {
        marginTop: 5
      }
    }, /*#__PURE__*/React.createElement(UM.LeadLabelChip, {
      color: c.tag.c
    }, c.tag.t))));
  }
  function WhatsApp() {
    return /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement("div", {
      className: "ax-panel",
      style: {
        overflow: "hidden",
        height: "calc(100vh - var(--navbar-h) - var(--contextbar-h) - 24px)",
        display: "grid",
        gridTemplateColumns: "320px minmax(0,1fr) 280px"
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        borderRight: "1px solid var(--line-soft)",
        display: "flex",
        flexDirection: "column",
        minHeight: 0
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        padding: 10,
        borderBottom: "1px solid var(--line-soft)"
      }
    }, /*#__PURE__*/React.createElement(UM.SearchInput, {
      placeholder: "Buscar conversa\u2026",
      style: {
        width: "100%",
        maxWidth: "none"
      }
    })), /*#__PURE__*/React.createElement("div", {
      style: {
        overflowY: "auto"
      }
    }, convos.map(c => /*#__PURE__*/React.createElement(Convo, {
      key: c.id,
      c: c
    })))), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        flexDirection: "column",
        minHeight: 0,
        background: "#f4f1ea"
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: "9px 14px",
        borderBottom: "1px solid var(--line-soft)",
        background: "#fff"
      }
    }, /*#__PURE__*/React.createElement("span", {
      className: "ax-avatar",
      style: {
        width: 34,
        height: 34,
        background: "#dcf5ee",
        color: "var(--entity-whatsapp)"
      }
    }, "MC"), /*#__PURE__*/React.createElement("div", {
      style: {
        flex: 1,
        minWidth: 0
      }
    }, /*#__PURE__*/React.createElement("strong", {
      style: {
        fontSize: 13.5,
        color: "var(--ink)"
      }
    }, "Marina Costa"), /*#__PURE__*/React.createElement("div", {
      style: {
        fontSize: 11.5,
        color: "var(--entity-whatsapp)"
      }
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-circle-fill",
      style: {
        fontSize: 7,
        marginRight: 4
      }
    }), "online")), /*#__PURE__*/React.createElement(UM.Badge, {
      tone: "green",
      dot: true
    }, "Ativo"), /*#__PURE__*/React.createElement("button", {
      className: "ax-ico-btn"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-telephone"
    })), /*#__PURE__*/React.createElement("button", {
      className: "ax-ico-btn"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-three-dots-vertical"
    }))), /*#__PURE__*/React.createElement("div", {
      style: {
        flex: 1,
        overflowY: "auto",
        padding: 16,
        display: "flex",
        flexDirection: "column",
        gap: 8
      }
    }, thread.map((m, i) => /*#__PURE__*/React.createElement("div", {
      key: i,
      style: {
        alignSelf: m.from === "me" ? "flex-end" : "flex-start",
        maxWidth: "72%",
        padding: "8px 11px",
        borderRadius: 10,
        fontSize: 13,
        lineHeight: 1.4,
        background: m.from === "me" ? "#d9fdd3" : "#fff",
        color: "var(--ink)",
        boxShadow: "0 1px 1px rgba(15,23,42,.08)"
      }
    }, m.doc && /*#__PURE__*/React.createElement("i", {
      className: "bi bi-file-earmark-pdf",
      style: {
        marginRight: 6,
        color: "var(--danger)"
      }
    }), m.text, /*#__PURE__*/React.createElement("div", {
      style: {
        fontSize: 10,
        color: "var(--ink-faint)",
        textAlign: "right",
        marginTop: 3
      }
    }, m.time, " ", m.from === "me" && /*#__PURE__*/React.createElement("i", {
      className: "bi bi-check2-all",
      style: {
        color: "#53bdeb"
      }
    }))))), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        alignItems: "center",
        gap: 8,
        padding: 10,
        borderTop: "1px solid var(--line-soft)",
        background: "#fff"
      }
    }, /*#__PURE__*/React.createElement("button", {
      className: "ax-ico-btn"
    }, /*#__PURE__*/React.createElement("i", {
      className: "bi bi-paperclip"
    })), /*#__PURE__*/React.createElement("input", {
      className: "ax-input",
      placeholder: "Digite uma mensagem\u2026",
      style: {
        flex: 1
      }
    }), /*#__PURE__*/React.createElement(UM.Button, {
      variant: "primary",
      icon: "send"
    }, "Enviar"))), /*#__PURE__*/React.createElement("div", {
      style: {
        borderLeft: "1px solid var(--line-soft)",
        padding: 14,
        overflowY: "auto",
        display: "grid",
        gap: 12,
        alignContent: "start"
      }
    }, /*#__PURE__*/React.createElement("div", {
      style: {
        textAlign: "center",
        display: "grid",
        gap: 6,
        justifyItems: "center",
        paddingBottom: 12,
        borderBottom: "1px solid var(--line-soft)"
      }
    }, /*#__PURE__*/React.createElement("span", {
      className: "ax-avatar",
      style: {
        width: 52,
        height: 52,
        fontSize: 18,
        background: "#dcf5ee",
        color: "var(--entity-whatsapp)"
      }
    }, "MC"), /*#__PURE__*/React.createElement("strong", {
      style: {
        fontSize: 14,
        color: "var(--ink)"
      }
    }, "Marina Costa"), /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 12,
        color: "var(--ink-muted)"
      }
    }, "+55 11 98765-4321")), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow",
      style: {
        marginBottom: 6
      }
    }, "Lead vinculado"), /*#__PURE__*/React.createElement(UM.ContextPin, {
      type: "lead"
    }, "Marina Costa \xB7 Novo")), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow",
      style: {
        marginBottom: 6
      }
    }, "Im\xF3vel de interesse"), /*#__PURE__*/React.createElement(UM.ContextPin, {
      type: "property"
    }, "Apto 302 \xB7 Vila Mariana")), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("span", {
      className: "ax-eyebrow",
      style: {
        marginBottom: 6
      }
    }, "Etiquetas"), /*#__PURE__*/React.createElement("div", {
      style: {
        display: "flex",
        gap: 4,
        flexWrap: "wrap"
      }
    }, /*#__PURE__*/React.createElement(UM.LeadLabelChip, {
      color: "red"
    }, "Quente"), /*#__PURE__*/React.createElement(UM.LeadLabelChip, {
      color: "green"
    }, "Visita agendada"))), /*#__PURE__*/React.createElement(UM.Button, {
      block: true,
      icon: "calendar-event"
    }, "Agendar visita"))));
  }
  window.UM_SCREENS.whatsapp = WhatsApp;
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/admin-crm/WhatsAppScreen.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Button = __ds_scope.Button;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Avatar = __ds_scope.Avatar;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.ContextPin = __ds_scope.ContextPin;

__ds_ns.LeadLabelChip = __ds_scope.LeadLabelChip;

__ds_ns.MetricCard = __ds_scope.MetricCard;

__ds_ns.Alert = __ds_scope.Alert;

__ds_ns.EmptyState = __ds_scope.EmptyState;

__ds_ns.Menu = __ds_scope.Menu;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.Field = __ds_scope.Field;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.SearchInput = __ds_scope.SearchInput;

__ds_ns.Select = __ds_scope.Select;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.Textarea = __ds_scope.Textarea;

__ds_ns.NavLink = __ds_scope.NavLink;

__ds_ns.Tabs = __ds_scope.Tabs;

})();
