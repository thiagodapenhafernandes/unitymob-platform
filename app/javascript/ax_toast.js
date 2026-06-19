// ===========================================================================
// Toast reutilizável do sistema.
// Renderiza o MESMO markup do _flash_messages (.ax-flash-toast) numa pilha
// compartilhada (.ax-flash-toast-stack), com auto-dismiss e botão fechar.
//
// Uso:
//   import { showToast } from "ax_toast"
//   showToast("Salvo!", "success")
// ou globalmente (sem import), de qualquer controller:
//   window.axToast({ message: "Erro ao salvar", type: "danger" })
//   window.dispatchEvent(new CustomEvent("ax-toast", { detail: { message, type } }))
// ===========================================================================

const ICONS = {
  success: "bi-check-circle-fill",
  danger: "bi-exclamation-triangle-fill",
  warning: "bi-exclamation-circle-fill",
  info: "bi-info-circle-fill"
}

// Aceita os nomes usados pelo flash do Rails e variações comuns.
const TYPE_ALIASES = { error: "danger", alert: "danger", notice: "success" }

function stackElement() {
  let stack = document.querySelector(".ax-flash-toast-stack")
  if (!stack) {
    stack = document.createElement("div")
    stack.className = "ax-flash-toast-stack"
    stack.setAttribute("aria-live", "polite")
    stack.setAttribute("aria-atomic", "true")
    document.body.appendChild(stack)
  }
  return stack
}

function dismiss(toast) {
  if (!toast || toast.dataset.leaving) return
  toast.dataset.leaving = "true"
  toast.classList.add("ax-flash-toast--leaving")
  const remove = () => toast.remove()
  toast.addEventListener("animationend", remove, { once: true })
  setTimeout(remove, 400)
}

export function showToast(message, type = "info", options = {}) {
  if (!message) return null

  const resolvedType = TYPE_ALIASES[type] || type || "info"
  const icon = ICONS[resolvedType] || ICONS.info
  const timeout = options.timeout ?? 6000

  const toast = document.createElement("div")
  toast.className = `ax-flash-toast ax-flash-toast--js ax-flash-toast--${resolvedType}`
  toast.setAttribute("role", resolvedType === "danger" ? "alert" : "status")

  const iconSpan = document.createElement("span")
  iconSpan.className = "ax-flash-toast__icon"
  iconSpan.innerHTML = `<i class="bi ${icon}"></i>`

  const messageSpan = document.createElement("span")
  messageSpan.className = "ax-flash-toast__message"
  messageSpan.textContent = message // textContent evita injeção de HTML

  const close = document.createElement("button")
  close.type = "button"
  close.className = "ax-flash-toast__close"
  close.setAttribute("aria-label", "Fechar aviso")
  close.innerHTML = '<i class="bi bi-x"></i>'
  close.addEventListener("click", () => dismiss(toast))

  toast.append(iconSpan, messageSpan, close)
  stackElement().appendChild(toast)

  if (timeout > 0) setTimeout(() => dismiss(toast), timeout)
  return toast
}

if (typeof window !== "undefined") {
  // window.axToast("msg", "success")  ou  window.axToast({ message, type, timeout })
  window.axToast = (arg, maybeType) => {
    if (typeof arg === "string") return showToast(arg, maybeType)
    const { message, type, ...rest } = arg || {}
    return showToast(message, type, rest)
  }

  window.addEventListener("ax-toast", (event) => {
    const detail = event.detail || {}
    showToast(detail.message, detail.type, detail)
  })
}
