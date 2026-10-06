// Preview only. Rails validates and normalizes the submitted values independently.
export function previewStyle(data, prefix = "") {
  const value = name => data[`${prefix}${name}`]
  const color = name => /^#[\da-f]{6}$/i.test(value(name) || "") ? value(name) : null
  const number = (name, min, max, fallback = 0) => Math.max(min, Math.min(max, Number(value(name) ?? fallback) || 0))
  const enabled = name => value(name) === "true" || value(name) === true
  const rgba = (hex, opacity) => `rgba(${hex.slice(1).match(/../g).map(channel => parseInt(channel, 16)).join(",")},${opacity / 100})`
  const styles = {}
  const background = color("background_color"), text = color("text_color")
  if (enabled("custom_colors") && background && text) Object.assign(styles, { "background-color": background, "border-color": background, color: text })
  const alpha = number("background_opacity", 0, 100, 100)
  let gradient
  if (value("background_mode") === "transparent") styles.background = "transparent"
  if (value("background_mode") === "solid" && background) styles.background = rgba(background, alpha)
  if (value("background_mode") === "gradient" && background && color("gradient_color")) {
    const stops = `${rgba(background, alpha)},${rgba(color("gradient_color"), alpha)}`
    gradient = value("gradient_kind") === "radial" ? `radial-gradient(circle,${stops})` : `linear-gradient(${number("gradient_angle", 0, 360)}deg,${stops})`
    styles.background = gradient
  }
  const textAlpha = number("text_opacity", 0, 100, 100)
  if (text && textAlpha < 100) styles.color = rgba(text, textAlpha)
  const fonts = { system: "system-ui,sans-serif", arial: "Arial,sans-serif", georgia: "Georgia,serif", mono: "ui-monospace,monospace" }
  if (Object.hasOwn(fonts, value("font_family"))) styles["font-family"] = fonts[value("font_family")]
  const enums = { font_weight: ["300", "400", "500", "600", "700", "800"], font_style: ["normal", "italic"], text_align: ["left", "center", "right", "justify"], text_decoration: ["none", "underline", "line-through"], text_transform: ["none", "uppercase", "lowercase", "capitalize"] }
  Object.entries(enums).forEach(([name, allowed]) => { if (allowed.includes(value(name))) styles[name.replaceAll("_", "-")] = value(name) })
  if (Number(value("font_size")) > 0) styles["font-size"] = `${number("font_size", 8, 120)}px`
  if (Number(value("line_height")) > 0) styles["line-height"] = String(number("line_height", 80, 250) / 100)
  if (Number(value("letter_spacing"))) styles["letter-spacing"] = `${number("letter_spacing", -3, 12)}px`
  if (enabled("text_gradient") && text && color("text_gradient_color")) {
    styles["background-image"] = `linear-gradient(${number("gradient_angle", 0, 360)}deg,${rgba(text, textAlpha)},${rgba(color("text_gradient_color"), textAlpha)}),${gradient || "none"}`
    styles["background-clip"] = styles["-webkit-background-clip"] = "text,border-box"
    styles.color = styles["-webkit-text-fill-color"] = "transparent"
  }
  if (enabled("custom_border") && color("border_color") && ["none", "solid", "dashed"].includes(value("border_style"))) {
    styles.border = `${number("border_width", 0, 12)}px ${value("border_style")} ${color("border_color")}`
    styles["border-radius"] = `${number("border_radius", 0, 64)}px`
  }
  if (enabled("backdrop_enabled")) styles["backdrop-filter"] = styles["-webkit-backdrop-filter"] = `blur(${number("backdrop_blur", 0, 40)}px) saturate(${number("backdrop_saturation", 0, 200)}%)`
  return styles
}
