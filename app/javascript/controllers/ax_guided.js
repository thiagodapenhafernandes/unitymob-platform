// Comportamento comum do formulário guiado (ax_guided_header / ax_guided_step / ax_guided_review).
// O controller da tela calcula o estado e chama estas funções; o markup é o dos helpers ax_guided_*.

export function focusStep(root, event) {
  const section = event.target.closest?.("[data-guided-step]")
  if (!section) return

  root.querySelectorAll("[data-guided-step]").forEach((item) => item.classList.toggle("is-active", item === section))
  root.querySelectorAll(".ax-guided-steps-nav__item").forEach((item) => item.classList.toggle("is-active", item.dataset.step === section.dataset.guidedStep))
}

export function goToStep(root, event) {
  const section = root.querySelector(`[data-guided-step='${event.currentTarget.dataset.step}']`)
  if (!section) return

  if (section.matches(".is-collapsible:not(.is-open)")) section.querySelector("[data-ax-disclosure-target~='trigger']")?.click()
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
  section.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" })
  section.querySelector("input:not([type='hidden']):not([type='checkbox']):not([type='radio']), select:not([hidden]), button[type='submit']")?.focus({ preventScroll: true })
}

// states: { "1": true, ... } por etapa; checks: { chave: [feito, texto] }; count: [feitos, total]
export function renderProgress(root, { states, checks, count, label, ready }) {
  const guided = (name) => root.querySelector(`[data-guided='${name}']`)
  if (!guided("progressBar")) return

  root.querySelectorAll("[data-guided-step]").forEach((section) => { section.dataset.state = states[section.dataset.guidedStep] ? "done" : "todo" })
  root.querySelectorAll(".ax-guided-steps-nav__item").forEach((item) => { item.dataset.state = states[item.dataset.step] ? "done" : "todo" })

  Object.entries(checks).forEach(([key, [done, text]]) => {
    const item = root.querySelector(`[data-check='${key}']`)
    if (!item) return
    item.dataset.state = done ? "done" : "todo"
    item.querySelector("span").textContent = text
  })

  guided("progressBar").style.width = `${Math.round((count[0] / count[1]) * 100)}%`
  guided("progressCount").textContent = `${count[0]} de ${count[1]}`
  guided("progressLabel").textContent = label
  root.classList.toggle("is-ready", ready)
}
