// Abre/fecha um bloco animando altura, paddings, margens e opacidade juntos (WAAPI).
// Sem salto no fim: margens e paddings entram na animação, e uma interrupção parte da altura atual.
const EASING = "cubic-bezier(.2, .8, .2, 1)"
const ZERO = { height: "0px", paddingTop: "0px", paddingBottom: "0px", marginTop: "0px", marginBottom: "0px", borderTopWidth: "0px", borderBottomWidth: "0px", opacity: 0 }

export function slide(element, open, { duration = 240, onDone } = {}) {
  const running = element.getAnimations().filter((animation) => animation.id === "ax-slide")
  const interruptedAt = running.length ? element.getBoundingClientRect().height : null
  running.forEach((animation) => animation.cancel())

  if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches || typeof element.animate !== "function") {
    element.hidden = !open
    onDone?.()
    return null
  }

  if (open) element.hidden = false
  const style = getComputedStyle(element)
  const full = {
    height: `${element.getBoundingClientRect().height}px`,
    paddingTop: style.paddingTop,
    paddingBottom: style.paddingBottom,
    marginTop: style.marginTop,
    marginBottom: style.marginBottom,
    borderTopWidth: style.borderTopWidth,
    borderBottomWidth: style.borderBottomWidth,
    opacity: 1
  }
  const current = interruptedAt === null ? null : { ...(open ? ZERO : full), height: `${interruptedAt}px` }
  const keyframes = open ? [current || ZERO, full] : [current || full, ZERO]

  element.style.overflow = "hidden"
  element.style.boxSizing = "border-box" // a altura medida é da caixa de borda; content-box somaria o padding de novo
  // fill: "forwards" segura o último quadro até o estado final ser aplicado (sem piscar no fim).
  const animation = element.animate(keyframes, { id: "ax-slide", duration, easing: EASING, fill: "forwards" })
  animation.onfinish = () => {
    element.style.overflow = ""
    element.style.boxSizing = ""
    if (!open) element.hidden = true
    onDone?.()
    animation.cancel()
  }
  animation.oncancel = () => { element.style.overflow = ""; element.style.boxSizing = "" }
  return animation
}
