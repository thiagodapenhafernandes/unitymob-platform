// Shared conditional field state: restore only controls disabled by this helper.
// Permission locks always take precedence over visibility changes.
export function setConditionalFieldsVisible(element, visible) {
  if (!element) return
  element.hidden = !visible
  element.classList.toggle("tw-hidden", !visible)
  element.querySelectorAll("input, select, textarea").forEach((field) => {
    if (!visible && !field.disabled) {
      field.dataset.conditionallyDisabled = "true"
      field.disabled = true
      field.tomselect?.disable()
    } else if (visible && field.dataset.conditionallyDisabled === "true") {
      delete field.dataset.conditionallyDisabled
      if (field.getAttribute("aria-disabled") === "true") return
      field.disabled = false
      field.tomselect?.enable()
    }
  })
}

// Reusable exclusive choices inside existing checklist components.
export function enforceExclusiveChoice(field, scope) {
  const group = field.dataset.exclusiveChoiceGroup
  if (!group || !field.checked) return
  const others = Array.from(scope.querySelectorAll("input[data-exclusive-choice-group]")).filter((other) => other !== field && other.dataset.exclusiveChoiceGroup === group && other.checked)
  if (others.some((other) => other.disabled || other.getAttribute("aria-disabled") === "true")) {
    field.checked = false
    return
  }
  others.forEach((other) => {
    other.checked = false
    other.dispatchEvent(new Event("change", { bubbles: true }))
  })
}
