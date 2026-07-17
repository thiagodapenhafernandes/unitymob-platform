const isStandalonePwa = () =>
  window.matchMedia?.("(display-mode: standalone)")?.matches ||
  window.navigator.standalone === true

const isMobileContext = () =>
  window.matchMedia?.("(max-width: 767.98px)")?.matches ||
  /Android|iPhone|iPad|iPod/i.test(window.navigator.userAgent || "")

const sameOriginUrl = (rawUrl) => {
  try {
    const url = new URL(rawUrl, window.location.href)
    return url.origin === window.location.origin ? url : null
  } catch (_) {
    return null
  }
}

const shouldKeepInsidePwa = () => isStandalonePwa() && isMobileContext()

document.addEventListener("click", (event) => {
  if (!shouldKeepInsidePwa()) return
  if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

  const link = event.target.closest?.("a[href]")
  if (!link || link.hasAttribute("download")) return

  const url = sameOriginUrl(link.href)
  if (!url) return

  const target = (link.getAttribute("target") || "").toLowerCase()
  if (target && target !== "_self") {
    event.preventDefault()
    link.removeAttribute("target")
    window.location.assign(url.href)
  }
}, true)

document.addEventListener("submit", (event) => {
  if (!shouldKeepInsidePwa()) return

  const form = event.target
  if (!(form instanceof HTMLFormElement)) return

  const target = (form.getAttribute("target") || "").toLowerCase()
  if (!target || target === "_self") return

  const url = sameOriginUrl(form.action || window.location.href)
  if (!url) return

  form.removeAttribute("target")
}, true)
