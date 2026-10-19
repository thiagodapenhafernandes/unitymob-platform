let stylesheetPromise = null

export function loadPhoneInputStyles() {
  if (stylesheetPromise) return stylesheetPromise

  stylesheetPromise = new Promise((resolve, reject) => {
    let link = document.querySelector("link[data-phone-input-css]")
    if (!link) {
      link = document.createElement("link")
      link.rel = "stylesheet"
      link.href = "https://cdn.jsdelivr.net/npm/intl-tel-input@25.12.2/build/css/intlTelInput.css"
      link.dataset.phoneInputCss = "true"
    }

    const style = document.createElement("style")
    style.dataset.phoneInputLocalCss = "true"
    style.textContent = `
      .iti { width: 100%; display: block; }
      .iti input.ax-control,
      .iti input.form-control,
      .iti input[type="tel"] { width: 100%; }
      .iti--separate-dial-code .iti__selected-country {
        background: #f6f8fb;
        border-right: 1px solid #d8e0eb;
      }
      .phone-input-group { align-items: stretch; }
      .phone-input-group > .iti {
        flex: 1 1 auto;
        min-width: 0;
      }
      .phone-input-group > .ax-input-group__addon,
      .phone-input-group > span[class*="bg-"] {
        display: none;
      }
      .iti.is-readonly .iti__selected-country {
        pointer-events: none;
      }
      .iti.is-readonly input {
        background-color: #f4f7fb;
        cursor: not-allowed;
      }
    `
    if (!document.querySelector("style[data-phone-input-local-css]")) document.head.appendChild(style)

    // The country selector must be styled before its width is measured.
    if (link.sheet) {
      resolve()
    } else {
      link.addEventListener("load", resolve, { once: true })
      link.addEventListener("error", () => {
        link.remove()
        stylesheetPromise = null
        reject(new Error("Não foi possível carregar os estilos do telefone."))
      }, { once: true })
      if (!link.isConnected) document.head.appendChild(link)
    }
  })
  return stylesheetPromise
}
