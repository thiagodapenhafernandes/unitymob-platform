// Inicia a escrita durante o toque, mesmo quando o texto depende de uma requisição.
export async function copyText(textOrPromise) {
  let text
  try {
    if (typeof textOrPromise !== "string" && navigator.clipboard?.write && typeof ClipboardItem !== "undefined") {
      const content = Promise.resolve(textOrPromise).then(value => {
        if (!value) throw new Error("Texto indisponível")
        return new Blob([value], { type: "text/plain" })
      })
      // Também trata rejeição quando o WebView recusa a escrita antes de ler o conteúdo.
      content.catch(() => {})
      await navigator.clipboard.write([new ClipboardItem({ "text/plain": content })])
      return true
    }
    if (typeof textOrPromise === "string" && navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(textOrPromise)
      return true
    }
  } catch (_error) {
    // WebViews e permissões do sistema podem bloquear a API.
  }

  try { text = await textOrPromise } catch (_error) { return false }
  if (!text) return false
  const previousFocus = document.activeElement
  const input = document.createElement("textarea")
  input.value = text
  input.setAttribute("readonly", "")
  input.style.cssText = "position:fixed;top:0;left:0;opacity:0"
  // Um dialog modal torna elementos fora dele inertes, inclusive para seleção.
  ;(document.querySelector("dialog[open]") || document.body).appendChild(input)
  let copied = false
  try {
    input.focus()
    input.select()
    input.setSelectionRange(0, input.value.length)
    copied = document.execCommand("copy")
  } catch (_error) {
    copied = false
  } finally {
    input.remove()
    previousFocus?.focus({ preventScroll: true })
  }
  if (!copied) window.prompt("Copie o texto abaixo:", text)
  return copied
}
