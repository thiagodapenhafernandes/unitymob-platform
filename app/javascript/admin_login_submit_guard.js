document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("form.login-form").forEach((form) => {
    form.addEventListener("submit", () => {
      const button = form.querySelector("button[type='submit']")
      if (!button || button.disabled) return

      button.disabled = true
      button.setAttribute("aria-busy", "true")
      button.querySelector("span")?.replaceChildren("Entrando...")
    })
  })

  document.querySelectorAll("[data-login-reveal]").forEach((toggle) => {
    const control = toggle.closest(".login-control")
    const input = control?.querySelector("input")
    if (!input) return

    toggle.addEventListener("click", () => {
      const revealed = input.type === "password"
      input.type = revealed ? "text" : "password"
      toggle.classList.toggle("is-active", revealed)
      toggle.setAttribute("aria-pressed", String(revealed))
      toggle.setAttribute("aria-label", revealed ? "Ocultar senha" : "Mostrar senha")
      toggle.querySelector("i")?.classList.toggle("bi-eye", !revealed)
      toggle.querySelector("i")?.classList.toggle("bi-eye-slash", revealed)
      input.focus()
    })
  })
})
