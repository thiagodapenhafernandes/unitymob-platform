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
})
