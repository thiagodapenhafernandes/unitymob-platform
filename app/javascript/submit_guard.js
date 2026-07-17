const FORM_GUARD_ATTR = "data-submit-guard-state"
const SUBMITTING_STATE = "submitting"
const DEFAULT_BUSY_LABEL = "Processando..."

const submitControlsFor = (form) =>
  Array.from(form.querySelectorAll("button[type='submit'], input[type='submit'], button:not([type])"))

const shouldGuardForm = (form) => {
  if (!(form instanceof HTMLFormElement)) return false
  if (form.dataset.submitGuard === "false") return false
  if (form.closest("[data-submit-guard='false']")) return false
  if (form.dataset.remote === "true") return false
  if (form.target && form.target !== "_self") return false

  return true
}

const lockControl = (control) => {
  if (!control || control.dataset.submitGuardLocked === "true") return

  control.dataset.submitGuardLocked = "true"
  control.dataset.submitGuardOriginalPointerEvents = control.style.pointerEvents || ""
  control.setAttribute("aria-disabled", "true")
  control.setAttribute("aria-busy", "true")
  control.classList.add("is-submitting")
  control.style.pointerEvents = "none"

  const busyLabel = control.dataset.submitGuardLabel || control.dataset.turboSubmitsWith
  if (!busyLabel) return

  if (control instanceof HTMLInputElement) {
    control.dataset.submitGuardOriginalValue = control.value
    control.value = busyLabel
    return
  }

  const labelTarget = control.querySelector("[data-submit-guard-label], span")
  if (labelTarget) {
    labelTarget.dataset.submitGuardOriginalText = labelTarget.textContent
    labelTarget.textContent = busyLabel
  } else if (!control.querySelector("svg, i")) {
    control.dataset.submitGuardOriginalText = control.textContent
    control.textContent = busyLabel
  }
}

const unlockControl = (control) => {
  if (!control || control.dataset.submitGuardLocked !== "true") return

  control.dataset.submitGuardLocked = "false"
  control.removeAttribute("aria-disabled")
  control.removeAttribute("aria-busy")
  control.classList.remove("is-submitting")
  control.style.pointerEvents = control.dataset.submitGuardOriginalPointerEvents || ""
  delete control.dataset.submitGuardOriginalPointerEvents

  if (control instanceof HTMLInputElement && control.dataset.submitGuardOriginalValue !== undefined) {
    control.value = control.dataset.submitGuardOriginalValue
    delete control.dataset.submitGuardOriginalValue
    return
  }

  const labelTarget = control.querySelector("[data-submit-guard-label], span")
  if (labelTarget?.dataset.submitGuardOriginalText !== undefined) {
    labelTarget.textContent = labelTarget.dataset.submitGuardOriginalText
    delete labelTarget.dataset.submitGuardOriginalText
  } else if (control.dataset.submitGuardOriginalText !== undefined) {
    control.textContent = control.dataset.submitGuardOriginalText
    delete control.dataset.submitGuardOriginalText
  }
}

const lockForm = (form, submitter = null) => {
  form.setAttribute(FORM_GUARD_ATTR, SUBMITTING_STATE)
  form.setAttribute("aria-busy", "true")
  form.classList.add("is-submitting")

  const controls = submitControlsFor(form)
  controls.forEach(lockControl)
  if (submitter && !controls.includes(submitter)) lockControl(submitter)
}

const unlockForm = (form) => {
  if (!(form instanceof HTMLFormElement)) return

  form.removeAttribute(FORM_GUARD_ATTR)
  form.removeAttribute("aria-busy")
  form.classList.remove("is-submitting")
  submitControlsFor(form).forEach(unlockControl)
}

const rejectDuplicateSubmit = (event, form) => {
  event.preventDefault()
  event.stopImmediatePropagation()

  const submitter = event.submitter || document.activeElement
  if (submitter instanceof HTMLElement) {
    submitter.setAttribute("aria-disabled", "true")
    submitter.setAttribute("aria-busy", "true")
  }
}

const handleSubmit = (event) => {
  const form = event.target
  if (!shouldGuardForm(form)) return

  if (form.getAttribute(FORM_GUARD_ATTR) === SUBMITTING_STATE) {
    rejectDuplicateSubmit(event, form)
    return
  }

  if (event.defaultPrevented) return

  lockForm(form, event.submitter)
}

const handleSubmitEnd = (event) => {
  const form = event.target
  if (!(form instanceof HTMLFormElement)) return

  if (event.detail?.success === false || event.detail?.fetchResponse?.redirected !== true) unlockForm(form)
}

const handlePageReady = () => {
  document.querySelectorAll(`form[${FORM_GUARD_ATTR}='${SUBMITTING_STATE}']`).forEach(unlockForm)
}

const handleBeforeCache = () => {
  document.querySelectorAll(`form[${FORM_GUARD_ATTR}]`).forEach(unlockForm)
}

export const installSubmitGuard = () => {
  if (window.__submitGuardInstalled) return
  window.__submitGuardInstalled = true

  document.addEventListener("submit", handleSubmit)
  document.addEventListener("turbo:submit-end", handleSubmitEnd)
  document.addEventListener("turbo:load", handlePageReady)
  document.addEventListener("turbo:render", handlePageReady)
  document.addEventListener("turbo:before-cache", handleBeforeCache)
  window.addEventListener("pageshow", handlePageReady)
}

installSubmitGuard()
